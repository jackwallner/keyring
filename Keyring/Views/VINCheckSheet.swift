import SwiftUI
import WebKit

/// NHTSA's VIN lookup inside the app, with the VIN filled in. The owner taps
/// Search on NHTSA's page; the result is read off it and the sheet closes.
struct VINCheckSheet: View {
    let vin: String
    let known: [Recall]
    let onResult: (VINRecallCheck) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loaded = false
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: Theme.sm) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundStyle(Theme.brass)
                    Text("Your VIN is filled in. Tap **Search** and the recalls still open on it come back here.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(Theme.md)
                .background(Theme.brassSoft)
                ZStack {
                    VINLookupWebView(vin: vin, loaded: $loaded, failed: $failed) { json in
                        guard let check = VINRecallCheck.parse(json, vin: vin, known: known) else { return }
                        Haptics.success()
                        onResult(check)
                        dismiss()
                    }
                    .id(attempt)
                    .opacity(failed ? 0 : 1)
                    if failed {
                        EmptyStateView(
                            symbol: "wifi.exclamationmark",
                            title: "Couldn't reach NHTSA",
                            message: "Check the connection and try again. The recalls for the model are still listed behind this sheet.",
                            actionTitle: "Try again",
                            action: { failed = false; loaded = false; attempt += 1 }
                        )
                        .padding(.horizontal, Theme.margin)
                    } else if !loaded {
                        ProgressView()
                    }
                }
            }
            .navigationTitle("Check the VIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct VINLookupWebView: UIViewRepresentable {
    let vin: String
    @Binding var loaded: Bool
    @Binding var failed: Bool
    let onMessage: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let script = WKUserScript(source: VINRecallCheck.pageScript(vin: vin), injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
        config.userContentController.add(context.coordinator, name: "recalls")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.accessibilityIdentifier = "vin.web"
        view.load(URLRequest(url: VINRecallCheck.lookupURL))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "recalls")
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: VINLookupWebView

        init(_ parent: VINLookupWebView) { self.parent = parent }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let json = message.body as? String else { return }
            parent.onMessage(json)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loaded = true
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        /// A tap on a link mid-load cancels the first navigation; that isn't a failure.
        private func fail(_ error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            parent.failed = true
        }
    }
}
