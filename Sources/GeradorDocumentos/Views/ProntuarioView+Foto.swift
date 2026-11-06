import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Resultado da última leitura por foto, mostrado na seção "Ler ficha por foto".
struct ResultadoDaFoto {
    var titulo: String
    var detalhes: [String] = []
    var duvidas: [String] = []
    var transcricao = ""
    var erro = false
}

/// Prontuário › Ler ficha por foto: o Claude lê a ficha de papel, a tela é preenchida e o cadastro do
/// paciente é criado (ou completado, se ele já existe).
extension ProntuarioView {
    static let nomesDosCamposLidos: [String: String] = [
        "nome": "Nome", "dataNascimento": "Data de nascimento", "cpf": "CPF", "rg": "RG", "telefone": "Telefone",
        "email": "E-mail", "endereco": "Endereço", "numero": "Número", "bairro": "Bairro", "cidade": "Cidade",
        "uf": "UF", "cep": "CEP", "cns": "CNS", "convenio": "Convênio", "dataAvaliacao": "Data da avaliação",
        "cid": "CID-10", "queixaPrincipal": "Queixa principal", "hda": "H.D.A.", "exameFisico": "Exame físico",
        "examesComplementares": "Exames complementares", "diagnostico": "Diagnóstico",
        "programacaoTerapeutica": "Programação terapêutica", "perfilCerII": "Perfil CER II",
    ]

    static func nomes(_ chaves: [String]) -> String {
        chaves.map { nomesDosCamposLidos[$0] ?? $0 }.joined(separator: ", ")
    }

