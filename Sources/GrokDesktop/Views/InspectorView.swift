import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab = InspectorTab.plan

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(InspectorTab.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider().overlay(GrokTheme.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .plan:
                        Text("Plan")
                            .font(.system(size: 16, weight: .semibold))
                        Text("进入 Plan 模式后，计划会出现在这里。批准、打回和行内评论会接到 ACP。")
                            .foregroundStyle(GrokTheme.secondary)
                        if model.client.mode == .plan {
                            Text("当前是 Plan 模式。")
                                .foregroundStyle(GrokTheme.text)
                        }
                    case .timeline:
                        Text("时间线")
                            .font(.system(size: 16, weight: .semibold))
                        Text("对应 /timeline 和 /jump，按轮次跳转。")
                            .foregroundStyle(GrokTheme.secondary)
                    case .workflows:
                        Text("工作流")
                            .font(.system(size: 16, weight: .semibold))
                        Text("对应 /workflows、/goal、/loop。第一期先占位，入口留在检查器。")
                            .foregroundStyle(GrokTheme.secondary)
                    }
                }
                .font(.system(size: 13))
                .padding(16)
            }
        }
        .background(GrokTheme.sidebar)
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case plan
    case timeline
    case workflows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: return "Plan"
        case .timeline: return "时间线"
        case .workflows: return "工作流"
        }
    }
}
