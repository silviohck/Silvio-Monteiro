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
                VStack(spacing: 0) {
                    HStack {
                        Text("\(armazenamento.dados.historico.count) \(armazenamento.dados.historico.count == 1 ? "documento" : "documentos")")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            confirmarLimpeza = true
                        } label: {
                            Label("Limpar histórico…", systemImage: "trash")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    List(armazenamento.dados.historico) { documento in
                        linha(documento)
                            .contextMenu {
                                Button("Remover do histórico") { remover(documento) }
                            }
                    }
                    .fundoSuave()
                }
                .background(Tema.fundo)
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
            Button("Limpar histórico", role: .destructive) { armazenamento.dados.historico.removeAll() }
        } message: {
            Text("Apenas a lista é apagada. Os arquivos dos documentos não são apagados e continuam nas pastas onde foram salvos.")
        }
    }

    /// Tira só o item da lista; o arquivo continua na pasta.
    private func remover(_ documento: DocumentoGerado) {
        armazenamento.dados.historico.removeAll { $0.id == documento.id }
    }

    private func linha(_ documento: DocumentoGerado) -> some View {
        let url = URL(fileURLWithPath: documento.caminho)
        let existe = FileManager.default.fileExists(atPath: documento.caminho)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text([documento.modelo, documento.paciente, documento.local ?? ""].filter { !$0.isEmpty }.joined(separator: " — "))
                Text("\(documento.data.formatted(date: .abbreviated, time: .shortened)) · \(existe ? url.lastPathComponent : "arquivo não encontrado")")
                    .fonteApp(.legenda)
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
            Button {
                remover(documento)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remover da lista (o arquivo não é apagado)")
        }
        .padding(.vertical, 2)
    }
}
