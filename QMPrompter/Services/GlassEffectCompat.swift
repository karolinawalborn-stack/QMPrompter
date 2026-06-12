import SwiftUI

/// 兼容存根：为 Xcode 16+ / iOS 18 SDK 提供 glassEffect 定义。
/// 某些 SDK 版本中没有公开 glassEffect View 修饰符，
/// 这里用 ultraThinMaterial 背景模拟 Liquid Glass 的外观。
extension View {
    /// Liquid Glass 风格背景（兼容实现）
    func glassEffect(_ style: Any?, in shape: some Shape) -> some View {
        self.background(.ultraThinMaterial, in: shape)
    }
}
