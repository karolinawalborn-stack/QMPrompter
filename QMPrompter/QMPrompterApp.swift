import SwiftUI

// MARK: - Liquid Glass 兼容存根
// 在缺少 glassEffect API 的 Xcode 版本中提供兼容实现。
// 用 ultraThinMaterial 背景模拟 Liquid Glass 外观。

extension View {
    /// Liquid Glass 风格背景 — 兼容实现
    func glassEffect(_ style: Any?, in shape: some Shape) -> some View {
        self.background(.ultraThinMaterial, in: shape)
    }
}

@main
struct QMPrompterApp: App {
    @StateObject private var scriptStore = ScriptStore()

    var body: some Scene {
        WindowGroup {
            ScriptListView()
                .environmentObject(scriptStore)
        }
    }
}
