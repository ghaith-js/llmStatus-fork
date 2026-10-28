import AppKit
import SwiftUI

/// A scroll view sized to its content when the popover opens, up to what the screen allows.
/// The height then stays put: folding or unfolding a row scrolls instead of resizing the popover.
struct FittingScrollView<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat = 0
    /// Height kept until the popover opens again; nil while the first layout settles.
    @State private var lockedHeight: CGFloat?

    /// Room under the menu bar, minus the popover's header, footer and arrow.
    static var maxHeight: CGFloat {
        max(300, (NSScreen.main?.visibleFrame.height ?? 800) - 140)
    }

    var body: some View {
        ScrollView {
            content
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                })
        }
        .frame(height: lockedHeight ?? min(max(contentHeight, 1), Self.maxHeight))
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .onAppear(perform: unlock)
        .onReceive(NotificationCenter.default.publisher(for: .popoverWillOpen)) { _ in unlock() }
    }

    /// Follows the content for a moment (rows still arriving), then keeps that height.
    private func unlock() {
        lockedHeight = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            lockedHeight = min(max(contentHeight, 1), Self.maxHeight)
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
