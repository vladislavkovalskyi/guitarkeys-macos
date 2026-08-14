import Foundation

enum Language: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, ru, en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Auto"
        case .ru:     return "Русский"
        case .en:     return "English"
        }
    }
}

/// Локализация словарями прямо в коде.
///
/// Приложение собирается вызовом `swiftc` без Xcode, поэтому каталоги `.lproj`
/// пришлось бы собирать и подкладывать вручную. Словарь в коде проще, полноту
/// перевода проверяет тест, а язык переключается без перезапуска.
///
/// Читают строки все слои, включая модели, поэтому тип не привязан к главному
/// потоку. Язык меняется только из интерфейса и только при явном выборе.
enum L {

    nonisolated(unsafe) static var language: Language = .system {
        didSet { resolve() }
    }

    nonisolated(unsafe) private static var active: [String: String] = ru

    /// Системный язык, если пользователь не выбрал явно.
    private static func resolve() {
        switch language {
        case .ru: active = ru
        case .en: active = en
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            active = preferred.hasPrefix("ru") ? ru : en
        }
    }

    static func callAsFunction(_ key: String) -> String { t(key) }

    /// Перевод по ключу. Не нашли — возвращаем ключ: пропажа сразу видна.
    static func t(_ key: String) -> String {
        active[key] ?? ru[key] ?? key
    }

