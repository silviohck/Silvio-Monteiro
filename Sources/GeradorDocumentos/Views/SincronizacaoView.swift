import AppKit
import SwiftUI

/// Mostra o painel para escolher uma pasta.
@MainActor
func escolherPasta(mensagem: String) -> URL? {
    let painel = NSOpenPanel()
    painel.canChooseDirectories = true
    painel.canChooseFiles = false
    painel.allowsMultipleSelection = false
    painel.prompt = "Escolher"
    painel.message = mensagem
    return painel.runModal() == .OK ? painel.url : nil
}

/// Quadro no topo da aba Modelos: pasta acompanhada, situação e botão de sincronizar.
struct PainelSincronizacao: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var configurando = false

    var body: some View {
        Group {
            if let pasta = armazenamento.urlPastaSincronizada {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Tema.destaque)
                        Text(pasta.lastPathComponent)
                            .bold()
                            .lineLimit(1)
                            .help(pasta.path)
                        Spacer()
                        Button {
                            Task { await armazenamento.sincronizar() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(armazenamento.sincronizacao.emAndamento)
                        .help("Sincronizar agora")
                        Button {
                            configurando = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.borderless)
                        .help("Pasta sincronizada e subpastas")
                    }
                    situacao
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Tema.fundo))
            } else {
                Button {
                    configurando = true
                } label: {
                    Label("Sincronizar com uma pasta…", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Os modelos da pasta entram sozinhos no app e se atualizam quando você muda os arquivos")
            }
        }
        .sheet(isPresented: $configurando, onDismiss: {
            Task { await armazenamento.sincronizar() }
        }) {
            AjustesSincronizacaoView()
                .environmentObject(armazenamento)
        }
    }

    @ViewBuilder
    private var situacao: some View {
        let estado = armazenamento.sincronizacao
        if estado.emAndamento {
            ProgressView(value: Double(estado.feitos), total: Double(max(estado.total, 1))) {
                Text("Sincronizando \(estado.feitos) de \(estado.total)…").fonteApp(.legenda)
            }
        } else if !estado.erros.isEmpty {
            Text("\(estado.erros.count) \(estado.erros.count == 1 ? "arquivo com problema" : "arquivos com problema")")
                .fonteApp(.legenda)
                .foregroundStyle(.orange)
                .help(estado.erros.joined(separator: "\n"))
        } else if let ultima = estado.ultima {
            Text("Atualizado às \(ultima.formatted(date: .omitted, time: .shortened))" + mudancas(estado))
                .fonteApp(.legenda)
                .foregroundStyle(.secondary)
        }
    }

    private func mudancas(_ estado: EstadoSincronizacao) -> String {
        var partes: [String] = []
        if estado.novos > 0 { partes.append("\(estado.novos) \(estado.novos == 1 ? "novo" : "novos")") }
        if estado.atualizados > 0 { partes.append("\(estado.atualizados) \(estado.atualizados == 1 ? "alterado" : "alterados")") }
        if estado.removidos > 0 { partes.append("\(estado.removidos) \(estado.removidos == 1 ? "removido" : "removidos")") }
        return partes.isEmpty ? "" : " · " + partes.joined(separator: ", ")
    }
}

/// Escolha da pasta sincronizada e de quais subpastas são locais de atendimento.
struct AjustesSincronizacaoView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @Environment(\.dismiss) private var dismiss
    @State private var subpastas: [String] = []
    @State private var confirmarParada = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pasta sincronizada").fonteApp(.titulo)
            Text("O app acompanha esta pasta: arquivos novos viram modelos, arquivos editados no Word são atualizados e arquivos apagados saem do app. Cada subpasta é um local de atendimento e, dentro dela, cada subpasta é um tipo de documento (a subpasta onde os documentos gerados são salvos). Seus arquivos nunca são alterados pelo app.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(armazenamento.urlPastaSincronizada.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Nenhuma pasta escolhida")
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button(armazenamento.urlPastaSincronizada == nil ? "Escolher pasta…" : "Trocar pasta…") {
                    if let url = escolherPasta(mensagem: "Escolha a pasta principal dos modelos (com uma subpasta para cada local).") {
                        armazenamento.definirPastaSincronizada(url)
                        lerSubpastas()
                    }
                }
                .buttonStyle(.borderedProminent)
                if let url = armazenamento.urlPastaSincronizada {
                    Button("Abrir no Finder") { NSWorkspace.shared.open(url) }
                }
            }

            if !subpastas.isEmpty {
                Text("O que é cada subpasta?").bold()
                List {
                    ForEach(subpastas, id: \.self) { pasta in
                        HStack {
                            Text(pasta)
                            Spacer()
                            Picker(pasta, selection: papel(de: pasta)) {
                                ForEach(PapelDaPasta.allCases) { papel in
                                    Text(papel.nome).tag(papel)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 300)
                        }
                    }
                }
                .fundoSuave(Tema.lateral)
                Text("“Local”: uma pasta por local de atendimento. “Todos os locais”: os modelos dela (ex.: 1 - APAC) aparecem em todos os locais, e os documentos gerados vão para uma subpasta com o mesmo nome dentro da pasta de cada local. “Ignorar”: pastas que não têm modelos (ex.: mídias). Arquivos .docx soltos na pasta principal também valem para todos os locais.")
                    .fonteApp(.legenda)
                    .foregroundStyle(.secondary)
            } else {
                Spacer(minLength: 0)
            }

            HStack {
                if armazenamento.urlPastaSincronizada != nil {
                    Button("Parar de sincronizar…", role: .destructive) { confirmarParada = true }
                }
                Spacer()
                Button("Concluído") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 600)
        .background(Tema.fundo)
        .onAppear {
            if armazenamento.urlPastaSincronizada == nil,
               let url = escolherPasta(mensagem: "Escolha a pasta principal dos modelos (com uma subpasta para cada local).") {
                armazenamento.definirPastaSincronizada(url)
            }
            lerSubpastas()
        }
        .confirmationDialog("Parar de sincronizar com esta pasta?", isPresented: $confirmarParada) {
            Button("Parar de sincronizar", role: .destructive) {
                armazenamento.definirPastaSincronizada(nil)
                subpastas = []
            }
        } message: {
            Text("Os modelos que vieram da pasta continuam no app como modelos comuns, mas deixam de ser atualizados.")
        }
    }

    private func papel(de pasta: String) -> Binding<PapelDaPasta> {
        Binding(
            get: {
                if armazenamento.dados.pastasIgnoradas.contains(pasta) { return .ignorar }
                if armazenamento.dados.ehCompartilhada(pasta) { return .todos }
                return .local
            },
            set: { papel in
                armazenamento.dados.pastasIgnoradas.removeAll { $0 == pasta }
                armazenamento.dados.pastasCompartilhadas.removeAll {
                    $0.compare(pasta, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }
                switch papel {
                case .local: break
                case .todos: armazenamento.dados.pastasCompartilhadas.append(pasta)
                case .ignorar: armazenamento.dados.pastasIgnoradas.append(pasta)
                }
            }
        )
    }

    private func lerSubpastas() {
        subpastas = armazenamento.urlPastaSincronizada.map(LeituraDaPasta.subpastasPrincipais) ?? []
    }
}

/// Papel de uma subpasta da pasta sincronizada.
enum PapelDaPasta: String, CaseIterable, Identifiable {
    case local
    case todos
    case ignorar

    var id: Self { self }

    var nome: String {
        switch self {
        case .local: return "Local"
        case .todos: return "Todos os locais"
        case .ignorar: return "Ignorar"
        }
    }
}
