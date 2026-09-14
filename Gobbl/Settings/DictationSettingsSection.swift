import GobblCore
import SwiftUI

/// Settings → Dictation: the Whisper model, clean-up style, language and custom words.
struct DictationSettingsSection: View {
    @State private var dictation = Dictation.shared
    @AppStorage("dictationStyle") private var style = DictationStyle.light.rawValue
    @AppStorage("dictationLanguage") private var language = "auto"
    @AppStorage("dictationWords") private var words = ""
    @State private var choice = Dictation.ModelChoice.turbo

    private static let languages: [(String, String)] = [
        ("auto", "Detect automatically"), ("en", "English"), ("hi", "Hindi"), ("ta", "Tamil"), ("te", "Telugu"),
        ("ml", "Malayalam"), ("kn", "Kannada"), ("bn", "Bengali"), ("mr", "Marathi"), ("es", "Spanish"),
        ("fr", "French"), ("de", "German"), ("pt", "Portuguese"), ("ja", "Japanese"), ("zh", "Chinese"), ("ar", "Arabic"),
    ]

    var body: some View {
        Section {
            if !Dictation.supported {
                Text("Dictation needs a Mac with Apple silicon.").foregroundStyle(.secondary)
            } else if let installed = dictation.installedModel {
                HStack {
                    LabeledContent("Model", value: installed.title)
                    Button("Remove", role: .destructive) { dictation.removeModel() }
                }
            } else if let progress = dictation.downloadProgress {
                ProgressView(value: progress) { Text("Downloading \(choice.title)") }
            } else {
                Picker("Model", selection: $choice) {
                    ForEach(Dictation.ModelChoice.allCases) { Text($0.title).tag($0) }
                }
                HStack {
                    Text("A one-time download. After that, dictation works offline.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Download") { dictation.downloadModel(choice) }
                }
            }
            if let status = dictation.status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }

            Picker("Clean-up", selection: $style) {
                Text("Verbatim").tag(DictationStyle.verbatim.rawValue)
                Text("Light: fillers and punctuation, on this Mac").tag(DictationStyle.light.rawValue)
                Text("Polish with AI").tag(DictationStyle.polish.rawValue)
            }
            Picker("Language", selection: $language) {
                ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom words")
                TextField("Names and jargon, separated by commas", text: $words, axis: .vertical)
                    .lineLimit(2...4)
                Text("Helps Whisper spell names, products and code terms your way.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Dictation")
        } footer: {
            Text("Hold right ⌥ and talk, then let go. Double-tap and hold for hands-free, and tap to stop. Your voice is transcribed on this Mac and never leaves it. Picking one language gives better results than detecting it, especially for mixed speech.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
