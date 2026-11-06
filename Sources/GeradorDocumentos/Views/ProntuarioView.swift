import AppKit
import DocxTemplateKit
import SwiftUI
import UniformTypeIdentifiers

/// Prontuário: a ficha do local (ex.: Avaliação ortopédica de Araruna) preenchida no app — identificação,
/// anamnese, exame físico, exames complementares e conduta — e gerada em Word, como os outros documentos.
/// O que é digitado aqui vale só para este atendimento; só os dados gerais vão para o cadastro.
struct ProntuarioView: View {
    @EnvironmentObject var armazenamento: Armazenamento
    @AppStorage("localSelecionado") var localSelecionado = ""
    @AppStorage("fichaSelecionada") var fichaSelecionada = ""
    @AppStorage("acaoDepoisDeGerar") var acaoDepoisDeGerar = "fila"
    @AppStorage("impressora") var impressora = ""
    @State var nomePaciente = ""
    @State var pacienteEscolhido: Paciente.ID?
    @State var valores: [String: String] = [:]
    /// Exames complementares quando a ficha não tem campo próprio: vão junto do exame físico.
    @State var examesExtras = ""
    @State var copias = 1
    @State var aviso: String?
    @State var ultimoDocumento: URL?
    @State var geracaoConcluida = false
    @State var importandoFicha = false
    @State var ultimoPaciente: Paciente.ID?
    @FocusState var focoNoNome: Bool

    // MARK: Estado derivado

    var local: LocalAtendimento? {
        armazenamento.dados.locais.first { $0.id.uuidString == localSelecionado }
    }

    var fichas: [ModeloDocumento] { armazenamento.fichas(para: local) }

    /// Só a ficha que está na tela e é deste local.
    var ficha: ModeloDocumento? {
        fichas.first { $0.id.uuidString == fichaSelecionada }
    }

    var nomeDigitado: String { nomePaciente.trimmingCharacters(in: .whitespacesAndNewlines) }

    var homonimos: [Paciente] { armazenamento.pacientes(chamados: nomeDigitado) }

    var pacienteCadastrado: Paciente? {
        if let id = pacienteEscolhido, let escolhido = homonimos.first(where: { $0.id == id }) { return escolhido }
        return homonimos.count == 1 ? homonimos[0] : nil
    }

    var precisaEscolherPaciente: Bool { homonimos.count > 1 && pacienteCadastrado == nil }