    var secaoFoto: some View {
        Section {
            if !chaveConfigurada {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Para ler fichas por foto, informe uma chave de API da Anthropic (console.anthropic.com). Ela fica guardada nas Chaves do Mac, não vai para o dados.json nem para o Google Drive.")
                        .fonteApp(.apoio)
                        .foregroundStyle(.secondary)
                    HStack {
                        SecureField("Chave de API (sk-ant-…)", text: $chaveDigitada)
                            .textFieldStyle(.roundedBorder)
                        Button("Guardar chave") {
                            chaveConfigurada = ChaveDaAnthropic.guardar(chaveDigitada) && ChaveDaAnthropic.configurada
                            chaveDigitada = ""
                        }
                        .disabled(chaveDigitada.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Button(action: escolherFoto) {
                        Label("Ler ficha por foto…", systemImage: "camera.viewfinder")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(lendoFoto)
                    if lendoFoto {
                        ProgressView().controlSize(.small)
                        Text("Lendo a ficha… (até um minuto)").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Trocar chave") {
                        ChaveDaAnthropic.apagar()
                        chaveConfigurada = false
                    }
                    .buttonStyle(.link)
                }
                Text("Escolha a foto da ficha (do iPhone, por AirDrop ou pelo app Fotos) ou arraste a imagem para cá. O Claude lê a ficha, preenche a tela e cria o cadastro do paciente, ou completa os campos vazios se ele já estiver cadastrado.")
                    .fonteApp(.legenda)
                    .foregroundStyle(.secondary)
            }

            if let pendente = fichaLidaPendente {
                VStack(alignment: .leading, spacing: 6) {
                    if homonimosDaFoto.isEmpty {
                        Label("O nome ficou com leitura duvidosa. Corrija o nome do paciente abaixo, se preciso, e clique em Cadastrar.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Cadastrar \(nomeDigitado.isEmpty ? "paciente" : nomeDigitado)") {
                            concluirLeitura(pendente, existente: nil, nome: nomeDigitado)
                        }
                        .disabled(nomeDigitado.isEmpty)
                    } else {
                        Label("Há \(homonimosDaFoto.count) pacientes chamados \(LeituraDeFicha.cadastro(de: pendente.paciente).nome). Qual é o da ficha?", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        ForEach(homonimosDaFoto) { paciente in
                            Button(Armazenamento.identificacao(paciente)) { concluirLeitura(pendente, existente: paciente) }
                                .buttonStyle(.link)
                        }
                        Button("É outro paciente: cadastrar como novo") { concluirLeitura(pendente, existente: nil) }
                            .buttonStyle(.link)
                    }
                    Button("Cancelar", role: .cancel) {
                        fichaLidaPendente = nil
                        homonimosDaFoto = []
                    }
                    .buttonStyle(.link)
                }
            }

            if let resultado = resultadoDaFoto {
                VStack(alignment: .leading, spacing: 4) {
                    Label(resultado.titulo, systemImage: resultado.erro ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .foregroundStyle(resultado.erro ? Color.red : Tema.sucesso)
                    ForEach(resultado.detalhes, id: \.self) { Text($0).fonteApp(.apoio) }
                    if !resultado.duvidas.isEmpty {
                        Label("Confira com atenção: \(resultado.duvidas.joined(separator: ", ")).", systemImage: "exclamationmark.triangle.fill")
                            .fonteApp(.apoio)
                            .foregroundStyle(.orange)
                    }
                    if !resultado.transcricao.isEmpty {
                        DisclosureGroup("Transcrição completa") {
                            Text(resultado.transcricao)
                                .fonteApp(.apoio)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        } header: {
            TituloSecao("Ler ficha por foto", icone: "camera.viewfinder")
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { itens in
            guard let item = itens.first, !lendoFoto, chaveConfigurada else { return false }
            _ = item.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { lerFoto(url) }
            }
            return true
        }
    }

    func escolherFoto() {
        let painel = NSOpenPanel()
        painel.allowedContentTypes = [.image]
        painel.allowsMultipleSelection = false
        painel.canChooseDirectories = false
        painel.message = "Escolha a foto da ficha do paciente."
        painel.prompt = "Ler ficha"
        painel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard painel.runModal() == .OK, let url = painel.url else { return }
        lerFoto(url)
    }

    func lerFoto(_ url: URL) {
        guard !lendoFoto else { return }
        lendoFoto = true
        resultadoDaFoto = nil
        fichaLidaPendente = nil
        homonimosDaFoto = []
        Task { @MainActor in
            defer { lendoFoto = false }
            do {
                let lida = try await LeituraDeFicha.ler(imagem: url)
                aplicarLeitura(lida)
            } catch {
                if error as? LeituraDeFicha.Falha == .semChave { chaveConfigurada = false }
                resultadoDaFoto = ResultadoDaFoto(titulo: error.localizedDescription, erro: true)
            }
        }
    }

    func aplicarLeitura(_ lida: FichaLida) {
        let lido = LeituraDeFicha.cadastro(de: lida.paciente)
        if lido.nome.isEmpty || Armazenamento.ilegivel(lido.nome) || lida.duvidas.contains("nome") {
            // Nome duvidoso: não cria cadastro com um nome errado. A pessoa corrige e confirma.
            if case .encontrado(let paciente) = armazenamento.procurar(lido), !lido.nome.isEmpty,
               !LeituraDeFicha.digitos(lido.cpf).isEmpty || !LeituraDeFicha.digitos(lido.cns).isEmpty {
                concluirLeitura(lida, existente: paciente) // CPF/CNS bateu: é ele, mesmo com o nome duvidoso
                return
            }
            limparAtendimento()
            nomePaciente = Armazenamento.ilegivel(lido.nome) ? "" : lido.nome
            pacienteEscolhido = nil
            fichaLidaPendente = lida
            homonimosDaFoto = []
            return
        }
        switch armazenamento.procurar(lido) {
        case .encontrado(let paciente):
            concluirLeitura(lida, existente: paciente)
        case .novo:
            concluirLeitura(lida, existente: nil)
        case .homonimos(let lista):
            fichaLidaPendente = lida
            homonimosDaFoto = lista
        }
    }

    /// Cadastra (ou completa) o paciente e preenche a ficha na tela.
    func concluirLeitura(_ lida: FichaLida, existente: Paciente?, nome: String? = nil) {
        fichaLidaPendente = nil
        homonimosDaFoto = []
        var lido = LeituraDeFicha.cadastro(de: lida.paciente)
        if let nome, !nome.isEmpty { lido.nome = GerarView.maiusculas(nome) }

        limparAtendimento()
        let cadastro = armazenamento.cadastrar(lido, em: existente, local: local)
        // Primeiro o paciente (o onChange não apaga o atendimento: é o mesmo paciente), depois a ficha.
        ultimoPaciente = cadastro.paciente.id
        pacienteEscolhido = cadastro.paciente.id
        nomePaciente = GerarView.maiusculas(cadastro.paciente.nome)
        let dataDaAvaliacao = LeituraDeFicha.data(lida.atendimento.dataAvaliacao)
        dataDaFicha = dataDaAvaliacao.isEmpty || Armazenamento.ilegivel(dataDaAvaliacao) ? nil : dataDaAvaliacao
        preencherIdentificacao()
        if let ficha { aplicarAtendimento(lida.atendimento, em: ficha) }

        var resultado = ResultadoDaFoto(
            titulo: cadastro.novo ? "Cadastro criado: \(cadastro.paciente.nome)" : "Paciente já cadastrado: \(cadastro.paciente.nome)",
            transcricao: lida.transcricao.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if !cadastro.completados.isEmpty {
            resultado.detalhes.append("Completado no cadastro: \(Self.nomes(cadastro.completados)).")
        }
        if !cadastro.diferentes.isEmpty {
            resultado.detalhes.append("Na ficha está diferente (ficou o do cadastro): \(Self.nomes(cadastro.diferentes)).")
        }
        if local == nil { resultado.detalhes.append("Escolha o local de atendimento acima.") }
        resultado.detalhes.append("A ficha abaixo foi preenchida. Confira e clique em Gerar prontuário.")
        resultado.duvidas = lida.duvidas.map { Self.nomesDosCamposLidos[$0] ?? $0 }
        if !lido.cpf.isEmpty && !LeituraDeFicha.cpfValido(lido.cpf) && !resultado.duvidas.contains("CPF") {
            resultado.duvidas.append("CPF (os dígitos não conferem)")
        }
        resultadoDaFoto = resultado
    }

    /// Põe o atendimento lido nos campos da ficha. Campos com linhas ({{HDA}}, {{HDA_LINHA_2}}…) são
    /// preenchidos linha a linha, como se tivessem sido digitados.
    func aplicarAtendimento(_ atendimento: FichaLida.Atendimento, em ficha: ModeloDocumento) {
        let clinicos = camposClinicos(ficha)
        func campo(_ nomes: [String]) -> String? {
            for nome in nomes { if let achado = clinicos.first(where: { CamposAutomaticos.chave($0) == nome }) { return achado } }
            for nome in nomes { if let achado = clinicos.first(where: { CamposAutomaticos.chave($0).hasPrefix(nome) }) { return achado } }
            return nil
        }
        func por(_ texto: String, em campo: String?) {
            let limpo = GerarView.maiusculas(texto.trimmingCharacters(in: .whitespacesAndNewlines))
            guard let campo, !limpo.isEmpty else { return }
            let linhas = [campo] + Self.continuacoes(de: campo, em: ficha)
            guard linhas.count > 1 else {
                valores[campo] = limpo
                return
            }
            var partes = Self.quebrarEmLinhas(limpo)
            if partes.count > linhas.count {
                let resto = partes[(linhas.count - 1)...].joined(separator: " ")
                partes = Array(partes.prefix(linhas.count - 1)) + [resto]
            }
            for (indice, linha) in linhas.enumerated() { valores[linha] = indice < partes.count ? partes[indice] : "" }
        }

        por(atendimento.queixaPrincipal, em: campo(["QUEIXA_PRINCIPAL", "QP", "QUEIXA"]))
        por(atendimento.hda, em: campo(["HDA", "HISTORIA", "ANAMNESE"]))
        por(atendimento.diagnostico, em: campo(["DIAGNOSTICO", "HIPOTESE"]))
        por(atendimento.cid, em: campo(["CID", "CID_10", "CID10"]))
        por(atendimento.programacaoTerapeutica, em: campo(["PROGRAMACAO_TERAPEUTICA", "PROGRAMACAO", "CONDUTA", "PLANO", "TRATAMENTO"]))
        por(atendimento.perfilCerII, em: campo(["PERFIL_CER_II", "PERFIL"]))

        let exames = atendimento.examesComplementares.trimmingCharacters(in: .whitespacesAndNewlines)
        let exameFisico = campo(["EXAME_FISICO"])
        if let proprio = Self.campoDeExames(ficha) {
            por(atendimento.exameFisico, em: exameFisico)
            por(exames, em: proprio)
        } else if !exames.isEmpty, Self.temLinhas(Self.campoDoExameFisico(ficha), em: ficha) {
            // Como na tela: sem campo próprio, os exames vão escritos nas linhas do exame físico.
            let junto = [atendimento.exameFisico.trimmingCharacters(in: .whitespacesAndNewlines), "EXAMES COMPLEMENTARES: \(exames)"]
                .filter { !$0.isEmpty }.joined(separator: "\n")
            por(junto, em: exameFisico)
        } else {
            por(atendimento.exameFisico, em: exameFisico)
            examesExtras = GerarView.maiusculas(exames)
        }
    }
}
