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

struct DocumentoGerado: Identifiable, Codable, Hashable {
    var id = UUID()
    var modelo: String
    var paciente: String
    var caminho: String
    var data = Date()
}

struct DadosApp: Codable {
    var modelos: [ModeloDocumento] = []
    var pacientes: [Paciente] = []
    var historico: [DocumentoGerado] = []
}
