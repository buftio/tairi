import SwiftUI

@MainActor
final class KeyboardShortcutsController: ObservableObject {
    @Published var isPresented = false

    func present() {
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}

struct KeyboardShortcutsCheatsheetView: View {
    @EnvironmentObject private var shortcutsController: KeyboardShortcutsController

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))

                Spacer()

                Button("Done") {
                    shortcutsController.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(TairiHotkeys.sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(section.entries) { entry in
                                    HStack(alignment: .center, spacing: 16) {
                                        Text(entry.title)
                                            .font(.system(size: 14, weight: .medium))

                                        Spacer(minLength: 20)

                                        HStack(spacing: 8) {
                                            ForEach(Array(entry.hotkey.displayTokens.enumerated()), id: \.offset) { _, token in
                                                shortcutKeycap(token)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 440)
    }

    private func shortcutKeycap(_ token: String) -> some View {
        Text(token)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(minWidth: 20)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.8)
            )
    }
}
