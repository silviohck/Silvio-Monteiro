import AppKit
import Foundation
import SwiftUI

/// Envio da pasta sincronizada ao Google Drive: um .zip com a pasta inteira e o backup dos dados,
/// sempre no mesmo arquivo do Drive (substituído a cada envio). Usa a conexão da cópia no Drive.
extension Armazenamento {
    static let nomeDoZipNoDrive = "Orthck - modelos (backup).zip"

    /// Cria o .zip e envia; devolve o tamanho enviado, para o aviso.
    func enviarPastaAoGoogleDrive() async throws -> Int {
        guard let pasta = urlPastaSincronizada else {
            throw NSError(domain: "Orthck", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Escolha antes a pasta sincronizada (aba Modelos).",
            ])
        }
        guard drive.conectado else { throw ErroGoogle.semAutorizacao }
        enviandoPastaAoDrive = true
        defer { enviandoPastaAoDrive = false }
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("orthck-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: zip) }
        let dadosDoApp = arquivoDados
        try await Task.detached(priority: .userInitiated) {
            try Armazenamento.criarZip(da: pasta, dados: dadosDoApp, em: zip)
        }.value
        let conteudo = try Data(contentsOf: zip)
        let existente = try await drive.procurarArquivo(nome: Self.nomeDoZipNoDrive)
        _ = try await drive.enviarArquivoGrande(conteudo, nome: Self.nomeDoZipNoDrive, tipo: "application/zip", id: existente?.id)
        return conteudo.count
    }
}

/// Barra lateral: botão para mandar a pasta sincronizada ao Google Drive.
struct EnviarPastaAoDrive: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @AppStorage("ultimoEnvioPastaDrive") private var ultimoEnvio = 0.0
    @State private var resultado: String?
    @State private var conectando = false

    var body: some View {
        if armazenamento.urlPastaSincronizada != nil {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    if armazenamento.googleConectado {
                        enviar()
                    } else {
                        conectando = true
                    }
                } label: {
                    Label(
                        armazenamento.enviandoPastaAoDrive ? "Enviando…" : "Enviar pasta ao Google Drive",
                        systemImage: "icloud.and.arrow.up"
                    )
                    .frame(maxWidth: .infinity)
                }
                .disabled(armazenamento.enviandoPastaAoDrive)
                .help("Manda ao Google Drive um .zip com a pasta sincronizada inteira e os dados do app (substitui o anterior)")
                if ultimoEnvio > 0 {
                    Text("Pasta enviada em \(Date(timeIntervalSince1970: ultimoEnvio).formatted(date: .abbreviated, time: .shortened))")
                        .fonteApp(.legenda)
                        .foregroundStyle(.secondary)
                }
            }
            .alert("Google Drive", isPresented: Binding(get: { resultado != nil }, set: { if !$0 { resultado = nil } })) {
                Button("OK") { resultado = nil }
            } message: {
                Text(resultado ?? "")
            }
            .sheet(isPresented: $conectando, onDismiss: {
                if armazenamento.googleConectado { enviar() }
            }) {
                ConectarGoogleView()
                    .environmentObject(armazenamento)
            }
        }
    }

    private func enviar() {
        Task {
            do {
                let bytes = try await armazenamento.enviarPastaAoGoogleDrive()
                ultimoEnvio = Date().timeIntervalSince1970
                let tamanho = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                resultado = "Pasta enviada ao seu Google Drive como “\(Armazenamento.nomeDoZipNoDrive)” (\(tamanho)), com o backup dos dados. O envio anterior foi substituído."
            } catch {
                resultado = error.localizedDescription
            }
        }
    }
}
