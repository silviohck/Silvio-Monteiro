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
                        mensagem: "Cadastre os lugares onde você atende (clínica, hospital, consultório). Na hora de gerar o documento, escolha o local e os campos {{LOCAL}}, {{LOCAL_ENDERECO}} e {{CIDADE}} são preenchidos sozinhos."
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

    private func campo(_ nome: String, _ valor: String) -> some View {
        LabeledContent {
            Text(valor.isEmpty ? "—" : valor).foregroundStyle(.secondary)
        } label: {
            Text(nome).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
    }
}
