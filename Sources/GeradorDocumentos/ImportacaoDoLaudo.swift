import Foundation

/// Arquivo "Orthck - entrada - dd-mm-aaaa HHhMM.json" deixado no Google Drive pelo app do Laudo AIH.
struct ArquivoDeEntrada: Decodable {
    let tipo: String?
    let pacientes: [PacienteDeEntrada]
}

/// Paciente no formato do dados.json; o resto (CNS, mãe, procedimento, valores dos documentos…) fica de fora:
/// este app guarda só os dados gerais do paciente.
struct PacienteDeEntrada: Decodable {
    let id: String?
    let nome: String?
    let cpf: String?
    let rg: String?
    let dataNascimento: String?
    let telefone: String?
    let email: String?
    let endereco: String?
    let convenio: String?
    let observacoes: String?
}

extension Armazenamento {
    static let prefixoDasEntradas = "Orthck - entrada - "

    /// Procura no Drive, na pasta do arquivo de dados, as entradas ainda não importadas e traz os pacientes.
    /// Devolve quantos pacientes vieram; nil quando o login não permite ler as entradas (conexão antiga).
    /// Um arquivo inválido é pulado e continua lá; os outros seguem.
    func importarEntradasDoLaudo(pastaDe idDosDados: String?) async -> Int? {
        guard drive.podeLerEntradas else { return nil }
        do {
            var pasta: String?
            if let idDosDados { pasta = try await drive.pastaDoArquivo(id: idDosDados) }
            let entradas = try await drive.listar(comecandoCom: Self.prefixoDasEntradas, naPasta: pasta)
                .filter { !dados.entradasImportadas.contains($0.id) }
            guard !entradas.isEmpty else { return 0 }
            var lidos: [(id: String, arquivo: ArquivoDeEntrada)] = []
            for entrada in entradas {
                guard let conteudo = try? await drive.baixar(id: entrada.id),
                      let arquivo = try? JSONDecoder().decode(ArquivoDeEntrada.self, from: conteudo),
                      arquivo.tipo == nil || arquivo.tipo == "orthck-entrada" else { continue }
                lidos.append((entrada.id, arquivo))
            }
            guard !lidos.isEmpty else { return 0 }
            // Tudo numa cópia e gravado uma vez só.
            var atual = dados
            var quantidade = 0
            for lido in lidos {
                for paciente in lido.arquivo.pacientes where !(paciente.nome ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    Self.incluir(paciente, em: &atual)
                    quantidade += 1
                }
                atual.entradasImportadas.append(lido.id)
            }
            dados = atual
            return quantidade
        } catch {
            return 0
        }
    }

    /// Paciente igual: pelo CPF (só os dígitos); sem CPF, pelo nome (sem acentos e espaços extras) e, quando os
    /// dois têm, pela data de nascimento. Achou: completa só o que está vazio. Não achou: cadastro novo.
    static func incluir(_ entrada: PacienteDeEntrada, em dados: inout DadosApp) {
        let cpf = somenteDigitos(entrada.cpf ?? "")
        let nome = nomeComparavel(entrada.nome ?? "")
        let nascimento = (entrada.dataNascimento ?? "").trimmingCharacters(in: .whitespaces)
        let indice = dados.pacientes.firstIndex { existente in
            let cpfExistente = somenteDigitos(existente.cpf)
            if !cpf.isEmpty && !cpfExistente.isEmpty { return cpf == cpfExistente }
            guard nomeComparavel(existente.nome) == nome else { return false }
            let nascimentoExistente = existente.dataNascimento.trimmingCharacters(in: .whitespaces)
            return nascimento.isEmpty || nascimentoExistente.isEmpty || nascimento == nascimentoExistente
        }
        var paciente: Paciente
        if let indice {
            paciente = dados.pacientes[indice]
        } else {
            let id = entrada.id.flatMap(UUID.init(uuidString:)).flatMap { id in
                dados.pacientes.contains { $0.id == id } ? nil : id
            } ?? UUID()
            paciente = Paciente(id: id)
        }
        func completar(_ campo: WritableKeyPath<Paciente, String>, _ valor: String?) {
            let valor = (valor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if paciente[keyPath: campo].trimmingCharacters(in: .whitespaces).isEmpty && !valor.isEmpty {
                paciente[keyPath: campo] = valor
            }
        }
        completar(\.nome, entrada.nome)
        completar(\.cpf, entrada.cpf)
        completar(\.rg, entrada.rg)
        completar(\.dataNascimento, entrada.dataNascimento)
        completar(\.telefone, entrada.telefone)
        completar(\.email, entrada.email)
        completar(\.endereco, entrada.endereco)
        completar(\.convenio, entrada.convenio)
        let observacoes = (entrada.observacoes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !observacoes.isEmpty && !paciente.observacoes.contains(observacoes) {
            paciente.observacoes = paciente.observacoes.isEmpty ? observacoes : paciente.observacoes + "\n" + observacoes
        }
        if let indice { dados.pacientes[indice] = paciente } else { dados.pacientes.append(paciente) }
    }

    static func somenteDigitos(_ texto: String) -> String {
        String(texto.filter(\.isNumber))
    }

    static func nomeComparavel(_ texto: String) -> String {
        texto.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
            .uppercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
