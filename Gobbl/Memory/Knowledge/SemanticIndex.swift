import Foundation
import GobblCore
import NaturalLanguage
import os

private let log = Logger(subsystem: "com.xeve.gobbl", category: "semantic")

/// Search by meaning, entirely on the Mac: Apple's sentence embedding turns
/// snippets into vectors in the background (300 at a time, every ten
/// minutes), and searches compare the question's vector against them.
@MainActor
final class SemanticIndex {
    static let shared = SemanticIndex()

    private var timer: Timer?
    private var running = false

    nonisolated private static let embedding = NLEmbedding.sentenceEmbedding(for: .english)

    /// Nil when the text isn't something the English model can place.
    nonisolated static func vector(_ text: String) -> [Float]? {
        guard let embedding, let v = embedding.vector(for: String(text.prefix(1000))) else { return nil }
        return v.map(Float.init)
    }

    func start() {
        let timer = Timer(timeInterval: 600, repeats: true) { _ in
            MainActor.assumeIsolated { SemanticIndex.shared.index() }
        }
        timer.tolerance = 120
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // A first pass soon after launch, once things have settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { SemanticIndex.shared.index() }
    }

    func index() {
        guard !running, MemoryModel.shared.isCapturing, let store = MemoryModel.shared.store else { return }
        running = true
        Task.detached(priority: .background) {
            let pending = (try? store.chunksNeedingVectors(limit: 300)) ?? []
            var done = 0
            for chunk in pending {
                // Text the model can't place gets an empty vector, so it isn't retried forever.
                try? store.setVector(.chunk, ref: chunk.id, Self.vector(chunk.text) ?? [0])
                done += 1
            }
            if done > 0 { log.info("embedded \(done) snippets") }
            await MainActor.run { SemanticIndex.shared.running = false }
        }
    }

    /// Snippets closest in meaning to `query`, best first.
    func search(_ query: String, limit: Int = 20) -> [MemoryStore.Hit] {
        guard let store = MemoryModel.shared.store, let v = Self.vector(query) else { return [] }
        let hits = (try? store.nearest(v, kinds: [.chunk], limit: limit)) ?? []
        return (try? store.hits(forChunks: hits.map(\.ref))) ?? []
    }
}