    var sugestoes: [Paciente] {
        guard nomeDigitado.count >= 2, homonimos.isEmpty else { return [] }
        return Array(armazenamento.pacientesOrdenados.filter { paciente in
            paciente.nome.range(of: nomeDigitado, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                && (local == nil || armazenamento.locaisDoPaciente(paciente).contains { $0.id == local?.id })
        }.prefix(6))
    }

    /// Campos que vêm do cadastro, do local ou da data (menos o nome, que é a caixa do paciente).
    func camposDeIdentificacao(_ ficha: ModeloDocumento) -> [String] {
        ficha.campos.filter { CamposAutomaticos.ehAutomatico($0) && !CamposAutomaticos.ehNomeDoPaciente($0) }
    }

    /// Campos do atendimento: queixa, história, exame, CID, conduta…
    func camposClinicos(_ ficha: ModeloDocumento) -> [String] {
        ficha.campos.filter { !CamposAutomaticos.ehAutomatico($0) }
    }

    static let partesLongas = ["QUEIXA", "HDA", "HISTORIA", "ANAMNESE", "EXAME", "PROGRAMACAO", "CONDUTA",
                               "EVOLUCAO", "PLANO", "OBSERVAC", "TRATAMENTO", "PRESCRICAO", "HIPOTESE"]

    static func ehLongo(_ campo: String) -> Bool {
        let chave = CamposAutomaticos.chave(campo)
        return partesLongas.contains { chave.contains($0) }
    }

    /// Nome amigável na tela ({{HDA}} → "História da doença atual (H.D.A.)").
    static func titulo(_ campo: String) -> String {
        let nomes = [
            "QUEIXA_PRINCIPAL": "Queixa principal (Q.P.)", "QP": "Queixa principal (Q.P.)",
            "HDA": "História da doença atual (H.D.A.)", "ANAMNESE": "Anamnese",
            "EXAME_FISICO": "Exame físico", "EXAMES_COMPLEMENTARES": "Exames complementares",
            "PROGRAMACAO_TERAPEUTICA": "Programação terapêutica", "CONDUTA": "Conduta",
            "DIAGNOSTICO": "Diagnóstico", "CID": "CID-10", "PERFIL_CER_II": "Perfil CER II",
            "DATA_NASCIMENTO": "Data de nascimento", "ENDERECO": "Endereço", "NUMERO": "Número",
            "CIDADE_PACIENTE": "Cidade", "TELEFONE": "Telefone", "DATA": "Data da avaliação",
            "CNS": "CNS (cartão do SUS)", "BAIRRO": "Bairro", "CEP": "CEP", "UF": "UF", "CPF": "CPF",
        ]
        return nomes[CamposAutomaticos.chave(campo)] ?? campo
    }

    /// A ficha tem um campo próprio para exames complementares?
    static func campoDeExames(_ ficha: ModeloDocumento) -> String? {
        ficha.campos.first { CamposAutomaticos.chave($0).hasPrefix("EXAMES") }
    }

    static func campoDoExameFisico(_ ficha: ModeloDocumento) -> String? {
        ficha.campos.first { CamposAutomaticos.chave($0).contains("EXAME_FISICO") }
    }

    func valor(_ campo: String) -> Binding<String> {
        Binding(
            get: { valores[campo, default: ""] },
            set: { novo in
                valores[campo] = GerarView.maiusculas(novo)
                geracaoConcluida = false
                aviso = nil
                ultimoDocumento = nil
            }
        )
    }

    // MARK: Tela

    var body: some View {
        Form {
            secaoFicha
            secaoPaciente
            if let ficha {
                secaoIdentificacao(ficha)
                secaoAtendimento(ficha)
                secaoGerar(ficha)
            }
        }
        .formStyle(.grouped)
        .fundoSuave()
        .onAppear {
            armazenamento.instalarFichasProntas()
            if local == nil { localSelecionado = "" }
            validarFicha()
            preencherIdentificacao()
            focoNoNome = true
        }
        .onChange(of: localSelecionado) { _ in
            validarFicha()
            recomecarAtendimento()
        }
        .onChange(of: fichaSelecionada) { _ in recomecarAtendimento() }
        .onChange(of: nomePaciente) { novo in
            let emMaiusculas = GerarView.maiusculas(novo)
            if novo != emMaiusculas {
                nomePaciente = emMaiusculas
                return
            }
            if let id = pacienteEscolhido, !homonimos.contains(where: { $0.id == id }) { pacienteEscolhido = nil }
            // Outro nome depois de gerar = outro paciente: nada do atendimento anterior continua.
            if geracaoConcluida || ultimoDocumento != nil { recomecarAtendimento() }
        }
        .onChange(of: pacienteCadastrado?.id) { novo in
            // Trocou de um paciente para outro: a anamnese e o exame do anterior não seguem.
            if let anterior = ultimoPaciente, anterior != novo { limparAtendimento() }
            ultimoPaciente = novo
            preencherIdentificacao()
        }
        .fileImporter(isPresented: $importandoFicha, allowedContentTypes: [UTType(filenameExtension: "docx") ?? .data]) { resultado in
            guard case .success(let url) = resultado else { return }
            let acesso = url.startAccessingSecurityScopedResource()
            defer { if acesso { url.stopAccessingSecurityScopedResource() } }
            do {
                let nova = try armazenamento.importarFicha(de: url, localID: local?.id)
                fichaSelecionada = nova.id.uuidString
            } catch {
                armazenamento.erro = "Não foi possível importar a ficha: \(error.localizedDescription)"
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: proximoPaciente) {
                    Label("Próximo paciente", systemImage: "arrow.uturn.left.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .help("Limpa o paciente e o atendimento; o local e a ficha continuam")
            }
        }
    }

    var secaoFicha: some View {
        Section {
            Picker("Local de atendimento", selection: $localSelecionado) {
                Text("Nenhum").tag("")
                ForEach(armazenamento.locaisOrdenados) { local in
                    Text(local.nome.isEmpty ? "Sem nome" : local.nome).tag(local.id.uuidString)
                }
            }
            if fichas.isEmpty {
                Text("Nenhuma ficha para este local. Importe uma ficha .docx com campos como {{NOME}}, {{HDA}} e {{EXAME_FISICO}}.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Ficha", selection: $fichaSelecionada) {
                    if ficha == nil { Text("Escolha…").tag("") }
                    ForEach(fichas) { ficha in
                        Text(ficha.nome).tag(ficha.id.uuidString)
                    }
                }
            }
            HStack {
                Button("Importar ficha (.docx)…") { importandoFicha = true }
                if let ficha {
                    Button("Abrir a ficha no Word") { NSWorkspace.shared.open(armazenamento.urlDoModelo(ficha)) }
                        .help("Só para ver a ficha. Alterações feitas nela aqui podem ser substituídas por uma versão nova do app.")
                    if ficha.id != FichasProntas.idAraruna {
                        Button("Remover ficha", role: .destructive) {
                            armazenamento.removerFicha(ficha)
                            fichaSelecionada = ""
                            validarFicha()
                        }
                    }
                }
            }
            .buttonStyle(.link)
        } header: {
            TituloSecao("Ficha do prontuário", icone: "list.clipboard.fill")
        }
    }

    var secaoPaciente: some View {
        Section {
            TextField("Nome do paciente", text: $nomePaciente)
                .focused($focoNoNome)
                .onSubmit {
                    if sugestoes.count == 1 { escolher(sugestoes[0]) }
                }
            if precisaEscolherPaciente {
                Label("Há \(homonimos.count) pacientes com este nome. Qual deles é?", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                ForEach(homonimos) { paciente in
                    Button(Armazenamento.identificacao(paciente)) { pacienteEscolhido = paciente.id }
                        .buttonStyle(.link)
                }
            } else if let paciente = pacienteCadastrado {
                Label("Paciente cadastrado · \(Armazenamento.identificacao(paciente)) — dados preenchidos abaixo", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Tema.sucesso)
            } else if !nomeDigitado.isEmpty {
                ForEach(sugestoes) { paciente in
                    Button("Usar o cadastro de \(paciente.nome) (\(Armazenamento.identificacao(paciente)))") { escolher(paciente) }
                        .buttonStyle(.link)
                }
                Text("Paciente novo: o cadastro será criado ao gerar o prontuário.")
                    .fonteApp(.apoio)
                    .foregroundStyle(.secondary)
            }
        } header: {
            TituloSecao("Paciente", icone: "person.fill")
        }
    }

    @ViewBuilder
    func secaoIdentificacao(_ ficha: ModeloDocumento) -> some View {
        let campos = camposDeIdentificacao(ficha)
        if !campos.isEmpty {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)], alignment: .leading, spacing: 10) {
                    ForEach(campos, id: \.self) { campo in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Self.titulo(campo)).fonteApp(.legenda).foregroundStyle(.secondary)
                            TextField(Self.titulo(campo), text: valor(campo))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            } header: {
                TituloSecao("Identificação", icone: "person.text.rectangle.fill")
            } footer: {
                Text("Vem do cadastro do paciente, do local e da data de hoje. O que você completar aqui (CPF, bairro, CNS…) fica guardado no cadastro.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    func secaoAtendimento(_ ficha: ModeloDocumento) -> some View {
        let campos = camposClinicos(ficha)
        Section {
            ForEach(campos, id: \.self) { campo in
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.titulo(campo)).fontWeight(.semibold)
                    if Self.ehLongo(campo) {
                        TextField(Self.titulo(campo), text: valor(campo), axis: .vertical)
                            .labelsHidden()
                            .lineLimit(4...14)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField(Self.titulo(campo), text: valor(campo), axis: .vertical)
                            .labelsHidden()
                            .lineLimit(1...3)
                            .textFieldStyle(.roundedBorder)
                    }
                    if SugestoesCID.ehCampoCID(campo) {
                        SugestoesCID(texto: valores[campo, default: ""]) { codigo in
                            valor(campo).wrappedValue = codigo.codigo
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if Self.campoDeExames(ficha) == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exames complementares").fontWeight(.semibold)
                    TextField("Exames complementares", text: Binding(
                        get: { examesExtras },
                        set: { examesExtras = GerarView.maiusculas($0); geracaoConcluida = false; aviso = nil }
                    ), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(3...10)
                        .textFieldStyle(.roundedBorder)
                    Text("Esta ficha não tem campo próprio: os exames saem junto do exame físico.")
                        .fonteApp(.legenda)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            TituloSecao("Atendimento", icone: "stethoscope")
        } footer: {
            Text("Anamnese, exame e conduta valem só para este prontuário: não ficam no cadastro e não passam para o próximo paciente.")
                .foregroundStyle(.secondary)
        }
    }

    func secaoGerar(_ ficha: ModeloDocumento) -> some View {
        Section {
            HStack {
                Picker("Depois de gerar", selection: $acaoDepoisDeGerar) {
                    Text("Adicionar à fila de impressão").tag("fila")
                    Text("Imprimir agora").tag("imprimir")
                    Text("Só abrir").tag("salvar")
                }
                .pickerStyle(.menu)
                Spacer()
                Stepper(value: $copias, in: 1...20) {
                    Text("\(copias) \(copias == 1 ? "cópia" : "cópias")").monospacedDigit()
                }
                .fixedSize()
            }
            HStack {
                if let aviso {
                    Label(aviso, systemImage: "checkmark.circle.fill").foregroundStyle(Tema.sucesso)
                    if let ultimoDocumento {
                        Button("Abrir") { NSWorkspace.shared.open(ultimoDocumento) }
                            .buttonStyle(.link)
                    }
                }
                Spacer()
                Button(action: proximoPaciente) {
                    Label("Próximo paciente", systemImage: "arrow.uturn.left.circle.fill")
                }
                .controlSize(.large)
                .tint(Tema.sucesso)
                .buttonStyle(.borderedProminent)
                .opacity(ultimoDocumento == nil ? 0.6 : 1)
                Button("Gerar prontuário") { gerar() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(geracaoConcluida || precisaEscolherPaciente || nomeDigitado.isEmpty)
                    .help(geracaoConcluida ? "Este prontuário já foi gerado. Altere os dados ou clique em Próximo paciente."
                        : nomeDigitado.isEmpty ? "Digite o nome do paciente" : "Gerar o prontuário em Word (Enter)")
            }
        } header: {
            TituloSecao("Gerar", icone: "doc.badge.plus")
        }
    }

    // MARK: Ações

    func escolher(_ paciente: Paciente) {
        nomePaciente = GerarView.maiusculas(paciente.nome)
        pacienteEscolhido = paciente.id
        focoNoNome = false
    }

    /// Fica com uma ficha deste local (a escolhida, se ainda valer; senão a primeira).
    func validarFicha() {
        if ficha == nil { fichaSelecionada = fichas.first?.id.uuidString ?? "" }
    }

    func preencherIdentificacao() {
        guard let ficha else { return }
        for campo in camposDeIdentificacao(ficha) {
            valores[campo] = GerarView.maiusculas(
                CamposAutomaticos.valor(para: campo, paciente: pacienteCadastrado, local: local) ?? ""
            )
        }
    }

    func limparAtendimento() {
        valores = [:]
        examesExtras = ""
        aviso = nil
        ultimoDocumento = nil
        geracaoConcluida = false
    }

    func recomecarAtendimento() {
        limparAtendimento()
        preencherIdentificacao()
    }

    func proximoPaciente() {
        nomePaciente = ""
        pacienteEscolhido = nil
        ultimoPaciente = nil
        recomecarAtendimento()
        focoNoNome = true
    }

    /// Valores que vão para o Word: o nome digitado e, sem campo próprio, os exames junto do exame físico.
    func valoresFinais(_ ficha: ModeloDocumento, nome: String) -> [String: String] {
        var finais = valores
        for campo in ficha.campos where CamposAutomaticos.ehNomeDoPaciente(campo) { finais[campo] = nome }
        let exames = examesExtras.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.campoDeExames(ficha) == nil, !exames.isEmpty, let alvo = Self.campoDoExameFisico(ficha) {
            let exame = finais[alvo, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            finais[alvo] = [exame, "EXAMES COMPLEMENTARES:\n\(exames)"].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        return finais
    }

    func gerar() {
        guard !geracaoConcluida, !precisaEscolherPaciente else { return }
        // Sempre a ficha que está na tela no momento do clique.
        guard let ficha else {
            armazenamento.erro = "Escolha a ficha do prontuário."
            return
        }
        let nome = nomeDigitado
        guard !nome.isEmpty else {
            armazenamento.erro = "Digite o nome do paciente."
            return
        }
        let finais = valoresFinais(ficha, nome: nome)
        let destino: URL
        do {
            destino = try armazenamento.caminhoParaNovoDocumento(
                modelo: ficha, subpasta: "Prontuário", local: local, paciente: nome
            )
            try DocxTemplate.fill(template: armazenamento.urlDoModelo(ficha), values: finais, output: destino)
        } catch {
            armazenamento.erro = error.localizedDescription
            return
        }
        var paciente = pacienteCadastrado ?? armazenamento.novoPaciente(nome: nome)
        if armazenamento.local(paciente.localID) == nil { paciente.localID = local?.id }
        CamposAutomaticos.guardar(finais, campos: ficha.campos, em: &paciente)
        armazenamento.atualizarPaciente(paciente)
        pacienteEscolhido = paciente.id
        ultimoPaciente = paciente.id

        let documento = DocumentoGerado(
            modelo: ficha.nome, modeloID: ficha.id, paciente: nome, pacienteID: paciente.id,
            local: local?.nome, caminho: destino.path
        )
        armazenamento.registrar(documento)
        aviso = "Prontuário pronto: \(destino.lastPathComponent)"
        ultimoDocumento = destino
        geracaoConcluida = true
        if acaoDepoisDeGerar == "fila" || acaoDepoisDeGerar == "imprimir" {
            let jaImprimindo = armazenamento.processandoFila
            let id = armazenamento.adicionarAFila(documento, copias: copias)
            if acaoDepoisDeGerar == "imprimir" && !jaImprimindo {
                aviso = "Prontuário enviado para impressão"
                Task { await armazenamento.imprimirFila(ids: Set([id]), impressora: impressora) }
            } else {
                aviso = "Prontuário na fila de impressão (\(armazenamento.pendentesNaFila) aguardando)"
            }
        } else {
            NSWorkspace.shared.open(destino)
        }
        armazenamento.limparDocumentosTemporarios()
    }
}
