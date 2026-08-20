import SwiftUI

/// Static Build-screen poster for promo screenshots. No NSView / WebView / ScrollViewReader.
struct DemoPosterView: View {
    private let palette = Palette(isDark: true)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
            Rectangle().fill(palette.hairline).frame(width: 1)
            chat
            Rectangle().fill(palette.hairline).frame(width: 1)
            inspector
                .frame(width: 320)
        }
        .background(palette.canvas)
        .frame(width: 1280, height: 840)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .environment(\.l10n, L10n(language: .english))
        .environment(\.palette, palette)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                GrokMark(size: 20)
                HStack(spacing: 2) {
                    tab("Chat", on: false)
                    tab("Build", on: true)
                }
                .padding(3)
                .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 2) {
                nav("New chat", "square.and.pencil", selected: true)
                nav("Live", "circle.hexagongrid", selected: false)
                nav("Imagine", "photo", selected: false)
                nav("Workflows", "bolt", selected: false)
                nav("Skills", "square.grid.2x2", selected: false)
            }
            .padding(.top, 4)

            Text("HISTORY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 6)

            history("Fix login retry on 401", selected: true)
            history("Rewrite the CLI help text", selected: false)
            history("Add fixtures for auth errors", selected: false)
            history("Review the upload pipeline", selected: false)

            Spacer()

            Rectangle().fill(palette.hairline).frame(height: 1)
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.purple)
                    Text("A").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ada Chen").font(.system(size: 13, weight: .medium)).foregroundStyle(palette.text)
                    Text("ada@northwind.dev").font(.system(size: 11)).foregroundStyle(palette.secondary)
                }
                Spacer()
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.secondary)
            }
            .padding(12)
        }
        .background(palette.sidebar)
    }

    private func tab(_ title: String, on: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(on ? palette.text : palette.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(on ? palette.elevated : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func nav(_ title: String, _ icon: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 16)
            Text(title).font(.system(size: 13.5))
            Spacer()
        }
        .foregroundStyle(selected ? palette.text : palette.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(selected ? palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 8)
    }

    private func history(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 13.5))
            .foregroundStyle(palette.text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(selected ? palette.selected : Color.clear)
    }

    private var chat: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(palette.secondary)
                Text("northwind")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("22%  ·  44k/200k")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 16) {
                userBubble("Login retry swallows the 401 and spins forever. Walk AuthClient and fix it.")
                toolLine("Read AuthClient.swift")
                toolLine("Read Retry.swift")
                toolLine("Edit AuthClient.swift")
                assistantCard
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            composer
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
        }
        .background(palette.canvas)
    }

    private func userBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func toolLine(_ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 12))
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(palette.secondary)
            Spacer()
            Text("done")
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The retry helper treated every HTTP error as transient. A 401 is a credential failure, so it should stop.")
                .font(.system(size: 15))
                .foregroundStyle(palette.text)
            Text("if status == 401 {\n    throw AuthError.unauthorized\n}")
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(palette.text)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Tests in AuthClientTests cover 401, 429, and timeout.")
                .font(.system(size: 15))
                .foregroundStyle(palette.text)
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.secondary)
            Text("Ask Grok to continue…")
                .font(.system(size: 15))
                .foregroundStyle(palette.secondary)
            Spacer()
            Text("34%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.secondary)
            Text("4.6")
                .font(.system(size: 12, weight: .medium))
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(palette.send)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.input, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Inspector")
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text("CONTEXT")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                HStack {
                    Text("22%").font(.system(size: 16, weight: .semibold, design: .monospaced))
                    Spacer()
                    Text("44k / 200k").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.secondary)
                }
                Capsule().fill(palette.chip).frame(height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.orange).frame(width: 56, height: 6)
                    }
                Text("northwind").font(.system(size: 11)).foregroundStyle(palette.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TASKS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                    Spacer()
                    Text("2/3").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.secondary)
                }
                task("Trace the login retry loop", done: true)
                task("Stop retrying on 401", done: true)
                task("Add AuthClient fixtures", done: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("CHANGES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                change("AuthClient.swift", plus: 18, minus: 6)
                change("AuthClientTests.swift", plus: 24, minus: 0)
            }
            Spacer()
        }
        .padding(14)
        .background(palette.sidebar)
    }

    private func task(_ title: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .orange)
                .font(.system(size: 12))
            Text(title).font(.system(size: 12)).foregroundStyle(palette.text)
        }
    }

    private func change(_ name: String, plus: Int, minus: Int) -> some View {
        HStack {
            Text(name).font(.system(size: 12))
            Spacer()
            Text("+\(plus)").foregroundStyle(.green)
            Text("-\(minus)").foregroundStyle(.red)
        }
        .font(.system(size: 12))
    }
}
