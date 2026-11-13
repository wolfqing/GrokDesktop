import AppKit
import SwiftUI

struct CreateProjectSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        OverlaySheet(
            title: l10n.createProject,
            width: 460,
            onDismiss: { model.showCreateProject = false }
        ) {
            TextField(l10n.projectName, text: $model.newProjectName)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .padding(10)
                .grokFieldChrome(cornerRadius: 9)

            HStack {
                Button {
                    pickFolder()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                        Text(model.newProjectFolder?.lastPathComponent ?? l10n.chooseFolder)
                    }
                }
                .buttonStyle(GrokSecondaryButtonStyle())
                Spacer()
                Button(l10n.t("Cancel", "取消")) { model.showCreateProject = false }
                    .buttonStyle(GrokSecondaryButtonStyle())
                Button(l10n.create) { model.createProject() }
                    .buttonStyle(GrokPrimaryButtonStyle())
                    .disabled(model.newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = l10n.chooseFolder
        if panel.runModal() == .OK {
            model.newProjectFolder = panel.url
            if model.newProjectName.isEmpty {
                model.newProjectName = panel.url?.lastPathComponent ?? ""
            }
        }
    }
}
