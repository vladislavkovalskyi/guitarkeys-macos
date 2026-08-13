import AVFoundation
import Observation
import SwiftUI

/// Что сейчас переназначаем.
enum BindingTarget: Hashable {
    case pad(UUID)
    case action(GuitarAction)
    /// Отдельная струна, номер по гитарному счёту: 0 — первая (тонкая).
    case string(Int)
}

@MainActor
@Observable
final class AppState {

    // MARK: Состояние

    var preferences: Preferences {
        didSet { scheduleSave() }
    }

    /// Аккорды, зажатые прямо сейчас (последний — звучащий).
    private(set) var heldPads: [UUID] = []
    /// Аккорд, по которому будет удар.
    private(set) var currentChord: Chord
    private(set) var currentVoicing: Voicing

    /// Для подсветки: когда по струне последний раз ударили.
    private(set) var stringPulse: [Date?] = Array(repeating: nil, count: 6)
    private(set) var lastStrum: StrumDirection = .down
    private(set) var lastStrumMuted = false
    private(set) var strumTick = 0

    var bindingTarget: BindingTarget?
    var inspectorPad: Pad?
    var showsSettings = false
    var showsGuitarPicker = false

    private let audio = AudioEngine()
    #if os(macOS)
    private let keyboard = KeyboardMonitor()
    #endif
    private var saveWorkItem: DispatchWorkItem?
    private var pulseWorkItems: [DispatchWorkItem] = []

    // MARK: Жизненный цикл

    init() {
        let prefs = PreferencesStore.load()
        preferences = prefs
        let chord = prefs.pads.first?.chord(in: prefs.key) ?? Chord(root: prefs.key.tonic, quality: .major)
        currentChord = chord
        currentVoicing = ChordLibrary.voicing(for: chord)

        audio.volume = Float(prefs.volume)
        audio.humanize = prefs.humanize
        audio.model = prefs.guitar
        audio.start()

        #if os(macOS)
        keyboard.onKeyDown = { [weak self] code, modifiers in
            self?.handleKeyDown(code, modifiers: modifiers) ?? false
        }
        keyboard.onKeyUp = { [weak self] code in
            self?.handleKeyUp(code) ?? false
        }
        keyboard.start()
        #endif
    }

    func shutdown() {
        // Файл нужно закрыть до остановки движка, иначе запись оборвётся на полуслове.
        stopRecording()
        stopPlayback()
        #if os(macOS)
        keyboard.stop()
        #endif
        audio.stop()
        saveWorkItem?.cancel()
        PreferencesStore.save(preferences)
    }

    // MARK: Клавиатура

    func handleKeyDown(_ code: UInt16, modifiers: KeyModifiers) -> Bool {
        // Режим переназначения перехватывает следующее нажатие целиком.
        if let target = bindingTarget {
            if code == KeyCodes.escape {
                bindingTarget = nil
                return true
            }
            guard !KeyCodes.reserved.contains(code) else { return true }
            assign(keyCode: code, to: target)
            bindingTarget = nil
            return true
        }

        if let pad = preferences.pad(for: code) {
            press(pad: pad, accented: modifiers.contains(.shift))
            return true
        }

        if let action = preferences.action(for: code) {
            perform(action, muted: modifiers.contains(.shift))
            return true
        }

        if let string = preferences.stringIndex(for: code) {
            pluck(string: string)
            return true
        }

        return false
    }

    func handleKeyUp(_ code: UInt16) -> Bool {
        guard let pad = preferences.pad(for: code) else { return false }
        release(pad: pad)
        return true
    }

    // MARK: Игра

    private func press(pad: Pad, accented: Bool) {
        heldPads.removeAll { $0 == pad.id }
        heldPads.append(pad.id)

        let chord = pad.chord(in: preferences.key)
        setChord(chord)

        if preferences.autoStrumOnPress {
            strum(direction: .down, muted: accented)
        } else {
            // Пальцы перешли на новую аппликатуру — прежние ноты гаснут сами собой,
            // иначе старый аккорд звенел бы поверх нового.
            audio.dampAll(release: 0.12)
        }
    }

    private func release(pad: Pad) {
        heldPads.removeAll { $0 == pad.id }

        if let previous = heldPads.last,
           let padModel = preferences.pads.first(where: { $0.id == previous }) {
            setChord(padModel.chord(in: preferences.key))
        } else if preferences.muteOnRelease {
            audio.dampAll(release: 0.13)
        }
    }

    private func perform(_ action: GuitarAction, muted: Bool) {
        switch action {
        case .strumDown: strum(direction: .down, muted: muted)
        case .strumUp:   strum(direction: .up, muted: muted)
        case .mutedDown: strum(direction: .down, muted: true)
        case .mutedUp:   strum(direction: .up, muted: true)
        case .transposeDown: transpose(by: -1)
        case .transposeUp:   transpose(by: +1)
        }
    }

