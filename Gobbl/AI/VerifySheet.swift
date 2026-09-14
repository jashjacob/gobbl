import SwiftUI
import WebKit

/// One-time bot check before turning on AI: loads gobbl.xeve.io/verify
/// (a Cloudflare Turnstile widget) and receives its token through a script
/// message, then registers this install with the AI service.
struct VerifySheet: View {
    let onDone: (Result<Void, Error>) -> Void
    @State private var status = "Checking you're a person…"
    @State private var working = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Turn on Gobbl AI").font(.headline)
            Text("A quick, private check keeps the free beta from being abused. Nothing is tracked.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            TurnstileView { token in
                guard !working else { return }
                working = true
                status = "Turning on…"
                Task {
                    do {
                        try await AIClient.shared.register(turnstileToken: token)
                        onDone(.success(()))
                    } catch {
                        status = error.localizedDescription
                        working = false
                    }
                }
            }
            .frame(width: 320, height: 90)
            Text(status).font(.caption).foregroundStyle(.secondary)
            Button("Cancel") { onDone(.failure(CancellationError())) }
        }
        .padding(22)
        .frame(width: 380)
    }
}

private struct TurnstileView: NSViewRepresentable {
    let onToken: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onToken: onToken) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "gobbl")
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.load(URLRequest(url: URL(string: "https://gobbl.xeve.io/verify")!))
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onToken: (String) -> Void
        init(onToken: @escaping (String) -> Void) { self.onToken = onToken }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let token = message.body as? String, !token.isEmpty else { return }
            DispatchQueue.main.async { self.onToken(token) }
        }
    }
}
