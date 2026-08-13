import AppKit
import SwiftUI

/// Official Grok mark paths from grok.com (viewBox 0 0 34 33).
enum GrokLogoSVG {
    static let mark = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 34 33" fill="black">
      <path d="M13.2371 21.0407L24.3186 12.8506C24.8619 12.4491 25.6384 12.6057 25.8973 13.2294C27.2597 16.5185 26.651 20.4712 23.9403 23.1851C21.2297 25.8989 17.4581 26.4941 14.0108 25.1386L10.2449 26.8843C15.6463 30.5806 22.2053 29.6665 26.304 25.5601C29.5551 22.3051 30.562 17.8683 29.6205 13.8673L29.629 13.8758C28.2637 7.99809 29.9647 5.64871 33.449 0.844576C33.5314 0.730667 33.6139 0.616757 33.6964 0.5L29.1113 5.09055V5.07631L13.2343 21.0436"/>
      <path d="M10.9503 23.0313C7.07343 19.3235 7.74185 13.5853 11.0498 10.2763C13.4959 7.82722 17.5036 6.82767 21.0021 8.2971L24.7595 6.55998C24.0826 6.07017 23.215 5.54334 22.2195 5.17313C17.7198 3.31926 12.3326 4.24192 8.67479 7.90126C5.15635 11.4239 4.0499 16.8403 5.94992 21.4622C7.36924 24.9165 5.04257 27.3598 2.69884 29.826C1.86829 30.7002 1.0349 31.5745 0.36364 32.5L10.9474 23.0341"/>
    </svg>
    """

    static func image(hex: String, width: CGFloat) -> NSImage {
        let height = width * 33 / 34
        let svg = mark
            .replacingOccurrences(of: "fill=\"black\"", with: "fill=\"\(hex)\"")
            .replacingOccurrences(of: "viewBox=\"0 0 34 33\"", with: "viewBox=\"0 0 34 33\" width=\"\(width)\" height=\"\(height)\"")
        return NSImage(data: Data(svg.utf8)) ?? NSImage(size: NSSize(width: width, height: height))
    }
}

struct GrokMark: View {
    var size: CGFloat = 22
    @Environment(\.palette) private var palette

    var body: some View {
        Image(nsImage: GrokLogoSVG.image(hex: palette.isDark ? "#F5F5F5" : "#111111", width: size * 2))
            .resizable()
            .interpolation(.high)
            .aspectRatio(34 / 33, contentMode: .fit)
            .frame(width: size, height: size * 33 / 34)
            .accessibilityLabel("Grok")
    }
}

struct SuperGrokWordmark: View {
    var markSize: CGFloat = 46
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            GrokMark(size: markSize)
            Text("SuperGrok")
                .font(.system(size: markSize * 0.92, weight: .medium, design: .default))
                .tracking(-0.8)
                .foregroundStyle(palette.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SuperGrok")
    }
}
