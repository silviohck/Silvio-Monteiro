import AppKit
import DocxTemplateKit
import SwiftUI
import UniformTypeIdentifiers

struct GerarView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @AppStorage("modeloSelecionado") private var modeloSelecionado = ""
    @AppStorage("localSelecionado") private var localSelecionado = ""
    @State private var nomePaciente = ""
    @State private var valores: [String: String] = [:]
    @State private var abrirAoGerar = true
    @State private var aviso: String?
    @FocusState private var focoNoNome: Bool

    private enum Escopo { case tudo, paciente, local }

    private var modelo: ModeloDocumento? {
        armazenamento.dados.modelos.first { $0.id.uuidString == modeloSelecionado }
    }

    private var local: LocalAtendimento? {
        armazenamento.dados.locais.first { $0.id.uuidString == localSelecionado }
    }

    private var nomeDigitado: String {
        nomePaciente.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pacienteCadastrado: Paciente? {
        armazenamento.paciente(chamado: nomeDigitado)
    }

    private var sugestoes: [Paciente] {
        guard nomeDigitado.count >= 2, pacienteCadastrado == nil else { return [] }
        return Array(armazenamento.pacientesOrdenados.filter {
            $0.nome.range(of: nomeDigitado, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }.prefix(6))
    }

    var body: some View {
        if armazenamento.dados.modelos.isEmpty {
            AvisoVazio(
                titulo: "Nenhum modelo importado",
                icone: "doc.text",
                mensagem: "Vá em “Modelos” e importe um arquivo .docx com campos como {{NOME_PACIENTE}}."
            )
        } else {
            formulario
        }
    }

    private var formulario: some View {
        Form {
            Section("Documento") {
                Picker("Modelo", selection: $modeloSelecionado) {
                    Text("Selecione…").tag("")
                    ForEach(armazenamento.dados.modelos) { modelo in
                        Text(modelo.nome).tag(modelo.id.uuidString)
                    }
                }
                Picker("Local de atendimento", selection: $localSelecionado) {
                    Text("Nenhum").tag("")
                    ForEach(armazenamento.locaisOrdenados) { local in
                        Text(local.nome.isEmpty ? "Sem nome" : local.nome).tag(local.id.uuidString)
                    }
                }
                if armazenamento.dados.locais.isEmpty {
                    Text("Cadastre seus locais na aba “Locais de atendimento”.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Paciente") {
                HStack {
                    TextField("Nome do paciente", text: $nomePaciente)
                        .focused($focoNoNome)
                    if !nomePaciente.isEmpty {
                        Button {
                            nomePaciente = ""
                            focoNoNome = true
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Limpar para o próximo paciente")
                    }
                }
                if let paciente = pacienteCadastrado {
                    Label(
                        "Paciente cadastrado" + (paciente.cpf.isEmpty ? "" : " · CPF \(paciente.cpf)") + " — dados preenchidos abaixo",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                    .foregroundStyle(.green)
                } else if !nomeDigitado.isEmpty {
                    ForEach(sugestoes) { paciente in
                        Button {
                            nomePaciente = paciente.nome
                        } label: {
                            Label("Usar o cadastro de \(paciente.nome)", systemImage: "person.crop.circle")
                        }
                        .buttonStyle(.link)
                    }
                    Text("Paciente novo: o cadastro será criado ao gerar o documento.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let modelo {
                let campos = modelo.campos.filter { !CamposAutomaticos.ehNomeDoPaciente($0) }
                Section {
                    if campos.isEmpty {
                        Text("Nenhum outro campo para preencher neste modelo.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(campos, id: \.self) { campo in
                        TextField(campo, text: valor(campo), axis: .vertical)
                            .lineLimit(1...5)
                    }
                } header: {
                    Text("Outros campos do documento")
                } footer: {
                    Text("Preenchidos com o cadastro do paciente, o local e a data de hoje. Você pode alterar qualquer valor; o que digitar fica salvo no cadastro do paciente.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Abrir o documento depois de gerar", isOn: $abrirAoGerar)
                    HStack {
                        if let aviso {
                            Label(aviso, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Button("Gerar documento…") { gerar(modelo) }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(nomeDigitado.isEmpty && modelo.campos.contains(where: CamposAutomaticos.ehNomeDoPaciente))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if modelo == nil { modeloSelecionado = armazenamento.dados.modelos.first?.id.uuidString ?? "" }
            if local == nil { localSelecionado = "" }
            preencher(.tudo)
            focoNoNome = true
        }
        .onChange(of: modeloSelecionado) { _ in preencher(.tudo) }
        .onChange(of: pacienteCadastrado?.id) { _ in preencher(.paciente) }
        .onChange(of: localSelecionado) { _ in preencher(.local) }
    }

    private func valor(_ campo: String) -> Binding<String> {
        Binding(get: { valores[campo, default: ""] }, set: { valores[campo] = $0 })
    }

    /// Recalcula os campos; ao trocar o local, os dados do paciente já digitados não são apagados (e vice-versa).
    private func preencher(_ escopo: Escopo) {
        aviso = nil
        guard let modelo else { return }
        for campo in modelo.campos where !CamposAutomaticos.ehNomeDoPaciente(campo) {
            var doLocal = false
            if case .local = CamposAutomaticos.mapa[CamposAutomaticos.chave(campo)] {
                doLocal = true
            }
            let atualizar = escopo == .tudo || (escopo == .local) == doLocal
            if atualizar {
                valores[campo] = CamposAutomaticos.valor(para: campo, paciente: pacienteCadastrado, local: local) ?? ""
            }
        }
    }

    private func gerar(_ modelo: ModeloDocumento) {
        let nome = nomeDigitado
        var valoresFinais = valores
        for campo in modelo.campos where CamposAutomaticos.ehNomeDoPaciente(campo) {
            valoresFinais[campo] = nome
        }

        let painel = NSSavePanel()
        painel.allowedContentTypes = [.documentoWord]
        painel.canCreateDirectories = true
        painel.nameFieldStringValue = nomeDoArquivo(modelo: modelo.nome, paciente: nome)
        guard painel.runModal() == .OK, let destino = painel.url else { return }

        do {
            try DocxTemplate.fill(template: armazenamento.urlDoModelo(modelo), values: valoresFinais, output: destino)
        } catch {
            armazenamento.erro = error.localizedDescription
            return
        }

        if !nome.isEmpty {
            var paciente = pacienteCadastrado ?? armazenamento.novoPaciente(nome: nome)
            CamposAutomaticos.guardar(valoresFinais, campos: modelo.campos, em: &paciente)
            armazenamento.atualizarPaciente(paciente)
        }
        armazenamento.registrar(DocumentoGerado(modelo: modelo.nome, paciente: nome, local: local?.nome, caminho: destino.path))
        aviso = "Documento salvo: \(destino.lastPathComponent)"
        if abrirAoGerar {
            NSWorkspace.shared.open(destino)
        }
    }

    private func nomeDoArquivo(modelo: String, paciente: String) -> String {
        let base = paciente.isEmpty ? modelo : "\(modelo) - \(paciente)"
        return base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".docx"
    }
}
