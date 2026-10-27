import AppKit
import SwiftUI

struct LocaisView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var selecao: LocalAtendimento.ID?
    @State private var confirmarExclusao = false

    var body: some View {
        HSplitView {
            List(armazenamento.locaisOrdenados, selection: $selecao) { local in
                VStack(alignment: .leading) {
                    Text(local.nome.isEmpty ? "Sem nome" : local.nome)
                    if !local.cidade.isEmpty {
                        Text(local.cidade).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
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
                        mensagem: "Cadastre os lugares onde você atende (clínica, hospital, consultório) e escolha a pasta de cada um. Os documentos gerados são salvos lá automaticamente, separados em Receitas, Laudos e Relatórios médicos."
                    )
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            Button {
                selecao = armazenamento.novoLocal().id
            } label: {
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

struct LocalEditor: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @Binding var local: LocalAtendimento

    var body: some View {
        Form {
            Section("Local de atendimento") {
                TextField("Nome", text: $local.nome, prompt: Text("Ex.: Clínica São Lucas"))
                TextField("Endereço", text: $local.endereco, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Cidade", text: $local.cidade, prompt: Text("Ex.: São Paulo"))
                TextField("Telefone", text: $local.telefone)
                TextField("E-mail", text: $local.email)
                TextField("CNPJ", text: $local.cnpj)
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
                Text("Os documentos são salvos automaticamente nesta pasta, separados em subpastas por tipo: \(armazenamento.dados.categorias.joined(separator: ", ")).")
                    .foregroundStyle(.secondary)
            }
            Section("Campos para usar nos modelos") {
                campo("{{LOCAL}}", local.nome)
                campo("{{LOCAL_ENDERECO}}", local.endereco)
                campo("{{CIDADE}}", local.cidade)
                campo("{{LOCAL_TELEFONE}}", local.telefone)
                campo("{{LOCAL_EMAIL}}", local.email)
                campo("{{CNPJ}}", local.cnpj)
            }
        }
        .formStyle(.grouped)
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

    private func campo(_ nome: String, _ valor: String) -> some View {
        LabeledContent {
            Text(valor.isEmpty ? "—" : valor).foregroundStyle(.secondary)
        } label: {
            Text(nome).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
    }
}
