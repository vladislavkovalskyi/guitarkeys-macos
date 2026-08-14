import AVFoundation
import Observation
import SwiftUI

/// Экран приложения.
enum AppScreen: String, Hashable, CaseIterable, Identifiable, Sendable {
    case play, studio

    var id: String { rawValue }
    var title: String { L.t("screen." + rawValue) }
    var symbolName: String { self == .play ? "guitars.fill" : "square.grid.3x2.fill" }
}

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

    var screen: AppScreen = .play {
        didSet { if screen != .studio { player.stop() } }
    }
    var bindingTarget: BindingTarget?
    var inspectorPad: Pad?
    var showsSettings = false
    var showsGuitarPicker = false
    var showsAbout = false
    /// Окно развёрнуто на весь экран: кнопки окна прячутся, отступ под них не нужен.
    var isFullScreen = false

    private let audio = AudioEngine()
    /// Проигрыватель проектов студии.
    let player: SongPlayer
    #if os(macOS)
    private let keyboard = KeyboardMonitor()
    #endif
    private var saveWorkItem: DispatchWorkItem?
    private var pulseWorkItems: [DispatchWorkItem] = []

    // MARK: Жизненный цикл

    init() {
        player = SongPlayer(audio: audio)

        let prefs = PreferencesStore.load()
        preferences = prefs
        let chord = prefs.pads.first?.chord(in: prefs.key) ?? Chord(root: prefs.key.tonic, quality: .major)
        currentChord = chord
        currentVoicing = ChordLibrary.voicing(for: chord)

        audio.volume = Float(prefs.volume)
        audio.humanize = prefs.humanize
        audio.model = prefs.guitar
        L.language = prefs.language
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

        // В студии клавиатура сначала обслуживает редактор.
        if screen == .studio, handleStudioKey(code, modifiers: modifiers) { return true }

        if let pad = preferences.pad(for: code) {
            pressPad(pad, accented: modifiers.contains(.shift))
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
        releasePad(pad)
        return true
    }

    // MARK: Игра

    /// Аккорд взят: клавишей на маке или пальцем на телефоне.
    func pressPad(_ pad: Pad, accented: Bool = false) {
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

    /// Аккорд отпущен.
    func releasePad(_ pad: Pad) {
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
    private var previewPlayer: AVAudioPlayer?

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        guard !isRecording else { return }
        stopPlayback()
        do {
            try audio.startRecording(format: preferences.recordingFormat)
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
            self.previewPlayer = player
            isPlayingBack = true

            // У AVAudioPlayer делегат требует NSObject, а опрос раз в пятую секунды
            // обходится дешевле отдельного класса ради одного колбэка.
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.previewPlayer?.isPlaying != true { self.stopPlayback() }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            playbackTimer = timer
        } catch {
            NSLog("GuitarKeys: не удалось воспроизвести запись — \(error.localizedDescription)")
        }
    }

    func stopPlayback() {
        previewPlayer?.stop()
        previewPlayer = nil
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

    // MARK: Студия

    var brush: StudioBrush = .strum(direction: .down, muted: false)
    var brushVelocity: Double = 1.0
    var brushFret: Int = 0
    var showsTabs = true
    /// Выделенные такты: ритм и правки применяются сразу ко всем.
    var selectedBars: Set<UUID> = []
    /// Ширина одного деления таймлайна — она же зум.
    var timelineZoom: Double = 30

    func setBeatsPerBar(_ beats: Int) {
        song.beatsPerBar = max(1, min(12, beats))
        song.normalizeBars()
    }

    func setDivision(_ division: Division) {
        song.division = division
        song.normalizeBars()
    }

    func zoom(by delta: Double) {
        timelineZoom = max(16, min(64, timelineZoom + delta))
    }

    /// Горячие клавиши студии. Возвращает true, если нажатие обработано.
    /// Всё, что не разобрали здесь, уходит обычной игре — чтобы можно было
    /// подбирать на слух, не выходя из студии.
    private func handleStudioKey(_ code: UInt16, modifiers: KeyModifiers) -> Bool {
        switch code {
        case KeyCodes.space:
            toggleSongPlayback()
        case KeyCodes.one:   brush = .strum(direction: .down, muted: false)
        case KeyCodes.two:   brush = .strum(direction: .up, muted: false)
        case KeyCodes.three: brush = .strum(direction: .down, muted: true)
        case KeyCodes.four:  brush = .strum(direction: .up, muted: true)
        case KeyCodes.five:  brush = .note
        case KeyCodes.six:   brush = .eraser
        case KeyCodes.l:     player.loops.toggle()
        case KeyCodes.t:     showsTabs.toggle()
        case KeyCodes.m:     metronome.toggle()
        case KeyCodes.escape: clearSelection()
        case KeyCodes.n:     addBar()
        case KeyCodes.leftBracket:  zoom(by: -4)
        case KeyCodes.rightBracket: zoom(by: +4)
        case KeyCodes.comma:  song.bpm = max(40, song.bpm - (modifiers.contains(.shift) ? 10 : 1))
        case KeyCodes.period: song.bpm = min(220, song.bpm + (modifiers.contains(.shift) ? 10 : 1))
        case KeyCodes.arrowUp   where brush.isNote: brushFret = min(24, brushFret + 1)
        case KeyCodes.arrowDown where brush.isNote: brushFret = max(0, brushFret - 1)
        case KeyCodes.arrowRight: brushVelocity = min(1.4, brushVelocity + 0.05)
        case KeyCodes.arrowLeft:  brushVelocity = max(0.25, brushVelocity - 0.05)
        default:
            return false
        }
        return true
    }

    /// Подписи горячих клавиш для подсказки в интерфейсе.
    static let studioShortcuts: [(keys: String, action: String)] = [
        ("␣", "играть / стоп"),
        ("1…4", "удары"),
        ("5", "лад"),
        ("6", "ластик"),
        ("←→", "сила кисти"),
        ("↑↓", "номер лада"),
        ("T", "табы"),
        ("M", "метроном"),
        ("L", "повтор"),
        ("N", "новый такт"),
        (", .", "темп"),
        ("[ ]", "масштаб"),
    ]

    var song: Song {
        get { preferences.song }
        set { preferences.song = newValue }
    }

    /// Инструмент проекта — с учётом правок тембра, сделанных пользователем.
    var songModel: GuitarModel {
        preferences.guitars.first { $0.kind == song.guitar } ?? GuitarModel.preset(song.guitar)
    }

    var isSongPlaying: Bool { player.isPlaying }

    func toggleSongPlayback() {
        player.isPlaying ? player.stop() : player.play(song, model: songModel)
    }

    /// Играть с нужной доли — курсор ставится щелчком по линейке.
    func playFrom(slot: Int) {
        player.play(song, model: songModel, fromSlot: slot)
    }

    var metronome: Bool {
        get { player.metronome }
        set { player.metronome = newValue }
    }

    // MARK: Выделение тактов

    func toggleSelection(_ id: UUID, extend: Bool) {
        if extend {
            if selectedBars.contains(id) { selectedBars.remove(id) } else { selectedBars.insert(id) }
        } else {
            selectedBars = selectedBars == [id] ? [] : [id]
        }
    }

    func selectAllBars() { selectedBars = Set(song.bars.map(\.id)) }
    func clearSelection() { selectedBars.removeAll() }

    /// Индексы выделенного, а если ничего не выбрано — весь проект.
    private func targetBarIndices() -> [Int] {
        let indices = song.bars.indices.filter { selectedBars.contains(song.bars[$0].id) }
        return indices.isEmpty ? Array(song.bars.indices) : indices
    }

    /// Ритм ложится в выделенные такты, а без выделения — во все.
    func applyPatternToSelection(_ pattern: RhythmPattern) {
        guard !song.bars.isEmpty else { return }
        pushUndo()
        adoptGrid(of: pattern)
        let slots = fitted(pattern)
        for index in targetBarIndices() {
            song.bars[index].slots = slots
        }
    }

    func clearSelectedBars() {
        pushUndo()
        for index in targetBarIndices() {
            song.bars[index].slots = Array(repeating: [], count: song.slotsPerBar)
        }
    }

    func removeSelectedBars() {
        let doomed = selectedBars
        guard !doomed.isEmpty, song.bars.count > doomed.count else { return }
        pushUndo()
        song.bars.removeAll { doomed.contains($0.id) }
        selectedBars.removeAll()
    }

    func duplicateSelectedBars() {
        pushUndo()
        for index in targetBarIndices().reversed() {
            var copy = song.bars[index]
            copy.id = UUID()
            song.bars.insert(copy, at: index + 1)
        }
    }

    func stopSongPlayback() {
        player.stop()
    }

    private func valid(bar: Int, slot: Int) -> Bool {
        song.bars.indices.contains(bar) && song.bars[bar].slots.indices.contains(slot)
    }

    /// Поставить или снять событие на доле. Повторный тап тем же — стирает.
    func toggleSlot(bar: Int, slot: Int, event: StepEvent) {
        guard valid(bar: bar, slot: slot) else { return }
        pushUndo()

        if let index = song.bars[bar].slots[slot].firstIndex(where: { $0.matchesKind(of: event) }) {
            song.bars[bar].slots[slot].remove(at: index)
            return
        }
        // Удар на доле может быть только один: два одновременных взмаха невозможны.
        if event.isStrum {
            song.bars[bar].slots[slot].removeAll(where: \.isStrum)
        }
        song.bars[bar].slots[slot].append(event)
        previewSlot(bar: bar, event: event)
    }

    /// Нота табулатуры: одна на струну и долю.
    func setNote(bar: Int, slot: Int, string: Int, fret: Int, velocity: Double = 1) {
        guard valid(bar: bar, slot: slot), (0...24).contains(fret) else { return }
        pushUndo()
        song.bars[bar].slots[slot].removeAll { $0.string == string }
        let event = StepEvent.note(string: string, fret: fret, velocity: velocity)
        song.bars[bar].slots[slot].append(event)
        previewSlot(bar: bar, event: event)
    }

    func clearNote(bar: Int, slot: Int, string: Int) {
        guard valid(bar: bar, slot: slot) else { return }
        pushUndo()
        song.bars[bar].slots[slot].removeAll { $0.string == string }
    }

    func clearSlot(bar: Int, slot: Int) {
        guard valid(bar: bar, slot: slot) else { return }
        pushUndo()
        song.bars[bar].slots[slot].removeAll()
    }

    /// Сила отдельного события — тише или с акцентом.
    func setVelocity(bar: Int, slot: Int, eventID: UUID, velocity: Double) {
        guard valid(bar: bar, slot: slot),
              let index = song.bars[bar].slots[slot].firstIndex(where: { $0.id == eventID })
        else { return }
        song.bars[bar].slots[slot][index].velocity = max(0.25, min(1.4, velocity))
    }

    func setBarView(bar: Int, view: BarView) {
        guard song.bars.indices.contains(bar) else { return }
        song.bars[bar].view = view
    }

    /// Перетаскивание такта на новое место.
    func moveBar(_ draggedID: UUID, before targetID: UUID) {
        pushUndo()
        guard draggedID != targetID,
              let from = song.bars.firstIndex(where: { $0.id == draggedID }),
              let to = song.bars.firstIndex(where: { $0.id == targetID })
        else { return }
        withAnimation(.snappy(duration: 0.28)) {
            let moved = song.bars.remove(at: from)
            song.bars.insert(moved, at: to)
        }
    }

    /// Дать услышать то, что только что поставили, — без запуска всего проекта.
    private func previewSlot(bar: Int, event: StepEvent) {
        guard !player.isPlaying, let chord = song.chord(inBar: bar) else { return }
        let voicing = ChordLibrary.voicing(for: chord)
        let previousModel = audio.model
        audio.model = songModel
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
            audio.strum(voicing: voicing, direction: direction, articulation: articulation)

        case .pluck(let string):
            var articulation = StrumArticulation.normalDown
            articulation.velocity = 0.78 * force
            audio.pluck(string: string, voicing: voicing, articulation: articulation)

        case .note(let string, let fret):
            var articulation = StrumArticulation.normalDown
            articulation.velocity = 0.80 * force
            if let note = StrumScheduler.note(string: string, fret: fret,
                                              articulation: articulation,
                                              model: songModel,
                                              humanize: song.humanize,
                                              origin: audio.currentSample &+ audio.scheduleLead) {
                audio.queue(note)
            }
        }
        audio.model = previousModel
    }

    // MARK: Ритмические рисунки

    /// Положить готовый бой в такт. Сетка при необходимости перестраивается:
    /// «галоп» шестнадцатыми в восьмых просто не поместится.
    func applyPattern(_ pattern: RhythmPattern, toBar index: Int) {
        guard song.bars.indices.contains(index) else { return }
        pushUndo()
        adoptGrid(of: pattern)
        song.bars[index].slots = fitted(pattern)
    }

    func applyPatternToAll(_ pattern: RhythmPattern) {
        guard !song.bars.isEmpty else { return }
        pushUndo()
        adoptGrid(of: pattern)
        let slots = fitted(pattern)
        for index in song.bars.indices {
            song.bars[index].slots = slots
        }
    }

    private func adoptGrid(of pattern: RhythmPattern) {
        if song.beatsPerBar != pattern.beatsPerBar || song.division != pattern.division {
            song.beatsPerBar = pattern.beatsPerBar
            song.division = pattern.division
            song.normalizeBars()
        }
    }

    /// Рисунок мог быть записан под другую сетку — подгоняем длину.
    private func fitted(_ pattern: RhythmPattern) -> [[StepEvent]] {
        var slots = pattern.slots
        let target = song.slotsPerBar
        if slots.count > target {
            slots = Array(slots.prefix(target))
        } else if slots.count < target {
            slots += Array(repeating: [], count: target - slots.count)
        }
        return slots
    }

    // MARK: Отмена и буфер

    private var undoStack: [Song] = []
    private var redoStack: [Song] = []
    private(set) var copiedBar: Bar?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Снимок перед правкой. Проект — значение, поэтому копия дёшева.
    func pushUndo() {
        undoStack.append(song)
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(song)
        player.stop()
        song = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(song)
        player.stop()
        song = next
    }

    func copyBar(at index: Int) {
        guard song.bars.indices.contains(index) else { return }
        copiedBar = song.bars[index]
    }

    func pasteBar(at index: Int) {
        guard let copied = copiedBar, song.bars.indices.contains(index) else { return }
        pushUndo()
        var bar = copied
        bar.id = song.bars[index].id
        bar.resize(to: song.slotsPerBar)
        song.bars[index] = bar
    }

    func setBarChord(bar: Int, source: PadSource) {
        pushUndo()
        guard song.bars.indices.contains(bar) else { return }
        song.bars[bar].chord = source
    }

    func addBar() {
        pushUndo()
        let source = song.bars.last?.chord ?? .degree(index: 0, seventh: false)
        song.bars.append(Bar(chord: source, slots: song.bars.last?.slots))
    }

    func duplicateBar(at index: Int) {
        pushUndo()
        guard song.bars.indices.contains(index) else { return }
        var copy = song.bars[index]
        copy.id = UUID()
        song.bars.insert(copy, at: index + 1)
    }

    func removeBar(at index: Int) {
        pushUndo()
        guard song.bars.count > 1, song.bars.indices.contains(index) else { return }
        song.bars.remove(at: index)
    }

    func clearBar(at index: Int) {
        pushUndo()
        guard song.bars.indices.contains(index) else { return }
        song.bars[index].slots = Array(repeating: [], count: song.slotsPerBar)
    }

    // MARK: Сохранение и сведение

    var isExporting = false
    var exportProgressLabel = ""
    var exportNotice: URL?
    var exportError: String?

    func saveSongProject() {
        do {
            let url = try SongStore.save(song)
            showExportNotice(url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    func loadSongProject(from url: URL) {
        do {
            player.stop()
            song = try SongStore.load(from: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// Сведение идёт быстрее реального времени и в стороне от главного потока,
    /// иначе интерфейс замирал бы на всё время рендеринга.
    func exportSong(format: AudioFileFormat) {
        guard !isExporting else { return }
        player.stop()
        isExporting = true
        exportProgressLabel = "Сведение в \(format.title)…"

        let song = self.song
        let model = self.songModel
        let url = SongExporter.exportURL(for: song, format: format)

        Task.detached(priority: .userInitiated) {
            do {
                let result = try SongExporter.export(song: song, model: model,
                                                     to: url, format: format)
                await MainActor.run {
                    self.isExporting = false
                    self.showExportNotice(result)
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    self.exportError = error.localizedDescription
                }
            }
        }
    }

    private func showExportNotice(_ url: URL) {
        lastRecording = url
        exportNotice = url
        recordingNotice = url
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.recordingNotice == url else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.recordingNotice = nil }
        }
    }

    // MARK: Настройки звука

    var volume: Double {
        get { preferences.volume }
        set {
            preferences.volume = newValue
            audio.volume = Float(newValue)
        }
    }

    /// Язык интерфейса. Меняется без перезапуска.
    var language: Language {
        get { preferences.language }
        set {
            preferences.language = newValue
            L.language = newValue
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
