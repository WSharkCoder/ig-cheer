import Foundation
import Combine
import CryptoKit
import Security

// MARK: - App paths

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("IGCheer", isDirectory: true)
    }

    static var modelsURL: URL { supportDirectory.appendingPathComponent("models.json") }
    static var cheerURL: URL {
        if let custom = ProcessInfo.processInfo.environment["IG_CHEER_DATA"],
           !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return supportDirectory.appendingPathComponent("cheer.json")
    }
    static var scheduleURL: URL {
        if let custom = ProcessInfo.processInfo.environment["IG_CHEER_SCHEDULE"],
           !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return supportDirectory.appendingPathComponent("schedule.json")
    }
    static var predictionsURL: URL { supportDirectory.appendingPathComponent("predictions.json") }

    static func ensureSupportDirectory() {
        try? FileManager.default.createDirectory(at: supportDirectory,
                                                 withIntermediateDirectories: true)
    }
}

enum AppClock {
    /// Preview/testing hook only. Normal launches use the wall clock.
    static var now: Date {
        if let raw = ProcessInfo.processInfo.environment["IG_CHEER_NOW"],
           let date = ISO8601.date(raw) {
            return date
        }
        return Date()
    }
}

// MARK: - Secret storage
//
// The API key ciphertext lives in models.json. The 256-bit AES-GCM master key
// lives in the macOS Keychain, never in the JSON file. Replacing models.json
// cannot expose a usable key without Keychain access.

enum SecretBoxError: LocalizedError {
    case keychain(OSStatus)
    case invalidCiphertext
    case cryptoFailed

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "无法访问钥匙串（OSStatus \(status)）。API Key 没有被保存。"
        case .invalidCiphertext:
            return "加密后的 Key 格式无效。"
        case .cryptoFailed:
            return "加密或解密失败。"
        }
    }
}

enum SecretBox {
    private static let service = "com.wsharkcoder.igcheer.model-keys"
    private static let account = "master-key-v1"
    private static let prefix = "v1."

    static func encrypt(_ plaintext: String) throws -> String {
        let key = try masterKey()
        guard let sealed = try? AES.GCM.seal(Data(plaintext.utf8), using: key),
              let combined = sealed.combined else {
            throw SecretBoxError.cryptoFailed
        }
        return prefix + combined.base64EncodedString()
    }

    static func decrypt(_ encoded: String) throws -> String {
        guard encoded.hasPrefix(prefix) else { throw SecretBoxError.invalidCiphertext }
        let base64 = String(encoded.dropFirst(prefix.count))
        guard let data = Data(base64Encoded: base64),
              let box = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(box, using: try masterKey()),
              let text = String(data: opened, encoding: .utf8) else {
            throw SecretBoxError.invalidCiphertext
        }
        return text
    }

    private static func masterKey() throws -> SymmetricKey {
        let data = try loadOrCreateKeyData()
        guard data.count == 32 else { throw SecretBoxError.cryptoFailed }
        return SymmetricKey(data: data)
    }

    private static func keychainQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }

    private static func loadOrCreateKeyData() throws -> Data {
        var query = keychainQuery()
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return data
        }
        guard status == errSecItemNotFound else {
            throw SecretBoxError.keychain(status)
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        var add = keychainQuery()
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // A racing first launch created it; read the winner.
            var retry = keychainQuery()
            retry[kSecReturnData] = true
            retry[kSecMatchLimit] = kSecMatchLimitOne
            var retryItem: CFTypeRef?
            let retryStatus = SecItemCopyMatching(retry as CFDictionary, &retryItem)
            if retryStatus == errSecSuccess, let retryData = retryItem as? Data {
                return retryData
            }
            throw SecretBoxError.keychain(retryStatus)
        }
        guard addStatus == errSecSuccess else {
            throw SecretBoxError.keychain(addStatus)
        }
        return data
    }
}

// MARK: - Models

enum ModelAPIFormat: String, Codable, CaseIterable {
    case openai
    case anthropic

