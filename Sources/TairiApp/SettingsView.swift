import SwiftUI

// MARK: - Section enum

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case terminal = "Terminal"
    case interface = "Interface"

    var id: Self { self }

    var icon: String {
        switch self {
        case .terminal: "terminal"
        case .interface: "switch.2"
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
            case .interface:
                interfaceForm
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
                Button("Open Ghostty config") {
                    GhosttyConfigAccess.openSettingsFile()
                }

                Button("Reload Ghostty config") {
                    runtime.reloadConfiguration()
                }
                .disabled(runtime.errorMessage != nil)
            } footer: {
                Text("Open the Ghostty config file in your editor, or reload it into running sessions without leaving Settings.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Terminal")
    }

    // MARK: - Interface

    private var interfaceForm: some View {
        Form {
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

            Section {
                Toggle("Disable animations", isOn: disableAnimationsBinding)

                LabeledContent("Animation speed") {
                    HStack(spacing: 10) {
                        Slider(
                            value: $settings.animationSpeedMultiplier,
                            in: 0.5...2,
                            step: 0.25
                        )
                        .disabled(!settings.animationsEnabled)

                        Text("\(settings.animationSpeedMultiplier, format: .number.precision(.fractionLength(2)))x")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            } footer: {
                Text(
                    "Animations are disabled immediately when this switch is on, during UI tests, or while macOS Reduce Motion is enabled.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Interface")
    }

    private var disableAnimationsBinding: Binding<Bool> {
        Binding(
            get: { !settings.animationsEnabled },
            set: { settings.animationsEnabled = !$0 }
        )
    }
}
