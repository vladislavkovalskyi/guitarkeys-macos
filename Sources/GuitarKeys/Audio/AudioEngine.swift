import AVFoundation
import Foundation
import Synchronization

enum StrumDirection: String, Codable, Sendable {
    case down   // от низких струн к высоким
    case up     // от высоких к низким

    var symbol: String { self == .down ? "arrow.down" : "arrow.up" }
}

/// Характер удара. Абсолютный тембр задаёт инструмент, здесь — только отклонения от него.
struct StrumArticulation: Sendable {
    var velocity: Float = 0.9
    var brightnessOffset: Float = 0     // резче или мягче обычного
    var sustainScale: Float = 1         // доля штатного затухания
    var spreadMs: Double = 16           // задержка между соседними струнами
    var muted: Bool = false             // глушение ладонью

    static let normalDown = StrumArticulation(velocity: 0.90, brightnessOffset: 0.00, sustainScale: 1.00, spreadMs: 17)
    static let normalUp   = StrumArticulation(velocity: 0.68, brightnessOffset: 0.06, sustainScale: 0.72, spreadMs: 11)
    static let mutedDown  = StrumArticulation(velocity: 0.80, brightnessOffset: -0.18, sustainScale: 0.055, spreadMs: 9, muted: true)
    static let mutedUp    = StrumArticulation(velocity: 0.62, brightnessOffset: -0.14, sustainScale: 0.048, spreadMs: 7, muted: true)
}

