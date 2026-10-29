import SwiftUI

/// Lateral da tela Gerar documento: atalho para imprimir a fila e os 5 últimos pacientes atendidos
/// (pelo Histórico). Um clique no paciente preenche o nome e o cadastro dele.
struct UltimosPacientes: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @AppStorage("impressora") private var impressora = ""
    let escolher: (DocumentoGerado) -> Void

    private var pendentes: [ItemFilaImpressao] {
        armazenamento.dados.filaImpressao.filter { $0.situacao == .pendente }
    }

    /// O documento mais recente de cada paciente, do mais novo para o mais antigo.
    private var recentes: [DocumentoGerado] {
        var vistos = Set<String>()
        var lista: [DocumentoGerado] = []
        for documento in armazenamento.dados.historico.sorted(by: { $0.data > $1.data }) {
            let nome = documento.paciente.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nome.isEmpty else { continue }
            let chave = documento.pacienteID?.uuidString ?? nome.uppercased()
            guard vistos.insert(chave).inserted else { continue }
            lista.append(documento)
            if lista.count == 5 { break }
        }
        return lista
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            filaDeImpressao
            Divider().padding(.vertical, 4)
            TituloSecao("Últimos pacientes", icone: "clock.arrow.circlepath")
            let lista = recentes
            if lista.isEmpty {
                Text("Os pacientes atendidos aparecem aqui.")
                    .fonteApp(.apoio)
                    .foregroundStyle(.secondary)
            }
            ForEach(lista) { documento in
                Button {
                    escolher(documento)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(documento.paciente.uppercased())
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text([documento.modelo, documento.local ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .fonteApp(.legenda)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(documento.data.formatted(date: .abbreviated, time: .shortened))
                            .fonteApp(.legenda)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Tema.lateral))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Usar \(documento.paciente)")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Tema.fundo)
    }

    /// Atalho da Fila de impressão: quantos esperam e o botão de imprimir todos.
    private var filaDeImpressao: some View {
        let quantidade = pendentes.count
        return VStack(alignment: .leading, spacing: 8) {
            TituloSecao("Fila de impressão", icone: "printer.fill")
            if armazenamento.processandoFila {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Imprimindo…").foregroundStyle(.secondary)
                }
            } else {
                Text(quantidade == 0 ? "Nenhum documento esperando." : "\(quantidade) \(quantidade == 1 ? "documento esperando" : "documentos esperando")")
                    .fonteApp(.apoio)
                    .foregroundStyle(.secondary)
            }
            Button {
                let ids = Set(pendentes.map(\.id))
                Task { await armazenamento.imprimirFila(ids: ids, impressora: impressora) }
            } label: {
                Label("Imprimir fila (\(quantidade))", systemImage: "printer.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(quantidade == 0 || armazenamento.processandoFila)
            .help("Imprime todos os documentos que estão esperando na Fila de impressão, um por vez")
        }
    }
}
