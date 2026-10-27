import AppKit
import SwiftUI

struct LocaisView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var selecao: LocalAtendimento.ID?
    @State private var localParaExcluir: LocalAtendimento?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                Button(action: novoLocal) {
                    Label("Novo local", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(8)
                List(armazenamento.locaisOrdenados, selection: $selecao) { local in
                    Text(local.nome.isEmpty ? "Novo local (sem nome)" : local.nome)
                }
                .fundoSuave(Tema.lateral)
            }
            .background(Tema.lateral)
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)

            Group {
                if let local = armazenamento.local(selecao) {
                    LocalEditor(
                        local: Binding(
                            get: { armazenamento.local(local.id) ?? local },
                            set: { armazenamento.atualizarLocal($0) }
                        ),
                        aoExcluir: { localParaExcluir = local }
                    )
                    .id(local.id)
                } else {
                    AvisoVazio(
                        titulo: armazenamento.dados.locais.isEmpty ? "Nenhum local cadastrado" : "Nenhum local selecionado",
                        icone: "building.2",
                        mensagem: "Cadastre os lugares onde você atende (clínica, hospital, consultório) e escolha a pasta de cada um. Os documentos gerados são salvos lá automaticamente, separados em Receitas, Laudos e Relatórios médicos.",
                        botao: "Cadastrar local de atendimento",
                        acao: novoLocal
                    )
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            Button(action: novoLocal) {
                Label("Novo local", systemImage: "plus")
            }
            Button(role: .destructive) {
                localParaExcluir = armazenamento.local(selecao)
            } label: {
                Label("Excluir local", systemImage: "trash")
            }
            .disabled(selecao == nil)
        }
        .sheet(item: $localParaExcluir) { local in
            ExcluirLocalView(local: local) {
                if selecao == local.id { selecao = nil }
            }
            .environmentObject(armazenamento)
        }
    }
}

extension LocaisView {
    private func novoLocal() {
        selecao = armazenamento.novoLocal().id
    }
}

struct LocalEditor: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @Binding var local: LocalAtendimento
    let aoExcluir: () -> Void

    var body: some View {
        Form {
            Section("Local de atendimento") {
                TextField("Nome", text: $local.nome, prompt: Text("Ex.: Alagoa Grande"))
            }
            Section {
                LabeledContent("Pasta") {
                    Text((armazenamento.pastaDoLocal(local).path as NSString).abbreviatingWithTildeInPath)
                        .foregroundColor(local.pasta.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Escolher pasta…") { escolherPasta() }
                    Button("Abrir no Finder") { abrirPasta() }
                    if !local.pasta.isEmpty {
                        Button("Usar pasta padrão") { local.pasta = "" }
                    }
                }
            } header: {
                Text("Onde salvar os documentos deste local")
            } footer: {
                Text("Os documentos gerados são salvos aqui, separados em subpastas por tipo (Receitas, Laudos…).")
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Spacer()
                    Button(role: .destructive, action: aoExcluir) {
                        Label("Excluir local…", systemImage: "trash")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fundoSuave()
    }

    private func escolherPasta() {
        let painel = NSOpenPanel()
        painel.canChooseDirectories = true
        painel.canChooseFiles = false
        painel.canCreateDirectories = true
        painel.allowsMultipleSelection = false
        painel.prompt = "Usar esta pasta"
        painel.message = "Escolha a pasta onde ficam os documentos de \(local.nome.isEmpty ? "este local" : local.nome)."
        guard painel.runModal() == .OK, let url = painel.url else { return }
        local.pasta = url.path
        criarSubpastas(local)
    }

    private func abrirPasta() {
        criarSubpastas(local)
        NSWorkspace.shared.open(armazenamento.pastaDoLocal(local))
    }

    private func criarSubpastas(_ local: LocalAtendimento) {
        do {
            try armazenamento.criarSubpastas(local)
        } catch {
            armazenamento.erro = "Não foi possível criar as pastas: \(error.localizedDescription)"
        }
    }
}

/// Exclusão de local: exige decidir antes o que acontece com os modelos e pacientes dele.
struct ExcluirLocalView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @Environment(\.dismiss) private var dismiss
    let local: LocalAtendimento
    let aoExcluir: () -> Void

    private enum Opcao { case transferir, desvincular }
    @State private var opcao: Opcao?
    @State private var destino: LocalAtendimento.ID?

    private var nome: String { local.nome.isEmpty ? "este local" : "“\(local.nome)”" }
    private var modelos: Int { armazenamento.dados.modelos.filter { $0.localID == local.id }.count }
    private var pacientes: Int { armazenamento.dados.pacientes.filter { $0.localID == local.id }.count }
    private var outrosLocais: [LocalAtendimento] { armazenamento.locaisOrdenados.filter { $0.id != local.id } }
    private var temVinculos: Bool { modelos > 0 || pacientes > 0 }

    private var podeExcluir: Bool {
        guard temVinculos else { return true }
        switch opcao {
        case .transferir: return destino != nil
        case .desvincular: return true
        case nil: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Excluir \(nome)").fonteApp(.titulo)

            if temVinculos {
                Text("Este local tem \(modelos) \(modelos == 1 ? "modelo" : "modelos") e \(pacientes) \(pacientes == 1 ? "paciente" : "pacientes"). Antes de excluir, escolha o que fazer com eles:")
                    .fixedSize(horizontal: false, vertical: true)
                Picker("", selection: $opcao) {
                    Text("Transferir para outro local").tag(Opcao?.some(.transferir))
                    Text("Desvincular: os modelos passam a valer para todos os locais e os pacientes ficam sem local").tag(Opcao?.some(.desvincular))
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if opcao == .transferir {
                    if outrosLocais.isEmpty {
                        Text("Não há outro local cadastrado para receber os modelos.")
                            .foregroundStyle(.orange)
                    } else {
                        Picker("Transferir para", selection: $destino) {
                            Text("Escolha o local…").tag(LocalAtendimento.ID?.none)
                            ForEach(outrosLocais) { outro in
                                Text(outro.nome.isEmpty ? "Local sem nome" : outro.nome).tag(Optional(outro.id))
                            }
                        }
                    }
                }
            } else {
                Text("Este local não tem modelos nem pacientes vinculados.")
            }

            if let pasta = local.pastaSincronizada {
                Text("Este local vem da pasta sincronizada “\(pasta)”. Ao transferir para um local sem pasta sincronizada, os arquivos dessa pasta passam a ser desse local; caso contrário, a pasta deixa de ser acompanhada e os modelos que vieram dela saem do app na próxima sincronização.")
                    .fonteApp(.apoio)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Os documentos já gerados não são apagados.")
                .fonteApp(.apoio)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Excluir local", role: .destructive) {
                    armazenamento.excluirLocal(local.id, transferirPara: opcao == .transferir ? destino : nil)
                    aoExcluir()
                    dismiss()
                }
                .disabled(!podeExcluir)
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
        .background(Tema.fundo)
    }
}
