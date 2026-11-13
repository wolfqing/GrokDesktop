import SwiftUI

/// Static Build-screen poster for promo screenshots. No NSView / WebView / ScrollViewReader.
struct DemoPosterView: View {
    var isDark: Bool = true
    private var palette: Palette { Palette(isDark: isDark) }

    var body: some View {
        VStack(spacing: 0) {
            windowTitleBar
            Rectangle().fill(palette.hairline).frame(height: 1)
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 260)
                Rectangle().fill(palette.hairline).frame(width: 1)
                chat
                Rectangle().fill(palette.hairline).frame(width: 1)
                inspector
                    .frame(width: 320)
            }
        }
        .background(palette.canvas)
        .frame(width: 1280, height: 840)
        .preferredColorScheme(isDark ? .dark : .light)
        .environment(\.colorScheme, isDark ? .dark : .light)
        .environment(\.l10n, L10n(language: .english))
        .environment(\.palette, palette)
    }

    private var windowTitleBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 12, height: 12)
            }
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(palette.sidebar)
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
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(palette.hairline, lineWidth: 1)
                )
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 2) {
                nav("New chat", "square.and.pencil", shortcut: "⌘N", selected: true)
                nav("Live", "circle.hexagongrid", shortcut: nil, selected: false)
                nav("Imagine", "photo", shortcut: nil, selected: false)
                nav("Workflows", "bolt", shortcut: nil, selected: false)
                nav("Skills", "square.grid.2x2", shortcut: nil, selected: false)
            }
            .padding(.top, 4)

            Text("PROJECTS")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(palette.tertiary)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 6)

            projectRow("northwind", count: 4, selected: true)

            Text("HISTORY")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(palette.tertiary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 2) {
                history("Fix login retry on 401", time: "2m", selected: true)
                history("Rewrite the CLI help text", time: "1h", selected: false)
                history("Add fixtures for auth errors", time: "4h", selected: false)
                history("Review the upload pipeline", time: "1d", selected: false)
            }

            Spacer()

            Rectangle().fill(palette.hairline).frame(height: 1)
            HStack(spacing: 10) {
                GrokAvatar(initial: "A", size: 28, fontSize: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ada Chen")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.text)
                    Text(verbatim: "ada@northwind.dev")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                }
                Spacer()
                Image(systemName: "gearshape")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 28, height: 28)
            }
            .padding(12)
        }
        .background(palette.sidebar)
    }

    private func tab(_ title: String, on: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(on ? palette.text : palette.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(on ? palette.elevated : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .shadow(color: on ? .black.opacity(isDark ? 0.25 : 0.08) : .clear, radius: 2, y: 1)
    }

    private func nav(_ title: String, _ icon: String, shortcut: String?, selected: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
            Spacer()
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
            }
        }
        .foregroundStyle(selected ? palette.text : palette.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected ? palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 8)
    }

    private func projectRow(_ name: String, count: Int, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: selected ? "folder.fill" : "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? palette.text : palette.secondary)
                .frame(width: 16)
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.text)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6.5)
        .background(selected ? palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 8)
    }

    private func history(_ title: String, time: String, selected: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? palette.text : palette.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(time)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(palette.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6.5)
        .background(selected ? palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 8)
    }

    private var chat: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.secondary)
                    Text("northwind")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.text)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.tertiary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.hairline, lineWidth: 1)
                )

                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10.5, weight: .medium))
                    Text("main")
                        .font(.system(size: 11.5, design: .monospaced))
                }
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(palette.chip, in: Capsule())

                Spacer()

                HStack(spacing: 3) {
                    rightTabPill("chevron.left.forwardslash.chevron.right", "Changes", active: false)
                    rightTabPill("eye", "Preview", active: false)
                    rightTabPill("terminal", "Terminal", active: false)
                    rightTabPill("text.bubble", "Aside", active: false)
                }

                Image(systemName: "sidebar.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.text)
                    .frame(width: 28, height: 28)
                    .background(palette.selected, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.hairline).frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer(minLength: 80)
                    userBubble("Login retry swallows the 401 and spins forever. Walk AuthClient and fix it.")
                }
                toolCluster
                assistantCard
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            composer
                .frame(maxWidth: 700)
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
        }
        .background(palette.canvas)
    }

    private func userBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14.5))
            .lineSpacing(3)
            .foregroundStyle(palette.text)
            .padding(.horizontal, 15)
            .padding(.vertical, 10.5)
            .background(palette.promptBubble, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.promptBubbleBorder, lineWidth: 1)
            )
    }

    private var toolCluster: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.tertiary)
                Text("Explored 2 files · Edited 1 file")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.secondary)
                Spacer()
                Text("1.4s")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                toolLine("Read", file: "AuthClient.swift")
                toolLine("Read", file: "Retry.swift")
                toolLine("Edit", file: "AuthClient.swift", diff: "+18 -6")
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(width: 1.5)
                    .padding(.leading, 3.5)
                    .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private func toolLine(_ verb: String, file: String, diff: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(palette.success)
                .font(.system(size: 11.5))
            Text(verb)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.secondary)
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                Text(file)
                    .font(.system(size: 12, design: .monospaced))
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            if let diff {
                Text(diff)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.success)
            }
            Spacer()
        }
    }

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The retry helper treated every HTTP error as transient. A 401 is a credential failure, so it should fail immediately instead of entering exponential backoff.")
                .font(.system(size: 14.5))
                .lineSpacing(4)
                .foregroundStyle(palette.text)

            VStack(spacing: 0) {
                HStack {
                    Text("swift")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text("Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(palette.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(palette.codeHeader)

                Rectangle().fill(palette.hairline).frame(height: 1)

                Text("if response.statusCode == 401 {\n    throw AuthError.unauthorized\n}")
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(palette.text)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 1)
            )

            Text("Added coverage in AuthClientTests for 401, 429, and request timeouts — all 14 suite assertions pass.")
                .font(.system(size: 14.5))
                .lineSpacing(4)
                .foregroundStyle(palette.text)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask Grok to build, inspect, or refactor…")
                .font(.system(size: 14))
                .foregroundStyle(palette.tertiary)
                .padding(.top, 2)

            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 26, height: 26)
                    .background(palette.chip, in: Circle())

                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.success)
                    Text("Auto")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.text)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(palette.chip, in: Capsule())

                HStack(spacing: 4) {
                    Text("grok-4 · High")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.tertiary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)

                Spacer()

                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.sendGlyph)
                    .frame(width: 28, height: 28)
                    .background(palette.send, in: Circle())
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(palette.input, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.borderStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(isDark ? 0.28 : 0.06), radius: 14, y: 4)
    }

    private func rightTabPill(_ icon: String, _ title: String, active: Bool) -> some View {
        HStack(spacing: 4.5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
            Text(title)
                .font(.system(size: 12, weight: active ? .semibold : .medium))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(active ? palette.text : palette.secondary)
        .padding(.horizontal, 7.5)
        .padding(.vertical, 5)
        .background(active ? palette.selected : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Inspector")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 24, height: 24)
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.hairline).frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                Text("CONTEXT")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(palette.tertiary)
                HStack(alignment: .firstTextBaseline) {
                    Text("22%")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.text)
                    Spacer()
                    Text("44k / 200k")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                }
                Capsule()
                    .fill(palette.chip)
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(palette.info)
                            .frame(width: 62, height: 6)
                    }
                Text("northwind · main")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.secondary)
            }
            .padding(12)
            .grokCard(cornerRadius: 12)

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("TASKS")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(palette.tertiary)
                    Spacer()
                    Text("2 / 3")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                }
                task("Trace the login retry loop", done: true)
                task("Stop retrying on 401", done: true)
                task("Add AuthClient fixtures", done: false)
            }
            .padding(12)
            .grokCard(cornerRadius: 12)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CHANGES")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(palette.tertiary)
                    Spacer()
                    Text("2 files")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                }
                change("AuthClient.swift", plus: 18, minus: 6)
                change("AuthClientTests.swift", plus: 24, minus: 0)
            }
            .padding(12)
            .grokCard(cornerRadius: 12)

                Spacer()
            }
            .padding(14)
        }
        .background(palette.sidebar)
    }

    private func task(_ title: String, done: Bool) -> some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(done ? palette.success : palette.warning)
                .font(.system(size: 12))
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(done ? palette.secondary : palette.text)
        }
    }

    private func change(_ name: String, plus: Int, minus: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
            Text(name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.text)
                .lineLimit(1)
            Spacer()
            Text("+\(plus)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.success)
            if minus > 0 {
                Text("-\(minus)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.danger)
            }
        }
    }
}
