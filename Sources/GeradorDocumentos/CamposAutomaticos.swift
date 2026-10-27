import Foundation

/// Campos do modelo que são preenchidos sozinhos a partir do cadastro do paciente ou da data.
enum CamposAutomaticos {
    enum Origem {
        case paciente(KeyPath<Paciente, String>)
        case idade
        case dataHoje
        case dataExtenso
    }

    static let mapa: [String: Origem] = {
        var mapa: [String: Origem] = [:]
        func registrar(_ chaves: [String], _ origem: Origem) {
            for chave in chaves { mapa[chave] = origem }
        }
        registrar(["NOME", "PACIENTE", "NOME_PACIENTE", "NOME_DO_PACIENTE", "NOME_COMPLETO"], .paciente(\.nome))
        registrar(["CPF", "CPF_PACIENTE", "CPF_DO_PACIENTE"], .paciente(\.cpf))
        registrar(["RG", "RG_PACIENTE", "RG_DO_PACIENTE"], .paciente(\.rg))
        registrar(["DATA_NASCIMENTO", "DATA_DE_NASCIMENTO", "NASCIMENTO", "DN"], .paciente(\.dataNascimento))
        registrar(["TELEFONE", "CELULAR", "FONE", "WHATSAPP"], .paciente(\.telefone))
        registrar(["EMAIL", "E_MAIL"], .paciente(\.email))
        registrar(["ENDERECO", "ENDERECO_PACIENTE"], .paciente(\.endereco))
        registrar(["CONVENIO", "PLANO", "PLANO_DE_SAUDE"], .paciente(\.convenio))
        registrar(["IDADE"], .idade)
        registrar(["DATA", "HOJE", "DATA_HOJE", "DATA_ATUAL"], .dataHoje)
        registrar(["DATA_EXTENSO", "DATA_POR_EXTENSO"], .dataExtenso)
        return mapa
    }()

    /// "Data de Nascimento" → "DATA_DE_NASCIMENTO"
    static func chave(_ campo: String) -> String {
        let simples = campo
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .uppercased()
        let partes = simples
            .map { $0.isLetter || $0.isNumber ? String($0) : " " }
            .joined()
            .split(separator: " ")
        return partes.joined(separator: "_")
    }

    static func ehAutomatico(_ campo: String) -> Bool {
        mapa[chave(campo)] != nil
    }

    static func valor(para campo: String, paciente: Paciente?, data: Date = Date()) -> String? {
        switch mapa[chave(campo)] {
        case .paciente(let caminho):
            return paciente?[keyPath: caminho]
        case .idade:
            return paciente.flatMap { idade(dataNascimento: $0.dataNascimento, em: data) }.map(String.init)
        case .dataHoje:
            return formatador("dd/MM/yyyy").string(from: data)
        case .dataExtenso:
            return formatador("d 'de' MMMM 'de' yyyy").string(from: data)
        case nil:
            return paciente?.outrosCampos[campo]
        }
    }

    static func idade(dataNascimento: String, em data: Date = Date()) -> Int? {
        guard let nascimento = formatador("dd/MM/yyyy").date(from: dataNascimento.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return Calendar(identifier: .gregorian).dateComponents([.year], from: nascimento, to: data).year
    }

    private static func formatador(_ formato: String) -> DateFormatter {
        let formatador = DateFormatter()
        formatador.locale = Locale(identifier: "pt_BR")
        formatador.calendar = Calendar(identifier: .gregorian)
        formatador.dateFormat = formato
        return formatador
    }
}
