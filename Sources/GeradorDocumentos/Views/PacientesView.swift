import SwiftUI

struct PacientesView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var selecao: Paciente.ID?
    @State private var busca = ""
    @State private var confirmarExclusao = false

    private var filtrados: [Paciente] {
        let termo = busca.trimmingCharacters(in: .whitespaces)
        guard !termo.isEmpty else { return armazenamento.pacientesOrdenados }
        return armazenamento.pacientesOrdenados.filter {
            $0.nome.localizedCaseInsensitiveContains(termo) || $0.cpf.contains(termo)
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                Button(action: novoPaciente) {
                    Label("Novo paciente", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding([.horizontal, .top], 8)
                TextField("Buscar por nome ou CPF", text: $busca)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                List(filtrados, selection: $selecao) { paciente in
                    VStack(alignment: .leading) {
                        Text(paciente.nome.isEmpty ? "Sem nome" : paciente.nome)
                        if !paciente.cpf.isEmpty {
                            Text(paciente.cpf).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)

            Group {
                if let paciente = armazenamento.paciente(selecao) {
                    PacienteEditor(paciente: Binding(
                        get: { armazenamento.paciente(paciente.id) ?? paciente },
                        set: { armazenamento.atualizarPaciente($0) }
                    ))
                    .id(paciente.id)
                } else {
                    AvisoVazio(
                        titulo: "Nenhum paciente selecionado",
                        icone: "person.crop.circle",
                        mensagem: "Escolha um paciente na lista ou cadastre um novo. Pacientes também são cadastrados sozinhos quando você gera um documento com um nome novo.",
                        botao: "Cadastrar paciente",
                        acao: novoPaciente
                    )
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            Button(action: novoPaciente) {
                Label("Novo paciente", systemImage: "person.badge.plus")
            }
            Button(role: .destructive) {
                confirmarExclusao = true
            } label: {
                Label("Excluir paciente", systemImage: "trash")
            }
            .disabled(selecao == nil)
        }
        .confirmationDialog("Excluir este paciente?", isPresented: $confirmarExclusao) {
            Button("Excluir", role: .destructive) {
                if let id = selecao {
                    selecao = nil
                    armazenamento.removerPaciente(id)
                }
            }
        } message: {
            Text("Os documentos já gerados não são apagados.")
        }
    }
}

extension PacientesView {
    private func novoPaciente() {
        busca = ""
        selecao = armazenamento.novoPaciente().id
    }
}

struct PacienteEditor: View {
    @Binding var paciente: Paciente

    var body: some View {
        Form {
            Section("Identificação") {
                TextField("Nome completo", text: $paciente.nome)
                TextField("CPF", text: $paciente.cpf)
                TextField("RG", text: $paciente.rg)
                LabeledContent("Data de nascimento") {
                    HStack {
                        TextField("dd/mm/aaaa", text: $paciente.dataNascimento)
                            .labelsHidden()
                        if let idade = CamposAutomaticos.idade(dataNascimento: paciente.dataNascimento) {
                            Text("\(idade) anos").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Contato") {
                TextField("Telefone", text: $paciente.telefone)
                TextField("E-mail", text: $paciente.email)
                TextField("Endereço", text: $paciente.endereco, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Convênio", text: $paciente.convenio)
            }
            Section("Observações") {
                TextField("Observações", text: $paciente.observacoes, axis: .vertical)
                    .lineLimit(3...8)
                    .labelsHidden()
            }
            if !paciente.outrosCampos.isEmpty {
                Section {
                    ForEach(paciente.outrosCampos.keys.sorted(), id: \.self) { campo in
                        HStack {
                            TextField(campo, text: Binding(
                                get: { paciente.outrosCampos[campo] ?? "" },
                                set: { paciente.outrosCampos[campo] = $0 }
                            ), axis: .vertical)
                            Button {
                                paciente.outrosCampos[campo] = nil
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remover este valor salvo")
                        }
                    }
                } header: {
                    Text("Outros campos salvos")
                } footer: {
                    Text("Valores digitados ao gerar documentos para este paciente; são reaproveitados na próxima vez.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
