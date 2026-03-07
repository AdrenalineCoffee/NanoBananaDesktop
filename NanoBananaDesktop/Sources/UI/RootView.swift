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
    private let sidebarColumnWidth: CGFloat = 246
    private let sidebarMenuTopInset: CGFloat = 58

    var body: some View {
        ZStack {
            rootBackground
                .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebarMenu
                    .frame(width: sidebarColumnWidth)

                detailContainer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowChromeConfigurator())
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var rootBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.11),
                    Color(red: 0.09, green: 0.10, blue: 0.14),
                    Color(red: 0.05, green: 0.06, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.18, green: 0.24, blue: 0.42).opacity(0.32),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 24,
                endRadius: 420
            )
        }
    }

    private var sidebarMenu: some View {
        ZStack(alignment: .topLeading) {
            SidebarGlassBackground()
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.018),
                            Color.black.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RadialGradient(
                        colors: [
                            Color(red: 0.92, green: 0.80, blue: 0.26).opacity(0.12),
                            Color.clear
                        ],
                        center: .bottomLeading,
                        startRadius: 12,
                        endRadius: 170
                    )
                )

            Rectangle()
                .fill(Color.black.opacity(0.26))
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: .trailing)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(RootSection.allCases) { section in
                    sidebarRow(for: section)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, sidebarMenuTopInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func sidebarRow(for section: RootSection) -> some View {
        let isSelected = section == selection
        let cornerRadius: CGFloat = 10

        HStack(spacing: 10) {
            Image(systemName: section.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Color.blue.opacity(0.98) : Color.blue.opacity(0.74))
                .frame(width: 16, alignment: .center)

            Text(viewModel.localized(section.titleKey))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? Color.white.opacity(0.96) : Color.white.opacity(0.82))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.16) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            isSelected ? Color.white.opacity(0.08) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            selection = section
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailContainer: some View {
        ZStack {
            MainView(viewModel: viewModel)
                .opacity(selection == .create ? 1 : 0)
                .allowsHitTesting(selection == .create)

            HistoryView(viewModel: viewModel, isVisible: selection == .history) {
                selection = .create
            }
            .opacity(selection == .history ? 1 : 0)
            .allowsHitTesting(selection == .history)

            SettingsView(viewModel: viewModel, isVisible: selection == .settings)
                .opacity(selection == .settings ? 1 : 0)
                .allowsHitTesting(selection == .settings)
        }
    }
}

private struct SidebarGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .underWindowBackground
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else {
            return
        }

        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.title = ""
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unifiedCompact
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
    }
}
