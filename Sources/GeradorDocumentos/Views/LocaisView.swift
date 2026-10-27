import AppKit
import DocxTemplateKit
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
                    VStack(alignment: .leading) {
                        Text(local.nome.isEmpty ? "Novo local (sem nome)" : local.nome)
                        if !local.cidade.isEmpty {
                            Text(local.cidade).font(.caption).foregroundStyle(.secondary)
                        }
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
                        mensagem: "Cadastre os lugares onde você atende (clínica, hospital, consultório) com endereço e cidade, e escolha a pasta onde os documentos gerados de cada um devem ficar.",
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
                Text("Os documentos gerados são salvos automaticamente nesta pasta, em subpastas com o mesmo nome da pasta do modelo (LAUDO MÉDICO, RX…).")
                    .foregroundStyle(.secondary)
            }
            if !armazenamento.biblioteca.isEmpty {
                Section {
                    Picker("Pasta de modelos", selection: $local.grupoModelos) {
                        Text("Mesmo nome do local").tag("")
                        ForEach(armazenamento.biblioteca) { grupo in
                            Text(grupo.nome).tag(grupo.nome)
                        }
                    }
                } footer: {
                    Text("Ao escolher esta pasta na tela Gerar documento, este local é selecionado sozinho.")
                        .foregroundStyle(.secondary)
                }
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
    }

    private func abrirPasta() {
        let pasta = armazenamento.pastaDoLocal(local)
        do {
            try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
            NSWorkspace.shared.open(pasta)
        } catch {
            armazenamento.erro = "Não foi possível criar a pasta: \(error.localizedDescription)"
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