    var title: String {
        switch self {
        case .openai: return "OpenAI 兼容"
        case .anthropic: return "Anthropic Messages"
        }
    }

    var shortTitle: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .anthropic: return "claude-sonnet-4-5"
        }
    }

    var chatPath: String {
        switch self {
        case .openai: return "/chat/completions"
        case .anthropic: return "/messages"
        }
    }
}

struct ModelConfig: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var model: String
    var baseURL: String
    var encryptedKey: String?
    var enabled: Bool
    var apiFormat: ModelAPIFormat

    init(id: String,
         name: String,
         model: String,
         baseURL: String,
         encryptedKey: String? = nil,
         enabled: Bool = true,
         apiFormat: ModelAPIFormat = .openai) {
        self.id = id
        self.name = name
        self.model = model
        self.baseURL = baseURL
        self.encryptedKey = encryptedKey
        self.enabled = enabled
        self.apiFormat = apiFormat
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, model, baseURL, encryptedKey, enabled, apiFormat
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        model = try container.decode(String.self, forKey: .model)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        encryptedKey = try container.decodeIfPresent(String.self, forKey: .encryptedKey)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        // Older models.json files have no apiFormat; they were all
        // OpenAI-compatible before this field was introduced.
        apiFormat = try container.decodeIfPresent(ModelAPIFormat.self, forKey: .apiFormat) ?? .openai
    }

    var hasKey: Bool {
        guard let key = encryptedKey else { return false }
        return !key.isEmpty
    }

    /// Trim a pasted full endpoint down to a base URL, then ensure the
    /// provider's version segment exists exactly once.
    private var normalizedBase: String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["/chat/completions", "/messages", "/models"] where value.hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count))
            break
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if value.isEmpty { return "" }
        if value.hasSuffix("/v1") || value.contains("/v1/") {
            return value
        }
        return value + "/v1"
    }

    var endpoint: URL? {
        let base = normalizedBase
        guard !base.isEmpty else { return nil }
        return URL(string: base + apiFormat.chatPath)
    }

    var modelsEndpoint: URL? {
        let base = normalizedBase
        guard !base.isEmpty else { return nil }
        return URL(string: base + "/models")
    }
}

private struct ModelConfigFile: Codable {
    var version: Int
    var activeModelID: String?
    var models: [ModelConfig]
}

final class ModelStore: ObservableObject {
    static let shared = ModelStore()

    @Published private(set) var models: [ModelConfig] = []
    @Published private(set) var activeModelID: String = ""

    private var keyCache: [String: String] = [:]
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private init() {
        load()
    }

    var activeModel: ModelConfig? {
        models.first(where: { $0.id == activeModelID })
            ?? models.first(where: { $0.enabled })
            ?? models.first
    }

    func load() {
        AppPaths.ensureSupportDirectory()
        let defaults = Self.defaultModels
        guard let data = try? Data(contentsOf: AppPaths.modelsURL),
              let file = try? JSONDecoder().decode(ModelConfigFile.self, from: data) else {
            models = defaults
            activeModelID = defaults.first?.id ?? ""
            save()
            return
        }
        models = file.models.isEmpty ? defaults : file.models
        activeModelID = file.activeModelID.flatMap { id in
            models.contains(where: { $0.id == id }) ? id : nil
        } ?? models.first?.id ?? ""
    }

