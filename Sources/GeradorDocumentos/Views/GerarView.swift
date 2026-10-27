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
    @AppStorage("imprimirAoGerar") private var imprimirAoGerar = false
    @AppStorage("impressora") private var impressora = ""
    @State private var imprimindo = false
    @State private var aviso: String?
    @State private var ultimoDocumento: URL?
    @State private var ultimoModeloID: ModeloDocumento.ID?
    /// Subpasta onde o documento será salvo ("" = direto na pasta do local).
    @State private var subpasta = ""
    @State private var pedindoSubpasta = false
    @State private var novaSubpasta = ""
    @State private var mostrandoCadastro = false
    @State private var pacienteEmEdicao: Paciente.ID?
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
                Picker("Modelo", selection: $modeloSelecionado) {
                    Text("Selecione…").tag("")
                    ForEach(armazenamento.modelos(para: local)) { modelo in
                        Text("\(modelo.categoria) — \(modelo.nome)").tag(modelo.id.uuidString)
                    }
                }
                if armazenamento.modelos(para: local).isEmpty {
                    Text("Nenhum modelo para este local. Importe na aba “Modelos”.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if modelo != nil {
                    HStack {
                        Picker("Subpasta", selection: $subpasta) {
                            Text("Nenhuma (direto na pasta do local)").tag("")
                            ForEach(opcoesDeSubpasta, id: \.self) { pasta in
                                Text(pasta).tag(pasta)
                            }
                        }
                        Button("Nova…") {
                            novaSubpasta = ""
                            pedindoSubpasta = true
                        }
                        .help("Salvar numa subpasta nova")
                    }
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
                    Button(action: abrirCadastro) {
                        Label("Cadastro", systemImage: pacienteCadastrado == nil ? "person.badge.plus" : "person.text.rectangle")
                    }
                    .controlSize(.small)
                    .disabled(nomeDigitado.isEmpty)
                    .help(pacienteCadastrado == nil ? "Criar o cadastro deste paciente e acrescentar informações" : "Abrir o cadastro do paciente para acrescentar informações")
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
                    LabeledContent("Será salvo em") {
                        HStack {
                            Text(caminhoAbreviado(pastaDeDestino))
                                .foregroundStyle(.secondary)
                                .truncationMode(.head)
                                .lineLimit(1)
                                .help(pastaDeDestino.path)
                            Button {
                                abrirPasta(pastaDeDestino)
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("Abrir esta pasta no Finder")
                        }
                    }
                    Toggle("Abrir o documento depois de gerar", isOn: $abrirAoGerar)
                    Toggle(isOn: $imprimirAoGerar) {
                        Text("Imprimir ao gerar")
                        Text("Impressora: \(impressora.isEmpty ? "padrão do sistema" : Impressao.nomeAmigavel(impressora)) (escolha na barra lateral)")
                    }
                    HStack {
                        if let aviso {
                            Label(aviso, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            if let ultimoDocumento {
                                Button("Mostrar no Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([ultimoDocumento])
                                }
                                .buttonStyle(.link)
                                Button(imprimindo ? "Imprimindo…" : "Imprimir") {
                                    imprimir(ultimoDocumento, modelo: armazenamento.modelo(ultimoModeloID), manterAberto: true)
                                }
                                .buttonStyle(.link)
                                .disabled(imprimindo)
                            }
                        }
                        Spacer()
                        Button("Gerar documento") { gerar(modelo) }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(nomeDigitado.isEmpty && modelo.campos.contains(where: CamposAutomaticos.ehNomeDoPaciente))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if local == nil { localSelecionado = "" }
            validarModelo()
            subpasta = modelo?.categoria ?? ""
            preencher(.tudo)
            focoNoNome = true
        }
        .onChange(of: nomePaciente) { _ in
            aviso = nil
            ultimoDocumento = nil
        }
        .onChange(of: modeloSelecionado) { _ in
            subpasta = modelo?.categoria ?? ""
            preencher(.tudo)
        }
        .alert("Nova subpasta", isPresented: $pedindoSubpasta) {
            TextField("Ex.: Exames", text: $novaSubpasta)
            Button("Usar") {
                let nome = novaSubpasta.trimmingCharacters(in: .whitespacesAndNewlines)
                if !nome.isEmpty { subpasta = nome }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("A subpasta é criada dentro da pasta do local quando o documento for gerado.")
        }
        .sheet(isPresented: $mostrandoCadastro, onDismiss: voltarDoCadastro) {
            if let id = pacienteEmEdicao {
                CadastroPacienteSheet(id: id)
                    .environmentObject(armazenamento)
            }
        }
        .onChange(of: pacienteCadastrado?.id) { _ in preencher(.paciente) }
        .onChange(of: localSelecionado) { _ in
            validarModelo()
            preencher(.local)
        }
    }

    /// Ao trocar de local, mantém o modelo só se ele também vale para o novo local.
    private func validarModelo() {
        let disponiveis = armazenamento.modelos(para: local)
        if !disponiveis.contains(where: { $0.id.uuidString == modeloSelecionado }) {
            modeloSelecionado = disponiveis.first?.id.uuidString ?? ""
        }
    }

    /// Imprime com os ajustes do modelo (páginas por folha e cópias).
    private func imprimir(_ arquivo: URL, modelo: ModeloDocumento?, manterAberto: Bool) {
        imprimindo = true
        Impressao.imprimir(
            arquivo,
            impressora: impressora,
            manterAberto: manterAberto,
            paginasPorFolha: modelo?.paginasPorFolha ?? 1,
            copias: modelo?.copias ?? 1
        ) { erro in
            imprimindo = false
            if let erro {
                armazenamento.erro = erro
            } else if ultimoDocumento == arquivo {
                aviso = "Salvo e enviado para impressão: \(arquivo.lastPathComponent)"
            }
        }
    }

    private var pastaDeDestino: URL {
        armazenamento.pastaDosDocumentos(subpasta: subpasta, local: local)
    }

    /// Tipos, pastas que já existem no local e a subpasta atual (se for uma nova).
    private var opcoesDeSubpasta: [String] {
        let opcoes = armazenamento.opcoesDeSubpasta(local)
        return subpasta.isEmpty || opcoes.contains(subpasta) ? opcoes : opcoes + [subpasta]
    }

    /// Abre o cadastro do paciente digitado, criando-o se ainda não existir.
    private func abrirCadastro() {
        var paciente: Paciente
        if let cadastrado = pacienteCadastrado {
            paciente = cadastrado
        } else {
            paciente = armazenamento.novoPaciente(nome: nomeDigitado)
            paciente.localID = local?.id
            armazenamento.atualizarPaciente(paciente)
        }
        pacienteEmEdicao = paciente.id
        mostrandoCadastro = true
    }

    /// Depois de editar o cadastro: acompanha mudança de nome e recarrega os dados no formulário.
    private func voltarDoCadastro() {
        if let id = pacienteEmEdicao, let paciente = armazenamento.paciente(id), !paciente.nome.isEmpty {
            nomePaciente = paciente.nome
        }
        pacienteEmEdicao = nil
        preencher(.paciente)
    }

    private func valor(_ campo: String) -> Binding<String> {
        Binding(get: { valores[campo, default: ""] }, set: { valores[campo] = $0 })
    }

    /// Recalcula os campos; ao trocar o local, os dados do paciente já digitados não são apagados (e vice-versa).
    private func preencher(_ escopo: Escopo) {
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

        let destino: URL
        do {
            destino = try armazenamento.caminhoParaNovoDocumento(modelo: modelo, subpasta: subpasta, local: local, paciente: nome)
            try DocxTemplate.fill(template: armazenamento.urlDoModelo(modelo), values: valoresFinais, output: destino)
        } catch {
            armazenamento.erro = error.localizedDescription
            return
        }

        if !nome.isEmpty {
            var paciente = pacienteCadastrado ?? armazenamento.novoPaciente(nome: nome)
            if armazenamento.local(paciente.localID) == nil {
                paciente.localID = local?.id
            }
            CamposAutomaticos.guardar(valoresFinais, campos: modelo.campos, em: &paciente)
            armazenamento.atualizarPaciente(paciente)
        }
        armazenamento.registrar(DocumentoGerado(modelo: modelo.nome, modeloID: modelo.id, paciente: nome, local: local?.nome, caminho: destino.path))
        aviso = "Salvo: \(destino.lastPathComponent)"
        ultimoDocumento = destino
        ultimoModeloID = modelo.id
        if imprimirAoGerar {
            imprimir(destino, modelo: modelo, manterAberto: abrirAoGerar)
        } else if abrirAoGerar {
            NSWorkspace.shared.open(destino)
        }
    }

    /// "/Users/silvio/Documents/…" → "~/Documents/…"
    private func caminhoAbreviado(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func abrirPasta(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
