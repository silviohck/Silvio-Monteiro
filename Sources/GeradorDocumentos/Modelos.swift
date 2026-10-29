import Foundation

/// Um modelo .docx importado; o arquivo fica copiado na pasta de dados do app.
struct ModeloDocumento: Identifiable, Codable, Hashable {
    var id = UUID()
    var nome: String
    var arquivo: String
    var campos: [String]
    /// Subpasta onde os documentos gerados com este modelo são guardados (Receitas, Laudos…).
    var categoria = "Outros"
    /// Local de atendimento dono do modelo; nil = disponível em todos os locais.
    var localID: UUID?
    /// Cópias impressas quando o documento é impresso pelo app.
    var copias = 1
    /// Caminho do arquivo dentro da pasta sincronizada (ex.: "OPERA PB/RX/rx joelho.docx");
    /// nil para modelos importados um a um.
    var origem: String?
    /// Data de modificação do arquivo de origem na última cópia, para saber quando ele mudou.
    var origemModificadaEm: Date?
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
        localID = try container.decodeIfPresent(UUID.self, forKey: .localID)
        copias = try container.decodeIfPresent(Int.self, forKey: .copias) ?? 1
        origem = try container.decodeIfPresent(String.self, forKey: .origem)
        origemModificadaEm = try container.decodeIfPresent(Date.self, forKey: .origemModificadaEm)
        criadoEm = try container.decodeIfPresent(Date.self, forKey: .criadoEm) ?? Date()
    }

    /// Sugere o tipo pelo nome do arquivo ("Receita simples" → o tipo cujo nome começa com "Receit").
    static func categoriaSugerida(para nome: String, entre tipos: [String]) -> String {
        func simples(_ texto: String) -> String {
            texto.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        let nome = simples(nome)
        let apelidos = ["rx": "radiograf", "raio x": "radiograf", "raio-x": "radiograf", "usg": "ultrassom"]
        for tipo in tipos {
            let raiz = String(simples(tipo).prefix(5))
            if raiz.count >= 4, nome.contains(raiz) { return tipo }
            for (apelido, alvo) in apelidos where nome.contains(apelido) && simples(tipo).hasPrefix(alvo) {
                return tipo
            }
        }
        return tipos.first { simples($0) == "outros" } ?? tipos.last ?? "Outros"
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
    // Campos próprios dos modelos (CID, dias, turno…) não ficam no cadastro: valem só para o documento.
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
    /// Subpasta da pasta sincronizada que pertence a este local (ex.: "OPERA PB").
    var pastaSincronizada: String?
    /// Tipos de documento (subpastas) deste local, na ordem escolhida.
    var tipos: [String] = []
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
        pastaSincronizada = try container.decodeIfPresent(String.self, forKey: .pastaSincronizada)
        tipos = try container.decodeIfPresent([String].self, forKey: .tipos) ?? []
    }
}

struct DocumentoGerado: Identifiable, Codable, Hashable {
    var id = UUID()
    var modelo: String
    /// Para reaproveitar os ajustes de impressão do modelo no Histórico.
    var modeloID: UUID?
    var paciente: String
    /// Identificador do cadastro do paciente (o nome sozinho pode se repetir).
    var pacienteID: UUID?
    var local: String?
    var caminho: String
    var data = Date()
}

/// Situação da fila: "enviado" indica que o Word aceitou o comando, não que o papel saiu.
enum SituacaoImpressao: String, Codable {
    case pendente
    case enviando
    case enviado
    case erro
    case incerto
}

/// Metadados da impressão; o arquivo .docx continua na pasta onde foi salvo.
struct ItemFilaImpressao: Identifiable, Codable, Hashable {
    var id = UUID()
    var documentoID: UUID
    var caminho: String
    var modelo: String
    var paciente: String
    var local: String?
    var copias: Int
    var criadoEm = Date()
    var situacao: SituacaoImpressao = .pendente
    var observacao: String?

    init(documento: DocumentoGerado, copias: Int) {
        documentoID = documento.id
        caminho = documento.caminho
        modelo = documento.modelo
        paciente = documento.paciente
        local = documento.local
        self.copias = max(1, min(20, copias))
    }
}

struct DadosApp: Codable {
    var modelos: [ModeloDocumento] = []
    var pacientes: [Paciente] = []
    var locais: [LocalAtendimento] = []
    /// Tipos dos modelos de "Todos os locais" e lista inicial de cada local novo.
    var categorias = DadosApp.categoriasPadrao
    var historico: [DocumentoGerado] = []
    /// Fila persistente para imprimir posteriormente, inclusive após reiniciar o aplicativo.
    var filaImpressao: [ItemFilaImpressao] = []
    /// Pasta com os modelos (uma subpasta por local, uma subpasta por tipo) acompanhada pelo app.
    var pastaSincronizada = ""
    /// Subpastas da pasta sincronizada que não são locais de atendimento.
    var pastasIgnoradas: [String] = []
    /// Subpastas da pasta sincronizada que valem para todos os locais (ex.: "1 - APAC"): aparecem como
    /// subpasta de cada local, sem precisar copiar nem criar atalhos.
    var pastasCompartilhadas: [String] = DadosApp.pastasCompartilhadasPadrao
    /// Pasta padrão dos documentos gerados para locais sem pasta própria (vazia = Documentos/Orthck).
    var pastaDocumentos = ""
    /// Nomes dos modelos favoritos (ex.: "Retorno"), na ordem escolhida. Pelo nome, para valer
    /// em todos os locais que tenham um modelo com esse nome.
    var favoritos: [String] = []

    static let categoriasPadrao = ["Receitas", "Atestados", "Laudos", "Relatórios médicos", "Radiografias", "Outros"]

    /// A pasta APAC já começa compartilhada; dá para mudar na ⚙️ da pasta sincronizada.
    static let pastasCompartilhadasPadrao = ["1 - APAC"]

    /// Sem diferenciar maiúsculas e acentos ("1 - Apac" = "1 - APAC").
    func ehCompartilhada(_ pasta: String) -> Bool {
        pastasCompartilhadas.contains {
            $0.compare(pasta, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    init() {}

    // Lê também arquivos salvos por versões anteriores, que não tinham todas as listas.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelos = try container.decodeIfPresent([ModeloDocumento].self, forKey: .modelos) ?? []
        pacientes = try container.decodeIfPresent([Paciente].self, forKey: .pacientes) ?? []
        locais = try container.decodeIfPresent([LocalAtendimento].self, forKey: .locais) ?? []
        categorias = try container.decodeIfPresent([String].self, forKey: .categorias) ?? Self.categoriasPadrao
        historico = try container.decodeIfPresent([DocumentoGerado].self, forKey: .historico) ?? []
        filaImpressao = try container.decodeIfPresent([ItemFilaImpressao].self, forKey: .filaImpressao) ?? []
        pastaSincronizada = try container.decodeIfPresent(String.self, forKey: .pastaSincronizada) ?? ""
        pastasIgnoradas = try container.decodeIfPresent([String].self, forKey: .pastasIgnoradas) ?? []
        pastasCompartilhadas = try container.decodeIfPresent([String].self, forKey: .pastasCompartilhadas)
            ?? Self.pastasCompartilhadasPadrao
        pastaDocumentos = try container.decodeIfPresent(String.self, forKey: .pastaDocumentos) ?? ""
        favoritos = try container.decodeIfPresent([String].self, forKey: .favoritos) ?? []
    }
}
