import AppKit
import SwiftUI

/// Lista local e persistente. Remover um item nunca apaga o .docx nem o histórico.
struct FilaImpressaoView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @AppStorage("impressora") private var impressora = ""
    @State private var selecionados = Set<UUID>()
    @State private var confirmarReenvio: ItemFilaImpressao?

    private var pendentes: [ItemFilaImpressao] {
        armazenamento.dados.filaImpressao.filter { $0.situacao == .pendente }
    }

    private var selecionadosPendentes: Set<UUID> {
        Set(pendentes.map(\.id)).intersection(selecionados)
    }

    private var enviados: Int {
        armazenamento.dados.filaImpressao.filter { $0.situacao == .enviado }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Fila de impressão")
                        .font(.title2.bold())
                    Text("\(pendentes.count) pendente(s) · \(enviados) enviado(s) ao Word")
                        .foregroundStyle(.secondary)
                    Text("Os documentos permanecem salvos nas pastas originais. A fila também permanece ao fechar o Orthck.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if armazenamento.processandoFila {
                    ProgressView("Enviando um por vez…")
                }
            }
            .padding(.horizontal)

            HStack(spacing: 10) {
                Button("Selecionar pendentes") {
                    selecionados = Set(pendentes.map(\.id))
                }
                .disabled(pendentes.isEmpty || armazenamento.processandoFila)

                Button("Imprimir selecionados (\(selecionadosPendentes.count))") {
                    iniciarImpressao(selecionadosPendentes)
                }
                .disabled(selecionadosPendentes.isEmpty || armazenamento.processandoFila)

                Button {
                    iniciarImpressao(Set(pendentes.map(\.id)))
                } label: {
                    Label("Imprimir todos os pendentes", systemImage: "printer.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(pendentes.isEmpty || armazenamento.processandoFila)

                Spacer()
                if enviados > 0 {
                    Button("Limpar enviados") {
                        armazenamento.limparEnviadosDaFila()
                    }
                    .disabled(armazenamento.processandoFila)
                    .help("Remove apenas os registros já enviados; não apaga arquivos Word")
                }
            }
            .padding(.horizontal)

            Text("Impressora: \(impressora.isEmpty ? "padrão do macOS" : Impressao.nomeAmigavel(impressora)). Para alterar, use o seletor da barra lateral.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if armazenamento.dados.filaImpressao.isEmpty {
                Spacer()
                AvisoVazio(
                    titulo: "Fila vazia",
                    icone: "printer",
                    mensagem: "Na tela Gerar documento, escolha “Adicionar à fila”. Depois imprima todos aqui."
                )
                Spacer()
            } else {
                List {
                    ForEach(armazenamento.dados.filaImpressao.reversed()) { item in
                        linha(item)
                    }
                }
                .listStyle(.inset)
            }

            Text("“Enviado” significa que o Word recebeu o comando; confirme a impressão na impressora. Itens com erro ou envio interrompido só podem ser reenviados após sua confirmação.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding([.horizontal, .bottom])
        }
        .padding(.top)
        .fundoSuave()
        .confirmationDialog(
            "Reenviar este documento?",
            isPresented: Binding(
                get: { confirmarReenvio != nil },
                set: { if !$0 { confirmarReenvio = nil } }
            ),
            presenting: confirmarReenvio
        ) { item in
            Button("Confirmar reenvio") {
                armazenamento.reenfileirar(item.id)
                iniciarImpressao(Set([item.id]))
                confirmarReenvio = nil
            }
            Button("Cancelar", role: .cancel) { confirmarReenvio = nil }
        } message: { item in
            Text("Confira antes se \(item.modelo) — \(item.paciente) já foi impresso. Reenviar pode produzir cópias duplicadas.")
        }
    }

    private func linha(_ item: ItemFilaImpressao) -> some View {
        let existe = FileManager.default.fileExists(atPath: item.caminho)
        return HStack(spacing: 12) {
            Toggle(
                "Selecionar",
                isOn: Binding(
                    get: { selecionados.contains(item.id) },
                    set: { marcado in
                        if marcado { selecionados.insert(item.id) }
                        else { selecionados.remove(item.id) }
                    }
                )
            )
            .labelsHidden()
            .disabled(item.situacao != .pendente || armazenamento.processandoFila)

            VStack(alignment: .leading, spacing: 3) {
                Text([item.modelo, item.paciente].filter { !$0.isEmpty }.joined(separator: " — "))
                    .fontWeight(.medium)
                Text("\(item.local ?? "Sem local") · \(item.copias) \(item.copias == 1 ? "cópia" : "cópias") · \(situacao(item.situacao))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let observacao = item.observacao {
                    Text(observacao)
                        .font(.caption)
                        .foregroundStyle(item.situacao == .erro || item.situacao == .incerto ? .orange : .secondary)
                        .lineLimit(2)
                }
                if !existe {
                    Label("Arquivo não encontrado", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            Button("Abrir") {
                NSWorkspace.shared.open(URL(fileURLWithPath: item.caminho))
            }
            .disabled(!existe)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.caminho)])
            } label: {
                Image(systemName: "folder")
            }
            .help("Mostrar no Finder")
            .disabled(!existe)
            if item.situacao == .erro || item.situacao == .incerto {
                Button("Reenviar…") { confirmarReenvio = item }
                    .disabled(armazenamento.processandoFila || !existe)
            }
            Button {
                selecionados.remove(item.id)
                armazenamento.removerDaFila(item.id)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .help("Remover da fila sem excluir o documento")
            .disabled(armazenamento.processandoFila)
        }
        .padding(.vertical, 5)
    }

    private func iniciarImpressao(_ ids: Set<UUID>) {
        guard !ids.isEmpty, !armazenamento.processandoFila else { return }
        selecionados.subtract(ids)
        Task {
            await armazenamento.imprimirFila(ids: ids, impressora: impressora)
        }
    }

    private func situacao(_ valor: SituacaoImpressao) -> String {
        switch valor {
        case .pendente: return "Aguardando impressão"
        case .enviando: return "Enviando ao Word"
        case .enviado: return "Enviado ao Word"
        case .erro: return "Erro no envio"
        case .incerto: return "Envio interrompido; conferir"
        }
    }
}
