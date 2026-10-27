import Foundation

/// Um modelo .docx importado; o arquivo fica copiado na pasta de dados do app.
struct ModeloDocumento: Identifiable, Codable, Hashable {
    var id = UUID()
    var nome: String
    var arquivo: String
    var campos: [String]
    /// Subpasta onde os documentos gerados com este modelo são guardados (Receitas, Laudos…).
    var categoria = "Outros"
    var criadoEm = Date()
}

extension ModeloDocumento {
    // Feito em extensão para manter o inicializador automático da struct.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nome = try container.decode(String.self, forKey: .nome)
        arquivo = try container.decode(String.self, forKey: .arquivo)
        campos = try container.decode([String].self, forKey: .campos)
        categoria = try container.decodeIfPresent(String.self, forKey: .categoria) ?? "Outros"
        criadoEm = try container.decodeIfPresent(Date.self, forKey: .criadoEm) ?? Date()
    }

    /// Sugere o tipo pelo nome do arquivo ("Receita simples" → Receitas).
    static func categoriaSugerida(para nome: String) -> String {
        let nome = nome.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if nome.contains("receit") { return "Receitas" }
        if nome.contains("laudo") { return "Laudos" }
        if nome.contains("relat") { return "Relatórios médicos" }
        return "Outros"
    }
}

struct Paciente: Identifiable, Codable, Hashable {
    var id = UUID()
    var nome = ""
    var cpf = ""
    var rg = ""
    var dataNascimento = ""
    var telefone = ""
    var email = ""
    var endereco = ""
    var convenio = ""
    var observacoes = ""
    /// Local de atendimento onde o paciente é atendido (opcional).
    var localID: UUID?
    /// Valores digitados para campos que não são do cadastro fixo, para reaproveitar depois.
    var outrosCampos: [String: String] = [:]
}

struct LocalAtendimento: Identifiable, Codable, Hashable {
    var id = UUID()
    var nome = ""
    var endereco = ""
    var cidade = ""
    var telefone = ""
    var email = ""
    var cnpj = ""
    /// Pasta onde os documentos deste local são salvos; vazia = pasta padrão em Documentos.
    var pasta = ""
}

extension LocalAtendimento {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nome = try container.decodeIfPresent(String.self, forKey: .nome) ?? ""
        endereco = try container.decodeIfPresent(String.self, forKey: .endereco) ?? ""
        cidade = try container.decodeIfPresent(String.self, forKey: .cidade) ?? ""
        telefone = try container.decodeIfPresent(String.self, forKey: .telefone) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        cnpj = try container.decodeIfPresent(String.self, forKey: .cnpj) ?? ""
        pasta = try container.decodeIfPresent(String.self, forKey: .pasta) ?? ""
    }
}

struct DocumentoGerado: Identifiable, Codable, Hashable {
    var id = UUID()
    var modelo: String
    var paciente: String
    var local: String?
    var caminho: String
    var data = Date()
}

struct DadosApp: Codable {
    var modelos: [ModeloDocumento] = []
    var pacientes: [Paciente] = []
    var locais: [LocalAtendimento] = []
    var categorias = DadosApp.categoriasPadrao
    var historico: [DocumentoGerado] = []

    static let categoriasPadrao = ["Receitas", "Laudos", "Relatórios médicos", "Outros"]

    init() {}

    // Lê também arquivos salvos por versões anteriores, que não tinham todas as listas.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelos = try container.decodeIfPresent([ModeloDocumento].self, forKey: .modelos) ?? []
        pacientes = try container.decodeIfPresent([Paciente].self, forKey: .pacientes) ?? []
        locais = try container.decodeIfPresent([LocalAtendimento].self, forKey: .locais) ?? []
        categorias = try container.decodeIfPresent([String].self, forKey: .categorias) ?? Self.categoriasPadrao
        historico = try container.decodeIfPresent([DocumentoGerado].self, forKey: .historico) ?? []
    }
}
