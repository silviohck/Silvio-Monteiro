import AppKit
import SwiftUI

@main
struct GeradorDocumentosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var armazenamento = Armazenamento()

    var body: some Scene {
        WindowGroup("Gerador de Documentos") {
            ContentView()
                .environmentObject(armazenamento)
                .frame(minWidth: 860, minHeight: 560)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Necessário quando o app é executado com `swift run`, fora de um pacote .app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
