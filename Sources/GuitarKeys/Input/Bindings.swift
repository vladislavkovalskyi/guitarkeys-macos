import Foundation

/// Что лежит на клавише-аккорде: ступень текущей тональности или жёстко заданный аккорд.
enum PadSource: Codable, Hashable, Sendable {
    case degree(index: Int, seventh: Bool)
    case fixed(Chord)
}

struct Pad: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var keyCode: UInt16
    var source: PadSource

    func chord(in key: MusicalKey) -> Chord {
        switch source {
        case .degree(let index, let seventh): return key.chord(degree: index, seventh: seventh)
        case .fixed(let chord): return chord
        }
    }

    func caption(in key: MusicalKey) -> String {
        switch source {
        case .degree(let index, let seventh): return key.roman(degree: index, seventh: seventh)
        case .fixed: return "фикс."
        }
    }
}

/// Действия правой руки.
enum GuitarAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case strumDown, strumUp, mutedDown, mutedUp, transposeDown, transposeUp

    var id: String { rawValue }

    var title: String { L.t("action." + rawValue) }

    var symbolName: String {
        switch self {
        case .strumDown:     return "arrow.down"
        case .strumUp:       return "arrow.up"
        case .mutedDown:     return "arrow.down.to.line"
        case .mutedUp:       return "arrow.up.to.line"
        case .transposeDown: return "minus"
        case .transposeUp:   return "plus"
        }
    }

    var isStrum: Bool {
        switch self {
        case .strumDown, .strumUp, .mutedDown, .mutedUp: return true
        default: return false
        }
    }
}

struct ActionBinding: Codable, Hashable, Identifiable, Sendable {
    var action: GuitarAction
    var keyCodes: [UInt16]

    var id: String { action.rawValue }
}

/// Полный набор настроек — сохраняется в Application Support.
struct Preferences: Codable, Sendable {
    var key: MusicalKey = MusicalKey(tonic: 0, scale: .major)
    var pads: [Pad] = Preferences.defaultPads
    var actions: [ActionBinding] = Preferences.defaultActions
    var strumSpread: Double = 17          // мс между струнами
    var autoStrumOnPress: Bool = true     // нажал аккорд — сразу звучит удар вниз
    var muteOnRelease: Bool = true        // отпустил — струны глушатся
    var volume: Double = 0.5
    var humanize: Double = 0.5            // насколько неровно играет рука
    /// Клавиши отдельных струн, по гитарной нумерации: первая — самая тонкая.
    var stringKeys: [UInt16] = Preferences.defaultStringKeys
    var selectedGuitar: GuitarModel.Kind = .acoustic
    /// В каком формате писать живую игру.
    var recordingFormat: AudioFileFormat = .m4a
    /// Язык интерфейса; system — брать из системы.
    var language: Language = .system
    /// Текущий проект студии, чтобы он не терялся между запусками.
    var song: Song = Song()
    /// Правки тембра хранятся отдельно для каждого инструмента.
    var guitars: [GuitarModel] = GuitarModel.presets

    var guitar: GuitarModel {
        get { guitars.first { $0.kind == selectedGuitar } ?? GuitarModel.preset(selectedGuitar) }
        set {
            selectedGuitar = newValue.kind
            if let index = guitars.firstIndex(where: { $0.kind == newValue.kind }) {
                guitars[index] = newValue
            } else {
                guitars.append(newValue)
            }
        }
    }

    init() {}

    /// Читаем по одному полю: файл, записанный прошлой версией, не должен обнулять
    /// все настройки только потому, что в нём нет нового ключа.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Preferences()
        key = try container.decodeIfPresent(MusicalKey.self, forKey: .key) ?? fallback.key
        pads = try container.decodeIfPresent([Pad].self, forKey: .pads) ?? fallback.pads
        actions = try container.decodeIfPresent([ActionBinding].self, forKey: .actions) ?? fallback.actions
        strumSpread = try container.decodeIfPresent(Double.self, forKey: .strumSpread) ?? fallback.strumSpread
        autoStrumOnPress = try container.decodeIfPresent(Bool.self, forKey: .autoStrumOnPress) ?? fallback.autoStrumOnPress
        muteOnRelease = try container.decodeIfPresent(Bool.self, forKey: .muteOnRelease) ?? fallback.muteOnRelease
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? fallback.volume
        humanize = try container.decodeIfPresent(Double.self, forKey: .humanize) ?? fallback.humanize
        stringKeys = try container.decodeIfPresent([UInt16].self, forKey: .stringKeys) ?? fallback.stringKeys
        if stringKeys.count != 6 { stringKeys = fallback.stringKeys }
        selectedGuitar = try container.decodeIfPresent(GuitarModel.Kind.self, forKey: .selectedGuitar) ?? fallback.selectedGuitar
        guitars = try container.decodeIfPresent([GuitarModel].self, forKey: .guitars) ?? fallback.guitars
        recordingFormat = try container.decodeIfPresent(AudioFileFormat.self, forKey: .recordingFormat) ?? fallback.recordingFormat
        language = try container.decodeIfPresent(Language.self, forKey: .language) ?? fallback.language
        // Проект читаем отдельно и мягко: его формат меняется чаще прочих настроек,
        // и несовместимый проект не должен утаскивать за собой привязки клавиш.
        song = ((try? container.decodeIfPresent(Song.self, forKey: .song)) ?? nil) ?? fallback.song

