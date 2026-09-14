import Foundation

/// How much Gobbl tidies what you said before it goes into the field.
public enum DictationStyle: String, CaseIterable, Codable, Sendable {
    /// Exactly what Whisper heard, minus its own artefacts.
    case verbatim
    /// Fillers, stutters and spacing fixed, on the Mac, instantly. The default.
    case light
    /// Light, then an AI rewrite for the app you're in (uses the AI allowance).
    case polish
}

/// Local, instant clean-up of a Whisper transcript. No network, no model:
/// this runs between releasing the key and the text appearing.
public enum DictationCleanup {
    /// Whisper's non-speech markers: "[BLANK_AUDIO]", "(music)", "*coughs*", "<|en|>".
    public static func verbatim(_ raw: String) -> String {
        var s = replace(raw, #"\[[A-Z_ ]+\]|\((?:music|applause|laughter|silence|inaudible|coughs?|sighs?)\)|<\|[^|]*\|>|\*[a-z ]+\*"#, "", caseInsensitive: true)
        s = replace(s, #"[ \t]{2,}"#, " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func light(_ raw: String) -> String {
        var s = verbatim(raw)
        // Spoken layout.
        // (Only a comma before is dropped: a period there ends the previous sentence.)
        s = replace(s, #",?[ \t]*\bnew paragraph\b[,.]?[ \t]*"#, "\n\n", caseInsensitive: true)
        s = replace(s, #",?[ \t]*\bnew line\b[,.]?[ \t]*"#, "\n", caseInsensitive: true)
        // Fillers, with the comma that usually comes with them.
        s = replace(s, #",?\s*\b(?:u+m+|u+h+|uhm|e+r+m+|er|a+h+|h+m+|m{2,})\b[,…]*"#, "", caseInsensitive: true)
        // Stutters: "the the" (but "that that" and "had had" are real English).
        s = replace(s, #"\b(?!that\b|had\b)(\w+)(?:\s+\1\b)+"#, "$1", caseInsensitive: true)
        // Spacing and punctuation.
        s = replace(s, #"[ \t]{2,}"#, " ")
        s = replace(s, #"[ \t]+([,.!?;:])"#, "$1")
        s = replace(s, #",{2,}"#, ",")
        s = replace(s, #",([.!?])"#, "$1")
        s = replace(s, #"^[ \t,]+|[ \t,]+$"#, "", anchorsMatchLines: true)
        return capitalizeSentences(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// What Whisper says when it hears silence or noise. Dropped when the
    /// clip was short or quiet, so an accidental hold types nothing.
    public static func isLikelyHallucination(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return t.isEmpty || [
            "thank you", "thanks", "thanks for watching", "thank you for watching", "thank you so much for watching",
            "bye", "you", "so", "okay", "please subscribe", "subtitles by the amaraorg community",
        ].contains(t)
    }

    /// The custom dictionary, given to Whisper as its prompt so it spells
    /// names and jargon the user's way.
    public static func vocabularyPrompt(_ words: [String]) -> String? {
        let clean = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return nil }
        return clean.prefix(80).joined(separator: ", ") + "."
    }

    // MARK: Helpers

    static func capitalizeSentences(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var capNext = true
        for ch in s {
            if capNext, ch.isLetter {
                out += ch.uppercased()
                capNext = false
                continue
            }
            out.append(ch)
            if ".!?\n".contains(ch) { capNext = true } else if !ch.isWhitespace { capNext = false }
        }
        return out
    }

    private static func replace(_ s: String, _ pattern: String, _ template: String,
                                caseInsensitive: Bool = false, anchorsMatchLines: Bool = false) -> String {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        if anchorsMatchLines { options.insert(.anchorsMatchLines) }
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}
