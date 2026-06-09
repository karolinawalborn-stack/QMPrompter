import Foundation

struct DeepSeekScriptGenerator {
    enum GenerationError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case emptyContent
        case server(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "请先填写 DeepSeek API Key。"
            case .invalidResponse:
                "DeepSeek 返回格式异常。"
            case .emptyContent:
                "DeepSeek 没有生成可用正文。"
            case .server(let message):
                message
            }
        }
    }

    private let apiKey: String
    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    init(apiKey: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func generateScript(for prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw GenerationError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90

        let body = DeepSeekRequest(
            model: "deepseek-v4-flash",
            messages: [
                .init(role: "system", content: Self.systemPrompt),
                .init(role: "user", content: userPrompt(from: prompt))
            ],
            thinking: .init(type: "disabled"),
            maxTokens: 2800,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GenerationError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(DeepSeekErrorResponse.self, from: data).error.message) ??
                "DeepSeek 请求失败：HTTP \(httpResponse.statusCode)。"
            throw GenerationError.server(message)
        }

        let decoded = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw GenerationError.invalidResponse
        }

        let cleaned = Self.cleanGeneratedScript(content)
        guard !cleaned.isEmpty else { throw GenerationError.emptyContent }
        return cleaned
    }

    private func userPrompt(from prompt: String) -> String {
        """
        用户的生成需求：
        \(prompt.trimmingCharacters(in: .whitespacesAndNewlines))

        请输出一篇可直接放进提词器朗读的中文口播文稿。
        """
    }

    private static let systemPrompt = """
    你是向阳乔木的提词器文稿作者，负责把用户的简单想法生成适合直接朗读的中文口播稿。

    写作方法参考向阳乔木的读书口播脚本工作流：
    从听众真实困境或强认知锚点开始；
    如果用户输入的是书名、作者或读书视频主题，先说明作者或这本书为什么值得听，再提炼三到五个真正改变认知的观点；
    如果不是书籍主题，也用同样的结构：一个清晰问题、三到五个观点、具体生活场景、自然收束；
    每个观点都要用一句话解释，再接一个普通人能立刻看见的场景；
    语言要像真人说话，短段落，一句只承载一个意思；
    结尾自然，不要强行销售。

    输出规则：
    只输出口播正文；
    不要 Markdown；
    不要代码块；
    不要标题；
    不要列表符号；
    不要加粗标记；
    不要小标题；
    不要“第一点、第二点、首先、其次、最后”；
    不要镜头提示、音乐提示、字幕提示或时长说明；
    不要解释你的写作过程；
    文本要适合提词器滚动显示，段落短，换行自然。

    避免这些词和句式：震惊、绝了、太牛了、赋能、落地、深度融合、内卷、这个时代、年轻人、精准打击、你知道吗、今天我要告诉你、重点来了、接下来告诉你、划重点。
    """

    private static func cleanGeneratedScript(_ content: String) -> String {
        var result = content
            .replacingOccurrences(of: "```text", with: "")
            .replacingOccurrences(of: "```markdown", with: "")
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")

        let lines = result
            .components(separatedBy: .newlines)
            .compactMap { rawLine -> String? in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return "" }
                guard !shouldDropGeneratedLine(line) else { return nil }
                let strippedLine = stripGeneratedLinePrefix(line)
                return strippedLine.isEmpty ? nil : strippedLine
            }

        result = lines.joined(separator: "\n")

        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldDropGeneratedLine(_ line: String) -> Bool {
        if line.hasPrefix("#") || line.hasPrefix(">") || line.contains("预估时长") {
            return true
        }

        let normalized = line
            .replacingOccurrences(of: "：", with: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ["口播正文", "口播正文:", "口播稿", "口播稿:", "正文", "正文:"].contains(normalized)
    }

    private static func stripGeneratedLinePrefix(_ line: String) -> String {
        var result = line
        let prefixPatterns = [
            #"^[-*•]\s+"#,
            #"^\d+[\.\)、]\s*"#,
            #"^第[一二三四五六七八九十]+[点部分][：:、，\s]*"#
        ]

        for pattern in prefixPatterns {
            if let range = result.range(of: pattern, options: .regularExpression) {
                result.removeSubrange(range)
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct DeepSeekRequest: Encodable {
    let model: String
    let messages: [DeepSeekMessage]
    let thinking: DeepSeekThinking
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case thinking
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct DeepSeekThinking: Encodable {
    let type: String
}

private struct DeepSeekMessage: Codable {
    let role: String
    let content: String
}

private struct DeepSeekResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: DeepSeekMessage
    }
}

private struct DeepSeekErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}