        // На случай, если в файле не хватает какого-то инструмента.
        for preset in GuitarModel.presets where !guitars.contains(where: { $0.kind == preset.kind }) {
            guitars.append(preset)
        }
    }

    static let defaultPads: [Pad] = {
        let triadKeys: [UInt16] = [KeyCodes.a, KeyCodes.s, KeyCodes.d, KeyCodes.f,
                                   KeyCodes.g, KeyCodes.h, KeyCodes.j]
        let seventhKeys: [UInt16] = [KeyCodes.q, KeyCodes.w, KeyCodes.e, KeyCodes.r,
                                     KeyCodes.t, KeyCodes.y, KeyCodes.u]
        var pads: [Pad] = []
        for (degree, code) in seventhKeys.enumerated() {
            pads.append(Pad(keyCode: code, source: .degree(index: degree, seventh: true)))
        }
        for (degree, code) in triadKeys.enumerated() {
            pads.append(Pad(keyCode: code, source: .degree(index: degree, seventh: false)))
        }
        return pads
    }()

    /// Цифровой ряд: 1 — тонкая, 6 — басовая. Ровно как считают струны гитаристы.
    static let defaultStringKeys: [UInt16] = [
        KeyCodes.one, KeyCodes.two, KeyCodes.three,
        KeyCodes.four, KeyCodes.five, KeyCodes.six,
    ]

    /// Индекс струны в синтезаторе (0 — низкая ми) по нажатой клавише.
    /// Гитарная нумерация обратна внутренней, поэтому переворачиваем.
    func stringIndex(for keyCode: UInt16) -> Int? {
        guard let number = stringKeys.firstIndex(of: keyCode) else { return nil }
        return 5 - number
    }

    /// Клавиша, назначенная струне с внутренним индексом (0 — низкая ми).
    func stringKey(forStringIndex index: Int) -> UInt16? {
        let number = 5 - index
        guard stringKeys.indices.contains(number) else { return nil }
        let code = stringKeys[number]
        return code == 0xFFFF ? nil : code
    }

    static let defaultActions: [ActionBinding] = [
        ActionBinding(action: .strumDown, keyCodes: [KeyCodes.arrowDown, KeyCodes.space]),
        ActionBinding(action: .strumUp, keyCodes: [KeyCodes.arrowUp]),
        ActionBinding(action: .mutedDown, keyCodes: [KeyCodes.arrowLeft]),
        ActionBinding(action: .mutedUp, keyCodes: [KeyCodes.arrowRight]),
        ActionBinding(action: .transposeDown, keyCodes: [KeyCodes.leftBracket]),
        ActionBinding(action: .transposeUp, keyCodes: [KeyCodes.rightBracket]),
    ]

    func action(for keyCode: UInt16) -> GuitarAction? {
        actions.first { $0.keyCodes.contains(keyCode) }?.action
    }

    func pad(for keyCode: UInt16) -> Pad? {
        pads.first { $0.keyCode == keyCode }
    }

    func keyCodes(for action: GuitarAction) -> [UInt16] {
        actions.first { $0.action == action }?.keyCodes ?? []
    }
}

extension Array where Element == Pad {
    /// Переставляет содержимое пэдов, оставляя привязки клавиш на своих позициях:
    /// аккорды переезжают, ряд под пальцами остаётся A S D F G H J.
    mutating func moveChord(from draggedID: UUID, to targetID: UUID) {
        guard draggedID != targetID,
              let from = firstIndex(where: { $0.id == draggedID }),
              let to = firstIndex(where: { $0.id == targetID })
        else { return }

        var sources = map(\.source)
        let moved = sources.remove(at: from)
        sources.insert(moved, at: to)
        for index in indices {
            self[index].source = sources[index]
        }
    }
}

/// Чтение и запись настроек: ~/Library/Application Support/GuitarKeys/preferences.json
enum PreferencesStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("GuitarKeys", isDirectory: true)
                   .appendingPathComponent("preferences.json")
    }

    static func load() -> Preferences {
        guard let data = try? Data(contentsOf: fileURL),
              let prefs = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return prefs
    }

    static func save(_ preferences: Preferences) {
        let url = fileURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(preferences).write(to: url, options: .atomic)
        } catch {
            NSLog("GuitarKeys: не удалось сохранить настройки — \(error.localizedDescription)")
        }
    }
}