    func strum(direction: StrumDirection, muted: Bool) {
        var articulation: StrumArticulation
        switch (direction, muted) {
        case (.down, false): articulation = .normalDown
        case (.up, false):   articulation = .normalUp
        case (.down, true):  articulation = .mutedDown
        case (.up, true):    articulation = .mutedUp
        }
        articulation.spreadMs = direction == .down
            ? preferences.strumSpread
            : preferences.strumSpread * 0.65
        if muted { articulation.spreadMs *= 0.55 }

        audio.strum(voicing: currentVoicing, direction: direction, articulation: articulation)

        lastStrum = direction
        lastStrumMuted = muted
        strumTick &+= 1
        animatePulse(direction: direction, spreadMs: articulation.spreadMs)
    }

    /// Щипок одной струны — цифрой на клавиатуре или мышью по грифу.
    /// Заглушённая в аккорде струна молчит, как и на настоящей гитаре.
    func pluck(string: Int) {
        guard currentVoicing.frets.indices.contains(string),
              currentVoicing.frets[string] != nil else { return }

        var articulation = StrumArticulation.normalDown
        articulation.velocity = 0.78
        audio.pluck(string: string, voicing: currentVoicing, articulation: articulation)
        markPulse(string: string)
    }

    private func setChord(_ chord: Chord) {
        currentChord = chord
        currentVoicing = ChordLibrary.voicing(for: chord)
    }

    func transpose(by semitones: Int) {
        var key = preferences.key
        key.tonic = ((key.tonic + semitones) % 12 + 12) % 12
        preferences.key = key
        refreshCurrentChord()
    }

    func setKey(tonic: Int? = nil, scale: ScaleType? = nil) {
        var key = preferences.key
        if let tonic { key.tonic = ((tonic % 12) + 12) % 12 }
        if let scale { key.scale = scale }
        preferences.key = key
        refreshCurrentChord()
    }

    private func refreshCurrentChord() {
        if let heldID = heldPads.last,
           let pad = preferences.pads.first(where: { $0.id == heldID }) {
            setChord(pad.chord(in: preferences.key))
        } else if let first = preferences.pads.first {
            setChord(first.chord(in: preferences.key))
        }
    }

    /// Показать аккорд пэда без звука — при наведении и в инспекторе.
    func preview(pad: Pad) {
        setChord(pad.chord(in: preferences.key))
    }

    /// Нажатие мышью по пэду — играем так же, как с клавиатуры.
    func tap(pad: Pad) {
        setChord(pad.chord(in: preferences.key))
        strum(direction: .down, muted: false)
    }

    var isPadHeld: (UUID) -> Bool {
        { [heldPads] id in heldPads.contains(id) }
    }

    // MARK: Подсветка струн

