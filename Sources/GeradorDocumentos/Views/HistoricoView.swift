import AppKit
import SwiftUI

struct HistoricoView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var confirmarLimpeza = false

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
                Text(documento.paciente.isEmpty ? documento.modelo : "\(documento.modelo) — \(documento.paciente)")
                Text("\(documento.data.formatted(date: .abbreviated, time: .shortened)) · \(existe ? url.lastPathComponent : "arquivo não encontrado")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Abrir") { NSWorkspace.shared.open(url) }
                .disabled(!existe)
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .disabled(!existe)
        }
        .padding(.vertical, 2)
    }
}
