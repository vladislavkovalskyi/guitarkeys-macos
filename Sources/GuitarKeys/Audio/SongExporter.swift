import AVFoundation
import Foundation

/// Разворачивает проект в поток событий для струн.
/// Одна и та же раскладка используется и при прослушивании, и при экспорте,
/// поэтому файл звучит ровно так же, как то, что слышал автор.
enum SongRenderer {

    static func events(for song: Song,
                       model: GuitarModel,
                       sampleRate: Double,
                       startSample: UInt64 = 0) -> [StringEvent] {

        var events: [StringEvent] = []
        var previousChord: Chord?
        let slotSamples = song.slotDuration * sampleRate

        for (barIndex, bar) in song.bars.enumerated() {
            guard let chord = song.chord(inBar: barIndex) else { continue }
            let voicing = ChordLibrary.voicing(for: chord)
            let barStart = Double(barIndex * Bar.slotCount) * slotSamples

            // Смена аппликатуры глушит то, что звенело от прошлого аккорда.
            if let previous = previousChord, previous != chord {
                let dampAt = max(0, barStart - 0.02 * sampleRate)
                events += StrumScheduler.damp(release: 0.16,
                                              origin: startSample &+ UInt64(dampAt))
            }
            previousChord = chord

            for (slot, slotEvents) in bar.slots.enumerated() {
                let at = startSample &+ UInt64(barStart + Double(slot) * slotSamples)

                for event in slotEvents {
                    let force = Float(max(0.05, min(1.6, event.velocity)))

                    switch event.kind {
                    case .strum(let direction, let muted):
                        var articulation: StrumArticulation
                        switch (direction, muted) {
                        case (.down, false): articulation = .normalDown
                        case (.up, false):   articulation = .normalUp
                        case (.down, true):  articulation = .mutedDown
                        case (.up, true):    articulation = .mutedUp
                        }
                        articulation.velocity *= force
                        events += StrumScheduler.strum(voicing: voicing,
                                                       direction: direction,
                                                       articulation: articulation,
                                                       model: model,
                                                       humanize: song.humanize,
                                                       sampleRate: sampleRate,
                                                       origin: at)

                    case .pluck(let string):
                        var articulation = StrumArticulation.normalDown
                        articulation.velocity = 0.78 * force
                        if let plucked = StrumScheduler.pluck(string: string,
                                                              voicing: voicing,
                                                              articulation: articulation,
                                                              model: model,
                                                              humanize: song.humanize,
                                                              origin: at) {
                            events.append(plucked)
                        }

                    case .note(let string, let fret):
                        // Табулатура играет мимо аккорда: лад задан явно.
                        var articulation = StrumArticulation.normalDown
                        articulation.velocity = 0.80 * force
                        if let note = StrumScheduler.note(string: string,
                                                          fret: fret,
                                                          articulation: articulation,
                                                          model: model,
                                                          humanize: song.humanize,
                                                          origin: at) {
                            events.append(note)
                        }
                    }
                }
            }
        }

        return events.sorted { $0.atSample < $1.atSample }
    }
}

/// Сведение проекта в звуковой файл без проигрывания в реальном времени.
enum SongExporter {

    enum Failure: LocalizedError {
        case emptySong
        case engineFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptySong: return "В проекте нет ни одного удара"
            case .engineFailed(let reason): return "Не удалось свести проект: \(reason)"
            }
        }
    }

    /// Рендерит проект и возвращает файл. Работает быстрее реального времени.
    @discardableResult
    static func export(song: Song,
                       model: GuitarModel,
                       to url: URL,
                       format: AudioFileFormat,
                       sampleRate: Double = 48000) throws -> URL {

        let events = SongRenderer.events(for: song, model: model, sampleRate: sampleRate)
        guard !events.isEmpty else { throw Failure.emptySong }

        let engine = AVAudioEngine()
        let synth = GuitarSynth(sampleRate: sampleRate)
        synth.gain = 0.55
        synth.drive = Float(model.drive)

        guard let format2ch = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw Failure.engineFailed("неверный формат")
        }

        let source = AVAudioSourceNode(format: format2ch) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.render(left: l, right: r, frames: Int(frameCount))
            return noErr
        }

        let eq = AVAudioUnitEQ(numberOfBands: 4)
        for (index, band) in model.eqBands.enumerated() where index < eq.bands.count {
            let target = eq.bands[index]
            target.filterType = band.type
            target.frequency = band.frequency
            target.bandwidth = band.bandwidth
            target.gain = band.gain
            target.bypass = false
        }
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = Float(max(0, min(1, model.reverb)) * 100)

        engine.attach(source)
        engine.attach(eq)
        engine.attach(reverb)
        engine.connect(source, to: eq, format: format2ch)
        engine.connect(eq, to: reverb, format: format2ch)
        engine.connect(reverb, to: engine.mainMixerNode, format: format2ch)

        let blockFrames: AVAudioFrameCount = 4096
        do {
            try engine.enableManualRenderingMode(.offline, format: format2ch,
                                                 maximumFrameCount: blockFrames)
            try engine.start()
        } catch {
            throw Failure.engineFailed(error.localizedDescription)
        }
        defer { engine.stop() }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: blockFrames) else {
            throw Failure.engineFailed("не удалось выделить буфер")
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let file = try AVAudioFile(forWriting: url,
                                   settings: format.settings(sampleRate: sampleRate, channels: 2))

        // Хвост: последним струнам нужно догаснуть, иначе файл обрывается на звоне.
        let tail = model.sustain + 1.0
        let lastEvent = events.last?.atSample ?? 0
        let totalFrames = AVAudioFramePosition(Double(lastEvent) + tail * sampleRate)

        var cursor: AVAudioFramePosition = 0
        var pending = 0

        while cursor < totalFrames {
            // Очередь конечна, поэтому события подкладываются окном, а не разом.
            let horizon = UInt64(cursor) &+ UInt64(blockFrames * 8)
            while pending < events.count && events[pending].atSample <= horizon {
                synth.queue.push(events[pending])
                pending += 1
            }

            let frames = AVAudioFrameCount(min(AVAudioFramePosition(blockFrames),
                                               totalFrames - cursor))
            let status = try engine.renderOffline(frames, to: buffer)
            switch status {
            case .success:
                try file.write(from: buffer)
                cursor += AVAudioFramePosition(buffer.frameLength)
            case .insufficientDataFromInputNode:
                cursor += AVAudioFramePosition(frames)
            case .cannotDoInCurrentContext, .error:
                throw Failure.engineFailed("сбой рендеринга")
            @unknown default:
                throw Failure.engineFailed("неизвестный статус рендеринга")
            }
        }

        return file.url
    }

    /// Куда складывать сведённые файлы.
    static func exportURL(for song: Song, format: AudioFileFormat) -> URL {
        let safe = song.name.replacingOccurrences(of: "/", with: "-")
        return AudioEngine.recordingsFolder
            .appendingPathComponent("\(safe).\(format.fileExtension)")
    }
}
