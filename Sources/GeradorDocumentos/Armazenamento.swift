import AppKit
import DocxTemplateKit
import Foundation

/// Guarda modelos, pacientes e histórico em ~/Library/Application Support/GeradorDocumentos.
@MainActor
final class Armazenamento: ObservableObject {
    @Published var dados = DadosApp() {
        didSet { salvar() }
    }
    @Published var erro: String?
    /// Modelos lidos da pasta principal (ver `Biblioteca`).
    @Published private(set) var biblioteca: [GrupoDeModelos] = []
    private var cacheCampos: [String: (data: Date, campos: [String])] = [:]

    let pasta: URL
    let pastaModelos: URL
    private var arquivoDados: URL { pasta.appendingPathComponent("dados.json") }

    init() {
        let suporte = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        pasta = suporte.appendingPathComponent("GeradorDocumentos", isDirectory: true)
        pastaModelos = pasta.appendingPathComponent("Modelos", isDirectory: true)
        try? FileManager.default.createDirectory(at: pastaModelos, withIntermediateDirectories: true)
        carregar()
        recarregarBiblioteca()
    }

    // MARK: Pasta de modelos

    static let grupoImportados = "Importados no app"

    var urlPastaModelos: URL? {
        dados.pastaModelos.isEmpty ? nil : URL(fileURLWithPath: dados.pastaModelos, isDirectory: true)
    }

    func definirPastaModelos(_ url: URL?) {
        dados.pastaModelos = url?.path ?? ""
        recarregarBiblioteca()
    }

    func recarregarBiblioteca() {
        biblioteca = urlPastaModelos.map(Biblioteca.ler) ?? []
        cacheCampos = [:]
    }

    /// Pastas da biblioteca mais os modelos importados um a um.
    var grupos: [GrupoDeModelos] {
        guard !dados.modelos.isEmpty else { return biblioteca }
        let importados = dados.modelos.map {
            ModeloDaPasta(url: urlDoModelo($0), nome: $0.nome, tipo: $0.categoria)
        }
        return biblioteca + [GrupoDeModelos(nome: Self.grupoImportados, modelos: importados)]
    }

    func grupo(_ nome: String) -> GrupoDeModelos? {
        grupos.first { $0.nome == nome }
    }

