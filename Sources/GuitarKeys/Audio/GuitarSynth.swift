import Foundation
import Synchronization

/// Одна струна: расширенный алгоритм Карплуса—Стронга.
/// Линия задержки + петлевой фильтр НЧ дают затухающий обертоновый спектр щипковой струны.
private struct StringVoice {
    var writeIndex: Int = 0
    var delayInt: Int = 100     // целая часть задержки
    var alpha: Float = 0        // коэффициент интерполятора дробной задержки
    var period: Float = 100     // период основного тона в сэмплах
    var decay: Float = 0.999    // множитель обратной связи за один оборот петли
    var lpCoef: Float = 0.3     // демпфирование: сколько НЧ-фильтра в петле
    var lpState: Float = 0
    var level: Float = 0        // огибающая амплитуды (для определения тишины)
    var active: Bool = false
    var panL: Float = 0.7
    var panR: Float = 0.7
}

/// Шестиструнный синтезатор. Весь рендеринг идёт в аудиопотоке без аллокаций и блокировок.
final class GuitarSynth: @unchecked Sendable {

    static let stringCount = 6
    private static let delayCapacity = 1024      // хватает до ~47 Гц при 48 кГц
    private static let delayMask = delayCapacity - 1
    private static let noiseSize = 8192
    private static let noiseMask = noiseSize - 1
    private static let pendingCapacity = 256

    private let sampleRate: Float

    private let voices: UnsafeMutablePointer<StringVoice>
    private let delayLines: UnsafeMutablePointer<Float>
    private let noise: UnsafeMutablePointer<Float>
    private let scratch: UnsafeMutablePointer<Float>

    private let pending: UnsafeMutablePointer<StringEvent>
    private var pendingCount: Int = 0

    let queue = EventQueue(capacity: 1024)

    /// Позиция аудиопотока в сэмплах — по ней главный поток планирует бой.
    let sampleClock = Atomic<UInt64>(0)
    /// Общая громкость, 0…1.
    let masterGain = Atomic<UInt64>(0x3F00_0000)   // хранится как битовый шаблон Float (0.5)
    /// Перегруз, 0…1.
    let driveAmount = Atomic<UInt64>(0)

    private var rngState: UInt32 = 0x9E3779B9

    // Метроном: отдельный голос, струнами щелчок не сыграть.
    private var clickPhase: Float = 0
    private var clickStep: Float = 0
    private var clickLevel: Float = 0
    private var clickDecay: Float = 0.9995

    // Состояние выходного фильтра постоянной составляющей.
    private var dcL: Float = 0, dcPrevL: Float = 0
    private var dcR: Float = 0, dcPrevR: Float = 0
    /// Снимок перегруза на текущий буфер — атомик не читаем в горячем цикле.
    private var currentDrive: Float = 0

    init(sampleRate: Double) {
        self.sampleRate = Float(sampleRate)

        voices = .allocate(capacity: Self.stringCount)
        voices.initialize(repeating: StringVoice(), count: Self.stringCount)

        delayLines = .allocate(capacity: Self.stringCount * Self.delayCapacity)
        delayLines.initialize(repeating: 0, count: Self.stringCount * Self.delayCapacity)

        noise = .allocate(capacity: Self.noiseSize)
        scratch = .allocate(capacity: Self.delayCapacity)
        scratch.initialize(repeating: 0, count: Self.delayCapacity)

        pending = .allocate(capacity: Self.pendingCapacity)
        pending.initialize(repeating: StringEvent(), count: Self.pendingCapacity)

        // Таблица шума считается заранее: в аудиопотоке случайных чисел не генерируем.
        var s: UInt32 = 0x1234_5678
        for i in 0..<Self.noiseSize {
            s ^= s << 13; s ^= s >> 17; s ^= s << 5
            noise[i] = Float(Int32(bitPattern: s)) / Float(Int32.max)
        }

        // Стереообраз: низкие струны чуть левее, высокие чуть правее.
        for i in 0..<Self.stringCount {
            let pan = (Float(i) / Float(Self.stringCount - 1) - 0.5) * 0.5   // −0.25…+0.25
            let angle = (pan + 1) * 0.25 * Float.pi                          // равномощное панорамирование
            voices[i].panL = cos(angle)
            voices[i].panR = sin(angle)
        }
    }