    private func animatePulse(direction: StrumDirection, spreadMs: Double) {
        pulseWorkItems.forEach { $0.cancel() }
        pulseWorkItems.removeAll(keepingCapacity: true)

        let strings = currentVoicing.soundingStrings
        let order = direction == .down ? strings : strings.reversed()
        for (position, string) in order.enumerated() {
            let delay = Double(position) * spreadMs / 1000
            if delay <= 0.001 {
                markPulse(string: string)
                continue
            }
            let item = DispatchWorkItem { [weak self] in self?.markPulse(string: string) }
            pulseWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    private func markPulse(string: Int) {
        guard string >= 0 && string < 6 else { return }
        withAnimation(.easeOut(duration: 0.08)) {
            stringPulse[string] = Date()
        }
    }

    // MARK: Переназначение

    private func assign(keyCode: UInt16, to target: BindingTarget) {
        // Клавиша может обслуживать только одну функцию — снимаем её со старого места.
        preferences.pads.indices.forEach { index in
            if preferences.pads[index].keyCode == keyCode {
                if case .pad(let id) = target, preferences.pads[index].id == id { return }
                preferences.pads[index].keyCode = 0xFFFF   // не назначена
            }
        }
        preferences.actions.indices.forEach { index in
            preferences.actions[index].keyCodes.removeAll { $0 == keyCode }
        }
        preferences.stringKeys.indices.forEach { index in
            if preferences.stringKeys[index] == keyCode {
                if case .string(let number) = target, number == index { return }
                preferences.stringKeys[index] = 0xFFFF
            }
        }

        switch target {
        case .pad(let id):
            if let index = preferences.pads.firstIndex(where: { $0.id == id }) {
                preferences.pads[index].keyCode = keyCode
            }
        case .action(let action):
            if let index = preferences.actions.firstIndex(where: { $0.action == action }) {
                preferences.actions[index].keyCodes = [keyCode]
            }
        case .string(let number):
            if preferences.stringKeys.indices.contains(number) {
                preferences.stringKeys[number] = keyCode
            }
        }
    }

    /// Перетаскивание аккорда на другое место. Клавиши закреплены за позициями,
    /// поэтому переезжает содержимое, а не привязка: ряд остаётся A S D F G H J.
    func movePad(_ draggedID: UUID, before targetID: UUID) {
        withAnimation(.snappy(duration: 0.28)) {
            preferences.pads.moveChord(from: draggedID, to: targetID)
        }
        refreshCurrentChord()
    }

    func updatePad(_ pad: Pad, source: PadSource) {
        guard let index = preferences.pads.firstIndex(where: { $0.id == pad.id }) else { return }
        preferences.pads[index].source = source
        if let updated = preferences.pads.first(where: { $0.id == pad.id }) {
            inspectorPad = updated
            preview(pad: updated)
        }
    }

    func resetBindings() {
        preferences.pads = Preferences.defaultPads
        preferences.actions = Preferences.defaultActions
        preferences.stringKeys = Preferences.defaultStringKeys
        refreshCurrentChord()
    }

    // MARK: Запись

    private(set) var isRecording = false
    private(set) var recordingTime: TimeInterval = 0
    private(set) var recordingLevel: Double = 0
    private(set) var lastRecording: URL?
    private(set) var isPlayingBack = false
    /// Плашка «сохранено», показывается сразу после остановки.
    var recordingNotice: URL?

    private var recordingTimer: Timer?
    private var playbackTimer: Timer?
    private var player: AVAudioPlayer?

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        guard !isRecording else { return }
        stopPlayback()
        do {
            try audio.startRecording()
            isRecording = true
            recordingTime = 0
            recordingLevel = 0
            recordingNotice = nil
            startRecordingTicker()
        } catch {
            NSLog("GuitarKeys: не удалось начать запись — \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        let url = audio.stopRecording()
        isRecording = false
        recordingLevel = 0
        recordingTimer?.invalidate()
        recordingTimer = nil

        guard let url else { return }
        lastRecording = url
        recordingNotice = url
        // Плашка не должна висеть вечно.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.recordingNotice == url else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.recordingNotice = nil }
        }
    }

    private func startRecordingTicker() {
        recordingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRecording else { return }
                self.recordingTime = self.audio.recordedDuration
                self.recordingLevel = Double(min(1, self.audio.recordingLevel))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        recordingTimer = timer
    }

    // MARK: Прослушивание записи

    func togglePlayback() {
        isPlayingBack ? stopPlayback() : playLastRecording()
    }

    func playLastRecording() {
        guard let url = lastRecording, !isRecording else { return }
        stopPlayback()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            self.player = player
            isPlayingBack = true

            // У AVAudioPlayer делегат требует NSObject, а опрос раз в пятую секунды
            // обходится дешевле отдельного класса ради одного колбэка.
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.player?.isPlaying != true { self.stopPlayback() }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            playbackTimer = timer
        } catch {
            NSLog("GuitarKeys: не удалось воспроизвести запись — \(error.localizedDescription)")
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlayingBack = false
    }

    func revealLastRecording() {
        guard let url = lastRecording else { return }
        FileReveal.reveal(url)
    }

    func openRecordingsFolder() {
        let folder = AudioEngine.recordingsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileReveal.open(folder)
    }

    /// Таймер записи в виде «м:сс».
    var recordingTimeText: String {
        let total = Int(recordingTime)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Настройки звука

    var volume: Double {
        get { preferences.volume }
        set {
            preferences.volume = newValue
            audio.volume = Float(newValue)
        }
    }

    var humanize: Double {
        get { preferences.humanize }
        set {
            preferences.humanize = newValue
            audio.humanize = newValue
        }
    }

    // MARK: Инструмент

    var guitar: GuitarModel { preferences.guitar }

    func selectGuitar(_ kind: GuitarModel.Kind) {
        guard preferences.selectedGuitar != kind else { return }
        preferences.selectedGuitar = kind
        audio.model = preferences.guitar
        // Дать услышать разницу сразу, не заставляя тянуться к клавише.
        strum(direction: .down, muted: false)
    }

    func updateGuitar(_ model: GuitarModel) {
        preferences.guitar = model
        audio.model = model
    }

    func resetGuitar() {
        updateGuitar(GuitarModel.preset(preferences.selectedGuitar))
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = preferences
        let item = DispatchWorkItem { PreferencesStore.save(snapshot) }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }
}
