import SwiftUI

struct PacientesView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var selecao: Paciente.ID?
    @State private var busca = ""
    @State private var pacienteParaExcluir: Paciente?
    /// "" = todos os locais, "sem" = sem local, ou o id do local.
    @AppStorage("filtroLocalPacientes") private var filtroLocal = ""

    private static let semLocal = "sem"

    private struct Grupo: Identifiable {
        let id: String
        let titulo: String
        let pacientes: [Paciente]
    }

    private var grupos: [Grupo] {
        let termo = busca.trimmingCharacters(in: .whitespaces)
        let pacientes = armazenamento.pacientesOrdenados.filter {
            termo.isEmpty || $0.nome.localizedCaseInsensitiveContains(termo) || $0.cpf.contains(termo)
        }
        var grupos: [Grupo] = []
        for local in armazenamento.locaisOrdenados where filtroLocal.isEmpty || filtroLocal == local.id.uuidString {
            let doLocal = pacientes.filter { $0.localID == local.id }
            if !doLocal.isEmpty {
                grupos.append(Grupo(id: local.id.uuidString, titulo: local.nome.isEmpty ? "Local sem nome" : local.nome, pacientes: doLocal))
            }
        }
        if filtroLocal.isEmpty || filtroLocal == Self.semLocal {
            let semLocal = pacientes.filter { armazenamento.local($0.localID) == nil }
            if !semLocal.isEmpty {
                grupos.append(Grupo(id: Self.semLocal, titulo: "Sem local de atendimento", pacientes: semLocal))
            }
        }
        return grupos
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
                Picker("Local", selection: $filtroLocal) {
                    Text("Todos os locais").tag("")
                    ForEach(armazenamento.locaisOrdenados) { local in
                        Text(local.nome.isEmpty ? "Local sem nome" : local.nome).tag(local.id.uuidString)
                    }
                    Text("Sem local de atendimento").tag(Self.semLocal)
                }
                .labelsHidden()
                .padding([.horizontal, .top], 8)
                TextField("Buscar por nome ou CPF", text: $busca)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                List(selection: $selecao) {
                    ForEach(grupos) { grupo in
                        Section("\(grupo.titulo) (\(grupo.pacientes.count))") {
                            ForEach(grupo.pacientes) { paciente in
                                linha(paciente)
                                    .tag(paciente.id)
                                    .contextMenu {
                                        Button("Excluir paciente…", role: .destructive) {
                                            pacienteParaExcluir = paciente
                                        }
                                    }
                            }
                        }
                    }
                }
                .onDeleteCommand {
                    pacienteParaExcluir = armazenamento.paciente(selecao)
                }
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)

            Group {
                if let paciente = armazenamento.paciente(selecao) {
                    PacienteEditor(
                        paciente: Binding(
                            get: { armazenamento.paciente(paciente.id) ?? paciente },
                            set: { armazenamento.atualizarPaciente($0) }
                        ),
                        aoExcluir: { pacienteParaExcluir = paciente }
                    )
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
                pacienteParaExcluir = armazenamento.paciente(selecao)
            } label: {
                Label("Excluir paciente", systemImage: "trash")
            }
            .disabled(selecao == nil)
        }
        .confirmationDialog(
            "Excluir \(pacienteParaExcluir.map { $0.nome.isEmpty ? "este paciente" : $0.nome } ?? "este paciente")?",
            isPresented: Binding(get: { pacienteParaExcluir != nil }, set: { if !$0 { pacienteParaExcluir = nil } }),
            presenting: pacienteParaExcluir
        ) { paciente in
            Button("Excluir", role: .destructive) {
                if selecao == paciente.id { selecao = nil }
                armazenamento.removerPaciente(paciente.id)
            }
        } message: { _ in
            Text("O cadastro será apagado. Os documentos já gerados não são apagados.")
        }
    }

    private func linha(_ paciente: Paciente) -> some View {
        VStack(alignment: .leading) {
            Text(paciente.nome.isEmpty ? "Sem nome" : paciente.nome)
            if !paciente.cpf.isEmpty {
                Text(paciente.cpf).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

extension PacientesView {
    /// Novo paciente já ligado ao local que está sendo filtrado.
    private func novoPaciente() {
        busca = ""
        var paciente = armazenamento.novoPaciente()
        if let local = armazenamento.dados.locais.first(where: { $0.id.uuidString == filtroLocal }) {
            paciente.localID = local.id
            armazenamento.atualizarPaciente(paciente)
        }
        selecao = paciente.id
    }
}

/// Cadastro do paciente aberto numa janela a partir da tela Gerar documento.
struct CadastroPacienteSheet: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @Environment(\.dismiss) private var dismiss
    let id: Paciente.ID
    @State private var confirmarExclusao = false

    var body: some View {
        VStack(spacing: 0) {
            if let paciente = armazenamento.paciente(id) {
                PacienteEditor(
                    paciente: Binding(
                        get: { armazenamento.paciente(id) ?? paciente },
                        set: { armazenamento.atualizarPaciente($0) }
                    ),
                    aoExcluir: { confirmarExclusao = true }
                )
            } else {
                AvisoVazio(titulo: "Paciente não encontrado", icone: "person.crop.circle.badge.questionmark")
            }
            Divider()
            HStack {
                Text("As alterações são salvas automaticamente.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Concluído") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 640)
        .confirmationDialog("Excluir este paciente?", isPresented: $confirmarExclusao) {
            Button("Excluir", role: .destructive) {
                armazenamento.removerPaciente(id)
                dismiss()
            }
        } message: {
            Text("O cadastro será apagado. Os documentos já gerados não são apagados.")
        }
    }
}

struct PacienteEditor: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @Binding var paciente: Paciente
    let aoExcluir: () -> Void

    var body: some View {
        Form {
            Section("Identificação") {
                TextField("Nome completo", text: $paciente.nome)
                Picker("Local de atendimento", selection: $paciente.localID) {
                    Text("Nenhum").tag(UUID?.none)
                    ForEach(armazenamento.locaisOrdenados) { local in
                        Text(local.nome.isEmpty ? "Local sem nome" : local.nome).tag(Optional(local.id))
                    }
                }
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
            Section {
                HStack {
                    Spacer()
                    Button(role: .destructive, action: aoExcluir) {
                        Label("Excluir paciente…", systemImage: "trash")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
