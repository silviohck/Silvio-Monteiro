import AppKit
import SwiftUI

/// Documentos gerados aguardando impressão, na ordem em que serão impressos (o mais antigo primeiro).
/// A fila fica salva ao fechar o app. Remover um item nunca apaga o .docx nem o histórico.
struct FilaImpressaoView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @AppStorage("impressora") private var impressora = ""
    @State private var selecionados = Set<UUID>()
    @State private var confirmarReenvio: ItemFilaImpressao?

    private var fila: [ItemFilaImpressao] { armazenamento.dados.filaImpressao }

    private var pendentes: [ItemFilaImpressao] {
        fila.filter { $0.situacao == .pendente }
    }

    private var selecionadosPendentes: Set<UUID> {
        Set(pendentes.map(\.id)).intersection(selecionados)
    }

    private var enviados: Int {
        fila.filter { $0.situacao == .enviado }.count
    }

    private var folhas: Int {
        pendentes.reduce(0) { $0 + $1.copias }
    }

    var body: some View {
        Group {
            if fila.isEmpty {
                AvisoVazio(
                    titulo: "Fila vazia",
                    icone: "printer",
                    mensagem: "Na tela Gerar documento, deixe “Depois de gerar” em “Adicionar à fila de impressão”. Ao fim dos atendimentos, imprima tudo aqui de uma vez."
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    cabecalho
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Tema.superficie)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Tema.borda.opacity(0.75)).frame(height: 1)
                        }
                    List {
                        ForEach(Array(fila.enumerated()), id: \.element.id) { posicao, item in
                            linha(item, posicao: posicao + 1)
                        }
                    }
                    .fundoSuave()
                    Text("Cada documento sai da fila assim que o Word o recebe para imprimir (continua salvo e no Histórico). Itens com erro ou envio interrompido ficam aqui e só são reenviados com sua confirmação, para não sair em dobro.")
                        .fonteApp(.legenda)
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
                .background(Tema.fundo)
            }
        }
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

    private var cabecalho: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                TituloSecao("Fila de impressão", icone: "printer.fill")
                Spacer()
                if armazenamento.processandoFila {
                    ProgressView().controlSize(.small)
                    Text("Imprimindo um por vez…").foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    armazenamento.pararImpressoes(impressora: impressora)
                } label: {
                    Label("Parar impressões", systemImage: "stop.circle.fill")
                }
                .tint(.red)
                .help("Para a fila do app e cancela o que já está na fila de impressão do Mac")
            }
            Text(resumo)
                .fonteApp(.apoio)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    iniciarImpressao(Set(pendentes.map(\.id)))
                } label: {
                    Label("Imprimir todos (\(pendentes.count))", systemImage: "printer.fill")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(pendentes.isEmpty || armazenamento.processandoFila)

                Button("Imprimir marcados (\(selecionadosPendentes.count))") {
                    iniciarImpressao(selecionadosPendentes)
                }
                .controlSize(.large)
                .disabled(selecionadosPendentes.isEmpty || armazenamento.processandoFila)

                Spacer()
                if enviados > 0 {
                    Button("Limpar enviados") {
                        armazenamento.limparEnviadosDaFila()
                    }
                    .disabled(armazenamento.processandoFila)
                    .help("Tira da lista os já enviados; os arquivos Word continuam salvos")
                }
            }
        }
    }

    private var resumo: String {
        var partes = ["\(pendentes.count) aguardando"]
        if folhas != pendentes.count { partes.append("\(folhas) cópias no total") }
        if enviados > 0 { partes.append("\(enviados) \(enviados == 1 ? "enviado" : "enviados")") }
        let destino = impressora.isEmpty ? "impressora padrão do Mac" : Impressao.nomeAmigavel(impressora)
        return partes.joined(separator: " · ") + " — imprime em: \(destino) (troque na barra lateral)"
    }

    private func linha(_ item: ItemFilaImpressao, posicao: Int) -> some View {
        let existe = FileManager.default.fileExists(atPath: item.caminho)
        let pendente = item.situacao == .pendente
        return HStack(spacing: 12) {
            Toggle("Marcar", isOn: Binding(
                get: { selecionados.contains(item.id) },
                set: { marcado in
                    if marcado { selecionados.insert(item.id) } else { selecionados.remove(item.id) }
                }
            ))
            .labelsHidden()
            .disabled(!pendente || armazenamento.processandoFila)

            Text("\(posicao)")
                .fonteApp(.codigo)
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.paciente.isEmpty ? item.modelo : "\(item.paciente) — \(item.modelo)")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text("\(item.local ?? "Sem local") · \(item.criadoEm.formatted(date: .omitted, time: .shortened))")
                    .fonteApp(.legenda)
                    .foregroundStyle(.secondary)
                if let observacao = item.observacao, !pendente {
                    Text(observacao)
                        .fonteApp(.legenda)
                        .foregroundStyle(item.situacao == .erro || item.situacao == .incerto ? Color.orange : Color.secondary)
                        .lineLimit(2)
                }
                if !existe {
                    Label("Arquivo não encontrado", systemImage: "exclamationmark.triangle.fill")
                        .fonteApp(.legenda)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)

            etiqueta(item.situacao)

            if pendente {
                Stepper(value: Binding(
                    get: { item.copias },
                    set: { armazenamento.definirCopias($0, doItem: item.id) }
                ), in: 1...20) {
                    Text("\(item.copias) \(item.copias == 1 ? "cópia" : "cópias")").monospacedDigit()
                }
                .fixedSize()
                .disabled(armazenamento.processandoFila)
            } else {
                Text("\(item.copias) \(item.copias == 1 ? "cópia" : "cópias")")
                    .foregroundStyle(.secondary)
            }

            if item.situacao == .erro || item.situacao == .incerto {
                Button("Reenviar…") { confirmarReenvio = item }
                    .disabled(armazenamento.processandoFila || !existe)
            }
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: item.caminho))
            } label: {
                Image(systemName: "doc.text")
            }
            .buttonStyle(.borderless)
            .disabled(!existe)
            .help("Abrir no Word")
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.caminho)])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .disabled(!existe)
            .help("Mostrar no Finder")
            Button {
                selecionados.remove(item.id)
                armazenamento.removerDaFila(item.id)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(armazenamento.processandoFila)
            .help("Tirar da fila (o documento continua salvo)")
        }
        .padding(.vertical, 4)
        .opacity(pendente || item.situacao == .enviando ? 1 : 0.75)
    }

    private func etiqueta(_ situacao: SituacaoImpressao) -> some View {
        let (texto, cor): (String, Color) = {
            switch situacao {
            case .pendente: return ("Aguardando", Tema.destaque)
            case .enviando: return ("Imprimindo…", Tema.destaque)
            case .enviado: return ("Enviado", Tema.sucesso)
            case .erro: return ("Erro", .orange)
            case .incerto: return ("Conferir", .orange)
            }
        }()
        return Text(texto)
            .fonteApp(.legenda)
            .foregroundStyle(cor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(cor.opacity(0.10)))
    }

    private func iniciarImpressao(_ ids: Set<UUID>) {
        guard !ids.isEmpty, !armazenamento.processandoFila else { return }
        selecionados.subtract(ids)
        Task {
            await armazenamento.imprimirFila(ids: ids, impressora: impressora)
        }
    }
}
