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
    /// Pasta escolhida em "Só este documento…"; volta para nil depois de gerar.
    @State private var pastaAvulsa: URL?
    @State private var ultimoModeloID: ModeloDocumento.ID?
    /// Subpasta = tipo do modelo (Receitas, Atestados…); filtra os modelos e é onde o documento é salvo.
    @AppStorage("subpastaSelecionada") private var subpasta = ""
    @State private var mostrandoCadastro = false
    @State private var pacienteEmEdicao: Paciente.ID?
    @FocusState private var focoNoNome: Bool
    /// Paciente escolhido quando há mais de um cadastro com o mesmo nome.
    @State private var pacienteEscolhido: Paciente.ID?
    /// "É outro paciente": cria um cadastro novo mesmo com o nome já existente.
    @State private var outroPaciente = false
    @State private var nascimentoDoNovo = ""

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

    /// Cadastros com exatamente o nome digitado (pode haver mais de um: homônimos).
    private var homonimos: [Paciente] {
        armazenamento.pacientes(chamados: nomeDigitado)
    }

    /// O paciente escolhido; com nome repetido, só depois de você escolher qual é.
    private var pacienteCadastrado: Paciente? {
        if outroPaciente { return nil }
        if let id = pacienteEscolhido, let escolhido = homonimos.first(where: { $0.id == id }) {
            return escolhido
        }
        return homonimos.count == 1 ? homonimos[0] : nil
    }

    /// Nome repetido e ainda não foi dito qual paciente é.
    private var precisaEscolherPaciente: Bool {
        homonimos.count > 1 && pacienteCadastrado == nil && !outroPaciente
    }

    private var sugestoes: [Paciente] {
        guard nomeDigitado.count >= 2, homonimos.isEmpty else { return [] }
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
                        .fonteApp(.apoio)
                        .foregroundStyle(.secondary)
                }
                if armazenamento.modelos(para: local).isEmpty {
                    Text("Nenhum modelo para este local. Importe na aba “Modelos”.")
                        .fonteApp(.apoio)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Subpasta", selection: $subpasta) {
                        ForEach(subpastasDisponiveis, id: \.self) { tipo in
                            Text(tipo).tag(tipo)
                        }
                    }
                    Picker("Modelo", selection: $modeloSelecionado) {
                        ForEach(modelosDaSubpasta) { modelo in
                            Text(modelo.nome).tag(modelo.id.uuidString)
                        }
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
                            Label("Usar o cadastro de \(paciente.nome) (\(Armazenamento.identificacao(paciente)))", systemImage: "person.crop.circle")
                        }
                        .buttonStyle(.link)
                    }
                    Text("Paciente novo: o cadastro será criado ao gerar o documento.")
                        .fonteApp(.apoio)
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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Será salvo em")
                            if pastaAvulsa != nil {
                                Text("(só este documento)").fonteApp(.legenda).foregroundStyle(.secondary)
                            }
                        }
                        Text(caminhoAbreviado(pastaDeDestino))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(pastaDeDestino.path)
                        if pastaAvulsa == nil {
                            Text(situacaoDasPastas)
                                .fonteApp(.legenda)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Button {
                                if let url = escolherPasta(mensagem: "Escolha a pasta principal. Dentro dela, o app usa (ou cria) uma pasta para cada local e, dentro desta, uma pasta para cada tipo de documento.") {
                                    armazenamento.dados.pastaDocumentos = url.path
                                    if let local, !local.pasta.isEmpty {
                                        // A pasta principal passa a valer também para este local.
                                        var semPastaPropria = local
                                        semPastaPropria.pasta = ""
                                        armazenamento.atualizarLocal(semPastaPropria)
                                    }
                                    pastaAvulsa = nil
                                }
                            } label: {
                                Label("Escolher pasta principal…", systemImage: "folder.badge.gearshape")
                            }
                            .buttonStyle(.borderedProminent)
                            Menu("Mais opções") {
                                if let local {
                                    Button("Usar outra pasta só para \(local.nome.isEmpty ? "este local" : local.nome)…") {
                                        if let url = escolherPasta(mensagem: "Escolha a pasta de \(local.nome.isEmpty ? "este local" : local.nome). Se ela não tiver o nome do local, o app cria a pasta do local dentro dela.") {
                                            armazenamento.definirPasta(url, doLocal: local.id)
                                            pastaAvulsa = nil
                                        }
                                    }
                                    if !local.pasta.isEmpty {
                                        Button("Voltar a usar a pasta principal") {
                                            var semPastaPropria = local
                                            semPastaPropria.pasta = ""
                                            armazenamento.atualizarLocal(semPastaPropria)
                                        }
                                    }
                                }
                                Button("Só este documento…") {
                                    pastaAvulsa = escolherPasta(mensagem: "Escolha onde salvar só este documento.")
                                }
                                if pastaAvulsa != nil {
                                    Button("Voltar para a pasta do local") { pastaAvulsa = nil }
                                }
                            }
                            .fixedSize()
                            Button("Abrir no Finder") { abrirPasta(pastaDeDestino) }
                        }
                    }
                    .padding(.vertical, 4)
                    Toggle("Abrir o documento depois de gerar", isOn: $abrirAoGerar)
                    Toggle(isOn: $imprimirAoGerar) {
                        Text("Imprimir ao gerar")
                        Text("Impressora: \(impressora.isEmpty ? "padrão do sistema" : Impressao.nomeAmigavel(impressora)) (escolha na barra lateral)")
                    }
                    HStack {
                        if let aviso {
                            Label(aviso, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Tema.sucesso)
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
                            .disabled(
                                precisaEscolherPaciente
                                    || (nomeDigitado.isEmpty && modelo.campos.contains(where: CamposAutomaticos.ehNomeDoPaciente))
                            )
                            .help(precisaEscolherPaciente ? "Escolha qual dos pacientes com este nome é o certo" : "")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fundoSuave()
        .onAppear {
            if local == nil { localSelecionado = "" }
            validarModelo()
            preencher(.tudo)
            focoNoNome = true
        }
        .onChange(of: nomePaciente) { _ in
            aviso = nil
            ultimoDocumento = nil
            // Nome mudou: a escolha entre homônimos só vale se ainda for o mesmo nome.
            if let id = pacienteEscolhido, !homonimos.contains(where: { $0.id == id }) {
                pacienteEscolhido = nil
            }
            if homonimos.isEmpty {
                outroPaciente = false
                nascimentoDoNovo = ""
            }
        }
        .onChange(of: modeloSelecionado) { _ in preencher(.tudo) }
        .onChange(of: subpasta) { _ in validarModelo() }
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

    /// Tipos que têm modelos para o local escolhido, na ordem cadastrada.
    private var subpastasDisponiveis: [String] {
        var tipos: [String] = []
        for modelo in armazenamento.modelos(para: local) where !tipos.contains(modelo.categoria) {
            tipos.append(modelo.categoria)
        }
        return tipos
    }

    private var modelosDaSubpasta: [ModeloDocumento] {
        armazenamento.modelos(para: local)
            .filter { $0.categoria == subpasta }
            .sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
    }

    /// Mantém subpasta e modelo coerentes com o local: a subpasta precisa ter modelos
    /// e o modelo precisa ser dessa subpasta.
    private func validarModelo() {
        let tipos = subpastasDisponiveis
        if !tipos.contains(subpasta) {
            subpasta = modelo.map(\.categoria).flatMap { tipos.contains($0) ? $0 : nil } ?? tipos.first ?? ""
        }
        let modelos = modelosDaSubpasta
        if !modelos.contains(where: { $0.id.uuidString == modeloSelecionado }) {
            modeloSelecionado = modelos.first?.id.uuidString ?? ""
        }
    }

    /// Imprime com os ajustes do modelo (cópias).
    private func imprimir(_ arquivo: URL, modelo: ModeloDocumento?, manterAberto: Bool) {
        imprimindo = true
        Impressao.imprimir(
            arquivo,
            impressora: impressora,
            manterAberto: manterAberto,
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

    /// "Pastas já existentes" ou quais serão criadas (pasta do local e/ou do tipo).
    private var situacaoDasPastas: String {
        let fm = FileManager.default
        let pastaDoLocal = armazenamento.pastaDoLocal(local)
        var novas: [String] = []
        if !fm.fileExists(atPath: pastaDoLocal.path) { novas.append("“\(pastaDoLocal.lastPathComponent)”") }
        if pastaDeDestino != pastaDoLocal, !fm.fileExists(atPath: pastaDeDestino.path) {
            novas.append("“\(pastaDeDestino.lastPathComponent)”")
        }
        if novas.isEmpty { return "Pasta do local e do tipo já existem; o arquivo vai direto para lá." }
        return "Será criada ao gerar: " + novas.joined(separator: " e ") + "."
    }

    private var pastaDeDestino: URL {
        pastaAvulsa ?? armazenamento.pastaDosDocumentos(subpasta: subpasta, local: local)
    }

    /// Nome repetido: lista os cadastros com data de nascimento e CPF para escolher o certo.
    private var escolhaDeHomonimo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Há \(homonimos.count) pacientes chamados “\(nomeDigitado)”. Qual deles é?", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            ForEach(homonimos) { paciente in
                Button {
                    pacienteEscolhido = paciente.id
                } label: {
                    Label(Armazenamento.identificacao(paciente), systemImage: "person.crop.circle")
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

    /// Cadastro novo com o nome digitado (e a data de nascimento informada, se for homônimo).
    private func criarPaciente() -> Paciente {
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
    private func abrirCadastro() {
        guard !precisaEscolherPaciente else { return }
        let paciente = pacienteCadastrado ?? criarPaciente()
        pacienteEmEdicao = paciente.id
        mostrandoCadastro = true
    }

    /// Depois de editar o cadastro: acompanha mudança de nome e recarrega os dados no formulário.
    private func voltarDoCadastro() {
        if let id = pacienteEmEdicao, let paciente = armazenamento.paciente(id), !paciente.nome.isEmpty {
            nomePaciente = paciente.nome
            pacienteEscolhido = id
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
        guard !precisaEscolherPaciente else { return }
        let nome = nomeDigitado
        var valoresFinais = valores
        for campo in modelo.campos where CamposAutomaticos.ehNomeDoPaciente(campo) {
            valoresFinais[campo] = nome
        }

        let destino: URL
        do {
            destino = try armazenamento.caminhoParaNovoDocumento(
                modelo: modelo, subpasta: subpasta, local: local, paciente: nome, pastaAvulsa: pastaAvulsa
            )
            try DocxTemplate.fill(template: armazenamento.urlDoModelo(modelo), values: valoresFinais, output: destino)
        } catch {
            armazenamento.erro = error.localizedDescription
            return
        }

        var pacienteID: UUID?
        if !nome.isEmpty {
            var paciente = pacienteCadastrado ?? criarPaciente()
            pacienteID = paciente.id
            if armazenamento.local(paciente.localID) == nil {
                paciente.localID = local?.id
            }
            CamposAutomaticos.guardar(valoresFinais, campos: modelo.campos, em: &paciente)
            armazenamento.atualizarPaciente(paciente)
        }
        armazenamento.registrar(DocumentoGerado(
            modelo: modelo.nome, modeloID: modelo.id, paciente: nome, pacienteID: pacienteID,
            local: local?.nome, caminho: destino.path
        ))
        aviso = "Salvo: \(destino.lastPathComponent)"
        ultimoDocumento = destino
        pastaAvulsa = nil
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
