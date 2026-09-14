import SwiftUI

/// Edit mode in the notch: the text, its versions, and an instruction box.
struct EditPanel: View {
    @State private var session = EditSession.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(session.appName.isEmpty ? "Editing" : "Editing in \(session.appName)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                if session.versions.count > 1 {
                    IconButton(symbol: "chevron.left", help: "Previous version") { session.step(-1) }
                        .disabled(session.index == 0)
                    Text(session.index == 0 ? "Original" : "\(session.index) of \(session.versions.count - 1)")
                        .font(.mono(11))
                        .foregroundStyle(Palette.textTertiary)
                    IconButton(symbol: "chevron.right", help: "Next version") { session.step(1) }
                        .disabled(session.index == session.versions.count - 1)
                }
            }

            ScrollView {
                Text(session.streaming ?? session.draft)
                    .font(.system(size: 12.5))
                    .foregroundStyle(session.busy ? Palette.textSecondary : Palette.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.well))

            HStack(spacing: 6) {
                ForEach(EditSession.suggestions, id: \.self) { suggestion in
                    Button(suggestion) { session.suggest(suggestion) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Capsule().fill(Palette.well))
                        .disabled(session.busy)
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: session.busy ? "ellipsis" : "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .symbolEffect(.pulse, isActive: session.busy)
                    TextField("How should it change? Hold right ⌥ to say it.", text: $session.instruction)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($focused)
                        .onSubmit { session.submit() }
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(Palette.well))
                PillButton(title: "Replace", symbol: "return") { session.replace() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!session.canReplace)
                    .help("Put this version into the field (⌘Return)")
            }

            if let error = session.error {
                Text(error).font(.system(size: 11)).foregroundStyle(Palette.gold)
            }
        }
        .onAppear { focused = true }
        .onDisappear { session.detach() }
    }
}
