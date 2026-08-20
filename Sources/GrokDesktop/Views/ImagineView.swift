import AppKit
import GrokDesktopCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ImagineView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    @State private var prompt = ""
    @State private var recent: [ImagineAsset] = []
    @State private var video = false
    @State private var aspect = "1:1"
    @State private var count = 1
    @State private var genMode = "speed"
    @State private var reference: URL?
    @State private var selected: ImagineAsset?
    @State private var pending: PendingImagine?
    @State private var showAspectPicker = false

    private let columns = [GridItem(.adaptive(minimum: 168), spacing: 10)]
    private let aspectChoices: [ImagineAspectChoice] = [
        .init(ratio: "2:3", captionEN: "Tall", captionZH: "高"),
        .init(ratio: "3:2", captionEN: "Wide", captionZH: "宽"),
        .init(ratio: "1:1", captionEN: "Square", captionZH: "正方形"),
        .init(ratio: "9:16", captionEN: "Portrait", captionZH: "垂直"),
        .init(ratio: "16:9", captionEN: "Landscape", captionZH: "宽屏")
    ]

    var body: some View {
        HStack(spacing: 0) {
            galleryColumn
            if let selected {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(width: 1)
                detailPane(selected)
                    .frame(width: 300)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(palette.canvas)
        .onAppear(perform: reload)
        .onChange(of: model.client.isTurnRunning) { _, running in
            reload()
            if !running { settlePending() }
        }
        .task(id: pending?.id) {
            guard pending != nil else { return }
            while pending != nil {
                try? await Task.sleep(for: .seconds(1))
                reload()
                settlePending()
            }
        }
    }

    private var galleryColumn: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(l10n.imagine)
                        .font(.system(size: 22, weight: .semibold))
                    if recent.isEmpty, pending == nil {
                        Text(l10n.t("Local generations from grok sessions show up here.", "本机 grok 会话里生成的图会显示在这里。"))
                            .font(.system(size: 13))
                            .foregroundStyle(palette.secondary)
                    } else {
                        LazyVGrid(columns: columns, spacing: 10) {
                            if let pending {
                                ImaginePendingTile(aspect: pending.aspect, prompt: pending.prompt)
                            }
                            ForEach(recent) { asset in
                                Button {
                                    selected = asset
                                    showAspectPicker = false
                                } label: {
                                    ImagineThumb(url: asset.url, aspect: clampedAspect(asset.aspectRatio))
                                        .overlay {
                                            if selected?.id == asset.id {
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(palette.text, lineWidth: 2)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .help(asset.url.lastPathComponent)
                                .contextMenu { ChatLinkContextButtons(url: asset.url) }
                            }
                        }
                    }
                }
                .padding(28)
                .padding(.bottom, 168)
            }
            .scrollIndicators(.never)

            if showAspectPicker {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { showAspectPicker = false }
            }

            composer
                .zIndex(2)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reference {
                HStack(spacing: 8) {
                    Image(systemName: video ? "video" : "photo")
                        .foregroundStyle(palette.secondary)
                    Text(reference.lastPathComponent)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        self.reference = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.t("Clear reference", "去掉参考图"))
                }
            }

            TextField(composerPlaceholder, text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(palette.text)
                .lineLimit(1...4)
                .onSubmit(submit)

            HStack(spacing: 8) {
                toolButton(systemImage: "plus") {
                    attachReference()
                }
                .help(l10n.t("Reference image", "参考图"))

                ImagineSlidingPair(
                    leftTitle: l10n.t("Image", "图片"),
                    leftIcon: "photo",
                    rightTitle: l10n.t("Video", "视频"),
                    rightIcon: "video",
                    rightSelected: $video
                )
                .onChange(of: video) { _, on in
                    if on { count = 1 }
                }

                if !video {
                    Menu {
                        ForEach(1...4, id: \.self) { n in
                            Button("\(n)") { count = n }
                        }
                    } label: {
                        toolLabel(systemImage: "square.on.square", title: "\(count)")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(l10n.t("How many images", "生成几张"))
                }

                ImagineSlidingPair(
                    leftTitle: l10n.t("Speed", "速度"),
                    rightTitle: l10n.t("Quality (v2.0)", "质量（v2.0）"),
                    rightSelected: Binding(
                        get: { genMode == "quality" },
                        set: { genMode = $0 ? "quality" : "speed" }
                    ),
                    showThumb: genMode != "auto"
                )
                .help(
                    genMode == "quality"
                        ? l10n.t("More care. Video is 10s at 720p.", "更细。视频 10 秒 720p。")
                        : l10n.t("Faster. Video is 6s at 480p.", "更快。视频 6 秒 480p。")
                )

                toolText(l10n.t("Auto", "自动模式"), on: genMode == "auto") {
                    genMode = "auto"
                }
                .help(l10n.t("Let grok choose.", "交给 grok 决定。"))

                aspectButton
                    .zIndex(3)

                Spacer(minLength: 8)

                if model.client.hasActiveWork {
                    Button {
                        if !model.client.isStopping { model.client.stopWork() }
                    } label: {
                        Group {
                            if model.client.isStopping {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 11, weight: .bold))
                            }
                        }
                        .foregroundStyle(palette.sendGlyph)
                        .frame(width: 28, height: 28)
                        .background(palette.send, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.client.isStopping)
                    .help(l10n.stop)
                }

                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(canSend ? palette.sendGlyph : palette.secondary)
                        .frame(width: 28, height: 28)
                        .background(canSend ? palette.send : palette.chip, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help(l10n.t("Generate", "生成"))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: 720)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(palette.elevated)
                .shadow(color: Color.black.opacity(palette.isDark ? 0.5 : 0.12), radius: 30, y: 12)
        )
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
    }

    private var aspectButton: some View {
        Button {
            showAspectPicker.toggle()
        } label: {
            ImagineAspectGlyph(ratio: ImaginePrompt.ratioValue(aspect), maxSide: 14)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(l10n.t("Aspect ratio", "画面比例"))
        .overlay(alignment: .top) {
            if showAspectPicker {
                ImagineAspectMenu(
                    choices: aspectChoices,
                    selected: aspect,
                    chinese: model.language.resolved() == .chinese
                ) { value in
                    aspect = value
                    showAspectPicker = false
                }
                .alignmentGuide(.top) { d in d[.bottom] + 10 }
            }
        }
    }

    private func toolButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
    }

    private func toolLabel(systemImage: String, title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(palette.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func toolText(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(on ? palette.text : palette.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detailPane(_ asset: ImagineAsset) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(asset.url.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .help(asset.url.path)
                Spacer()
                Button {
                    selected = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(l10n.t("Close", "关闭"))
            }
            .foregroundStyle(palette.secondary)

            ImagineThumb(url: asset.url, aspect: clampedAspect(asset.aspectRatio), maxPixel: 720)
                .frame(maxHeight: 280)
                .onTapGesture { ChatLinkActions.open(asset.url) }

            VStack(alignment: .leading, spacing: 4) {
                Text(RelativeTime.format(asset.modified, chinese: model.language.resolved() == .chinese))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                Text(asset.url.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            VStack(spacing: 8) {
                detailButton(l10n.t("Insert into chat", "插入对话"), systemImage: "text.badge.plus") {
                    let mention = "@\(asset.url.path)"
                    if model.draft.isEmpty {
                        model.draft = mention + " "
                    } else {
                        model.draft += " " + mention
                    }
                    model.destination = .build
                }
                detailButton(l10n.t("Show in Finder", "在 Finder 中显示"), systemImage: "folder") {
                    ChatLinkActions.reveal(asset.url)
                }
                detailButton(l10n.t("Edit from this", "以此再生成"), systemImage: "wand.and.stars") {
                    reference = asset.url
                    video = false
                }
                detailButton(l10n.t("Make video", "做成视频"), systemImage: "video") {
                    reference = asset.url
                    video = true
                    if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        prompt = l10n.t("A slow camera move on this frame.", "镜头在这张图上缓缓移动。")
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(palette.sidebar)
    }

    private func detailButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 14)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var composerPlaceholder: String {
        if reference != nil {
            return video
                ? l10n.t("How should this image move?", "这张图怎么动？")
                : l10n.t("What should change?", "改成什么样？")
        }
        return l10n.t("Describe what you imagine", "输入你的想象")
    }

    private func attachReference() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = l10n.t("Use", "使用")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        reference = url
    }

    private func clampedAspect(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.55), 1.85)
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        showAspectPicker = false
        let line = ImaginePrompt.make(
            text: text,
            video: video,
            aspect: aspect,
            reference: reference,
            count: video ? 1 : count,
            mode: genMode
        )
        pending = PendingImagine(
            prompt: text,
            aspect: clampedAspect(ImaginePrompt.ratioValue(aspect)),
            started: Date(),
            seen: Set(recent.map(\.id))
        )
        prompt = ""
        model.sendImagine(line)
    }

    private func reload() {
        let items = ImagineLibrary.recent()
        recent = items
        if let selected, !items.contains(where: { $0.id == selected.id }) {
            self.selected = nil
        }
    }

    private func settlePending() {
        guard let pending else { return }
        if recent.contains(where: { !pending.seen.contains($0.id) }) {
            self.pending = nil
            return
        }
        if !model.client.isTurnRunning, !model.client.hasActiveWork,
           Date().timeIntervalSince(pending.started) > 2 {
            self.pending = nil
        }
    }
}

private struct ImagineSlidingPair: View {
    let leftTitle: String
    var leftIcon: String? = nil
    let rightTitle: String
    var rightIcon: String? = nil
    @Binding var rightSelected: Bool
    var showThumb: Bool = true
    @Environment(\.palette) private var palette
    @Namespace private var slide

    var body: some View {
        HStack(spacing: 0) {
            segment(title: leftTitle, icon: leftIcon, selected: !rightSelected) {
                rightSelected = false
            }
            segment(title: rightTitle, icon: rightIcon, selected: rightSelected) {
                rightSelected = true
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(palette.chip))
        .animation(.easeInOut(duration: 0.18), value: rightSelected)
        .animation(.easeInOut(duration: 0.18), value: showThumb)
    }

    private func segment(title: String, icon: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected && showThumb ? palette.text : palette.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if selected, showThumb {
                    Capsule(style: .continuous)
                        .fill(palette.elevated)
                        .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
                        .matchedGeometryEffect(id: "thumb", in: slide)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ImagineAspectChoice: Identifiable {
    var id: String { ratio }
    let ratio: String
    let captionEN: String
    let captionZH: String
}

private struct ImagineAspectGlyph: View {
    let ratio: CGFloat
    var maxSide: CGFloat = 18
    @Environment(\.palette) private var palette

    var body: some View {
        let width = ratio >= 1 ? maxSide : max(8, maxSide * ratio)
        let height = ratio >= 1 ? max(8, maxSide / ratio) : maxSide
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .stroke(palette.text.opacity(0.88), lineWidth: 1.35)
            .frame(width: width, height: height)
    }
}

private struct ImagineAspectMenu: View {
    let choices: [ImagineAspectChoice]
    let selected: String
    let chinese: Bool
    let onPick: (String) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(choices) { choice in
                Button {
                    onPick(choice.ratio)
                } label: {
                    HStack(spacing: 12) {
                        ImagineAspectGlyph(ratio: ImaginePrompt.ratioValue(choice.ratio), maxSide: 20)
                            .frame(width: 28, height: 22)
                        Text(choice.ratio)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.text)
                        Spacer(minLength: 12)
                        Text(chinese ? choice.captionZH : choice.captionEN)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        selected == choice.ratio ? palette.chip : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 196)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.elevated)
                .shadow(color: Color.black.opacity(palette.isDark ? 0.5 : 0.14), radius: 22, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        )
    }
}

private struct PendingImagine: Identifiable, Equatable {
    let id = UUID()
    let prompt: String
    let aspect: CGFloat
    let started: Date
    let seen: Set<String>
}

private struct ImaginePendingTile: View {
    let aspect: CGFloat
    let prompt: String
    @Environment(\.palette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(palette.chip)
            .aspectRatio(max(aspect, 0.45), contentMode: .fit)
            .overlay {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(prompt)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
            }
    }
}

private struct ImagineThumb: View {
    let url: URL
    var aspect: CGFloat = 1
    var maxPixel: CGFloat = 480
    @Environment(\.palette) private var palette
    @State private var image: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(palette.chip)
            .aspectRatio(max(aspect, 0.45), contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(palette.secondary)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .task(id: url) {
                image = ImagineThumbLoader.thumbnail(url: url, maxPixel: maxPixel)
            }
    }
}

private enum ImagineThumbLoader {
    static func thumbnail(url: URL, maxPixel: CGFloat) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return NSImage(contentsOf: url)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
