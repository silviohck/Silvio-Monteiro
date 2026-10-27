import AppKit
import DocxTemplateKit
import Foundation
import SwiftUI

/// Guarda modelos, pacientes e histórico em ~/Library/Application Support/GeradorDocumentos
/// (nome da versão anterior do app, mantido para não perder os dados).
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
        let categoria = tipo ?? ModeloDocumento.categoriaSugerida(para: nome, entre: tipos(doLocal: localID))
        adicionarCategoria(categoria, local: localID)
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
        let ordem = tipos(doLocal: local?.id)
        return dados.modelos
            .filter { modelo in
                guard let dono = localDoModelo(modelo) else { return true }
                return dono.id == local?.id
            }
            .sorted { a, b in
                // "RX / Joelho" fica logo depois de "RX".
                let principalA = a.categoria.components(separatedBy: Self.separadorDeSubpastas)[0]
                let principalB = b.categoria.components(separatedBy: Self.separadorDeSubpastas)[0]
                let tipoA = ordem.firstIndex(of: principalA) ?? ordem.firstIndex(of: a.categoria) ?? Int.max
                let tipoB = ordem.firstIndex(of: principalB) ?? ordem.firstIndex(of: b.categoria) ?? Int.max
                if tipoA != tipoB { return tipoA < tipoB }
                if a.categoria != b.categoria {
                    return a.categoria.localizedStandardCompare(b.categoria) == .orderedAscending
                }
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
    /// Todos os pacientes com exatamente este nome (homônimos).
    func pacientes(chamados nome: String) -> [Paciente] {
        let nome = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nome.isEmpty else { return [] }
        return dados.pacientes.filter {
            $0.nome.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(nome, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    /// "nasc. 01/02/1990 · CPF 123" — para diferenciar pacientes com o mesmo nome.
    static func identificacao(_ paciente: Paciente) -> String {
        var partes: [String] = []
        let nascimento = paciente.dataNascimento.trimmingCharacters(in: .whitespaces)
        partes.append(nascimento.isEmpty ? "sem data de nascimento" : "nasc. \(nascimento)")
        if !paciente.cpf.isEmpty { partes.append("CPF \(paciente.cpf)") }
        return partes.joined(separator: " · ")
    }

    func paciente(chamado nome: String) -> Paciente? {
        let nome = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nome.isEmpty else { return nil }
        return dados.pacientes.first {
            $0.nome.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(nome, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    /// Locais onde o paciente já foi atendido: o do cadastro e os dos documentos gerados para ele.
    func locaisDoPaciente(_ paciente: Paciente) -> [LocalAtendimento] {
        var ids: [UUID] = paciente.localID.map { [$0] } ?? []
        for documento in dados.historico where documento.pacienteID == paciente.id {
            guard let nome = documento.local,
                  let local = dados.locais.first(where: { Self.mesmoNome($0.nome, nome) }),
                  !ids.contains(local.id) else { continue }
            ids.append(local.id)
        }
        return ids.compactMap(local)
    }

    /// "Alagoa Grande" ou "Alagoa Grande, Araruna"
    func nomesDosLocais(_ paciente: Paciente) -> String {
        locaisDoPaciente(paciente).map(\.nome).filter { !$0.isEmpty }.joined(separator: ", ")
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
        var local = LocalAtendimento()
        local.tipos = dados.categorias
        dados.locais.append(local)
        return local
    }

    /// Exclui o local depois de decidir o destino dos modelos e pacientes dele:
    /// `destino` = outro local (transferir) ou nil (desvincular: modelos de todos os locais, pacientes sem local).
    func excluirLocal(_ id: LocalAtendimento.ID, transferirPara destino: LocalAtendimento.ID?) {
        guard let local = local(id) else { return }
        for i in dados.modelos.indices where dados.modelos[i].localID == id {
            dados.modelos[i].localID = destino
        }
        for i in dados.pacientes.indices where dados.pacientes[i].localID == id {
            dados.pacientes[i].localID = destino
        }
        // Pasta sincronizada do local: passa para o destino, se ele ainda não tiver uma;
        // senão deixa de ser acompanhada, para o local não voltar na próxima sincronização.
        if let pasta = local.pastaSincronizada {
            if let destino, let indice = dados.locais.firstIndex(where: { $0.id == destino }),
               dados.locais[indice].pastaSincronizada == nil {
                dados.locais[indice].pastaSincronizada = pasta
            } else if !dados.pastasIgnoradas.contains(pasta) {
                dados.pastasIgnoradas.append(pasta)
            }
        }
        dados.locais.removeAll { $0.id == id }
    }

    // MARK: Pastas dos documentos gerados

    // MARK: Tipos de documento
    // Cada local tem a sua lista de tipos; `local == nil` são os modelos de "Todos os locais".

    /// Tipos do local, na ordem escolhida, mais algum tipo usado por modelo dele que não esteja na lista.
    func tipos(doLocal id: UUID?) -> [String] {
        var lista = listaDeTipos(id)
        for modelo in dados.modelos where pertence(modelo, ao: id) && !lista.contains(modelo.categoria) {
            lista.append(modelo.categoria)
        }
        return lista
    }

    func pertence(_ modelo: ModeloDocumento, ao local: UUID?) -> Bool {
        local == nil ? localDoModelo(modelo) == nil : modelo.localID == local
    }

    private func listaDeTipos(_ id: UUID?) -> [String] {
        if let id, let local = local(id) { return local.tipos }
        return dados.categorias
    }

    private func definirListaDeTipos(_ lista: [String], _ id: UUID?) {
        if let id, let indice = dados.locais.firstIndex(where: { $0.id == id }) {
            dados.locais[indice].tipos = lista
        } else {
            dados.categorias = lista
        }
    }

    func adicionarCategoria(_ nome: String, local id: UUID?) {
        let nome = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        var lista = listaDeTipos(id)
        guard !nome.isEmpty, !lista.contains(nome) else { return }
        lista.append(nome)
        definirListaDeTipos(lista, id)
    }

    /// Renomeia o tipo e os modelos dele no local; se o novo nome já existir, junta os dois tipos.
    func renomearCategoria(_ antigo: String, para novo: String, local id: UUID?) {
        let novo = novo.trimmingCharacters(in: .whitespacesAndNewlines)
        var lista = tipos(doLocal: id)
        guard !novo.isEmpty, novo != antigo, let indice = lista.firstIndex(of: antigo) else { return }
        if lista.contains(novo) {
            lista.remove(at: indice)
        } else {
            lista[indice] = novo
        }
        var modelos = dados.modelos
        for i in modelos.indices where modelos[i].categoria == antigo && pertence(modelos[i], ao: id) {
            modelos[i].categoria = novo
        }
        definirListaDeTipos(lista, id)
        dados.modelos = modelos
    }

    /// Exclui o tipo do local; os modelos dele passam para `destino`.
    func removerCategoria(_ nome: String, moverPara destino: String, local id: UUID?) {
        var lista = tipos(doLocal: id)
        guard nome != destino, lista.count > 1 else { return }
        var modelos = dados.modelos
        for i in modelos.indices where modelos[i].categoria == nome && pertence(modelos[i], ao: id) {
            modelos[i].categoria = destino
        }
        dados.modelos = modelos
        lista.removeAll { $0 == nome }
        definirListaDeTipos(lista, id)
    }

    func moverCategorias(de origem: IndexSet, para destino: Int, local id: UUID?) {
        var lista = tipos(doLocal: id)
        lista.move(fromOffsets: origem, toOffset: destino)
        definirListaDeTipos(lista, id)
    }

    func quantidadeDeModelos(doTipo tipo: String, local id: UUID?) -> Int {
        dados.modelos.filter { $0.categoria == tipo && pertence($0, ao: id) }.count
    }

    /// Documentos/Orthck, ou Documentos/Gerador de Documentos se já existir da época do nome antigo.
    private static let nomeDaPastaPadrao: String = {
        let documentos = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let antiga = documentos.appendingPathComponent("Gerador de Documentos").path
        return FileManager.default.fileExists(atPath: antiga) ? "Gerador de Documentos" : "Orthck"
    }()

    /// Pasta do local dentro da pasta principal: usa a que já existir com o nome do local
    /// (sem diferenciar maiúsculas e acentos: "CAMPINA GRANDE" = "Campina Grande") ou a que será criada.
    /// Se o local tiver uma pasta própria escolhida e ela já for a pasta do local (mesmo nome), usa direto;
    /// se for uma pasta geral, procura/cria a pasta do local dentro dela.
    func pastaDoLocal(_ local: LocalAtendimento?) -> URL {
        let nome = Self.nomeSeguro(local?.nome ?? "")
        let nomeDaPasta = nome.isEmpty ? "Sem local" : nome
        if let pasta = local?.pasta, !pasta.isEmpty {
            let escolhida = URL(fileURLWithPath: pasta, isDirectory: true)
            if Self.mesmoNome(escolhida.lastPathComponent, nomeDaPasta) { return escolhida }
            return Self.pasta(em: escolhida, chamada: nomeDaPasta)
        }
        return Self.pasta(em: pastaPadraoDosDocumentos, chamada: nomeDaPasta)
    }

    /// Subpasta de `base` com este nome, se já existir (sem diferenciar maiúsculas e acentos);
    /// senão, o caminho da que será criada ao salvar. Um atalho (alias) do Finder com esse nome
    /// é seguido até a pasta original (ex.: o atalho "1 - APAC" dentro da pasta do local).
    static func pasta(em base: URL, chamada nome: String) -> URL {
        let existentes = (try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey, .isAliasFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for item in existentes where mesmoNome(item.lastPathComponent, nome) {
            let valores = try? item.resourceValues(forKeys: [.isDirectoryKey, .isAliasFileKey, .isSymbolicLinkKey])
            if valores?.isAliasFile == true || valores?.isSymbolicLink == true {
                if let destino = try? URL(resolvingAliasFileAt: item, options: [.withoutUI, .withoutMounting]),
                   (try? destino.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    return destino
                }
            } else if valores?.isDirectory == true {
                return item
            }
        }
        return base.appendingPathComponent(nomeSeguro(nome), isDirectory: true)
    }

    static func mesmoNome(_ a: String, _ b: String) -> Bool {
        nomeSeguro(a).compare(nomeSeguro(b), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Pasta escolhida em "Pasta padrão para todos os locais" ou Documentos/Orthck.
    var pastaPadraoDosDocumentos: URL {
        if !dados.pastaDocumentos.isEmpty {
            return URL(fileURLWithPath: dados.pastaDocumentos, isDirectory: true)
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.nomeDaPastaPadrao, isDirectory: true)
    }

    func definirPasta(_ url: URL, doLocal id: LocalAtendimento.ID) {
        guard let indice = dados.locais.firstIndex(where: { $0.id == id }) else { return }
        dados.locais[indice].pasta = url.path
    }

    /// Separa as pastas de uma subpasta com mais de um nível: "RX / Joelho".
    static let separadorDeSubpastas = " / "

    /// "RX" + ["Joelho"] → "RX / Joelho"
    static func subpasta(_ tipo: String, dentro pastas: [String]) -> String {
        ([tipo] + pastas).joined(separator: separadorDeSubpastas)
    }

    /// Pasta do local + subpasta escolhida (vazia = direto na pasta do local);
    /// "RX / Joelho" vira a pasta Joelho dentro de RX.
    func pastaDosDocumentos(subpasta: String, local: LocalAtendimento?) -> URL {
        subpasta.components(separatedBy: Self.separadorDeSubpastas)
            .map(Self.nomeSeguro)
            .filter { !$0.isEmpty }
            .reduce(pastaDoLocal(local)) { pasta, nome in Self.pasta(em: pasta, chamada: nome) }
    }

    /// Cria as subpastas de todas as categorias dentro da pasta do local.
    func criarSubpastas(_ local: LocalAtendimento?) throws {
        for categoria in tipos(doLocal: local?.id) {
            try FileManager.default.createDirectory(
                at: pastaDosDocumentos(subpasta: categoria, local: local),
                withIntermediateDirectories: true
            )
        }
    }

    /// Caminho livre para o novo documento: "<Modelo> - <Paciente> - 27-10-2026.docx", com (2), (3)… se já existir.
    /// `pastaAvulsa`: pasta escolhida só para este documento (sem subpasta).
    func caminhoParaNovoDocumento(
        modelo: ModeloDocumento,
        subpasta: String,
        local: LocalAtendimento?,
        paciente: String,
        pastaAvulsa: URL? = nil,
        data: Date = Date()
    ) throws -> URL {
        let pasta = pastaAvulsa ?? pastaDosDocumentos(subpasta: subpasta, local: local)
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
            separarTiposPorLocal()
        } catch {
            // Mantém uma cópia do arquivo que não pôde ser lido em vez de sobrescrevê-lo.
            let copia = pasta.appendingPathComponent("dados-ilegivel-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: arquivoDados, to: copia)
            erro = "Não foi possível ler os dados salvos. Uma cópia foi guardada em \(copia.lastPathComponent)."
        }
    }

    /// Versões anteriores tinham uma lista de tipos só: cada local passa a ter a sua,
    /// começando pelos tipos que os modelos dele já usam.
    private func separarTiposPorLocal() {
        for indice in dados.locais.indices where dados.locais[indice].tipos.isEmpty {
            let id = dados.locais[indice].id
            let usados = Set(dados.modelos.filter { $0.localID == id }.map(\.categoria))
            var lista = dados.categorias.filter { usados.contains($0) }
            lista += usados.subtracting(lista).sorted()
            dados.locais[indice].tipos = lista.isEmpty ? dados.categorias : lista
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
