import Foundation

/// Um modelo .docx importado; o arquivo fica copiado na pasta de dados do app.
struct ModeloDocumento: Identifiable, Codable, Hashable {
    var id = UUID()
    var nome: String
    var arquivo: String
    var campos: [String]
    var criadoEm = Date()
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
    var historico: [DocumentoGerado] = []

    init() {}

    // Lê também arquivos salvos por versões anteriores, que não tinham todas as listas.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelos = try container.decodeIfPresent([ModeloDocumento].self, forKey: .modelos) ?? []
        pacientes = try container.decodeIfPresent([Paciente].self, forKey: .pacientes) ?? []
        locais = try container.decodeIfPresent([LocalAtendimento].self, forKey: .locais) ?? []
        historico = try container.decodeIfPresent([DocumentoGerado].self, forKey: .historico) ?? []
    }
}
