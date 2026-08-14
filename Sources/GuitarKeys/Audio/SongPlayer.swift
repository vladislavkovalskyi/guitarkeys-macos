import Foundation
import Observation

/// Проигрывает проект через живой движок.
///
/// События не отправляются разом: очередь в аудиопоток конечна, а длинный проект
/// её переполнит. Поэтому раскладка считается заранее, а подкладывается окном —
/// так темп не плывёт даже если интерфейс подтормаживает.
@MainActor
@Observable
final class SongPlayer {

    private(set) var isPlaying = false
    /// Доля под курсором воспроизведения, −1 если стоим.
    private(set) var currentSlot: Int = -1
    var loops = true
    /// Счёт вслух: без него сочинять ритм приходится вслепую.
    var metronome = false

    private let audio: AudioEngine
    private var events: [StringEvent] = []
    private var pending = 0
    private var startSample: UInt64 = 0
    private var totalSamples: UInt64 = 0
    private var slotSamples: Double = 1
    private var timer: Timer?
    private var song: Song?
    private var model: GuitarModel = .acoustic

    init(audio: AudioEngine) {
        self.audio = audio
    }

    func play(_ song: Song, model: GuitarModel, fromSlot: Int = 0) {
        stop()
        guard !song.bars.isEmpty else { return }

        self.song = song
        self.model = model
        let sampleRate = audio.outputSampleRate
        slotSamples = song.slotDuration * sampleRate
        startSample = audio.currentSample &+ audio.scheduleLead &+ UInt64(0.05 * sampleRate)

        // Перемотка: сдвигаем начало отсчёта назад, чтобы нужная доля пришлась на сейчас.
        let offset = UInt64(Double(max(0, fromSlot)) * slotSamples)
        startSample = startSample >= offset ? startSample &- offset : startSample

        events = SongRenderer.events(for: song, model: model,
                                     sampleRate: sampleRate, startSample: startSample)
            .filter { $0.atSample >= audio.currentSample }
        if metronome { events += clicks(for: song, sampleRate: sampleRate) }
        events.sort { $0.atSample < $1.atSample }
        guard !events.isEmpty else { return }

        pending = 0
        totalSamples = UInt64(Double(song.totalSlots) * slotSamples)
        isPlaying = true
        currentSlot = max(0, fromSlot)

        let ticker = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        guard isPlaying else {
            currentSlot = -1
            return
        }
        isPlaying = false
        currentSlot = -1
        events.removeAll()
        pending = 0
        audio.dampAll(release: 0.15)
    }

    func toggle(_ song: Song, model: GuitarModel) {
        isPlaying ? stop() : play(song, model: model)
    }

    /// Щелчки на каждую долю; первая в такте — акцент.
    private func clicks(for song: Song, sampleRate: Double) -> [StringEvent] {
        var result: [StringEvent] = []
        var slot = 0
        for bar in song.bars {
            for index in 0..<bar.slotCount where index % song.division.perBeat == 0 {
                var event = StringEvent()
                event.atSample = startSample &+ UInt64(Double(slot + index) * slotSamples)
                event.kind = .click
                let accent = index == 0
                event.frequency = accent ? 1600 : 1050
                event.velocity = accent ? 0.5 : 0.3
                result.append(event)
            }
            slot += bar.slotCount
        }
        return result.filter { $0.atSample >= audio.currentSample }
    }

    private func tick() {
        guard isPlaying else { return }
        let now = audio.currentSample
        let sampleRate = audio.outputSampleRate

        // Подкладываем события на полторы секунды вперёд.
        let horizon = now &+ UInt64(1.5 * sampleRate)
        while pending < events.count && events[pending].atSample <= horizon {
            audio.queue(events[pending])
            pending += 1
        }

        // Курсор по сетке.
        if now >= startSample {
            let elapsed = Double(now &- startSample)
            currentSlot = min(Int(elapsed / slotSamples), (song?.totalSlots ?? 1) - 1)
        }

        // Конец проекта.
        if now >= startSample &+ totalSamples {
            guard let song, loops else {
                stop()
                return
            }
            play(song, model: model)
        }
    }
}
