import AppKit
import SwiftUI

@main
struct GeradorDocumentosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var armazenamento = Armazenamento()
    @AppStorage("tamanhoTexto") private var tamanhoTexto = TamanhoTexto.normal.rawValue
    @AppStorage("aparencia") private var aparencia = Aparencia.automatica.rawValue

    private var tamanho: TamanhoTexto { TamanhoTexto(rawValue: tamanhoTexto) ?? .normal }

    var body: some Scene {
        WindowGroup("Orthck") {
            ContentView()
                .environmentObject(armazenamento)
                .temaDoApp(tamanho: tamanho, aparencia: Aparencia(rawValue: aparencia) ?? .automatica)
                .frame(minWidth: 960, minHeight: 600)
        }
        .commands {
            // Aparência fica em Orthck › Ajustes… (⌘,); a pasta de dados, no menu Arquivo.
            CommandGroup(after: .newItem) {
                Button("Abrir pasta de dados (backup)") { armazenamento.abrirPastaDeDados() }
            }
            CommandGroup(after: .toolbar) {
                Button("Aumentar texto") {
                    tamanhoTexto = min(tamanhoTexto + 1, TamanhoTexto.muitoGrande.rawValue)
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(tamanho == .muitoGrande)
                Button("Diminuir texto") {
                    tamanhoTexto = max(tamanhoTexto - 1, TamanhoTexto.normal.rawValue)
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(tamanho == .normal)
                Button("Tamanho normal do texto") {
                    tamanhoTexto = TamanhoTexto.normal.rawValue
                }
                .keyboardShortcut("0", modifiers: .command)
                Divider()
            }
        }

        Settings {
            AjustesAparenciaView()
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

    /// Antes de fechar, envia ao Google Drive as mudanças que ainda esperavam o envio periódico
    /// (no máximo 15 segundos; sem internet, fecha assim mesmo).
    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let armazenamento = Armazenamento.atual, armazenamento.envioPendente else { return .terminateNow }
        var respondido = false
        let responder = {
            guard !respondido else { return }
            respondido = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        Task { @MainActor in
            await armazenamento.enviarPendenteAoDrive()
            responder()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { responder() }
        return .terminateLater
    }
}
