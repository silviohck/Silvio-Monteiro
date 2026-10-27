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

    let pasta: URL
    let pastaModelos: URL
    private var arquivoDados: URL { pasta.appendingPathComponent("dados.json") }

    init() {
        let suporte = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        pasta = suporte.appendingPathComponent("GeradorDocumentos", isDirectory: true)
        pastaModelos = pasta.appendingPathComponent("Modelos", isDirectory: true)
        try? FileManager.default.createDirectory(at: pastaModelos, withIntermediateDirectories: true)
        carregar()
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
        dados.modelos.append(ModeloDocumento(nome: nome, arquivo: arquivo, campos: campos))
    }

    /// Copia (ou converte, se não for .docx) o arquivo escolhido e devolve os campos encontrados.
    private func copiarModelo(_ origem: URL, para destino: URL) throws -> [String] {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destino)
        try lerCoordenado(origem) { url in
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
    private func lerCoordenado(_ url: URL, _ acao: (URL) throws -> Void) throws {
        var erroCoordenacao: NSError?
        var erroAcao: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &erroCoordenacao) { urlLocal in
            do {
                try acao(urlLocal)
            } catch {
                erroAcao = error
            }
        }
        if let erroCoordenacao { throw erroCoordenacao }
        if let erroAcao { throw erroAcao }
    }

    /// Relê os campos depois que o modelo foi editado no Word.
    func atualizarCampos(_ modelo: ModeloDocumento) throws {
        let campos = try DocxTemplate.placeholders(in: urlDoModelo(modelo))
        guard let indice = dados.modelos.firstIndex(where: { $0.id == modelo.id }) else { return }
        dados.modelos[indice].campos = campos
    }

    func substituirArquivo(_ modelo: ModeloDocumento, por origem: URL) throws {
        // Valida o arquivo novo antes de apagar o modelo atual.
        let novo = pastaModelos.appendingPathComponent("\(UUID().uuidString).docx")
        let campos = try copiarModelo(origem, para: novo)
        let destino = urlDoModelo(modelo)
        try? FileManager.default.removeItem(at: destino)
        try FileManager.default.moveItem(at: novo, to: destino)
        guard let indice = dados.modelos.firstIndex(where: { $0.id == modelo.id }) else { return }
        dados.modelos[indice].campos = campos
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