    func save() {
        AppPaths.ensureSupportDirectory()
        let file = ModelConfigFile(version: 1, activeModelID: activeModelID, models: models)
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: AppPaths.modelsURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: AppPaths.modelsURL.path)
    }

    func setActive(_ id: String) {
        guard models.contains(where: { $0.id == id }) else { return }
        activeModelID = id
        save()
    }

    @discardableResult
    func addModel() -> ModelConfig {
        let model = ModelConfig(id: UUID().uuidString,
                                name: "新模型",
                                model: "",
                                baseURL: "https://api.openai.com/v1",
                                encryptedKey: nil,
                                enabled: true,
                                apiFormat: .openai)
        models.append(model)
        save()
        return model
    }

    /// `keyDraft == nil` keeps an existing key; an empty string removes it.
    func update(id: String,
                name: String,
                model: String,
                baseURL: String,
                apiFormat: ModelAPIFormat = .openai,
                keyDraft: String?) throws {
        guard let index = models.firstIndex(where: { $0.id == id }) else { return }
        var updated = models[index]
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.apiFormat = apiFormat
        if updated.name.isEmpty { updated.name = "未命名模型" }
        if let keyDraft {
            if keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated.encryptedKey = nil
                keyCache.removeValue(forKey: id)
            } else {
                updated.encryptedKey = try SecretBox.encrypt(keyDraft)
                keyCache[id] = keyDraft
            }
        }
        models[index] = updated
        save()
    }

    func delete(id: String) throws {
        models.removeAll { $0.id == id }
        keyCache.removeValue(forKey: id)
        if models.isEmpty {
            let fallback = Self.defaultModels[0]
            models = [fallback]
            activeModelID = fallback.id
        } else if activeModelID == id {
            activeModelID = models.first?.id ?? ""
        }
        save()
    }

    func apiKey(for model: ModelConfig) throws -> String? {
        if let cached = keyCache[model.id] { return cached.isEmpty ? nil : cached }
        guard let encrypted = model.encryptedKey, !encrypted.isEmpty else { return nil }
        let key = try SecretBox.decrypt(encrypted)
        keyCache[model.id] = key
        return key
    }

    func clearKeyCache() {
        keyCache.removeAll()
    }

    private static let defaultModels: [ModelConfig] = [
        ModelConfig(id: "deepseek",
                    name: "DeepSeek V3.2",
                    model: "deepseek-chat",
                    baseURL: "https://api.deepseek.com/v1",
                    encryptedKey: nil,
                    enabled: true,
                    apiFormat: .openai),
        ModelConfig(id: "openai",
                    name: "OpenAI GPT-4o mini",
                    model: "gpt-4o-mini",
                    baseURL: "https://api.openai.com/v1",
                    encryptedKey: nil,
                    enabled: true,
                    apiFormat: .openai),
        ModelConfig(id: "anthropic",
                    name: "Anthropic Claude",
                    model: "claude-sonnet-4-5",
                    baseURL: "https://api.anthropic.com/v1",
                    encryptedKey: nil,
                    enabled: true,
                    apiFormat: .anthropic)
    ]
}

// MARK: - Daily cheer calendar

private struct CheerFile: Codable {
    var version: Int
    var dates: [String]
}

enum CheerStore {
    private static let lock = NSLock()
    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dateKey(for date: Date) -> String {
        keyFormatter.string(from: date)
    }

