import AppKit
import UniformTypeIdentifiers
import SwiftUI

/// Uma cópia dos dados guardada em Backups: a do dia (feita sozinha, antes da primeira mudança do dia)
/// ou a feita antes de importar um arquivo.
struct CopiaDosDados: Identifiable {
    let url: URL
    let data: Date
    let antesDeImportar: Bool
    let pacientes: Int
    let documentos: Int
    var id: URL { url }
}

extension Armazenamento {
    /// As cópias guardadas em Backups, da mais nova para a mais antiga.
    func copiasDosDados() -> [CopiaDosDados] {
        let arquivos = (try? FileManager.default.contentsOfDirectory(
            at: pastaBackups, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return arquivos
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> CopiaDosDados? in
                let nome = url.lastPathComponent
                guard nome.hasPrefix("dados-") || nome.hasPrefix("antes-de-importar-") else { return nil }
                let data = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                // Só conta pacientes e documentos (sem ler o arquivo inteiro como dados do app).
                let json = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                guard let json else { return nil }
                return CopiaDosDados(
                    url: url, data: data, antesDeImportar: nome.hasPrefix("antes-de-importar-"),
                    pacientes: (json["pacientes"] as? [Any])?.count ?? 0,
                    documentos: (json["historico"] as? [Any])?.count ?? 0
                )
            }
            .sorted { $0.data > $1.data }
    }
}

/// Restaurar: escolher uma das cópias guardadas e voltar os dados para ela. Antes, os dados de agora
/// também viram uma cópia (dá para desfazer escolhendo essa cópia).
struct RestaurarBackupView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @Environment(\.dismiss) private var fechar
    @State private var copias: [CopiaDosDados] = []
    @State private var escolhida: CopiaDosDados?
    @State private var outroArquivo: URL?
    @State private var resultado: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restaurar uma cópia dos dados").font(.title2.bold())
            Text("O app guarda sozinho uma cópia dos pacientes, locais e histórico por dia (dos últimos 30 dias). Restaurar volta os dados para como estavam na cópia escolhida; os dados de agora viram uma cópia antes, para poder desfazer. A fila de impressão e os arquivos Word não mudam.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if copias.isEmpty {
                Text("Ainda não há cópias guardadas.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(copias) { copia in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(copia.data.formatted(date: .long, time: .shortened)).bold()
                            Text("\(copia.pacientes) pacientes · \(copia.documentos) documentos\(copia.antesDeImportar ? " · feita antes de importar/restaurar" : "")")
                                .fonteApp(.apoio)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restaurar…") { escolhida = copia }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 260)
            }
            HStack {
                Button("Abrir a pasta das cópias") { NSWorkspace.shared.open(armazenamento.pastaBackups) }
                Button("Usar outro arquivo…") { outroArquivo = escolherArquivo() }
                    .help("Um dados.json de outro computador ou guardado em outro lugar")
                Spacer()
                Button("Fechar") { fechar() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear { copias = armazenamento.copiasDosDados() }
        .confirmationDialog(
            "Voltar os dados para a cópia de \(escolhida?.data.formatted(date: .abbreviated, time: .shortened) ?? "")?",
            isPresented: Binding(get: { escolhida != nil }, set: { if !$0 { escolhida = nil } }),
            presenting: escolhida
        ) { copia in
            Button("Restaurar esta cópia", role: .destructive) { importar(copia.url, modo: .substituir) }
            Button("Cancelar", role: .cancel) {}
        } message: { copia in
            Text("Ficam \(copia.pacientes) pacientes e \(copia.documentos) documentos no histórico. O que foi feito depois dessa cópia sai do app (os dados de agora são guardados antes, como uma nova cópia).")
        }
        .confirmationDialog(
            "Usar “\(outroArquivo?.lastPathComponent ?? "")”?",
            isPresented: Binding(get: { outroArquivo != nil }, set: { if !$0 { outroArquivo = nil } }),
            presenting: outroArquivo
        ) { url in
            Button("Juntar com os dados atuais") { importar(url, modo: .juntar) }
            Button("Substituir todos os dados", role: .destructive) { importar(url, modo: .substituir) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Juntar: entram só os pacientes, locais e documentos que ainda não estão aqui; nada é apagado. Substituir: os dados atuais são trocados pelos do arquivo. Nos dois casos, os dados de agora são guardados antes, como uma cópia.")
        }
        .alert("Pronto", isPresented: Binding(get: { resultado != nil }, set: { if !$0 { resultado = nil } })) {
            Button("OK") { resultado = nil }
        } message: {
            Text(resultado ?? "")
        }
    }

    private func escolherArquivo() -> URL? {
        let painel = NSOpenPanel()
        painel.allowedContentTypes = [.json]
        painel.allowsMultipleSelection = false
        painel.canChooseDirectories = false
        painel.message = "Escolha um arquivo de dados do Orthck (dados.json)."
        painel.prompt = "Escolher"
        return painel.runModal() == .OK ? painel.url : nil
    }

    private func importar(_ url: URL, modo: Armazenamento.ModoDeImportacao) {
        do {
            resultado = try armazenamento.importarDados(de: url, modo: modo)
            copias = armazenamento.copiasDosDados()
        } catch {
            armazenamento.erro = error.localizedDescription
        }
        escolhida = nil
        outroArquivo = nil
    }
}
