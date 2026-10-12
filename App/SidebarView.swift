import SwiftUI
import PMPaneCore

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: Binding<SidebarSection?>(
            get: { model.sidebarSection },
            set: { section in
                if let section {
                    model.sidebarSectionChanged(section)
                }
            }
        )) {
            Section {
                sidebarRow(.all)
                sidebarRow(.updates, badge: model.updatesBadgeCount)
            }

            Section("Homebrew") {
                ForEach(SidebarSection.homebrewSections) { section in
                    sidebarRow(section)
                }
            }

            Section("Language runtimes") {
                ForEach(SidebarSection.runtimeSections) { section in
                    runtimeRow(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("")
        .toolbar(removing: .title)
    }

    @ViewBuilder
    private func sidebarRow(_ section: SidebarSection, badge: Int? = nil) -> some View {
        HStack {
            Text(section.title)
            Spacer()
            if let source = section.inventorySourceForProgress, model.isRefreshing(source) {
                ProgressView()
                    .controlSize(.small)
            }
            if let badge, badge > 0 {
                Text("\(badge)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .tag(section)
    }

    @ViewBuilder
    private func runtimeRow(_ section: SidebarSection) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                Text(PackageFormatting.runtimeSubtitle(for: model.runtimeTool(for: section)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let source = section.inventorySourceForProgress, model.isRefreshing(source) {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .tag(section)
    }
}