    deinit {
        voices.deinitialize(count: Self.stringCount)
        voices.deallocate()
        delayLines.deinitialize(count: Self.stringCount * Self.delayCapacity)
        delayLines.deallocate()
        noise.deallocate()
        scratch.deinitialize(count: Self.delayCapacity)
        scratch.deallocate()
        pending.deinitialize(count: Self.pendingCapacity)
        pending.deallocate()
    }

    var gain: Float {
        get { Float(bitPattern: UInt32(truncatingIfNeeded: masterGain.load(ordering: .relaxed))) }
        set { masterGain.store(UInt64(newValue.bitPattern), ordering: .relaxed) }
    }

    var drive: Float {
        get { Float(bitPattern: UInt32(truncatingIfNeeded: driveAmount.load(ordering: .relaxed))) }
        set { driveAmount.store(UInt64(max(0, min(1, newValue)).bitPattern), ordering: .relaxed) }
    }

    // MARK: - Рендеринг

    /// Заполняет стереобуфер. Вызывается только из аудиопотока.
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        drainQueue()

        let start = sampleClock.load(ordering: .relaxed)
        let g = gain
        currentDrive = drive

        var frame = 0
        while frame < frames {
            let now = start &+ UInt64(frame)
            applyDueEvents(now: now)

            // Считаем до ближайшего запланированного события — так удар попадает точно в сэмпл.
            var segmentEnd = frames
            if let next = nextEventSample() {
                if next > now {
                    let offset = Int(min(next &- start, UInt64(frames)))
                    segmentEnd = max(frame + 1, min(frames, offset))
                }
            }

            renderSegment(left: left, right: right, from: frame, to: segmentEnd, gain: g)
            frame = segmentEnd
        }

