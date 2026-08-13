import AppKit
import SwiftUI

struct CreateProjectSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        ZStack {
            palette.overlay.ignoresSafeArea()
                .onTapGesture { model.showCreateProject = false }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(l10n.createProject)
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Button {
                        model.showCreateProject = false
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(palette.secondary)
                    }
                    .buttonStyle(.plain)
                }

                TextField(l10n.projectName, text: $model.newProjectName)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairline))

                HStack {
                    Button {
                        pickFolder()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text(model.newProjectFolder?.lastPathComponent ?? l10n.addFiles)
                        }
                        .foregroundStyle(palette.secondary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(l10n.create) { model.createProject() }
                        .buttonStyle(GrokPrimaryButtonStyle())
                        .disabled(model.newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(22)
            .frame(width: 460)
            .background(palette.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.hairline))
            .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
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
