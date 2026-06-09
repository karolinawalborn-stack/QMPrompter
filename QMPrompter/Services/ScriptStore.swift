import Foundation

@MainActor
final class ScriptStore: ObservableObject {
    @Published private(set) var scripts: [Script] = []

    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = directory.appendingPathComponent("scripts.json")
        load()
    }

    func script(with id: Script.ID) -> Script? {
        scripts.first { $0.id == id }
    }

    func createDraft() -> Script {
        Script(title: "未命名文稿", content: "")
    }

    func createScript(title: String, content: String) -> Script {
        Script(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名文稿" : title,
            content: content
        )
    }

    func save(_ script: Script) {
        var next = script
        next.updatedAt = Date()

        if let index = scripts.firstIndex(where: { $0.id == next.id }) {
            scripts[index] = next
        } else {
            scripts.insert(next, at: 0)
        }

        scripts.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func delete(_ script: Script) {
        scripts.removeAll { $0.id == script.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        scripts.remove(atOffsets: offsets)
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            scripts = [Self.sampleScript]
            persist()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            scripts = try JSONDecoder.qmPrompter.decode([Script].self, from: data)
        } catch {
            scripts = [Self.sampleScript]
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder.qmPrompter.encode(scripts)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save scripts: \(error)")
        }
    }

    private static let sampleScript = Script(
        title: "第一次试讲",
        content: """
        大家好，今天想和你聊一个很普通的问题。

        为什么我们明明准备了很多材料，真正开口时，却还是容易讲散？

        因为表达不是把信息倒出来，而是带着听的人走一段路。

        先给他一个明确的问题。
        再给他一个可以抓住的判断。
        最后，用一个具体场景，让这个判断落地。

        提词器存在的意义，不是替你表演。
        它只是把那些容易丢掉的线索，安静地放回你的视线里。

        你看着镜头，说你真正想说的话。
        这就够了。
        """,
        fontSize: Script.defaultFontSize,
        scrollSpeed: 78
    )
}

private extension JSONEncoder {
    static var qmPrompter: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var qmPrompter: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
