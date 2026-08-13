import SwiftUI

struct RunningStatusIcon: View {
    var active: Bool
    var idleSystemImage: String
    var color: Color
    var size: CGFloat = 12

    @State private var angle = 0.0
    @State private var inhaling = false

    var body: some View {
        ZStack {
            if active {
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 1.6)
                Circle()
                    .trim(from: 0.08, to: 0.74)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                    .rotationEffect(.degrees(angle))
            } else {
                Image(systemName: idleSystemImage)
                    .font(.system(size: max(9, size - 1), weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(active && inhaling ? 1.12 : 1)
        .opacity(active && inhaling ? 0.55 : 1)
        .onAppear { sync(active) }
        .onChange(of: active) { _, on in
            sync(on)
        }
    }

    private func sync(_ on: Bool) {
        if on {
            angle = 0
            inhaling = false
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                angle = 360
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                inhaling = true
            }
        } else {
            angle = 0
            inhaling = false
        }
    }
}
