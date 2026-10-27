import Foundation

/// Campos do modelo que são preenchidos sozinhos a partir do paciente, do local de atendimento ou da data.
enum CamposAutomaticos {
    enum Origem {
        case paciente(WritableKeyPath<Paciente, String>)
        case local(KeyPath<LocalAtendimento, String>)
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
        registrar(["LOCAL", "LOCAL_ATENDIMENTO", "LOCAL_DE_ATENDIMENTO", "NOME_LOCAL", "CLINICA", "NOME_CLINICA"], .local(\.nome))
        registrar(["LOCAL_ENDERECO", "ENDERECO_LOCAL", "ENDERECO_CLINICA"], .local(\.endereco))
        registrar(["CIDADE", "LOCAL_CIDADE", "CIDADE_LOCAL"], .local(\.cidade))
        registrar(["LOCAL_TELEFONE", "TELEFONE_LOCAL", "TELEFONE_CLINICA"], .local(\.telefone))
        registrar(["LOCAL_EMAIL", "EMAIL_LOCAL", "EMAIL_CLINICA"], .local(\.email))
        registrar(["CNPJ", "LOCAL_CNPJ", "CNPJ_LOCAL", "CNPJ_CLINICA"], .local(\.cnpj))
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

    /// Campos que vêm do nome digitado na caixa "Nome do paciente".
    static func ehNomeDoPaciente(_ campo: String) -> Bool {
        if case .paciente(let caminho) = mapa[chave(campo)] {
            return caminho == \Paciente.nome
        }
        return false
    }

    static func valor(
        para campo: String,
        paciente: Paciente?,
        local: LocalAtendimento? = nil,
        data: Date = Date()
    ) -> String? {
        switch mapa[chave(campo)] {
        case .paciente(let caminho):
            return paciente?[keyPath: caminho]
        case .local(let caminho):
            return local?[keyPath: caminho]
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

    /// Guarda no cadastro do paciente o que foi digitado no formulário
    /// (CPF, telefone etc. e também campos próprios do modelo, como CID).
    static func guardar(_ valores: [String: String], campos: [String], em paciente: inout Paciente) {
        for campo in campos {
            let texto = valores[campo, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            switch mapa[chave(campo)] {
            case .paciente(let caminho) where caminho != \Paciente.nome:
                if !texto.isEmpty { paciente[keyPath: caminho] = texto }
            case nil:
                paciente.outrosCampos[campo] = texto.isEmpty ? nil : texto
            default:
                break
            }
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
