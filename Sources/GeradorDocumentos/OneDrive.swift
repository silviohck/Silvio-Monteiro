import AppKit
import Foundation

/// Envio da pasta sincronizada ao OneDrive pelo app do OneDrive instalado no Mac: o Orthck copia a
/// pasta para dentro da pasta do OneDrive, e o app do OneDrive leva para a nuvem (sem outro login).
extension Armazenamento {
    /// A pasta do OneDrive no Mac (~/Library/CloudStorage/OneDrive-…), se o app do OneDrive estiver instalado.
    static func pastaDoOneDriveDetectada() -> URL? {
        let nuvens = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let itens = (try? FileManager.default.contentsOfDirectory(at: nuvens, includingPropertiesForKeys: nil)) ?? []
        return itens
            .filter { $0.lastPathComponent.hasPrefix("OneDrive") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    /// Copia a pasta sincronizada para `<OneDrive>/Orthck/<nome da pasta>`, deixando igual à daqui
    /// (o que foi apagado aqui também sai de lá), sem os arquivos temporários do Word. Junto vai o
    /// backup dos dados do app. Devolve a pasta de destino.
    func enviarAoOneDrive(base: URL) async throws -> URL {
        guard let origem = urlPastaSincronizada else {
            throw NSError(domain: "Orthck", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Escolha antes a pasta sincronizada (aba Modelos).",
            ])
        }
        enviandoOneDrive = true
        defer { enviandoOneDrive = false }
        let pastaOrthck = base.appendingPathComponent("Orthck", isDirectory: true)
        let destino = pastaOrthck.appendingPathComponent(origem.lastPathComponent, isDirectory: true)
        let dadosDoApp = arquivoDados
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
            let processo = Process()
            processo.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
            processo.arguments = [
                "-a", "--delete",
                "--exclude", "~$*", "--exclude", ".DS_Store",
                origem.path + "/", destino.path + "/",
            ]
            let erro = Pipe()
            processo.standardError = erro
            try processo.run()
            processo.waitUntilExit()
            guard processo.terminationStatus == 0 else {
                let mensagem = String(data: erro.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw NSError(domain: "Orthck", code: Int(processo.terminationStatus), userInfo: [
                    NSLocalizedDescriptionKey: "Não foi possível copiar para o OneDrive. \(mensagem)",
                ])
            }
            // Backup dos pacientes, locais e histórico ao lado da pasta (fora dela, para não virar modelo).
            let backup = pastaOrthck.appendingPathComponent("Orthck - dados (backup).json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: dadosDoApp, to: backup)
        }.value
        return destino
    }
}

/// Barra lateral: botão para enviar a pasta sincronizada ao OneDrive.
struct EnviarAoOneDrive: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    /// Pasta do OneDrive escolhida (vazia = a detectada em ~/Library/CloudStorage).
    @AppStorage("pastaOneDrive") private var pastaEscolhida = ""
    @AppStorage("ultimoEnvioOneDrive") private var ultimoEnvio = 0.0
    @State private var resultado: String?

    var body: some View {
        if armazenamento.urlPastaSincronizada != nil {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Button {
                        enviar()
                    } label: {
                        Label(armazenamento.enviandoOneDrive ? "Enviando…" : "Enviar ao OneDrive", systemImage: "icloud.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(armazenamento.enviandoOneDrive)
                    .help("Copia a pasta sincronizada (e os dados do app) para a pasta do OneDrive; o app do OneDrive leva para a nuvem")
                    Menu {
                        Button("Escolher a pasta do OneDrive…") { _ = escolherPasta() }
                        if let base = base {
                            Button("Abrir no Finder") {
                                NSWorkspace.shared.open(base.appendingPathComponent("Orthck", isDirectory: true))
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                if ultimoEnvio > 0 {
                    Text("Enviado em \(Date(timeIntervalSince1970: ultimoEnvio).formatted(date: .abbreviated, time: .shortened))")
                        .fonteApp(.legenda)
                        .foregroundStyle(.secondary)
                }
            }
            .alert("OneDrive", isPresented: Binding(get: { resultado != nil }, set: { if !$0 { resultado = nil } })) {
                Button("OK") { resultado = nil }
            } message: {
                Text(resultado ?? "")
            }
        }
    }

    private var base: URL? {
        if !pastaEscolhida.isEmpty, FileManager.default.fileExists(atPath: pastaEscolhida) {
            return URL(fileURLWithPath: pastaEscolhida, isDirectory: true)
        }
        return Armazenamento.pastaDoOneDriveDetectada()
    }

    private func escolherPasta() -> URL? {
        let url = Self.painel()
        if let url { pastaEscolhida = url.path }
        return url
    }

    private static func painel() -> URL? {
        let painel = NSOpenPanel()
        painel.canChooseDirectories = true
        painel.canChooseFiles = false
        painel.prompt = "Usar esta pasta"
        painel.message = "Escolha a pasta do OneDrive (fica na barra lateral do Finder, em Locais). O Orthck cria dentro dela a pasta “Orthck”."
        painel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage")
        return painel.runModal() == .OK ? painel.url : nil
    }

    private func enviar() {
        guard let base = base ?? escolherPasta() else {
            resultado = "Não achei a pasta do OneDrive neste Mac. Instale o app do OneDrive e entre na sua conta, ou escolha a pasta em “…” › Escolher a pasta do OneDrive…"
            return
        }
        Task {
            do {
                let destino = try await armazenamento.enviarAoOneDrive(base: base)
                ultimoEnvio = Date().timeIntervalSince1970
                resultado = "Pasta copiada para “\(base.lastPathComponent)/Orthck/\(destino.lastPathComponent)”, com o backup dos dados. O app do OneDrive envia para a nuvem em seguida."
            } catch {
                resultado = error.localizedDescription
            }
        }
    }
}
