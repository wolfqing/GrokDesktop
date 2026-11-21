import AppKit
import Combine
import GrokDesktopCore
import SwiftUI

struct ModelEffortPicker: View {
    @Binding var isOpen: Bool
    @Binding var modelID: String
    let choices: [ModelChoice]
    @Binding var effort: EffortLevel
    let chinese: Bool
    let refreshChoices: () -> Void
    let applyTier: (ModelTier) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    @State private var chipHover = false

    var body: some View {
        chip
            .background {
                // SwiftUI `.popover` hosts its content as the NSPopover content view.
                // Switching model or effort changes that view's ideal size, and
                // NSHostingView then calls setFrame inside the display-cycle
                // constraint pass. AppKit aborts from
                // `_postWindowNeedsUpdateConstraints`. This popover keeps the
                // hosting view off the window content view and resizes on the
                // next turn.
                ModelMenuPopover(isPresented: $isOpen, width: 260) {
                    ModelEffortMenu(
                        modelID: $modelID,
                        choices: choices,
                        effort: $effort,
                        chinese: chinese,
                        applyTier: applyTier
                    )
                    .environment(\.palette, palette)
                    .environment(\.l10n, l10n)
                    .environment(\.colorScheme, palette.isDark ? .dark : .light)
                }
            }
            .onChange(of: isOpen) { _, open in
                if open { refreshChoices() }
            }
    }

