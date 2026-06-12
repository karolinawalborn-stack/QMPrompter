import SwiftUI

// MARK: - Liquid Glass 兼容存根
// 某些 Xcode 版本中 glassEffect API 不可用，
// 这里用 ultraThinMaterial 模拟其外观。

/// Liquid Glass 风格的占位类型
struct GlassEffectStyle {
    static let regular = GlassEffectStyle()
    func tint(_ color: Color) -> GlassEffectStyle { self }
    func interactive() -> GlassEffectStyle { self }
}

extension View {
    /// Liquid Glass 风格背景 — 兼容实现
    func glassEffect(_ style: GlassEffectStyle, in shape: some Shape) -> some View {
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
