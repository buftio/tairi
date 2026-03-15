import SwiftUI

// MARK: - Section enum

private enum SettingsSection: String, CaseIterable, Identifiable {
    case terminal = "Terminal"

    var id: Self { self }

    var icon: String {
        switch self {
        case .terminal: "terminal"
        }
    }
}

// MARK: - Palette

private enum SettingsPalette {
    static let primaryText = Color.black.opacity(0.84)
    static let secondaryText = Color.black.opacity(0.48)
    static let selectedNavBg = Color.black.opacity(0.88)
    static let selectedNavText = Color.white
    static let cardBackground = Color.white.opacity(0.52)
    static let cardStroke = Color.white.opacity(0.72)
    static let divider = Color.black.opacity(0.08)
    static let windowTop = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let windowBottom = Color(red: 0.91, green: 0.90, blue: 0.86)
    static let sidebarOverlay = Color.white.opacity(0.26)
    static let sidebarStroke = Color.white.opacity(0.60)
}

// MARK: - Main view

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var selectedSection: SettingsSection = .terminal

    var body: some View {
        HStack(spacing: 0) {
            nav
            content
        }
        .frame(width: 580, height: 400)
        .background(windowBackground)
    }

    // MARK: Nav sidebar

    private var nav: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 17, weight: .bold, design: .serif))
                .foregroundStyle(SettingsPalette.primaryText)
                .padding(.bottom, 10)

            ForEach(SettingsSection.allCases) { section in
                navButton(section)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(width: 158)
        .background(navBackground)
    }

    private func navButton(_ section: SettingsSection) -> some View {
        Button {
            selectedSection = section
        } label: {
            let isSelected = selectedSection == section
            HStack(spacing: 7) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14, alignment: .center)
                Text(section.rawValue)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? SettingsPalette.selectedNavBg : Color.clear)
            )
            .foregroundStyle(isSelected ? SettingsPalette.selectedNavText : SettingsPalette.primaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Section content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(selectedSection.rawValue)
            ScrollView(.vertical) {
                sectionBody
                    .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.15), value: selectedSection)
    }

    @ViewBuilder
    private var sectionBody: some View {
        switch selectedSection {
        case .terminal:
            terminalSection
        }
    }

    // MARK: Terminal

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    rowLabel("After terminal exit")
                    Picker("", selection: $settings.terminalExitBehavior) {
                        ForEach(TerminalExitBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    rowDetail(settings.terminalExitBehavior.detail)
                }
                .padding(14)
            }
        }
    }

    // MARK: Reusable building blocks

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .foregroundStyle(SettingsPalette.primaryText)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SettingsPalette.cardStroke, lineWidth: 1)
        )
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(SettingsPalette.primaryText)
    }

    private func rowDetail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(SettingsPalette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func placeholderRow(label: String) -> some View {
        Text(label)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(SettingsPalette.secondaryText)
            .padding(14)
    }

    // MARK: Backgrounds

    private var windowBackground: some View {
        LinearGradient(
            colors: [SettingsPalette.windowTop, SettingsPalette.windowBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var navBackground: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(SettingsPalette.sidebarOverlay)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SettingsPalette.sidebarStroke)
                .frame(width: 1)
        }
    }
}