        sampleClock.store(start &+ UInt64(frames), ordering: .relaxed)
    }

    private func renderSegment(left: UnsafeMutablePointer<Float>,
                               right: UnsafeMutablePointer<Float>,
                               from: Int, to: Int, gain g: Float) {
        for i in from..<to {
            left[i] = 0
            right[i] = 0
        }

        for s in 0..<Self.stringCount {
            guard voices[s].active else { continue }
            let line = delayLines + s * Self.delayCapacity
            var v = voices[s]

            let delayInt = v.delayInt
            let alpha = v.alpha
            var peak: Float = 0

            for i in from..<to {
                // Дробная задержка через линейную интерполяцию.
                let i0 = (v.writeIndex - delayInt - 1) & Self.delayMask
                let i1 = (i0 + 1) & Self.delayMask
                let sample = line[i0] * alpha + line[i1] * (1 - alpha)

                // Петлевой фильтр НЧ: высокие обертоны гаснут быстрее низких.
                v.lpState = sample * (1 - v.lpCoef) + v.lpState * v.lpCoef
                let out = v.lpState * v.decay

                line[v.writeIndex] = out
                v.writeIndex = (v.writeIndex + 1) & Self.delayMask

                left[i] += out * v.panL
                right[i] += out * v.panR

                let a = abs(out)
                if a > peak { peak = a }
            }

            v.level = peak
            if peak < 0.00002 {
                v.active = false
                // Обнуляем линию, чтобы следующий щипок начинался с тишины.
                for k in 0..<Self.delayCapacity { line[k] = 0 }
                v.lpState = 0
            }
            voices[s] = v
        }

        // Фильтр постоянной составляющей — на выходе, а не в петле обратной связи:
        // в петле он расстроил бы низкие струны.
        for i in from..<to {
            var click: Float = 0
            if clickLevel > 0.0001 {
                click = sin(clickPhase) * clickLevel * 0.5
                clickPhase += clickStep
                if clickPhase > 2 * Float.pi { clickPhase -= 2 * Float.pi }
                clickLevel *= clickDecay
            }
            let inL = left[i] + click, inR = right[i] + click
            dcL = inL - dcPrevL + 0.995 * dcL
            dcPrevL = inL
            dcR = inR - dcPrevR + 0.995 * dcR
            dcPrevR = inR
            // Общая громкость и мягкое ограничение — шесть струн легко уходят в клиппинг.
            left[i] = saturate(dcL * g)
            right[i] = saturate(dcR * g)
        }
    }

    /// Перегруз и защита от клиппинга — одна и та же нелинейность.
    /// Компенсация громкости не даёт звуку скакать при повороте ручки.
    @inline(__always)
    private func saturate(_ x: Float) -> Float {
        let d = currentDrive
        guard d > 0.001 else { return softClip(x) }
        return softClip(x * (1 + d * 4)) / (1 + d * 1.9)
    }

    @inline(__always)
    private func softClip(_ x: Float) -> Float {
        if x > 1.2 { return 1.0 }
        if x < -1.2 { return -1.0 }
        return x - (x * x * x) / 3.6
    }

    // MARK: - События

    private func drainQueue() {
        while pendingCount < Self.pendingCapacity, let event = queue.pop() {
            pending[pendingCount] = event
            pendingCount += 1
        }
    }

    private func nextEventSample() -> UInt64? {
        guard pendingCount > 0 else { return nil }
        var best = pending[0].atSample
        for i in 1..<pendingCount where pending[i].atSample < best {
            best = pending[i].atSample
        }
        return best
    }

    private func applyDueEvents(now: UInt64) {
        var i = 0
        while i < pendingCount {
            if pending[i].atSample <= now {
                apply(pending[i])
                pending[i] = pending[pendingCount - 1]
                pendingCount -= 1
            } else {
                i += 1
            }
        }
    }

    private func apply(_ event: StringEvent) {
        if event.kind == .click {
            startClick(frequency: event.frequency, velocity: event.velocity)
            return
        }
        let s = Int(event.string)
        guard s >= 0 && s < Self.stringCount else { return }
        switch event.kind {
        case .pluck:   pluck(string: s, event: event)
        case .damp:    damp(string: s, sustain: max(0.03, event.sustain))
        case .silence: silence(string: s)
        case .click:   startClick(frequency: event.frequency, velocity: event.velocity)
        }
    }

    // MARK: - Возбуждение струны

    private func pluck(string s: Int, event: StringEvent) {
        let freq = max(20, min(2000, event.frequency))
        let brightness = max(0, min(1, event.brightness))

        // Демпфирование петли: ярче удар — меньше НЧ-фильтра.
        let lpCoef = 0.42 - 0.30 * brightness

        // Высоту задаёт суммарная фазовая задержка петли на основном тоне, а не одна
        // длина линии: НЧ-фильтр и интерполятор тоже задерживают сигнал. Считаем их
        // вклад точно на нужной частоте — иначе строй уезжает тем сильнее, чем выше нота.
        let period = sampleRate / freq
        let omega = 2 * Float.pi * freq / sampleRate
        let lpPhaseDelay = atan2(lpCoef * sin(omega), 1 - lpCoef * cos(omega)) / omega

        var needed = period - lpPhaseDelay
        needed = max(2, min(Float(Self.delayCapacity - 4), needed))
        let delayInt = Int(needed.rounded(.down))
        let remainder = needed - Float(delayInt)
        let alpha = interpolatorFraction(phaseDelay: remainder, omega: omega)

        let length = min(delayInt + 2, Self.delayCapacity)

        // Возбуждение: отфильтрованный шум + гребёнка от позиции медиатора.
        rngState ^= rngState << 13; rngState ^= rngState >> 17; rngState ^= rngState << 5
        let offset = Int(rngState & UInt32(Self.noiseMask))
        let attackLP = 0.25 + 0.65 * brightness
        var z: Float = 0
        for k in 0..<length {
            let raw = noise[(offset + k) & Self.noiseMask]
            z += attackLP * (raw - z)
            scratch[k] = z
        }

        // Медиатор бьёт не по центру струны — это гасит кратные гармоники и даёт «щипок».
        let pickPosition = max(0.03, min(0.45, event.pickPosition))
        let p = max(1, Int(Float(length) * pickPosition))
        if p < length {
            var k = length - 1
            while k >= p {
                scratch[k] -= scratch[k - p] * 0.85
                k -= 1
            }
        }

        // Возбуждение должно быть без постоянной составляющей: петля Карплуса—Стронга
        // не гасит DC и струна «уползла» бы в насыщение.
        var mean: Float = 0
        for k in 0..<length { mean += scratch[k] }
        mean /= Float(length)

        var peak: Float = 0.0001
        for k in 0..<length {
            scratch[k] -= mean
            if abs(scratch[k]) > peak { peak = abs(scratch[k]) }
        }
        let norm = event.velocity / peak

        // Повторный удар по звучащей струне не обнуляет её: медиатор глушит колебание,
        // но часть энергии остаётся и даёт характерный призвук.
        let residual: Float = voices[s].active ? 0.12 : 0
        let line = delayLines + s * Self.delayCapacity
        for k in 0..<Self.delayCapacity {
            let carried = line[k] * residual
            line[k] = (k < length ? scratch[k] * norm : 0) + carried
        }

        var v = voices[s]
        v.writeIndex = length & Self.delayMask
        v.delayInt = delayInt
        v.alpha = alpha
        v.period = period
        v.lpCoef = lpCoef
        v.lpState = 0
        v.decay = decayFactor(period: period, sustain: max(0.05, event.sustain))
        v.active = true
        v.level = event.velocity
        voices[s] = v
    }

    /// Подбирает коэффициент линейного интерполятора, дающий нужную фазовую задержку
    /// на частоте `omega`. У интерполятора y[n] = (1−a)·x[n] + a·x[n−1] задержка
    /// растёт от 0 до 1 монотонно, поэтому хватает деления пополам.
    private func interpolatorFraction(phaseDelay target: Float, omega: Float) -> Float {
        guard target > 0.0005 else { return 0 }
        guard target < 0.9995 else { return 1 }

        func phaseDelay(_ a: Float) -> Float {
            atan2(a * sin(omega), (1 - a) + a * cos(omega)) / omega
        }

        var low: Float = 0
        var high: Float = 1
        for _ in 0..<24 {
            let mid = (low + high) * 0.5
            if phaseDelay(mid) < target { low = mid } else { high = mid }
        }
        return (low + high) * 0.5
    }

    /// Множитель за оборот петли, дающий спад на 60 дБ за `sustain` секунд.
    private func decayFactor(period: Float, sustain: Float) -> Float {
        let loops = sampleRate * sustain / period
        guard loops > 1 else { return 0.5 }
        return exp(-6.907755 / loops)
    }

    private func damp(string s: Int, sustain: Float) {
        guard voices[s].active else { return }
        voices[s].decay = decayFactor(period: voices[s].period, sustain: sustain)
        voices[s].lpCoef = min(0.75, voices[s].lpCoef + 0.25)
    }

    /// Короткий затухающий тон: слышно сквозь гитару и не мешает ей.
    private func startClick(frequency: Float, velocity: Float) {
        clickStep = 2 * Float.pi * max(200, min(4000, frequency)) / sampleRate
        clickPhase = 0
        clickLevel = max(0, min(1, velocity))
        // Спад примерно за 40 мс.
        clickDecay = exp(-1.0 / (0.04 * sampleRate))
    }

    private func silence(string s: Int) {
        voices[s].active = false
        let line = delayLines + s * Self.delayCapacity
        for k in 0..<Self.delayCapacity { line[k] = 0 }
        voices[s].lpState = 0
    }
}