    /// Cadastro do local ligado a uma pasta da biblioteca (escolhido no cadastro ou pelo mesmo nome).
    func local(doGrupo nome: String) -> LocalAtendimento? {
        dados.locais.first { $0.grupoModelos == nome }
            ?? dados.locais.first {
                $0.grupoModelos.isEmpty
                    && $0.nome.trimmingCharacters(in: .whitespaces).compare(nome, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
    }

    func campos(de modelo: ModeloDaPasta) throws -> [String] {
        let data = (try? modelo.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if let cache = cacheCampos[modelo.id], cache.data == data {
            return cache.campos
        }
        let campos = try lerCoordenado(modelo.url) { try DocxTemplate.placeholders(in: $0) }
        cacheCampos[modelo.id] = (data, campos)
        return campos
    }

    func gerarDocumento(_ modelo: ModeloDaPasta, valores: [String: String], destino: URL) throws {
        try lerCoordenado(modelo.url) { try DocxTemplate.fill(template: $0, values: valores, output: destino) }
    }

    var pacientesOrdenados: [Paciente] {
        dados.pacientes.sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
    }

    // MARK: Modelos

    func urlDoModelo(_ modelo: ModeloDocumento) -> URL {
        pastaModelos.appendingPathComponent(modelo.arquivo)
    }

    func importarModelo(de origem: URL) throws {
        let arquivo = "\(UUID().uuidString).docx"
        let destino = pastaModelos.appendingPathComponent(arquivo)
        let campos = try copiarModelo(origem, para: destino)
        let nome = origem.deletingPathExtension().lastPathComponent
        var categoria = ModeloDocumento.categoriaSugerida(para: nome)
        if !dados.categorias.contains(categoria) { categoria = dados.categorias.last ?? categoria }
        dados.modelos.append(ModeloDocumento(nome: nome, arquivo: arquivo, campos: campos, categoria: categoria))
    }

    /// Copia (ou converte, se não for .docx) o arquivo escolhido e devolve os campos encontrados.
    private func copiarModelo(_ origem: URL, para destino: URL) throws -> [String] {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destino)
        try lerCoordenado(origem) { (url: URL) -> Void in
            if url.pathExtension.lowercased() == "docx" {
                try fileManager.copyItem(at: url, to: destino)
            } else {
                try DocxTemplate.convertToDocx(url, output: destino)
            }
        }
        do {
            return try DocxTemplate.placeholders(in: destino)
        } catch {
            try? fileManager.removeItem(at: destino)
            throw DocxError.arquivoInvalido(origem.lastPathComponent)
        }
    }

    /// Leitura coordenada: faz o macOS baixar antes arquivos que estão só no iCloud/OneDrive.
    private func lerCoordenado<T>(_ url: URL, _ acao: (URL) throws -> T) throws -> T {
        var erroCoordenacao: NSError?
        var resultado: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &erroCoordenacao) { urlLocal in
            resultado = Result { try acao(urlLocal) }
        }
        if let erroCoordenacao { throw erroCoordenacao }
        guard let resultado else { throw DocxError.arquivoInvalido(url.lastPathComponent) }
        return try resultado.get()
    }

    func removerModelo(_ modelo: ModeloDocumento) {
        try? FileManager.default.removeItem(at: urlDoModelo(modelo))
        dados.modelos.removeAll { $0.id == modelo.id }
    }

    // MARK: Pacientes

    func paciente(_ id: Paciente.ID?) -> Paciente? {
        dados.pacientes.first { $0.id == id }
    }

    func atualizarPaciente(_ paciente: Paciente) {
        guard let indice = dados.pacientes.firstIndex(where: { $0.id == paciente.id }) else { return }
        dados.pacientes[indice] = paciente
    }

    func novoPaciente(nome: String = "") -> Paciente {
        let paciente = Paciente(nome: nome)
        dados.pacientes.append(paciente)
        return paciente
    }

    /// Paciente cadastrado com exatamente este nome (sem diferenciar maiúsculas e acentos).
    func paciente(chamado nome: String) -> Paciente? {
        let nome = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nome.isEmpty else { return nil }
        return dados.pacientes.first {
            $0.nome.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(nome, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    func removerPaciente(_ id: Paciente.ID) {
        dados.pacientes.removeAll { $0.id == id }
    }

    // MARK: Locais de atendimento

    var locaisOrdenados: [LocalAtendimento] {
        dados.locais.sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
    }

    func local(_ id: LocalAtendimento.ID?) -> LocalAtendimento? {
        dados.locais.first { $0.id == id }
    }

    func atualizarLocal(_ local: LocalAtendimento) {
        guard let indice = dados.locais.firstIndex(where: { $0.id == local.id }) else { return }
        dados.locais[indice] = local
    }

    func novoLocal() -> LocalAtendimento {
        let local = LocalAtendimento()
        dados.locais.append(local)
        return local
    }

    func removerLocal(_ id: LocalAtendimento.ID) {
        dados.locais.removeAll { $0.id == id }
    }

    // MARK: Pastas dos documentos gerados

    func adicionarCategoria(_ nome: String) {
        let nome = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nome.isEmpty, !dados.categorias.contains(nome) else { return }
        dados.categorias.append(nome)
    }

    /// Pasta escolhida para o local ou, se nenhuma, Documentos/Gerador de Documentos/<local>.
    func pastaDoLocal(_ local: LocalAtendimento?) -> URL {
        if let pasta = local?.pasta, !pasta.isEmpty {
            return URL(fileURLWithPath: pasta, isDirectory: true)
        }
        let documentos = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let nome = Self.nomeSeguro(local?.nome ?? "")
        return documentos
            .appendingPathComponent("Gerador de Documentos", isDirectory: true)
            .appendingPathComponent(nome.isEmpty ? "Sem local" : nome, isDirectory: true)
    }

    /// Pasta do local (ou, sem cadastro, Documentos/Gerador de Documentos/<pasta do grupo>) + subpasta do tipo.
    func pastaDosDocumentos(modelo: ModeloDaPasta, grupo: String, local: LocalAtendimento?) -> URL {
        let base: URL
        if let local {
            base = pastaDoLocal(local)
        } else {
            base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Gerador de Documentos", isDirectory: true)
                .appendingPathComponent(Self.nomeSeguro(grupo), isDirectory: true)
        }
        guard modelo.tipo != Biblioteca.tipoGeral else { return base }
        return base.appendingPathComponent(Self.nomeSeguro(modelo.tipo), isDirectory: true)
    }

    /// Caminho livre para o novo documento: "<Modelo> - <Paciente> - 27-10-2026.docx", com (2), (3)… se já existir.
    func caminhoParaNovoDocumento(modelo: ModeloDaPasta, grupo: String, local: LocalAtendimento?, paciente: String, data: Date = Date()) throws -> URL {
        let pasta = pastaDosDocumentos(modelo: modelo, grupo: grupo, local: local)
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)

        let formatador = DateFormatter()
        formatador.dateFormat = "dd-MM-yyyy"
        let base = Self.nomeSeguro([modelo.nome, paciente, formatador.string(from: data)].filter { !$0.isEmpty }.joined(separator: " - "))

        var destino = pasta.appendingPathComponent(base + ".docx")
        var numero = 2
        while FileManager.default.fileExists(atPath: destino.path) {
            destino = pasta.appendingPathComponent("\(base) (\(numero)).docx")
            numero += 1
        }
        return destino
    }

    static func nomeSeguro(_ nome: String) -> String {
        nome.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Histórico

    func registrar(_ documento: DocumentoGerado) {
        dados.historico.insert(documento, at: 0)
    }

    // MARK: Disco

    func abrirPastaDeDados() {
        NSWorkspace.shared.open(pasta)
    }

    private func carregar() {
        guard let conteudo = try? Data(contentsOf: arquivoDados) else { return }
        do {
            dados = try Self.decodificador.decode(DadosApp.self, from: conteudo)
        } catch {
            // Mantém uma cópia do arquivo que não pôde ser lido em vez de sobrescrevê-lo.
            let copia = pasta.appendingPathComponent("dados-ilegivel-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: arquivoDados, to: copia)
            erro = "Não foi possível ler os dados salvos. Uma cópia foi guardada em \(copia.lastPathComponent)."
        }
    }

    private func salvar() {
        do {
            try Self.codificador.encode(dados).write(to: arquivoDados, options: .atomic)
        } catch {
            erro = "Não foi possível salvar os dados: \(error.localizedDescription)"
        }
    }

    private static let codificador: JSONEncoder = {
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys]
        codificador.dateEncodingStrategy = .iso8601
        return codificador
    }()

    private static let decodificador: JSONDecoder = {
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .iso8601
        return decodificador
    }()
}
