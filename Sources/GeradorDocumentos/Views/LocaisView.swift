import AppKit
import SwiftUI

struct LocaisView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var selecao: LocalAtendimento.ID?
    @State private var confirmarExclusao = false

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
                    LocalEditor(local: Binding(
                        get: { armazenamento.local(local.id) ?? local },
                        set: { armazenamento.atualizarLocal($0) }
                    ))
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
                confirmarExclusao = true
            } label: {
                Label("Excluir local", systemImage: "trash")
            }
            .disabled(selecao == nil)
        }
        .confirmationDialog("Excluir este local de atendimento?", isPresented: $confirmarExclusao) {
            Button("Excluir", role: .destructive) {
                if let id = selecao {
                    selecao = nil
                    armazenamento.removerLocal(id)
                }
            }
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
