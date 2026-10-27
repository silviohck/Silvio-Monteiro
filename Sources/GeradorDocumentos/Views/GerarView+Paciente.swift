import AppKit
import DocxTemplateKit
import SwiftUI

/// Seção Paciente da tela Gerar documento: nome, homônimos, cadastro e sugestões.
extension GerarView {
    /// Nome do paciente, colar/copiar, cadastro, homônimos e sugestões.
    var secaoPaciente: some View {
        Section {
            HStack {
                TextField("Nome do paciente", text: $nomePaciente)
                    .focused($focoNoNome)
                if !nomePaciente.isEmpty {
                    Button(action: limparPaciente) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Limpar o nome e os campos do paciente")
                }
                Button {
                    // Cola o nome copiado de outro lugar (sistema da clínica, mensagem…), numa linha só.
                    if let texto = NSPasteboard.general.string(forType: .string) {
                        nomePaciente = texto.components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .first { !$0.isEmpty } ?? ""
                        focoNoNome = true
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .help("Colar o nome copiado")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(nomeDigitado, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(nomeDigitado.isEmpty)
                .help("Copiar o nome do paciente")
                Button(action: abrirCadastro) {
                    Label("Cadastro", systemImage: pacienteCadastrado == nil ? "person.badge.plus" : "person.text.rectangle")
                }
                .controlSize(.small)
                .disabled(nomeDigitado.isEmpty || precisaEscolherPaciente)
                .help(pacienteCadastrado == nil ? "Criar o cadastro deste paciente e acrescentar informações" : "Abrir o cadastro do paciente para acrescentar informações")
            }
            if precisaEscolherPaciente {
                escolhaDeHomonimo
            } else if let paciente = pacienteCadastrado {
                Label(
                    "Paciente cadastrado · \(Armazenamento.identificacao(paciente)) — dados preenchidos abaixo",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                .foregroundStyle(Tema.sucesso)
                if let outro = localDeOrigem(paciente) {
                    Label("Paciente de \(outro) — o documento sai como \(local?.nome ?? "sem local") e fica na pasta deste local.", systemImage: "arrow.left.arrow.right")
                        .fonteApp(.apoio)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if homonimos.count > 1 {
                        Button("Trocar de paciente") { pacienteEscolhido = nil }
                    }
                    Button("É outro paciente com o mesmo nome") { outroPaciente = true }
                }
                .buttonStyle(.link)
                .fonteApp(.apoio)
            } else if outroPaciente {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Novo cadastro, diferente dos que já têm este nome.", systemImage: "person.badge.plus")
                    TextField("Data de nascimento (dd/mm/aaaa) — ajuda a diferenciar", text: $nascimentoDoNovo)
                    Button("Cancelar: é um paciente já cadastrado") {
                        outroPaciente = false
                        nascimentoDoNovo = ""
                    }
                    .buttonStyle(.link)
                    .fonteApp(.apoio)
                }
            } else if !nomeDigitado.isEmpty {
                ForEach(sugestoes) { paciente in
                    Button {
                        nomePaciente = paciente.nome
                        pacienteEscolhido = paciente.id
                    } label: {
                        Label(textoDaSugestao(paciente), systemImage: "person.crop.circle")
                    }
                    .buttonStyle(.link)
                }
                Text("Paciente novo: o cadastro será criado ao gerar o documento.")
                    .fonteApp(.apoio)
                    .foregroundStyle(.secondary)
            }
        } header: {
            TituloSecao("Paciente", icone: "person.fill")
        }
    }

    /// Nome repetido: lista os cadastros com data de nascimento e CPF para escolher o certo.
    var escolhaDeHomonimo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Há \(homonimos.count) pacientes chamados “\(nomeDigitado)”. Qual deles é?", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            ForEach(homonimos) { paciente in
                Button {
                    pacienteEscolhido = paciente.id
                } label: {
                    Label(
                        [Armazenamento.identificacao(paciente), armazenamento.nomesDosLocais(paciente)]
                            .filter { !$0.isEmpty }.joined(separator: " · "),
                        systemImage: "person.crop.circle"
                    )
                }
                .buttonStyle(.link)
            }
            Button("É outro paciente (novo cadastro)") { outroPaciente = true }
                .buttonStyle(.link)
            if homonimos.contains(where: { $0.dataNascimento.trimmingCharacters(in: .whitespaces).isEmpty }) {
                Text("Dica: cadastre a data de nascimento desses pacientes para diferenciá-los com segurança.")
                    .fonteApp(.apoio)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Nome do local do cadastro, quando o paciente é de outro local.
    func localDeOrigem(_ paciente: Paciente) -> String? {
        guard let origem = armazenamento.local(paciente.localID), origem.id != local?.id else { return nil }
        return origem.nome.isEmpty ? "outro local" : origem.nome
    }

    func textoDaSugestao(_ paciente: Paciente) -> String {
        var texto = "Usar o cadastro de \(paciente.nome) (\(Armazenamento.identificacao(paciente)))"
        let locais = armazenamento.nomesDosLocais(paciente)
        if !locais.isEmpty { texto += " · \(locais)" }
        return texto
    }

    /// Cadastro novo com o nome digitado (e a data de nascimento informada, se for homônimo).
    func criarPaciente() -> Paciente {
        var paciente = armazenamento.novoPaciente(nome: nomeDigitado)
        paciente.localID = local?.id
        let nascimento = nascimentoDoNovo.trimmingCharacters(in: .whitespaces)
        if !nascimento.isEmpty { paciente.dataNascimento = nascimento }
        armazenamento.atualizarPaciente(paciente)
        pacienteEscolhido = paciente.id
        outroPaciente = false
        nascimentoDoNovo = ""
        return paciente
    }

    /// Abre o cadastro do paciente digitado, criando-o se ainda não existir.
    func abrirCadastro() {
        guard !precisaEscolherPaciente else { return }
        let paciente = pacienteCadastrado ?? criarPaciente()
        pacienteEmEdicao = paciente.id
        mostrandoCadastro = true
    }

    /// Depois de editar o cadastro: acompanha mudança de nome e recarrega os dados no formulário.
    func voltarDoCadastro() {
        if let id = pacienteEmEdicao, let paciente = armazenamento.paciente(id), !paciente.nome.isEmpty {
            nomePaciente = paciente.nome
            pacienteEscolhido = id
        }
        pacienteEmEdicao = nil
        preencher(.paciente)
    }
}
