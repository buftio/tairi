import SwiftUI

// MARK: - Section enum

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case terminal = "Terminal"

    var id: Self { self }

    var icon: String {
        switch self {
        case .terminal: "terminal"
        }
    }
}

// MARK: - Root view

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var runtime: GhosttyRuntime
    @State private var selectedSection: SettingsSection? = .terminal

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 140, ideal: 160)
        } detail: {
            switch selectedSection ?? .terminal {
            case .terminal:
                terminalForm
            }
        }
        .frame(width: 600, height: 440)
    }

    // MARK: - Terminal

    private var terminalForm: some View {
        Form {
            Section {
                Picker(selection: $settings.terminalExitBehavior) {
                    ForEach(TerminalExitBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                } label: {
                    Text("After terminal exit")
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text(settings.terminalExitBehavior.detail)
            }

            Section {
                LabeledContent("Window glass") {
                    HStack(spacing: 10) {
                        Slider(
                            value: $settings.windowGlassOpacityPercent,
                            in: 0...100,
                            step: 1
                        )
                        Text("\(Int(settings.windowGlassOpacityPercent.rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            } footer: {
                Text("Controls how strong the frosted-glass background appears behind the app content without fading the content itself.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Terminal")
    }
}
