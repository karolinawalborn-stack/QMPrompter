import Foundation
import Security

enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case deepSeek
    case openAICompatible
    case anthropicCompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .openAICompatible: "OpenAI 兼容"
        case .anthropicCompatible: "Claude 兼容"
        }
    }

    var subtitle: String {
        switch self {
        case .deepSeek:
            "默认生成口播文稿，适合直接开始。"
        case .openAICompatible:
            "适合 OpenAI 协议的中转或自定义模型。"
        case .anthropicCompatible:
            "适合 Anthropic 协议的 Claude 或第三方中转。"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepSeek: "https://api.deepseek.com"
        case .openAICompatible: "https://api.aigocode.com"
        case .anthropicCompatible: "https://api.aigocode.com"
        }
    }

    var legacyDefaultBaseURLs: [String] {
        switch self {
        case .deepSeek: []
        case .openAICompatible: ["https://api.openai.com/v1"]
        case .anthropicCompatible: ["https://api.anthropic.com"]
        }
    }

    var defaultModel: String {
        switch self {
        case .deepSeek: "deepseek-v4-flash"
        case .openAICompatible: "gpt-5.4-mini"
        case .anthropicCompatible: "claude-sonnet-4-6"
        }
    }

    var legacyDefaultModels: [String] {
        switch self {
        case .deepSeek: []
        case .openAICompatible: ["gpt-4o-mini"]
        case .anthropicCompatible: ["claude-sonnet-4-20250514"]
        }
    }

    var modelOptions: [AIModelOption] {
        switch self {
        case .deepSeek:
            [
                AIModelOption("deepseek-v4-flash", title: "DeepSeek V4 Flash", detail: "当前默认"),
                AIModelOption("deepseek-chat", title: "DeepSeek Chat"),
                AIModelOption("deepseek-reasoner", title: "DeepSeek Reasoner")
            ]
        case .openAICompatible:
            [
                AIModelOption("gpt-5.4-mini", title: "GPT-5.4 mini", detail: "默认"),
                AIModelOption("gpt-5.4", title: "GPT-5.4", detail: "已验证"),
                AIModelOption("gpt-5.5", title: "GPT-5.5", detail: "已验证"),
                AIModelOption("codex-auto-review", title: "Codex Auto Review", detail: "已验证")
            ]
        case .anthropicCompatible:
            [
                AIModelOption("claude-sonnet-4-6", title: "Claude Sonnet 4.6", detail: "默认"),
                AIModelOption("claude-haiku-4-5-20251001", title: "Claude Haiku 4.5", detail: "已验证"),
                AIModelOption("claude-opus-4-6", title: "Claude Opus 4.6"),
                AIModelOption("claude-opus-4-7", title: "Claude Opus 4.7"),
                AIModelOption("claude-opus-4-8", title: "Claude Opus 4.8")
            ]
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .deepSeek, .openAICompatible: "sk-..."
        case .anthropicCompatible: "sk-ant-... 或第三方 token"
        }
    }

    func matchesDefaultBaseURL(_ value: String) -> Bool {
        let normalizedValue = Self.normalizedBaseURL(value)
        guard !normalizedValue.isEmpty else { return true }

        let defaults = [defaultBaseURL] + legacyDefaultBaseURLs
        return defaults.contains { Self.normalizedBaseURL($0) == normalizedValue }
    }

    func matchesDefaultModel(_ value: String) -> Bool {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedValue.isEmpty else { return true }

        let defaults = [defaultModel] + legacyDefaultModels
        return defaults.contains { $0.lowercased() == normalizedValue }
    }

    private static func normalizedBaseURL(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}

struct AIModelOption: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String

    init(_ id: String, title: String? = nil, detail: String = "") {
        self.id = id
        self.title = title ?? id
        self.detail = detail
    }
}

struct AIConnectionConfiguration {
    let provider: AIProvider
    let apiKey: String
    let baseURL: String
    let model: String
}

@MainActor
final class APIKeyStore: ObservableObject {
    @Published var provider: AIProvider
    @Published var apiKey: String
    @Published var baseURL: String
    @Published var model: String

    private let account = "ai-api-key"
    private let legacyDeepSeekAccount = "deepseek-api-key"
    private let service = "com.qiaomu.Prompter"
    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let provider = "ai.provider"
        static let baseURL = "ai.baseURL"
        static let model = "ai.model"
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var configuration: AIConnectionConfiguration {
        AIConnectionConfiguration(
            provider: provider,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: resolvedBaseURL,
            model: resolvedModel
        )
    }

    init() {
        let savedProvider = defaults.string(forKey: DefaultsKey.provider)
            .flatMap(AIProvider.init(rawValue:)) ?? .deepSeek
        provider = savedProvider
        apiKey = Self.read(account: account, service: service) ??
            Self.read(account: legacyDeepSeekAccount, service: service) ?? ""
        baseURL = Self.initialBaseURL(
            defaults.string(forKey: DefaultsKey.baseURL),
            provider: savedProvider
        )
        model = Self.initialModel(
            defaults.string(forKey: DefaultsKey.model),
            provider: savedProvider
        )
        defaults.set(baseURL, forKey: DefaultsKey.baseURL)
        defaults.set(model, forKey: DefaultsKey.model)
    }

    func save() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextBaseURL = resolvedBaseURL
        let nextModel = resolvedModel

        apiKey = key
        baseURL = nextBaseURL
        model = nextModel

        defaults.set(provider.rawValue, forKey: DefaultsKey.provider)
        defaults.set(nextBaseURL, forKey: DefaultsKey.baseURL)
        defaults.set(nextModel, forKey: DefaultsKey.model)

        if key.isEmpty {
            Self.delete(account: account, service: service)
        } else {
            Self.save(key, account: account, service: service)
        }
        Self.delete(account: legacyDeepSeekAccount, service: service)
    }

    private var resolvedBaseURL: String {
        let value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? provider.defaultBaseURL : value
    }

    private var resolvedModel: String {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? provider.defaultModel : value
    }

    private static func initialBaseURL(_ savedBaseURL: String?, provider: AIProvider) -> String {
        guard let savedBaseURL else {
            return provider.defaultBaseURL
        }

        let trimmedBaseURL = savedBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return provider.matchesDefaultBaseURL(trimmedBaseURL) ? provider.defaultBaseURL : trimmedBaseURL
    }

    private static func initialModel(_ savedModel: String?, provider: AIProvider) -> String {
        guard let savedModel else {
            return provider.defaultModel
        }

        let trimmedModel = savedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return provider.matchesDefaultModel(trimmedModel) ? provider.defaultModel : trimmedModel
    }

    private static func save(_ value: String, account: String, service: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(account: account, service: service)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private static func read(account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data
        else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service
        ]

        SecItemDelete(query as CFDictionary)
    }
}
