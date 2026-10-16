import AppKit
import GrokDesktopCore
import SwiftUI

func appUpdateFailureText(_ failure: AppUpdateFailure, l10n: L10n) -> String {
    switch failure {
    case .unavailable:
        return l10n.t("Couldn't check for updates.", "暂时检查不到更新。")
    case .malformed:
        return l10n.t("The update feed was unreadable.", "更新信息无法读取。")
    case .noZip:
        return l10n.t("The latest release has no app download.", "最新版本里没有应用安装包。")
    case .untrusted:
        return l10n.t("The download address was rejected.", "下载地址不可信，已取消。")
    case .tooLarge:
        return l10n.t("The update file is too large.", "更新包过大，已取消。")
    case .badArchive:
        return l10n.t("The update file could not be verified.", "更新包校验失败。")
    case .installFailed:
        return l10n.t("The update could not be installed.", "更新没有安装成功。")
    }
}

struct AppUpdateBanner: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.l10n) private var l10n

    var body: some View {
        if let notice = model.appUpdateNotice {
            HStack(spacing: 10) {
                Image(systemName: symbol(for: notice))
                    .font(.system(size: 12, weight: .semibold))
                Text(message(for: notice))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                Spacer(minLength: 8)
                switch notice {
                case .ready:
                    Button(l10n.t("Restart now", "立即重启")) {
                        model.installDownloadedAppUpdate()
                    }
                    .buttonStyle(GrokPrimaryButtonStyle())
                case .failed:
                    Button(l10n.t("Retry", "重试")) {
                        model.checkAppUpdate()
                    }
                    .buttonStyle(GrokSecondaryButtonStyle())
                    Button {
                        model.appUpdateNotice = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.secondary)
                case .moveToApplications:
                    Button(l10n.t("Show in Finder", "在访达中显示")) {
                        if let url = RunningApp.bundleURL() {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .buttonStyle(GrokSecondaryButtonStyle())
                case .downloading:
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.elevated)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.hairline).frame(height: 1)
            }
        }
    }

    private func symbol(for notice: AppUpdateNotice) -> String {
        switch notice {
        case .downloading: return "arrow.down.circle"
        case .ready: return "arrow.clockwise.circle"
        case .moveToApplications: return "folder"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private func message(for notice: AppUpdateNotice) -> String {
        switch notice {
        case .downloading(let version):
            return l10n.t("Downloading Grok Desktop \(version)…", "正在下载 Grok Desktop \(version)…")
        case .ready(let version):
            return l10n.t(
                "Grok Desktop \(version) is ready. It installs the next time you open the app.",
                "Grok Desktop \(version) 已准备好，下次打开时安装。"
            )
        case .moveToApplications:
            return l10n.t(
                "Move Grok Desktop to the Applications folder to install updates.",
                "把 Grok Desktop 移到“应用程序”文件夹后才能安装更新。"
            )
        case .failed(let failure):
            return appUpdateFailureText(failure, l10n: l10n)
        }
    }
}
