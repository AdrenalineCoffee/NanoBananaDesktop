import AppKit
import SwiftUI

enum RootSection: String, CaseIterable, Identifiable, Hashable {
    case create
    case concepting
    case history
    case settings

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .create:
            return "sparkles"
        case .concepting:
            return "paintbrush.pointed"
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
        case .concepting:
            return "nav.concepting"
        case .history:
            return "nav.history"
        case .settings:
            return "nav.settings"
        }
    }
}

struct RootView: View {
    @ObservedObject var viewModel: MainViewModel
    @StateObject private var conceptingViewModel = ConceptingViewModel()
    @State private var selection: RootSection = .create
    @SceneStorage("root.sidebarCollapsed") private var isSidebarCollapsed: Bool = false
    private let sidebarExpandedWidth: CGFloat = 246
    private let sidebarMenuTopInset: CGFloat = 58
    private let topBarHeight: CGFloat = 52
    private let titlebarButtonSize: CGFloat = 30
    private let collapsedButtonLeadingInset: CGFloat = 104
    private var expandedButtonLeadingInset: CGFloat { sidebarExpandedWidth - titlebarButtonSize - 8 }
    private var titlebarButtonTopInset: CGFloat { (topBarHeight - titlebarButtonSize) / 2 }

    var body: some View {
        ZStack {
            rootBackground
                .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebarMenu
                    .frame(width: sidebarExpandedWidth)
                    .frame(width: isSidebarCollapsed ? 0 : sidebarExpandedWidth, alignment: .leading)
                    .clipped()

                detailContainer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(.container, edges: .top)
            .animation(.easeInOut(duration: 0.22), value: isSidebarCollapsed)

            sidebarToggleButton
                .padding(.leading, isSidebarCollapsed ? collapsedButtonLeadingInset : expandedButtonLeadingInset)
                .padding(.top, titlebarButtonTopInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

            VStack(alignment: .leading, spacing: 0) {
                ForEach(RootSection.allCases) { section in
                    sidebarRow(for: section)
                }

                Spacer(minLength: 16)

                if viewModel.shouldShowKieBalance {
                    kieBalanceBadge
                        .padding(.bottom, 18)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, sidebarMenuTopInset)
            .frame(width: sidebarExpandedWidth, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .opacity(isSidebarCollapsed ? 0 : 1)
            .offset(x: isSidebarCollapsed ? -18 : 0)
            .allowsHitTesting(!isSidebarCollapsed)
        }
        .frame(width: sidebarExpandedWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
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
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
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

    private var kieBalanceBadge: some View {
        Button {
            viewModel.refreshKieBalance()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "creditcard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.blue.opacity(0.9))
                    .frame(width: 16)

                Text(viewModel.kieBalanceDisplayText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(viewModel.kieBalanceError ?? viewModel.localized("sidebar.kie_balance_refresh"))
    }

    private var detailContainer: some View {
        ZStack {
            MainView(viewModel: viewModel)
                .opacity(selection == .create ? 1 : 0)
                .allowsHitTesting(selection == .create)

            ConceptingView(
                appViewModel: viewModel,
                viewModel: conceptingViewModel,
                isVisible: selection == .concepting
            )
            .opacity(selection == .concepting ? 1 : 0)
            .allowsHitTesting(selection == .concepting)

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

    private var sidebarToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                isSidebarCollapsed.toggle()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: titlebarButtonSize, height: titlebarButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(viewModel.localized("main.inspector_resize_help"))
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