    static func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), arguments: arguments)
    }

    static var allKeys: Set<String> { Set(ru.keys) }
    static func dictionary(for language: Language) -> [String: String] {
        language == .en ? en : ru
    }

    // MARK: Русский

    static let ru: [String: String] = [
        // Экраны
        "screen.play": "Игра",
        "screen.studio": "Студия",

        // Шапка
        "header.instrument": "Инструмент и тембр",
        "header.settings": "Настройки и привязки клавиш",
        "header.keyDown": "Понизить тональность",
        "header.keyUp": "Повысить тональность",
        "scale.major": "мажор",
        "scale.minor": "минор",

        // Игра
        "play.hint.chord": "аккорд",
        "play.hint.chordValue": "удерживайте клавишу",
        "play.hint.strum": "бой",
        "play.hint.strings": "струны",
        "play.hint.stringsValue": "1…6 или мышью по грифу",
        "play.hint.mute": "глушение",
        "play.hint.key": "тональность",
        "play.autoStrumOn": "звучит\nпри нажатии",
        "play.autoStrumOff": "молчит\nдо удара",
        "play.autoStrumHelpOn": "Аккорд звучит сразу при нажатии клавиши. Выключите, чтобы зажимать аккорд молча и играть бой самому",
        "play.autoStrumHelpOff": "Клавиша только зажимает аккорд. Ритм — стрелками или по струнам",
        "play.open": "открытый",
        "play.muted": "глушение",
        "play.record": "запись",
        "play.recording": "идёт",
        "play.recordStart": "Записать игру в файл",
        "play.recordStop": "Остановить запись",
        "play.recordingsFolder": "Папка с записями",
        "play.revealLast": "Показать последнюю запись",
        "play.pressKey": "Нажмите клавишу",
        "play.cancelHint": "Esc — отмена",
        "play.configureChord": "Настроить аккорд…",
        "play.assignKey": "Назначить клавишу",
        "play.fretboard": "Гриф, аккорд %@. Щёлкните по струне, чтобы дёрнуть её",

        // Студия
        "studio.play": "Играть",
        "studio.stop": "Стоп",
        "studio.loop": "Повторять по кругу (L)",
        "studio.metronome": "Метроном (M)",
        "studio.tempo": "темп",
        "studio.meter": "размер",
        "studio.grid": "сетка",
        "studio.rhythm": "Ритм",
        "studio.rhythmAll": "Положить готовый бой во все такты",
        "studio.rhythmSelection": "Положить бой в выделенные такты",
        "studio.save": "Сохранить проект",
        "studio.export": "Свести",
        "studio.exporting": "Сведение…",
        "studio.exportSection": "Свести в файл",
        "studio.addBar": "Такт",
        "studio.bar": "такт",
        "studio.chord": "аккорд",
        "studio.strumTrack": "бой",
        "studio.tabs": "табы",
        "studio.tabsHelp": "Показать табулатуру (T)",
        "studio.zoom": "Масштаб таймлайна ([ ])",
        "studio.fret": "лад",
        "studio.eraser": "Ластик",
        "studio.selected": "выделено: %d",
        "studio.deselect": "снять",
        "studio.selectBar": "Выделить такт",
        "studio.degreeSection": "Ступень тональности",
        "studio.anyChord": "Любой аккорд",
        "studio.barRhythm": "Ритм такта",
        "studio.copyBar": "Копировать такт",
        "studio.pasteBar": "Вставить в этот такт",
        "studio.duplicateBar": "Продублировать такт",
        "studio.clearBar": "Очистить такт",
        "studio.deleteBar": "Удалить такт",
        "studio.brushHintNote": "в табах ставится этот лад · тяга по ячейке перебирает лады",
        "studio.brushHintChord": "в табах тап ставит ноту аккорда · сила — тягой по ячейке",
        "studio.duration": "%d такта · %d:%02d",
        "studio.stringSilent": "Струна %d в этом аккорде не звучит",
        "studio.fretManual": "Струна %d, лад %d — задан вручную",
        "studio.fretFromChord": "Струна %d, лад %d — из аккорда",
        "studio.string": "Струна %d",
        "studio.force": "Сила %d%%",

        // Настройки
        "settings.sound": "Звук",
        "settings.volume": "Громкость",
        "settings.spread": "Разброс боя",
        "settings.humanize": "Живая рука",
        "settings.humanizeHint": "Живая рука делает каждый удар чуть другим: сила, тайминг, строй и место щипка. На нуле — механически ровно.",
        "settings.playing": "Игра",
        "settings.autoStrum": "Удар вниз при нажатии аккорда",
        "settings.muteOnRelease": "Глушить струны при отпускании",
        "settings.rightHandKeys": "Клавиши правой руки",
        "settings.recordFormat": "Формат записи",
        "settings.stringKeys": "Клавиши струн",
        "settings.stringKeysHint": "Струна 1 — самая тонкая. По грифу можно бить и мышью: проводка через несколько струн играется как бой.",
        "settings.contextHint": "Правый клик по любой клавише — настроить аккорд.",
        "settings.reset": "Сбросить",
        "settings.assign": "назначить",
        "settings.language": "Язык",

        // Инструмент
        "guitar.timbre": "Тембр",
        "guitar.brightness": "Яркость",
        "guitar.brightnessHint": "мягко ↔ звонко",
        "guitar.sustain": "Сустейн",
        "guitar.sustainHint": "как долго тянется струна",
        "guitar.pick": "Медиатор",
        "guitar.pickHint": "у бриджа ↔ у грифа",
        "guitar.body": "Корпус",
        "guitar.bodyHint": "гулкость деки",
        "guitar.room": "Помещение",
        "guitar.drive": "Перегруз",
        "guitar.reset": "Вернуть заводской",
        "guitar.classical": "Классика",
        "guitar.acoustic": "Акустика",
        "guitar.electric": "Электро",
        "guitar.classicalHint": "нейлон, мягкая атака",
        "guitar.acousticHint": "сталь, звонкий корпус",
        "guitar.electricHint": "звукосниматель, длинный сустейн",

        // Запись
        "record.saved": "Записано",
        "record.listen": "Прослушать",
        "record.stopPlayback": "Стоп",
        "record.reveal": "Показать",

        // Форматы
        "format.m4a": "сжатый, компактный — чтобы отправить",
        "format.wav": "без потерь, 24 бита — для монтажа",
        "format.aiff": "без потерь, для программ Apple",
        "format.caf": "без потерь, без ограничения длины",

        // Меню
        "menu.game": "Игра",
        "menu.strumDown": "Удар вниз",
        "menu.strumUp": "Удар вверх",
        "menu.keyUp": "Тональность выше",
        "menu.keyDown": "Тональность ниже",
        "menu.record": "Записать игру",
        "menu.recordStop": "Остановить запись",
        "menu.resetBindings": "Сбросить привязки",
        "menu.studio": "Студия",
        "menu.playStop": "Играть или стоп",
        "menu.metronomeOn": "Включить метроном",
        "menu.metronomeOff": "Выключить метроном",
        "menu.selectAll": "Выделить все такты",
        "menu.deselect": "Снять выделение",
        "menu.duplicate": "Продублировать",
        "menu.clearBars": "Очистить такты",
        "menu.deleteBars": "Удалить такты",
        "menu.undo": "Отменить",
        "menu.redo": "Повторить",
        "menu.about": "О программе",

        // О программе
        "about.subtitle": "Гитара на клавиатуре MacBook",
        "about.author": "Автор",
        "about.github": "GitHub",
        "about.telegram": "Telegram",
        "about.version": "Версия %@",
        "about.madeWith": "Звук считается физической моделью струны в реальном времени. Сэмплов нет.",

        // Ритмы
        "rhythm.strumming": "Бой",
        "rhythm.picking": "Перебор",
        "rhythm.waltz": "Трёхдольные",
        "rhythm.eight": "Восьмёрка",
        "rhythm.eightHint": "вниз-вверх на каждую восьмую",
        "rhythm.eightMuted": "Восьмёрка с глушением",
        "rhythm.eightMutedHint": "та же, но слабые доли приглушены",
        "rhythm.six": "Шестёрка",
        "rhythm.sixHint": "вниз, вниз-вверх, вверх-вниз-вверх",
        "rhythm.four": "Четвёрка",
        "rhythm.fourHint": "ровные удары вниз по долям",
        "rhythm.gallop": "Галоп",
        "rhythm.gallopHint": "шестнадцатыми, с оттяжкой",
        "rhythm.offbeat": "Офбит",
        "rhythm.offbeatHint": "акцент на слабую долю, как в регги",
        "rhythm.pick4": "Перебор четвёркой",
        "rhythm.pick4Hint": "бас и три струны вверх",
        "rhythm.pick6": "Перебор шестёркой",
        "rhythm.pick6Hint": "бас, вверх и обратно",
        "rhythm.pick8": "Восьмёрка перебором",
        "rhythm.pick8Hint": "ровная россыпь по струнам",
        "rhythm.waltzBasic": "Вальс",
        "rhythm.waltzBasicHint": "бас и два удара вверх",
        "rhythm.waltzPick": "Вальс перебором",
        "rhythm.waltzPickHint": "бас и раскладка по струнам",

        // Сетка
        "division.quarter": "1/4",
        "division.eighth": "1/8",
        "division.triplet": "триоли",
        "division.sixteenth": "1/16",

        // Аккорды
        "chords.triads": "Простые",
        "chords.sevenths": "Септаккорды",
        "chords.suspended": "Sus и квинты",
        "chords.colour": "Сложные",

        // Действия правой руки
        "action.strumDown": "Удар вниз",
        "action.strumUp": "Удар вверх",
        "action.mutedDown": "Глушёный вниз",
        "action.mutedUp": "Глушёный вверх",
        "action.transposeDown": "Тональность −1",
        "action.transposeUp": "Тональность +1",

        // Подсказки клавиш
        "hint.playStop": "играть / стоп",
        "hint.strikes": "удары",
        "hint.fret": "лад",
        "hint.eraser": "ластик",
        "hint.brushForce": "сила кисти",
        "hint.fretNumber": "номер лада",
        "hint.tabs": "табы",
        "hint.metronome": "метроном",
        "hint.loop": "повтор",
        "hint.newBar": "новый такт",
        "hint.tempo": "темп",
        "hint.zoom": "масштаб",
    ]

    // MARK: English

    static let en: [String: String] = [
        "screen.play": "Play",
        "screen.studio": "Studio",

        "header.instrument": "Instrument and tone",
        "header.settings": "Settings and key bindings",
        "header.keyDown": "Transpose down",
        "header.keyUp": "Transpose up",
        "scale.major": "major",
        "scale.minor": "minor",

        "play.hint.chord": "chord",
        "play.hint.chordValue": "hold the key",
        "play.hint.strum": "strum",
        "play.hint.strings": "strings",
        "play.hint.stringsValue": "1…6 or drag across the fretboard",
        "play.hint.mute": "muting",
        "play.hint.key": "key",
        "play.autoStrumOn": "sounds\non key press",
        "play.autoStrumOff": "silent\nuntil strum",
        "play.autoStrumHelpOn": "The chord sounds the moment you press a key. Turn off to hold chords silently and strum yourself",
        "play.autoStrumHelpOff": "A key only holds the shape. Rhythm is up to the arrow keys or the strings",
        "play.open": "open",
        "play.muted": "muted",
        "play.record": "record",
        "play.recording": "running",
        "play.recordStart": "Record your playing to a file",
        "play.recordStop": "Stop recording",
        "play.recordingsFolder": "Recordings folder",
        "play.revealLast": "Reveal last recording",
        "play.pressKey": "Press a key",
        "play.cancelHint": "Esc to cancel",
        "play.configureChord": "Edit chord…",
        "play.assignKey": "Assign a key",
        "play.fretboard": "Fretboard, chord %@. Click a string to pluck it",

        "studio.play": "Play",
        "studio.stop": "Stop",
        "studio.loop": "Loop (L)",
        "studio.metronome": "Metronome (M)",
        "studio.tempo": "tempo",
        "studio.meter": "meter",
        "studio.grid": "grid",
        "studio.rhythm": "Rhythm",
        "studio.rhythmAll": "Apply a rhythm to every bar",
        "studio.rhythmSelection": "Apply a rhythm to selected bars",
        "studio.save": "Save project",
        "studio.export": "Bounce",
        "studio.exporting": "Bouncing…",
        "studio.exportSection": "Bounce to a file",
        "studio.addBar": "Bar",
        "studio.bar": "bar",
        "studio.chord": "chord",
        "studio.strumTrack": "strum",
        "studio.tabs": "tabs",
        "studio.tabsHelp": "Show tablature (T)",
        "studio.zoom": "Timeline zoom ([ ])",
        "studio.fret": "fret",
        "studio.eraser": "Eraser",
        "studio.selected": "selected: %d",
        "studio.deselect": "clear",
        "studio.selectBar": "Select bar",
        "studio.degreeSection": "Scale degree",
        "studio.anyChord": "Any chord",
        "studio.barRhythm": "Bar rhythm",
        "studio.copyBar": "Copy bar",
        "studio.pasteBar": "Paste into this bar",
        "studio.duplicateBar": "Duplicate bar",
        "studio.clearBar": "Clear bar",
        "studio.deleteBar": "Delete bar",
        "studio.brushHintNote": "tabs get this fret · drag a cell to walk the frets",
        "studio.brushHintChord": "tabs get the chord note · drag a cell for velocity",
        "studio.duration": "%d bars · %d:%02d",
        "studio.stringSilent": "String %d is muted in this chord",
        "studio.fretManual": "String %d, fret %d — set by hand",
        "studio.fretFromChord": "String %d, fret %d — from the chord",
        "studio.string": "String %d",
        "studio.force": "Velocity %d%%",

        "settings.sound": "Sound",
        "settings.volume": "Volume",
        "settings.spread": "Strum spread",
        "settings.humanize": "Human hand",
        "settings.humanizeHint": "A human hand makes every strum slightly different: force, timing, tuning and pick spot. At zero it is machine-even.",
        "settings.playing": "Playing",
        "settings.autoStrum": "Strum down when a chord key is pressed",
        "settings.muteOnRelease": "Mute strings on key release",
        "settings.rightHandKeys": "Right hand keys",
        "settings.recordFormat": "Recording format",
        "settings.stringKeys": "String keys",
        "settings.stringKeysHint": "String 1 is the thinnest. You can also strum with the mouse: dragging across strings plays them in order.",
        "settings.contextHint": "Right-click any pad to edit its chord.",
        "settings.reset": "Reset",
        "settings.assign": "assign",
        "settings.language": "Language",

        "guitar.timbre": "Tone",
        "guitar.brightness": "Brightness",
        "guitar.brightnessHint": "mellow ↔ bright",
        "guitar.sustain": "Sustain",
        "guitar.sustainHint": "how long a string rings",
        "guitar.pick": "Pick",
        "guitar.pickHint": "bridge ↔ neck",
        "guitar.body": "Body",
        "guitar.bodyHint": "resonance of the top",
        "guitar.room": "Room",
        "guitar.drive": "Drive",
        "guitar.reset": "Restore factory",
        "guitar.classical": "Classical",
        "guitar.acoustic": "Acoustic",
        "guitar.electric": "Electric",
        "guitar.classicalHint": "nylon, soft attack",
        "guitar.acousticHint": "steel, ringing body",
        "guitar.electricHint": "pickup, long sustain",

        "record.saved": "Recorded",
        "record.listen": "Listen",
        "record.stopPlayback": "Stop",
        "record.reveal": "Reveal",

        "format.m4a": "compressed, small — easy to send",
        "format.wav": "lossless, 24-bit — for editing",
        "format.aiff": "lossless, for Apple software",
        "format.caf": "lossless, no length limit",

        "menu.game": "Play",
        "menu.strumDown": "Strum down",
        "menu.strumUp": "Strum up",
        "menu.keyUp": "Transpose up",
        "menu.keyDown": "Transpose down",
        "menu.record": "Record playing",
        "menu.recordStop": "Stop recording",
        "menu.resetBindings": "Reset bindings",
        "menu.studio": "Studio",
        "menu.playStop": "Play or stop",
        "menu.metronomeOn": "Turn metronome on",
        "menu.metronomeOff": "Turn metronome off",
        "menu.selectAll": "Select all bars",
        "menu.deselect": "Deselect",
        "menu.duplicate": "Duplicate",
        "menu.clearBars": "Clear bars",
        "menu.deleteBars": "Delete bars",
        "menu.undo": "Undo",
        "menu.redo": "Redo",
        "menu.about": "About GuitarKeys",

        "about.subtitle": "A guitar on your MacBook keyboard",
        "about.author": "Author",
        "about.github": "GitHub",
        "about.telegram": "Telegram",
        "about.version": "Version %@",
        "about.madeWith": "The sound is a physical string model computed in real time. No samples.",

        "rhythm.strumming": "Strumming",
        "rhythm.picking": "Fingerpicking",
        "rhythm.waltz": "Triple meter",
        "rhythm.eight": "Eights",
        "rhythm.eightHint": "down-up on every eighth",
        "rhythm.eightMuted": "Eights with muting",
        "rhythm.eightMutedHint": "same, but offbeats are damped",
        "rhythm.six": "Sixes",
        "rhythm.sixHint": "down, down-up, up-down-up",
        "rhythm.four": "Fours",
        "rhythm.fourHint": "even downstrokes on the beat",
        "rhythm.gallop": "Gallop",
        "rhythm.gallopHint": "sixteenths with a swing",
        "rhythm.offbeat": "Offbeat",
        "rhythm.offbeatHint": "accent on the upbeat, reggae style",
        "rhythm.pick4": "Four-finger picking",
        "rhythm.pick4Hint": "bass and three strings up",
        "rhythm.pick6": "Six-finger picking",
        "rhythm.pick6Hint": "bass, up and back",
        "rhythm.pick8": "Eight-note picking",
        "rhythm.pick8Hint": "an even run across the strings",
        "rhythm.waltzBasic": "Waltz",
        "rhythm.waltzBasicHint": "bass and two upstrokes",
        "rhythm.waltzPick": "Picked waltz",
        "rhythm.waltzPickHint": "bass and a run across strings",

        "division.quarter": "1/4",
        "division.eighth": "1/8",
        "division.triplet": "triplets",
        "division.sixteenth": "1/16",

        "chords.triads": "Simple",
        "chords.sevenths": "Sevenths",
        "chords.suspended": "Sus and fifths",
        "chords.colour": "Extended",

        "action.strumDown": "Strum down",
        "action.strumUp": "Strum up",
        "action.mutedDown": "Muted down",
        "action.mutedUp": "Muted up",
        "action.transposeDown": "Key −1",
        "action.transposeUp": "Key +1",

        "hint.playStop": "play / stop",
        "hint.strikes": "strums",
        "hint.fret": "fret",
        "hint.eraser": "eraser",
        "hint.brushForce": "brush force",
        "hint.fretNumber": "fret number",
        "hint.tabs": "tabs",
        "hint.metronome": "metronome",
        "hint.loop": "loop",
        "hint.newBar": "new bar",
        "hint.tempo": "tempo",
        "hint.zoom": "zoom",
    ]
}
