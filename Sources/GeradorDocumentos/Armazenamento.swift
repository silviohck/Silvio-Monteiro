import AppKit
import DocxTemplateKit
import Foundation
import SwiftUI

/// Guarda modelos, pacientes e histórico em ~/Library/Application Support/GeradorDocumentos.
@MainActor
final class Armazenamento: ObservableObject {
    @Published var dados = DadosApp() {
        didSet { salvar() }
    }
    @Published var erro: String?
    @Published var sincronizacao = EstadoSincronizacao()

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

    @discardableResult
    func importarModelo(de origem: URL, localID: UUID? = nil, tipo: String? = nil) throws -> ModeloDocumento {
        let arquivo = "\(UUID().uuidString).docx"
        let destino = pastaModelos.appendingPathComponent(arquivo)
        let campos = try Self.copiarModelo(origem, para: destino)
        let nome = origem.deletingPathExtension().lastPathComponent
        let categoria = tipo ?? ModeloDocumento.categoriaSugerida(para: nome, entre: dados.categorias)
        let modelo = ModeloDocumento(nome: nome, arquivo: arquivo, campos: campos, categoria: categoria, localID: localID)
        dados.modelos.append(modelo)
        return modelo
    }

    /// Copia (ou converte, se não for .docx) o arquivo escolhido e devolve os campos encontrados.
    nonisolated static func copiarModelo(_ origem: URL, para destino: URL) throws -> [String] {
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
    nonisolated private static func lerCoordenado(_ url: URL, _ acao: (URL) throws -> Void) throws {
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
        let campos = try Self.copiarModelo(origem, para: novo)
        let destino = urlDoModelo(modelo)
        try? FileManager.default.removeItem(at: destino)
        try FileManager.default.moveItem(at: novo, to: destino)
        guard let indice = dados.modelos.firstIndex(where: { $0.id == modelo.id }) else { return }
        dados.modelos[indice].campos = campos
    }

    func modelo(_ id: ModeloDocumento.ID?) -> ModeloDocumento? {
        dados.modelos.first { $0.id == id }
    }

    func atualizarModelo(_ modelo: ModeloDocumento) {
        guard let indice = dados.modelos.firstIndex(where: { $0.id == modelo.id }) else { return }
        dados.modelos[indice] = modelo
    }

    /// Local dono do modelo; nil quando o modelo vale para todos (ou o local foi excluído).
    func localDoModelo(_ modelo: ModeloDocumento) -> LocalAtendimento? {
        local(modelo.localID)
    }

    /// Modelos que aparecem para um local: os dele e os de todos os locais, em ordem de tipo e nome.
    func modelos(para local: LocalAtendimento?) -> [ModeloDocumento] {
        dados.modelos
            .filter { modelo in
                guard let dono = localDoModelo(modelo) else { return true }
                return dono.id == local?.id
            }
            .sorted { a, b in
                let tipoA = dados.categorias.firstIndex(of: a.categoria) ?? Int.max
                let tipoB = dados.categorias.firstIndex(of: b.categoria) ?? Int.max
                if tipoA != tipoB { return tipoA < tipoB }
                return a.nome.localizedStandardCompare(b.nome) == .orderedAscending
            }
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

    /// Renomeia o tipo e os modelos dele; se o novo nome já existir, junta os dois tipos.
    func renomearCategoria(_ antigo: String, para novo: String) {
        let novo = novo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !novo.isEmpty, novo != antigo, let indice = dados.categorias.firstIndex(of: antigo) else { return }
        var categorias = dados.categorias
        if categorias.contains(novo) {
            categorias.remove(at: indice)
        } else {
            categorias[indice] = novo
        }
        var modelos = dados.modelos
        for i in modelos.indices where modelos[i].categoria == antigo {
            modelos[i].categoria = novo
        }
        dados.categorias = categorias
        dados.modelos = modelos
    }

    /// Exclui o tipo; os modelos dele passam para `destino`.
    func removerCategoria(_ nome: String, moverPara destino: String) {
        guard nome != destino, dados.categorias.count > 1 else { return }
        var modelos = dados.modelos
        for i in modelos.indices where modelos[i].categoria == nome {
            modelos[i].categoria = destino
        }
        dados.modelos = modelos
        dados.categorias.removeAll { $0 == nome }
    }

    func moverCategorias(de origem: IndexSet, para destino: Int) {
        dados.categorias.move(fromOffsets: origem, toOffset: destino)
    }

    func quantidadeDeModelos(doTipo tipo: String) -> Int {
        dados.modelos.filter { $0.categoria == tipo }.count
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

    /// Pasta do local + subpasta escolhida (vazia = direto na pasta do local).
    func pastaDosDocumentos(subpasta: String, local: LocalAtendimento?) -> URL {
        let nome = Self.nomeSeguro(subpasta)
        guard !nome.isEmpty else { return pastaDoLocal(local) }
        return pastaDoLocal(local).appendingPathComponent(nome, isDirectory: true)
    }

    /// Cria as subpastas de todas as categorias dentro da pasta do local.
    func criarSubpastas(_ local: LocalAtendimento?) throws {
        for categoria in dados.categorias {
            try FileManager.default.createDirectory(
                at: pastaDoLocal(local).appendingPathComponent(Self.nomeSeguro(categoria), isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    /// Caminho livre para o novo documento: "<Modelo> - <Paciente> - 27-10-2026.docx", com (2), (3)… se já existir.
    func caminhoParaNovoDocumento(
        modelo: ModeloDocumento,
        subpasta: String,
        local: LocalAtendimento?,
        paciente: String,
        data: Date = Date()
    ) throws -> URL {
        let pasta = pastaDosDocumentos(subpasta: subpasta, local: local)
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
