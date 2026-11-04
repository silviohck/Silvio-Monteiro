import AppKit
import SwiftUI

/// Lateral da tela Gerar documento: atalho da fila de impressão e os últimos pacientes atendidos
/// (até 12), em ordem alfabética, com o local e os documentos de cada um, para escolher de novo com um clique.
struct PainelPacientesRecentes: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    /// Paciente escolhido agora no formulário, destacado na lista.
    let pacienteAtual: Paciente.ID?
    let escolher: (Paciente) -> Void
    /// "" = todos os locais, ou o nome do local.
    @AppStorage("filtroLocalRecentes") private var filtro = ""
    @AppStorage("impressora") private var impressora = ""

    private var pendentes: [ItemFilaImpressao] {
        armazenamento.dados.filaImpressao.filter { $0.situacao == .pendente }
    }
    /// nil = todas as datas; senão, só quem teve documento gerado nesse dia.
    @State private var dia: Date?

    var body: some View {
        let dias = armazenamento.diasComAtendimento
        // Os mais recentes entram na lista; na tela, ficam em ordem alfabética.
        let itens = armazenamento.pacientesRecentes(
            local: filtro.isEmpty ? nil : filtro, dia: dia, limite: dia == nil ? 12 : .max
        ).sorted { $0.paciente.nome.localizedStandardCompare($1.paciente.nome) == .orderedAscending }
        VStack(alignment: .leading, spacing: 10) {
            filaDeImpressao
            Divider().padding(.vertical, 2)
            TituloSecao("Atendidos recentemente", icone: "clock.arrow.circlepath")
            Picker("Local", selection: $filtro) {
                Text("Todos os locais").tag("")
                ForEach(armazenamento.locaisOrdenados) { local in
                    Text(local.nome.isEmpty ? "Local sem nome" : local.nome).tag(local.nome)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            // Só os dias em que houve atendimento (documento gerado).
            Picker("Data", selection: $dia) {
                Text("Todas as datas").tag(Date?.none)
                if !dias.isEmpty { Divider() }
                ForEach(dias, id: \.self) { umDia in
                    Text(umDia.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits).year()))
                        .tag(Optional(umDia))
                }
            }
            .pickerStyle(.menu)
            .onChange(of: dias) { novos in
                if let dia, !novos.contains(dia) { self.dia = nil }
            }
            if itens.isEmpty {
                Text(filtro.isEmpty && dia == nil
                    ? "Os pacientes aparecem aqui depois do primeiro documento gerado."
                    : "Nenhum paciente com esse filtro.")
                    .fonteApp(.apoio)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(itens, id: \.paciente.id) { item in
                        LinhaPacienteRecente(
                            paciente: item.paciente,
                            ultimo: item.ultimo,
                            documentos: armazenamento.documentos(de: item.paciente),
                            selecionado: item.paciente.id == pacienteAtual
                        ) {
                            escolher(item.paciente)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Tema.lateral)
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
            .disabled(quantidade == 0 || armazenamento.processandoFila)
            .help("Imprime todos os documentos que estão esperando na Fila de impressão, um por vez")
        }
    }
}


/// Uma linha da lista: nome e, embaixo, o último documento, o local e a data.
/// À direita, o número de documentos; clicando, aparecem os documentos gerados para o paciente.
private struct LinhaPacienteRecente: View {
    let paciente: Paciente
    let ultimo: DocumentoGerado
    let documentos: [DocumentoGerado]
    let selecionado: Bool
    let escolher: () -> Void
    @State private var sobre = false
    @State private var aberto = false

    /// Mais que isso fica para a aba Histórico, para a lista não crescer demais.
    private static let documentosVisiveis = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button(action: escolher) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(paciente.nome)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text([ultimo.modelo, ultimo.local ?? "", ultimo.data.formatted(.dateTime.day().month(.twoDigits))]
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                                .fonteApp(.legenda)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(paciente.nome) · \(Armazenamento.identificacao(paciente)) · último: \(ultimo.modelo)")
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { aberto.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.text")
                        Text("\(documentos.count)")
                            .monospacedDigit()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(aberto ? 180 : 0))
                    }
                    .fonteApp(.legenda)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 5)
                    .background(Capsule().fill(aberto || sobre ? Tema.lateral : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(aberto ? "Esconder os documentos" : "Ver os documentos gerados para \(paciente.nome)")
            }
            if aberto {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(documentos.prefix(Self.documentosVisiveis)) { documento in
                        LinhaDocumentoGerado(documento: documento)
                    }
                    if documentos.count > Self.documentosVisiveis {
                        Text("+ \(documentos.count - Self.documentosVisiveis) na aba Histórico")
                            .fonteApp(.legenda)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 2)
                    }
                }
                .padding(.leading, 13)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selecionado ? Tema.destaqueSuave : (sobre || aberto ? Tema.superficie : .clear))
        )
        .onHover { sobre = $0 }
    }
}

/// Um documento gerado: atalhos para abrir no Word e mostrar no Finder ao lado (clicar no nome também abre).
private struct LinhaDocumentoGerado: View {
    let documento: DocumentoGerado
    @State private var sobre = false
    /// Nome completo do arquivo, mostrado logo depois que o cursor para sobre o nome.
    @State private var mostrarNomeCompleto = false
    @State private var esperaDoNome: Task<Void, Never>?

    private var arquivo: URL { URL(fileURLWithPath: documento.caminho) }
    private var existe: Bool { FileManager.default.fileExists(atPath: documento.caminho) }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                NSWorkspace.shared.open(arquivo)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text(documento.modelo)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .underline(sobre && existe)
                    Spacer(minLength: 4)
                    Text(documento.data.formatted(.dateTime.day().month(.twoDigits)))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { dentro in
                esperaDoNome?.cancel()
                if dentro {
                    esperaDoNome = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        guard !Task.isCancelled else { return }
                        mostrarNomeCompleto = true
                    }
                } else {
                    mostrarNomeCompleto = false
                }
            }
            .popover(isPresented: $mostrarNomeCompleto, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(arquivo.lastPathComponent)
                        .fontWeight(.medium)
                    Text(existe
                        ? arquivo.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                        : "Arquivo não encontrado")
                        .fonteApp(.legenda)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420, alignment: .leading)
                .padding(10)
            }
            Button {
                NSWorkspace.shared.open(arquivo)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .help("Abrir no Word")
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([arquivo])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Mostrar no Finder")
        }
        .fonteApp(.legenda)
        .padding(.vertical, 3)
        .disabled(!existe)
        .opacity(existe ? 1 : 0.45)
        .onHover { sobre = $0 }
        .contextMenu {
            Button("Abrir") { NSWorkspace.shared.open(arquivo) }
                .disabled(!existe)
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([arquivo]) }
                .disabled(!existe)
        }
    }
}
