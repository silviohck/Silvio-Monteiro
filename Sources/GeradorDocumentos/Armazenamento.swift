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
        let campos = try DocxTemplate.placeholders(in: origem)
        let arquivo = "\(UUID().uuidString).docx"
        try FileManager.default.copyItem(at: origem, to: pastaModelos.appendingPathComponent(arquivo))
        let nome = origem.deletingPathExtension().lastPathComponent
        dados.modelos.append(ModeloDocumento(nome: nome, arquivo: arquivo, campos: campos))
    }

    /// Relê os campos depois que o modelo foi editado no Word.
    func atualizarCampos(_ modelo: ModeloDocumento) throws {
        let campos = try DocxTemplate.placeholders(in: urlDoModelo(modelo))
        guard let indice = dados.modelos.firstIndex(where: { $0.id == modelo.id }) else { return }
        dados.modelos[indice].campos = campos
    }

    func substituirArquivo(_ modelo: ModeloDocumento, por origem: URL) throws {
        let campos = try DocxTemplate.placeholders(in: origem)
        let destino = urlDoModelo(modelo)
        try? FileManager.default.removeItem(at: destino)
        try FileManager.default.copyItem(at: origem, to: destino)
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

    func novoPaciente() -> Paciente {
        let paciente = Paciente()
        dados.pacientes.append(paciente)
        return paciente
    }

    func removerPaciente(_ id: Paciente.ID) {
        dados.pacientes.removeAll { $0.id == id }
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