    private var chip: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 5.5) {
                Text(ModelCatalog.shortTitle(for: modelID, choices: choices))
                    .foregroundStyle(palette.text)
                Text(effort.title(chinese: chinese))
                    .foregroundStyle(palette.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(palette.tertiary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(chipHover || isOpen ? palette.selected : palette.chip, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { chipHover = $0 }
        .animation(.easeOut(duration: 0.12), value: chipHover)
        .help("\(ModelCatalog.name(for: modelID, choices: choices)) · \(effort.title(chinese: chinese))")
    }

}

private struct ModelEffortMenu: View {
    @Binding var modelID: String
    let choices: [ModelChoice]
    @Binding var effort: EffortLevel
    let chinese: Bool
    let applyTier: (ModelTier) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n
    @EnvironmentObject private var menu: ModelEffortMenuState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch menu.page {
            case .home:
                homePage
            case .model:
                drillPage(title: l10n.t("Model", "模型")) {
                    ForEach(listedChoices) { item in
                        optionRow(
                            id: "model-\(item.id)",
                            title: item.name,
                            detail: item.detail.isEmpty ? nil : item.detail,
                            selected: modelID == item.id
                        ) {
                            modelID = item.id
                            menu.page = .home
                        }
                    }
                }
            case .effort:
                drillPage(title: l10n.t("Reasoning", "推理强度")) {
                    ForEach(EffortLevel.allCases) { level in
                        optionRow(
                            id: "effort-\(level.id)",
                            title: level.title(chinese: chinese),
                            selected: effort == level
                        ) {
                            effort = level
                            menu.page = .home
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .frame(width: 260, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private var homePage: some View {
        drillRow(
            id: "row-model",
            title: l10n.t("Model", "模型"),
            value: ModelCatalog.shortTitle(for: modelID, choices: choices)
        ) {
            menu.page = .model
        }
        drillRow(
            id: "row-effort",
            title: l10n.t("Reasoning", "推理强度"),
            value: effort.title(chinese: chinese)
        ) {
            menu.page = .effort
        }
        Rectangle()
            .fill(palette.hairline)
            .frame(height: 1)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        Button {
            menu.showAdvanced.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(l10n.t("Advanced", "高级"))
                    .font(.system(size: 14, weight: .medium))
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(menu.showAdvanced ? 0 : 180))
                Spacer()
            }
            .foregroundStyle(palette.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if menu.showAdvanced {
            ForEach(ModelTier.allCases) { tier in
                optionRow(
                    id: "tier-\(tier.id)",
                    title: tier.menuTitle,
                    detail: tier.menuSubtitle,
                    selected: false
                ) {
                    applyTier(tier)
                }
            }
        }
    }

    private var listedChoices: [ModelChoice] {
        guard !choices.contains(where: { $0.id == modelID }) else { return choices }
        return [
            ModelChoice(
                id: modelID,
                name: modelID,
                shortTitle: ModelCatalog.shortTitle(for: modelID)
            )
        ] + choices
    }

    private func drillPage<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                menu.page = .home
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(palette.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            content()
        }
    }

    private func drillRow(id: String, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(palette.text)
                Spacer(minLength: 12)
                Text(value)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .foregroundStyle(palette.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(menu.hovered == id ? palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering in
            menu.hovered = hovering ? id : (menu.hovered == id ? nil : menu.hovered)
        }
    }

    private func optionRow(id: String, title: String, detail: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(menu.hovered == id ? palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering in
            menu.hovered = hovering ? id : (menu.hovered == id ? nil : menu.hovered)
        }
    }
}

@MainActor
private final class ModelEffortMenuState: ObservableObject {
    enum Page {
        case home
        case model
        case effort
    }

    @Published var page: Page = .home
    @Published var showAdvanced = false
    @Published var hovered: String?

    func reset() {
        page = .home
        showAdvanced = false
        hovered = nil
    }
}

private struct ModelMenuPopover<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    var width: CGFloat
    var content: Content

    init(isPresented: Binding<Bool>, width: CGFloat, @ViewBuilder content: () -> Content) {
        _isPresented = isPresented
        self.width = width
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ModelMenuAnchorView {
        let view = ModelMenuAnchorView()
        view.host = context.coordinator
        context.coordinator.anchor = view
        return view
    }

    func updateNSView(_ nsView: ModelMenuAnchorView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.anchor = nsView
        nsView.host = context.coordinator
        context.coordinator.sync()
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate, ModelMenuPopoverHost {
        var parent: ModelMenuPopover
        weak var anchor: ModelMenuAnchorView?
        let menu = ModelEffortMenuState()
        private var popover: NSPopover?
        private var hosting: NSHostingView<AnyView>?
        private var container: ModelMenuContainer?
        private var wasPresented = false
        private var resizeToken = 0
        private var menuCancellable: AnyCancellable?
        nonisolated(unsafe) private var monitor: Any?

        init(parent: ModelMenuPopover) {
            self.parent = parent
            super.init()
            menuCancellable = menu.objectWillChange.sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleResize()
                }
            }
        }

        func sync() {
            let opening = parent.isPresented && !wasPresented
            wasPresented = parent.isPresented
            if opening { menu.reset() }
            if parent.isPresented {
                presentIfNeeded()
                hosting?.rootView = hostedContent()
                scheduleResize()
            } else {
                dismiss()
            }
        }

        func anchorDidMoveToWindow() {
            guard parent.isPresented else { return }
            presentIfNeeded()
            scheduleResize()
        }

        func popoverDidClose(_ notification: Notification) {
            removeMonitor()
            if parent.isPresented {
                parent.isPresented = false
            }
            wasPresented = parent.isPresented
        }

        private func hostedContent() -> AnyView {
            AnyView(parent.content.environmentObject(menu))
        }

        private func presentIfNeeded() {
            let popover = ensurePopover()
            guard let anchor, anchor.window != nil, !popover.isShown else { return }
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
            installMonitor()
        }

        private func ensurePopover() -> NSPopover {
            if let popover { return popover }
            let hosting = NSHostingView(rootView: hostedContent())
            hosting.sizingOptions = [.intrinsicContentSize]
            hosting.safeAreaRegions = []
            hosting.translatesAutoresizingMaskIntoConstraints = false
            let container = ModelMenuContainer(hosting: hosting)
            let controller = NSViewController()
            controller.view = container
            let popover = NSPopover()
            popover.behavior = .applicationDefined
            popover.animates = false
            popover.delegate = self
            popover.contentViewController = controller
            popover.contentSize = NSSize(width: parent.width, height: 180)
            self.hosting = hosting
            self.container = container
            self.popover = popover
            return popover
        }

        private func dismiss() {
            guard let popover, popover.isShown else { return }
            popover.performClose(nil)
            removeMonitor()
        }

        private func scheduleResize() {
            resizeToken += 1
            let token = resizeToken
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.resizeToken else { return }
                self.applySize()
            }
        }

        private func applySize() {
            guard let popover, popover.isShown, let hosting else { return }
            let size = measuredSize(of: hosting, width: parent.width)
            if abs(popover.contentSize.width - size.width) > 0.5
                || abs(popover.contentSize.height - size.height) > 0.5 {
                popover.contentSize = size
            }
            container?.needsLayout = true
        }

        private func measuredSize(of hosting: NSHostingView<AnyView>, width: CGFloat) -> NSSize {
            hosting.frame.size.width = width
            hosting.layoutSubtreeIfNeeded()
            var size = hosting.intrinsicContentSize
            if !size.width.isFinite || size.width < 50 { size.width = width }
            if !size.height.isFinite || size.height < 44 || size.height > 4000 {
                size.height = 180
            }
            return NSSize(width: width, height: min(ceil(size.height), 520))
        }

        private func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let popover, popover.isShown else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    parent.isPresented = false
                    dismiss()
                    return nil
                }
                return event
            }
            // Popover clicks can report the parent window, so the event window
            // is not a reliable inside-test. Use the popover frame on screen.
            let screenPoint = NSEvent.mouseLocation
            if let frame = popover.contentViewController?.view.window?.frame, frame.contains(screenPoint) {
                return event
            }
            if let anchor, let window = anchor.window {
                let local = anchor.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
                if anchor.bounds.insetBy(dx: -4, dy: -4).contains(local) { return event }
            }
            parent.isPresented = false
            dismiss()
            return event
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

@MainActor
private protocol ModelMenuPopoverHost: AnyObject {
    func anchorDidMoveToWindow()
}

private final class ModelMenuAnchorView: NSView {
    weak var host: ModelMenuPopoverHost?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        host?.anchorDidMoveToWindow()
    }
}

private final class ModelMenuContainer: NSView {
    let hosting: NSView

    init(hosting: NSView) {
        self.hosting = hosting
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 180))
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        hosting.frame = bounds
    }
}
