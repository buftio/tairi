import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Terminal") {
                Picker("After terminal exit", selection: $settings.terminalExitBehavior) {
                    ForEach(TerminalExitBehavior.allCases) { behavior in
                        Text(behavior.title)
                            .tag(behavior)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(settings.terminalExitBehavior.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
