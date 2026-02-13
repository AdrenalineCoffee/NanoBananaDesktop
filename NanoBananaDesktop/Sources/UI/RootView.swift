import AppKit
import SwiftUI

enum RootSection: String, CaseIterable, Identifiable, Hashable {
    case create
    case history
    case settings

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .create:
            return "sparkles"
        case .history:
            return "clock.arrow.circlepath"
        case .settings:
            return "gearshape"
        }
    }

    var titleKey: String {
        switch self {
        case .create:
            return "nav.create"
        case .history:
            return "nav.history"
        case .settings:
            return "nav.settings"
        }
    }
}

struct RootView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var selection: RootSection = .create

    var body: some View {
        NavigationSplitView {
            List(RootSection.allCases, selection: $selection) { section in
                Label(viewModel.localized(section.titleKey), systemImage: section.iconName)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle(viewModel.localized("app.title"))
        } detail: {
            detailView(for: selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.proxyStatusSymbol)
                    Text(viewModel.localized(viewModel.proxyStatusKey))
                    Text(viewModel.proxySummary)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func detailView(for section: RootSection) -> some View {
        switch section {
        case .create:
            MainView(viewModel: viewModel)
        case .history:
            HistoryView(viewModel: viewModel)
        case .settings:
            SettingsView(viewModel: viewModel)
        }
    }
}