    static func load() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: AppPaths.cheerURL),
              let file = try? JSONDecoder().decode(CheerFile.self, from: data) else {
            return []
        }
        return Set(file.dates)
    }

    @discardableResult
    static func markToday() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        AppPaths.ensureSupportDirectory()
        var dates = loadUnlocked()
        let key = dateKey(for: AppClock.now)
        guard !dates.contains(key) else { return false }
        dates.insert(key)
        let file = CheerFile(version: 1, dates: dates.sorted())
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: AppPaths.cheerURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: AppPaths.cheerURL.path)
        }
        return true
    }

    static func streak(dates: Set<String> = load(), now: Date = AppClock.now) -> Int {
        guard !dates.isEmpty else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var day = calendar.startOfDay(for: now)
        if !dates.contains(dateKey(for: day)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while dates.contains(dateKey(for: day)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    static func monthLikedDays(year: Int, month: Int, dates: Set<String>) -> [Int] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var result: [Int] = []
        for key in dates {
            guard let date = keyFormatter.date(from: key) else { continue }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            if components.year == year, components.month == month, let day = components.day {
                result.append(day)
            }
        }
        return result.sorted()
    }

    private static func loadUnlocked() -> Set<String> {
        guard let data = try? Data(contentsOf: AppPaths.cheerURL),
              let file = try? JSONDecoder().decode(CheerFile.self, from: data) else {
            return []
        }
        return Set(file.dates)
    }
}

// MARK: - Schedule

enum ISO8601 {
    private static let plain = ISO8601DateFormatter()
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(_ string: String) -> Date? {
        plain.date(from: string) ?? fractional.date(from: string)
    }
}

struct ScheduleTeam: Codable, Equatable {
    var code: String
    var name: String
    var gameWins: Int?
    var outcome: String?
}

struct ScheduleMatch: Codable, Identifiable, Equatable {
    var id: String
    var startTime: String
    var state: String
    var stage: String
    var league: String
    var leagueSlug: String?
    var tournament: String
    var bestOf: Int
    var teams: [ScheduleTeam]

    var startDate: Date? {
        ISO8601.date(startTime)
    }

    var isCompleted: Bool {
        state.lowercased() == "completed" || state.lowercased() == "finished"
    }

    var igTeam: ScheduleTeam? {
        teams.first(where: { $0.code.uppercased() == "IG" })
    }

    var opponent: ScheduleTeam? {
        teams.first(where: { $0.code.uppercased() != "IG" })
    }

    var scoreText: String? {
        guard isCompleted, let ig = igTeam, let opponent else { return nil }
        return "\(ig.gameWins ?? 0) : \(opponent.gameWins ?? 0)"
    }
}

private struct ScheduleFile: Codable {
    var version: Int
    var source: String
    var fetchedAt: String
    var team: String
    var league: String
    var matches: [ScheduleMatch]
}

struct LoadedSchedule {
    var source: String
    var fetchedAt: String
    var matches: [ScheduleMatch]
    var isSample: Bool
}

enum ScheduleStore {
    static func load() -> LoadedSchedule {
        guard let data = try? Data(contentsOf: AppPaths.scheduleURL),
              let file = try? JSONDecoder().decode(ScheduleFile.self, from: data) else {
            return sample
        }
        return LoadedSchedule(source: file.source,
                              fetchedAt: file.fetchedAt,
                              matches: file.matches,
                              isSample: file.source == "sample")
    }

    static func upcoming(from schedule: LoadedSchedule, limit: Int = 3) -> [ScheduleMatch] {
        let now = AppClock.now
        return schedule.matches
            .filter { !$0.isCompleted && ($0.startDate ?? .distantPast) >= now.addingTimeInterval(-3600) }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    static func recentCompleted(from schedule: LoadedSchedule, limit: Int = 3) -> [ScheduleMatch] {
        schedule.matches
            .filter(\.isCompleted)
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    private static var sample: LoadedSchedule {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = AppClock.now
        let base = calendar.startOfDay(for: now)
        let times = [16, 19, 20].enumerated().compactMap { index, hour -> Date? in
            guard let day = calendar.date(byAdding: .day, value: index + 2, to: base) else {
                return nil
            }
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
        }
        let stages = ["八强赛", "四强赛", "决赛"]
        let opponents = [("T1", "T1"), ("GEN", "Gen.G Esports"), ("BLG", "Bilibili Gaming")]
        let matches = zip(zip(times, stages), opponents).enumerated().map { index, value in
            let ((date, stage), opponent) = value
            return ScheduleMatch(
                id: "sample-\(index)",
                startTime: ISO8601DateFormatter().string(from: date),
                state: "unstarted",
                stage: stage,
                league: "Worlds",
                leagueSlug: "worlds",
                tournament: "2026",
                bestOf: 5,
                teams: [
                    ScheduleTeam(code: "IG", name: "Invictus Gaming", gameWins: nil, outcome: nil),
                    ScheduleTeam(code: opponent.0, name: opponent.1, gameWins: nil, outcome: nil)
                ]
            )
        }
        return LoadedSchedule(source: "sample",
                              fetchedAt: ISO8601DateFormatter().string(from: now),
                              matches: matches,
                              isSample: true)
    }
}

// MARK: - Predictions

struct ScorePrediction: Codable, Identifiable, Equatable {
    var matchID: String
    var igScore: Int
    var opponentScore: Int
    var confidence: Int
    var id: String { matchID }
}

private struct PredictionFile: Codable {
    var version: Int
    var modelID: String
    var modelName: String
    var generatedAt: String
    var predictions: [ScorePrediction]
}

struct LoadedPredictions {
    var modelID: String
    var modelName: String
    var generatedAt: String
    var predictions: [ScorePrediction]
    var isSample: Bool

    var isFresh: Bool {
        guard let date = ISO8601.date(generatedAt) else { return false }
        return Date().timeIntervalSince(date) < 30 * 60
    }
}

enum PredictionStore {
    static func load() -> LoadedPredictions? {
        guard let data = try? Data(contentsOf: AppPaths.predictionsURL),
              let file = try? JSONDecoder().decode(PredictionFile.self, from: data) else {
            return nil
        }
        return LoadedPredictions(modelID: file.modelID,
                                 modelName: file.modelName,
                                 generatedAt: file.generatedAt,
                                 predictions: file.predictions,
                                 isSample: false)
    }

    static func save(_ predictions: [ScorePrediction], model: ModelConfig) {
        let file = PredictionFile(version: 1,
                                  modelID: model.model,
                                  modelName: model.name,
                                  generatedAt: ISO8601DateFormatter().string(from: Date()),
                                  predictions: predictions)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: AppPaths.predictionsURL, options: [.atomic])
    }

    static func sample(for matches: [ScheduleMatch], modelName: String) -> [ScorePrediction] {
        let scores = [(2, 1, 64), (2, 1, 58), (2, 0, 61)]
        return matches.prefix(3).enumerated().map { index, match in
            let score = scores[min(index, scores.count - 1)]
            return ScorePrediction(matchID: match.id,
                                   igScore: score.0,
                                   opponentScore: score.1,
                                   confidence: score.2)
        }
    }
}

// MARK: - Panel state passed to the local HTML surface

struct PanelCalendarState: Codable {
    var year: Int
    var month: Int
    var today: Int
    var likedDays: [Int]
}

struct PanelScheduleRow: Codable {
    var id: String
    var dateText: String
    var weekday: String
    var timeText: String
    var opponent: String
    var stage: String
    var bestOf: Int
    var next: Bool
    var completed: Bool
    var scoreText: String?
}

struct PanelPredictionRow: Codable {
    var matchID: String
    var opponent: String
    var stage: String
    var dateText: String
    var igScore: Int
    var opponentScore: Int
    var confidence: Int
}

struct PanelState: Codable {
    var mode: String
    var quote: String
    var quoteIndex: Int
    var quoteCount: Int
    var likedToday: Bool
    var streak: Int
    var calendar: PanelCalendarState
    var schedule: [PanelScheduleRow]
    var predictions: [PanelPredictionRow]
    var modelName: String
    var modelID: String
    var modelConfigured: Bool
    var predictionSample: Bool
    var scheduleSample: Bool
    var scheduleSource: String
    var scheduleUpdated: String
    var toast: String?
}

// MARK: - Display formatting

enum DisplayFormat {
    static func stage(_ raw: String) -> String {
        switch raw.lowercased() {
        case "swiss": return "瑞士轮"
        case "quarterfinals": return "八强赛"
        case "semifinals": return "四强赛"
        case "finals", "final": return "决赛"
        default: return raw.isEmpty ? "Worlds" : raw
        }
    }

    static func dateParts(_ date: Date?) -> (date: String, weekday: String, time: String) {
        guard let date else { return ("--.--", "--", "--:--") }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "MM.dd"
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.timeZone = .current
        weekdayFormatter.dateFormat = "周EEE"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm"
        return (dateFormatter.string(from: date),
                weekdayFormatter.string(from: date),
                timeFormatter.string(from: date))
    }

    static func relativeUpdated(_ raw: String) -> String {
        guard let date = ISO8601.date(raw) else { return "更新时间未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "MM.dd HH:mm"
        return "更新于 " + formatter.string(from: date)
    }
}