/// Обвязка AVAudioEngine: источник → эквалайзер корпуса → реверберация → выход.
final class AudioEngine: @unchecked Sendable {

    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 4)
    private let reverb = AVAudioUnitReverb()
    private var sourceNode: AVAudioSourceNode!
    private let synth: GuitarSynth
    private let sampleRate: Double

    /// Запас перед первым событием: гарантирует, что удар не «опоздает» в текущий буфер.
    private let scheduleLeadSamples: UInt64

    private(set) var isRunning = false

    /// Инструмент. Задаёт тембр, сустейн, корпус и перегруз.
    var model: GuitarModel = .acoustic {
        didSet { applyModel() }
    }

    /// Насколько «живой» игрок: 0 — метроном, 1 — заметно неровная рука.
    var humanize: Double = 0.5

    init() {
        // На iOS сессию нужно поднять до чтения формата: пока она не активна,
        // устройство вывода не настроено и частота дискретизации ещё неизвестна.
        Self.activateSessionIfNeeded()

        let format = engine.outputNode.outputFormat(forBus: 0)
        // Если устройство вывода ещё не готово, берём безопасное значение.
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 48000
        synth = GuitarSynth(sampleRate: sampleRate)
        scheduleLeadSamples = UInt64(sampleRate * 0.004)

        buildGraph()
        applyModel()
        observeConfigurationChanges()
    }

    private func buildGraph() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let synth = self.synth

        sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)
            guard buffers.count >= 2,
                  let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
                for buffer in buffers {
                    memset(buffer.mData, 0, Int(buffer.mDataByteSize))
                }
                return noErr
            }
            synth.render(left: l, right: r, frames: frames)
            return noErr
        }

        reverb.loadFactoryPreset(.smallRoom)

        engine.attach(sourceNode)
        engine.attach(eq)
        engine.attach(reverb)
        engine.connect(sourceNode, to: eq, format: format)
        engine.connect(eq, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    /// Переносит параметры инструмента в граф: корпус — в эквалайзер, помещение —
    /// в реверберацию, перегруз — в нелинейность синтезатора.
    private func applyModel() {
        let bands = model.eqBands
        for (index, band) in bands.enumerated() where index < eq.bands.count {
            let target = eq.bands[index]
            target.filterType = band.type
            target.frequency = band.frequency
            target.bandwidth = band.bandwidth
            target.gain = band.gain
            target.bypass = false
        }
        eq.globalGain = 0
        reverb.wetDryMix = Float(max(0, min(1, model.reverb)) * 100)
        synth.drive = Float(model.drive)
    }

    /// Категория `playback` даёт звук при выключенном звонке и в фоне, а короткий
    /// буфер держит задержку игры в разумных пределах.
    private static func activateSessionIfNeeded() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            NSLog("GuitarKeys: не удалось настроить аудиосессию — \(error.localizedDescription)")
        }
        #endif
    }

    private func observeConfigurationChanges() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            try? self.engine.start()
        }
    }

    // MARK: - Управление

    func start() {
        guard !isRunning else { return }
        do {
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
            NSLog("GuitarKeys: не удалось запустить аудиодвижок — \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        isRunning = false
    }

    var volume: Float {
        get { synth.gain }
        set { synth.gain = max(0, min(1, newValue)) }
    }

    /// Сколько сэмплов отдал аудиопоток. Растёт — значит CoreAudio тянет граф.
    var renderedSampleCount: UInt64 { synth.sampleClock.load(ordering: .relaxed) }

    var outputSampleRate: Double { sampleRate }

    // MARK: - Игра

    private var scheduleOrigin: UInt64 {
        synth.sampleClock.load(ordering: .relaxed) &+ scheduleLeadSamples
    }

    /// Бой по прижатому аккорду. Струны звучат последовательно — в этом и слышен «бой».
    /// Каждый удар отличается от предыдущего: рука не автомат.
    func strum(voicing: Voicing, direction: StrumDirection, articulation: StrumArticulation) {
        let sounding = voicing.soundingStrings
        guard !sounding.isEmpty else { return }

        let human = Float(max(0, min(1, humanize)))
        var order: [Int] = direction == .down ? sounding : sounding.reversed()

        // Движение вверх начинается с тонких струн и часто не достаёт до басов.
        if direction == .up && human > 0 && order.count > 3 {
            if Float.random(in: 0...1) < 0.40 * human {
                order.removeLast()
                if order.count > 3 && Float.random(in: 0...1) < 0.30 * human {
                    order.removeLast()
                }
            }
        }

        // Сила и скорость всего движения гуляют от удара к удару.
        let strokeGain = 1 + Float.random(in: -0.11...0.11) * human
        let spreadMs = articulation.spreadMs * (1 + Double.random(in: -0.22...0.22) * Double(human))
        let origin = scheduleOrigin

        for (position, stringIndex) in order.enumerated() {
            guard let midi = voicing.midiNote(string: stringIndex) else { continue }

            var velocity = articulation.velocity * strokeGain
            if direction == .up {
                // Медиатор входит в струны под углом: первые задеты полнее последних.
                let depth = Float(position) / Float(max(1, order.count - 1))
                velocity *= 0.55 + 0.45 * (1 - depth)
            }
            velocity *= 1 + Float.random(in: -0.19...0.19) * human

            // Живая гитара не строит идеально: палец давит на лад каждый раз чуть иначе.
            let detuneCents = Float.random(in: -3.0...3.0) * human
            let frequency = Float(Pitch.frequency(midi: Double(midi))) * pow(2, detuneCents / 1200)

            // Дрожание руки во времени — главное, что отличает игру от секвенсора.
            let jitterMs = Double.random(in: -2.2...2.2) * Double(human)
            let offsetMs = max(0, Double(position) * spreadMs + jitterMs)

            var event = StringEvent()
            event.atSample = origin &+ UInt64(offsetMs * sampleRate / 1000)
            event.string = Int32(stringIndex)
            event.frequency = frequency
            event.velocity = min(1, max(0.04, velocity))
            event.brightness = brightness(articulation: articulation, human: human)
            event.pickPosition = pickPosition(human: human)
            event.sustain = sustain(string: stringIndex, articulation: articulation, human: human)
            event.kind = .pluck
            synth.queue.push(event)
        }
    }

    /// Одиночная струна — для перебора.
    func pluck(string: Int, voicing: Voicing, articulation: StrumArticulation) {
        guard let midi = voicing.midiNote(string: string) else { return }
        let human = Float(max(0, min(1, humanize)))
        let detuneCents = Float.random(in: -3.0...3.0) * human

        var event = StringEvent()
        event.atSample = scheduleOrigin
        event.string = Int32(string)
        event.frequency = Float(Pitch.frequency(midi: Double(midi))) * pow(2, detuneCents / 1200)
        event.velocity = min(1, articulation.velocity * (1 + Float.random(in: -0.15...0.15) * human))
        event.brightness = brightness(articulation: articulation, human: human)
        event.pickPosition = pickPosition(human: human)
        event.sustain = sustain(string: string, articulation: articulation, human: human)
        event.kind = .pluck
        synth.queue.push(event)
    }

    private func brightness(articulation: StrumArticulation, human: Float) -> Float {
        let jitter = Float.random(in: -0.09...0.09) * human
        return max(0, min(1, Float(model.brightness) + articulation.brightnessOffset + jitter))
    }

    private func pickPosition(human: Float) -> Float {
        // Рука не попадает дважды в одну точку струны.
        let jitter = Float.random(in: -0.035...0.035) * human
        return max(0.04, min(0.42, Float(model.pickPosition) + jitter))
    }

    private func sustain(string: Int, articulation: StrumArticulation, human: Float) -> Float {
        let base = Float(model.sustain(forString: string)) * articulation.sustainScale
        return max(0.03, base * (1 + Float.random(in: -0.10...0.10) * human))
    }

    /// Приглушить все струны — палец снят с аккорда.
    func dampAll(release: Float = 0.12) {
        let origin = scheduleOrigin
        for string in 0..<GuitarSynth.stringCount {
            var event = StringEvent()
            event.atSample = origin
            event.string = Int32(string)
            event.sustain = release
            event.kind = .damp
            synth.queue.push(event)
        }
    }

    // MARK: - Запись

    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordedFrames: AVAudioFramePosition = 0
    private var recordingSampleRate: Double = 48000
    /// Ответвление снимается на потоке рендера, поэтому доступ к файлу под замком.
    private let recordingLock = NSLock()
    private let recordingPeak = Atomic<UInt64>(0)

    var isRecording: Bool {
        recordingLock.lock()
        defer { recordingLock.unlock() }
        return recordingFile != nil
    }

    /// Длительность записи, посчитанная по реально записанным кадрам.
    var recordedDuration: TimeInterval {
        recordingLock.lock()
        defer { recordingLock.unlock() }
        guard recordingSampleRate > 0 else { return 0 }
        return Double(recordedFrames) / recordingSampleRate
    }

    /// Пиковый уровень последнего записанного блока, 0…1.
    var recordingLevel: Float {
        Float(bitPattern: UInt32(truncatingIfNeeded: recordingPeak.load(ordering: .relaxed)))
    }

    /// Пишем с выходного микшера — в файл попадает ровно то, что слышно,
    /// вместе с корпусом и реверберацией.
    @discardableResult
    func startRecording() throws -> URL {
        recordingLock.lock()
        if let existing = recordingURL, recordingFile != nil {
            recordingLock.unlock()
            return existing
        }
        recordingLock.unlock()

        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        let url = try Self.makeRecordingURL()

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: min(2, Int(format.channelCount)),
            AVEncoderBitRateKey: 192_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)

        recordingLock.lock()
        recordingFile = file
        recordingURL = url
        recordedFrames = 0
        recordingSampleRate = format.sampleRate
        recordingLock.unlock()
        recordingPeak.store(0, ordering: .relaxed)

        mixer.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.appendToRecording(buffer)
        }
        return url
    }

    private func appendToRecording(_ buffer: AVAudioPCMBuffer) {
        recordingLock.lock()
        defer { recordingLock.unlock() }
        guard let file = recordingFile else { return }

        do {
            try file.write(from: buffer)
            recordedFrames += AVAudioFramePosition(buffer.frameLength)
        } catch {
            NSLog("GuitarKeys: сбой записи — \(error.localizedDescription)")
        }

        if let channels = buffer.floatChannelData {
            var peak: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = channels[channel]
                for frame in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(samples[frame]))
                }
            }
            recordingPeak.store(UInt64(peak.bitPattern), ordering: .relaxed)
        }
    }

    /// Возвращает файл записи или nil, если запись не шла.
    @discardableResult
    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        engine.mainMixerNode.removeTap(onBus: 0)

        recordingLock.lock()
        defer { recordingLock.unlock() }
        let url = recordingURL
        recordingFile = nil   // закрывается и дописывает заголовок при освобождении
        recordingURL = nil
        recordingPeak.store(0, ordering: .relaxed)
        return url
    }

    static var recordingsFolder: URL {
        #if os(macOS)
        let base = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
        #else
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
        return base.appendingPathComponent("GuitarKeys", isDirectory: true)
    }

    private static func makeRecordingURL() throws -> URL {
        let folder = recordingsFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return folder.appendingPathComponent("GuitarKeys \(formatter.string(from: Date())).m4a")
    }

    func silenceAll() {
        let origin = scheduleOrigin
        for string in 0..<GuitarSynth.stringCount {
            var event = StringEvent()
            event.atSample = origin
            event.string = Int32(string)
            event.kind = .silence
            synth.queue.push(event)
        }
    }
}
