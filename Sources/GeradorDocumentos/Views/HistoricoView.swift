import AppKit
import SwiftUI

struct HistoricoView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var confirmarLimpeza = false
    @AppStorage("impressora") private var impressora = ""
    @State private var imprimindo: DocumentoGerado.ID?

    var body: some View {
        Group {
            if armazenamento.dados.historico.isEmpty {
                AvisoVazio(titulo: "Nenhum documento gerado ainda", icone: "clock")
            } else {
                List(armazenamento.dados.historico) { documento in
                    linha(documento)
                }
            }
        }
        .toolbar {
            Button {
                confirmarLimpeza = true
            } label: {
                Label("Limpar histórico", systemImage: "trash")
            }
            .disabled(armazenamento.dados.historico.isEmpty)
        }
        .confirmationDialog("Limpar o histórico?", isPresented: $confirmarLimpeza) {
            Button("Limpar", role: .destructive) { armazenamento.dados.historico.removeAll() }
        } message: {
            Text("Apenas a lista é apagada; os arquivos gerados continuam onde foram salvos.")
        }
    }

    private func linha(_ documento: DocumentoGerado) -> some View {
        let url = URL(fileURLWithPath: documento.caminho)
        let existe = FileManager.default.fileExists(atPath: documento.caminho)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text([documento.modelo, documento.paciente, documento.local ?? ""].filter { !$0.isEmpty }.joined(separator: " — "))
                Text("\(documento.data.formatted(date: .abbreviated, time: .shortened)) · \(existe ? url.lastPathComponent : "arquivo não encontrado")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Abrir") { NSWorkspace.shared.open(url) }
                .disabled(!existe)
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .disabled(!existe)
            Button(imprimindo == documento.id ? "Imprimindo…" : "Imprimir") {
                imprimindo = documento.id
                let modelo = armazenamento.modelo(documento.modeloID)
                Impressao.imprimir(
                    url,
                    impressora: impressora,
                    manterAberto: false,
                    paginasPorFolha: modelo?.paginasPorFolha ?? 1,
                    copias: modelo?.copias ?? 1
                ) { erro in
                    imprimindo = nil
                    if let erro { armazenamento.erro = erro }
                }
            }
            .disabled(!existe || imprimindo != nil)
        }
        .padding(.vertical, 2)
    }
}
