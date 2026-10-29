import AppKit
import CryptoKit
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
    /// Criando o .zip da pasta sincronizada.
    @Published var compactando = false
    /// Bloqueio global: não dispara duas sequências de impressão simultaneamente.
    @Published private(set) var processandoFila = false

    let pasta: URL
    let pastaModelos: URL
    var arquivoDados: URL { pasta.appendingPathComponent("dados.json") }
    /// Cópias diárias do dados.json (as últimas 30), em Backups/ dentro da pasta de dados.
    var pastaBackups: URL { pasta.appendingPathComponent("Backups", isDirectory: true) }
    private var diaDoUltimoBackup = ""
    private static let backupsGuardados = 30

    /// Cópia dos dados no Google Drive, direto pela internet.
    let drive: GoogleDrive
    @Published private(set) var googleConectado = false
    /// Situação da cópia no Google Drive, mostrada na barra lateral.
    @Published var situacaoNuvem = ""
    @Published private(set) var sincronizandoDrive = false
    /// Há mudanças esperando o próximo envio ao Drive.
    @Published private(set) var envioPendente = false
    private var envioAgendado: Task<Void, Never>?
    /// Ao voltar para o app, o Drive é consultado no máximo uma vez a cada 30 segundos.
    private static let intervaloMinimoAoVoltar: TimeInterval = 30
    private var ultimaConsultaAoVoltar = Date.distantPast
    private var outraSincronizacaoPedida = false
    /// Arquivo no Drive e a versão dele já lida ou enviada por este Mac (ficam só neste Mac).
    private var idNoDrive: String? {
        get { UserDefaults.standard.string(forKey: "driveArquivoID") }
        set { UserDefaults.standard.set(newValue, forKey: "driveArquivoID") }
    }
    private var versaoConhecidaNoDrive: String {
        get { UserDefaults.standard.string(forKey: "driveVersaoConhecida") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "driveVersaoConhecida") }
    }
    /// Resumo do último conteúdo enviado, para não reenviar o que não mudou.
    private var ultimoEnviado: String {
        get { UserDefaults.standard.string(forKey: "driveUltimoEnviado") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "driveUltimoEnviado") }
    }
    static let nomeDoArquivoNuvem = "Orthck - dados.json"

    /// O armazenamento do app, para o fechamento do app enviar ao Drive o que estiver pendente.
    static weak var atual: Armazenamento?

    init() {
        let suporte = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        pasta = suporte.appendingPathComponent("GeradorDocumentos", isDirectory: true)
        pastaModelos = pasta.appendingPathComponent("Modelos", isDirectory: true)
        drive = GoogleDrive(pasta: pasta)
        googleConectado = drive.conectado
        try? FileManager.default.createDirectory(at: pastaModelos, withIntermediateDirectories: true)
        carregar()
        Self.atual = self
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

    /// Modelos que aparecem para um local: os dele e os de todos os locais, em ordem alfabética de subpasta e nome.
    func modelos(para local: LocalAtendimento?) -> [ModeloDocumento] {
        dados.modelos
            .filter { modelo in
                guard let dono = localDoModelo(modelo) else { return true }
                return dono.id == local?.id
            }
            .sorted { a, b in
                if a.categoria != b.categoria {
                    return a.categoria.localizedStandardCompare(b.categoria) == .orderedAscending
                }
                return a.nome.localizedStandardCompare(b.nome) == .orderedAscending
            }
    }

    // MARK: Favoritos

    func ehFavorito(_ modelo: ModeloDocumento) -> Bool {
        dados.favoritos.contains { Self.mesmoNome($0, modelo.nome) }
    }

    func alternarFavorito(_ modelo: ModeloDocumento) {
        if ehFavorito(modelo) {
            dados.favoritos.removeAll { Self.mesmoNome($0, modelo.nome) }
        } else {
            dados.favoritos.append(modelo.nome)
        }
    }

    /// Os favoritos que existem neste local, na ordem em que foram marcados.
    func favoritos(para local: LocalAtendimento?) -> [ModeloDocumento] {
        let disponiveis = modelos(para: local)
        return dados.favoritos.compactMap { nome in
            disponiveis.first { Self.mesmoNome($0.nome, nome) }
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

    /// Tipos do local mais algum tipo usado por modelo dele que não esteja na lista, em ordem alfabética.
    func tipos(doLocal id: UUID?) -> [String] {
        var lista = listaDeTipos(id)
        for modelo in dados.modelos where pertence(modelo, ao: id) && !lista.contains(modelo.categoria) {
            lista.append(modelo.categoria)
        }
        return Self.emOrdemAlfabetica(lista)
    }

    /// Ordem alfabética do Finder: "1 - APAC" antes de "2 - RX", "RX" antes de "RX / Joelho".
    static func emOrdemAlfabetica(_ nomes: [String]) -> [String] {
        nomes.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
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

    /// Caminho livre para o novo documento: "<Modelo> - <Paciente> - <Local> - 27-10-2026.docx", com (2), (3)… se já existir.
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
        // O local entra no nome: o Word não abre dois documentos com o mesmo nome ao mesmo tempo,
        // e mostraria o do outro local no lugar do novo.
        let partes = [modelo.nome, paciente, local?.nome ?? "", formatador.string(from: data)]
        let base = Self.nomeSeguro(partes.filter { !$0.isEmpty }.joined(separator: " - "))

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

    // MARK: Fila de impressão

    var pendentesNaFila: Int {
        dados.filaImpressao.filter { $0.situacao == .pendente }.count
    }

    /// Salva uma referência ao documento, nunca uma cópia do arquivo Word. Se o documento já está
    /// aguardando na fila, devolve esse item; se já foi impresso, entra de novo (ex.: pelo Histórico).
    @discardableResult
    func adicionarAFila(_ documento: DocumentoGerado, copias: Int) -> UUID {
        if let existente = dados.filaImpressao.first(where: { $0.documentoID == documento.id && $0.situacao == .pendente }) {
            return existente.id
        }
        let item = ItemFilaImpressao(documento: documento, copias: copias)
        dados.filaImpressao.append(item)
        return item.id
    }

    /// Remover da fila não apaga documentos nem registros do histórico.
    func removerDaFila(_ id: UUID) {
        guard !processandoFila else { return }
        dados.filaImpressao.removeAll { $0.id == id }
    }

    func limparEnviadosDaFila() {
        guard !processandoFila else { return }
        dados.filaImpressao.removeAll { $0.situacao == .enviado }
    }

    func definirCopias(_ copias: Int, doItem id: UUID) {
        guard let indice = dados.filaImpressao.firstIndex(where: { $0.id == id }),
              dados.filaImpressao[indice].situacao == .pendente else { return }
        dados.filaImpressao[indice].copias = max(1, min(20, copias))
    }

    /// Reenvio só após confirmação explícita na interface: pode causar impressão duplicada.
    func reenfileirar(_ id: UUID) {
        guard !processandoFila,
              let indice = dados.filaImpressao.firstIndex(where: { $0.id == id }),
              dados.filaImpressao[indice].situacao == .erro
                || dados.filaImpressao[indice].situacao == .incerto else { return }
        dados.filaImpressao[indice].situacao = .pendente
        dados.filaImpressao[indice].observacao = nil
    }

    /// Envia os arquivos um por vez ao Word. Sucesso significa "comando enviado", não impressão física.
    /// `manterAberto`: deixa o documento aberto no Word depois de imprimir (quando também foi aberto ao gerar).
    func imprimirFila(ids: Set<UUID>, impressora: String, manterAberto: Bool = false) async {
        guard !processandoFila else { return }
        processandoFila = true
        defer { processandoFila = false }

        // Fotografia da ordem no momento do clique. Novos itens aguardarão a próxima rodada.
        let ordem = dados.filaImpressao
            .filter { ids.contains($0.id) && $0.situacao == .pendente }
            .map(\.id)

        for id in ordem {
            if Task.isCancelled { break }
            guard let indice = dados.filaImpressao.firstIndex(where: { $0.id == id }),
                  dados.filaImpressao[indice].situacao == .pendente else { continue }
            let item = dados.filaImpressao[indice]
            guard FileManager.default.fileExists(atPath: item.caminho) else {
                dados.filaImpressao[indice].situacao = .erro
                dados.filaImpressao[indice].observacao = "Arquivo não encontrado. Confira a pasta antes de tentar novamente."
                continue
            }

            dados.filaImpressao[indice].situacao = .enviando
            let erroDaImpressao: String? = await withCheckedContinuation { continuation in
                Impressao.imprimir(
                    URL(fileURLWithPath: item.caminho),
                    impressora: impressora,
                    manterAberto: manterAberto,
                    copias: item.copias
                ) { erro in
                    continuation.resume(returning: erro)
                }
            }

            guard let atualizado = dados.filaImpressao.firstIndex(where: { $0.id == id }) else { continue }
            if let erroDaImpressao {
                // Erro não prova que a impressão não saiu. Reenvio somente com confirmação.
                dados.filaImpressao[atualizado].situacao = .erro
                dados.filaImpressao[atualizado].observacao = erroDaImpressao
            } else {
                // Impresso: sai da fila (o documento continua salvo e no Histórico).
                dados.filaImpressao.remove(at: atualizado)
            }
        }
    }

    // MARK: Disco

    func abrirPastaDeDados() {
        NSWorkspace.shared.open(pasta)
    }

    private func carregar() {
        guard let conteudo = try? Data(contentsOf: arquivoDados) else { return }
        do {
            dados = try Self.decodificador.decode(DadosApp.self, from: conteudo)
            // O app pode ter sido encerrado enquanto o Word recebia o comando.
            // Não reenviar automaticamente: a impressão anterior pode ter acontecido.
            for indice in dados.filaImpressao.indices where dados.filaImpressao[indice].situacao == .enviando {
                dados.filaImpressao[indice].situacao = .incerto
                dados.filaImpressao[indice].observacao = "O aplicativo foi fechado durante o envio. Confira a impressora antes de reenviar."
            }
            separarTiposPorLocal()
        } catch {
            // Mantém uma cópia do arquivo que não pôde ser lido em vez de sobrescrevê-lo.
            let copia = pasta.appendingPathComponent("dados-ilegivel-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: arquivoDados, to: copia)
            erro = "Não foi possível ler os dados salvos. Uma cópia foi guardada em \(copia.lastPathComponent)."
        }
    }

    // MARK: Importar dados (.json)

    enum ModoDeImportacao {
        /// Acrescenta pacientes, locais, histórico e fila que ainda não existem aqui.
        case juntar
        /// Troca todos os dados por os do arquivo (restaurar um backup).
        case substituir
    }

    /// Importa um dados.json (de um backup diário ou do .zip). Antes, guarda uma cópia dos dados atuais
    /// em Backups/. Devolve um resumo do que entrou.
    /// `deOutroComputador`: junção automática da cópia no Google Drive — sem cópia de segurança a cada vez
    /// e sem a fila de impressão (ela é de cada computador).
    func importarDados(de url: URL, modo: ModoDeImportacao, deOutroComputador: Bool = false) throws -> String {
        let conteudo = try Data(contentsOf: url)
        let importados: DadosApp
        do {
            importados = try Self.decodificador.decode(DadosApp.self, from: conteudo)
        } catch {
            throw NSError(domain: "Orthck", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "“\(url.lastPathComponent)” não é um arquivo de dados do Orthck.",
            ])
        }

        // Cópia dos dados de agora, para poder voltar atrás.
        if !deOutroComputador, FileManager.default.fileExists(atPath: arquivoDados.path) {
            let formatador = DateFormatter()
            formatador.dateFormat = "yyyy-MM-dd-HHmmss"
            try? FileManager.default.createDirectory(at: pastaBackups, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(
                at: arquivoDados,
                to: pastaBackups.appendingPathComponent("antes-de-importar-\(formatador.string(from: Date())).json")
            )
        }

        switch modo {
        case .substituir:
            var novos = importados
            // Pastas de outro computador podem não existir neste: mantém as daqui.
            if !FileManager.default.fileExists(atPath: novos.pastaSincronizada) {
                novos.pastaSincronizada = dados.pastaSincronizada
            }
            if !novos.pastaDocumentos.isEmpty && !FileManager.default.fileExists(atPath: novos.pastaDocumentos) {
                novos.pastaDocumentos = dados.pastaDocumentos
            }
            // Modelos importados à mão cujo arquivo não está neste Mac não funcionariam; os da pasta
            // sincronizada são copiados de novo na próxima sincronização.
            let antes = novos.modelos.count
            novos.modelos.removeAll { $0.origem == nil && !FileManager.default.fileExists(atPath: urlDoModelo($0).path) }
            let semArquivo = antes - novos.modelos.count
            for indice in novos.filaImpressao.indices where novos.filaImpressao[indice].situacao == .enviando {
                novos.filaImpressao[indice].situacao = .incerto
            }
            dados = novos
            separarTiposPorLocal()
            var resumo = "Dados substituídos: \(novos.pacientes.count) pacientes, \(novos.locais.count) locais e \(novos.historico.count) documentos no histórico."
            if semArquivo > 0 {
                resumo += " \(semArquivo) modelo(s) importado(s) à mão ficaram de fora porque o arquivo não está neste Mac."
            }
            return resumo

        case .juntar:
            var atual = dados
            // Locais: o mesmo (pelo id ou pelo nome) é reaproveitado; os outros entram.
            var mapaDeLocais: [UUID: UUID] = [:]
            var locaisNovos = 0
            for local in importados.locais {
                if atual.locais.contains(where: { $0.id == local.id }) {
                    mapaDeLocais[local.id] = local.id
                } else if let mesmo = atual.locais.first(where: { Self.mesmoNome($0.nome, local.nome) }) {
                    mapaDeLocais[local.id] = mesmo.id
                } else {
                    atual.locais.append(local)
                    mapaDeLocais[local.id] = local.id
                    locaisNovos += 1
                }
            }
            var pacientesNovos = 0
            for paciente in importados.pacientes where !atual.pacientes.contains(where: { $0.id == paciente.id }) {
                var paciente = paciente
                paciente.localID = paciente.localID.flatMap { mapaDeLocais[$0] }
                atual.pacientes.append(paciente)
                pacientesNovos += 1
            }
            let idsDoHistorico = Set(atual.historico.map(\.id))
            let historicoNovo = importados.historico.filter { !idsDoHistorico.contains($0.id) }
            atual.historico = (atual.historico + historicoNovo).sorted { $0.data > $1.data }
            if !deOutroComputador {
                let idsDaFila = Set(atual.filaImpressao.map(\.id))
                atual.filaImpressao += importados.filaImpressao.filter { !idsDaFila.contains($0.id) && $0.situacao == .pendente }
            }
            // Favoritos marcados no outro computador também valem aqui.
            for favorito in importados.favoritos where !atual.favoritos.contains(where: { Self.mesmoNome($0, favorito) }) {
                atual.favoritos.append(favorito)
            }
            dados = atual
            return "Dados juntados: \(pacientesNovos) pacientes, \(locaisNovos) locais e \(historicoNovo.count) documentos no histórico entraram."
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
        fazerBackupDoDia()
        do {
            try Self.codificador.encode(dados).write(to: arquivoDados, options: .atomic)
            agendarEnvioAoDrive()
        } catch {
            erro = "Não foi possível salvar os dados: \(error.localizedDescription)"
        }
    }

    // MARK: Cópia no Google Drive

    /// Intervalo entre uma mudança e o envio ao Drive: as mudanças desse intervalo vão juntas.
    private static let intervaloDoDrive: UInt64 = 120

    /// Depois de uma mudança, a cópia no Drive é atualizada em até 2 minutos; mais mudanças
    /// nesse tempo entram no mesmo envio. Ao fechar o app, o que estiver pendente é enviado.
    private func agendarEnvioAoDrive() {
        guard drive.conectado else { return }
        envioPendente = true
        guard envioAgendado == nil else { return }
        envioAgendado = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.intervaloDoDrive * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.envioAgendado = nil
            await self?.sincronizarDrive()
        }
    }

    /// Antes de fechar o app: envia na hora o que estiver pendente.
    func enviarPendenteAoDrive() async {
        guard envioPendente, drive.conectado else { return }
        envioAgendado?.cancel()
        envioAgendado = nil
        // Uma sincronização em andamento já leva as mudanças; espera ela terminar.
        while sincronizandoDrive { try? await Task.sleep(nanoseconds: 200_000_000) }
        if envioPendente { await sincronizarDrive() }
    }

    /// Ao abrir o app, ao voltar para ele e depois de cada mudança: se a cópia no Drive mudou
    /// em outro computador, junta com os dados daqui; depois envia o resultado, se mudou.
    func sincronizarDrive() async {
        googleConectado = drive.conectado
        guard drive.conectado else { return }
        guard !sincronizandoDrive else {
            outraSincronizacaoPedida = true
            return
        }
        sincronizandoDrive = true
        envioPendente = false
        defer {
            sincronizandoDrive = false
            if outraSincronizacaoPedida {
                outraSincronizacaoPedida = false
                agendarEnvioAoDrive()
            }
        }
        do {
            var remoto: ArquivoNoDrive?
            if let id = idNoDrive { remoto = try await drive.metadados(id: id) }
            if remoto == nil { remoto = try await drive.procurarArquivo(nome: Self.nomeDoArquivoNuvem) }
            var resumo: String?
            if let remoto, remoto.modificado != versaoConhecidaNoDrive {
                let conteudo = try await drive.baixar(id: remoto.id)
                let temporario = FileManager.default.temporaryDirectory
                    .appendingPathComponent("orthck-drive-\(UUID().uuidString).json")
                try conteudo.write(to: temporario)
                defer { try? FileManager.default.removeItem(at: temporario) }
                resumo = try importarDados(de: temporario, modo: .juntar, deOutroComputador: true)
                versaoConhecidaNoDrive = remoto.modificado
            }
            let local = try Self.codificador.encode(dados)
            let marca = SHA256.hash(data: local).map { String(format: "%02x", $0) }.joined()
            if remoto == nil || marca != ultimoEnviado || remoto?.id != idNoDrive {
                let enviado = try await drive.enviar(local, nome: Self.nomeDoArquivoNuvem, id: remoto?.id)
                idNoDrive = enviado.id
                versaoConhecidaNoDrive = enviado.modificado
                ultimoEnviado = marca
            } else if let remoto {
                idNoDrive = remoto.id
            }
            let hora = Date().formatted(date: .omitted, time: .shortened)
            situacaoNuvem = resumo.map { "Atualizado às \(hora) · \($0)" } ?? "Atualizado às \(hora)"
        } catch {
            situacaoNuvem = error.localizedDescription
            // Não foi: tenta de novo no próximo intervalo.
            agendarEnvioAoDrive()
        }
        googleConectado = drive.conectado
    }

    /// Ao abrir o app e ao voltar para ele: consulta o Drive só se a última consulta por esse motivo
    /// foi há mais de 30 segundos. O envio a cada 2 minutos, ao fechar e o "Sincronizar agora" não
    /// passam por esse limite.
    func sincronizarDriveAoVoltar() async {
        guard drive.conectado, Date().timeIntervalSince(ultimaConsultaAoVoltar) >= Self.intervaloMinimoAoVoltar else { return }
        ultimaConsultaAoVoltar = Date()
        await sincronizarDrive()
    }

    /// Login no Google pelo navegador; em seguida junta a cópia que já existir no Drive.
    func conectarGoogle(clientID: String, clientSecret: String) async throws {
        try await drive.conectar(clientID: clientID, clientSecret: clientSecret)
        idNoDrive = nil
        versaoConhecidaNoDrive = ""
        ultimoEnviado = ""
        googleConectado = true
        await sincronizarDrive()
    }

    func desconectarGoogle() {
        envioAgendado?.cancel()
        envioAgendado = nil
        envioPendente = false
        drive.desconectar()
        googleConectado = false
        situacaoNuvem = ""
    }

    var enderecoNoDrive: URL? {
        idNoDrive.flatMap { URL(string: "https://drive.google.com/file/d/\($0)/view") }
    }

    /// Uma vez por dia, antes de gravar, guarda uma cópia do dados.json como estava (a versão boa
    /// do dia anterior) e apaga as mais antigas que as últimas 30.
    private func fazerBackupDoDia() {
        let formatador = DateFormatter()
        formatador.dateFormat = "yyyy-MM-dd"
        let hoje = formatador.string(from: Date())
        guard hoje != diaDoUltimoBackup else { return }
        diaDoUltimoBackup = hoje
        let arquivos = FileManager.default
        guard arquivos.fileExists(atPath: arquivoDados.path) else { return }
        let destino = pastaBackups.appendingPathComponent("dados-\(hoje).json")
        guard !arquivos.fileExists(atPath: destino.path) else { return }
        do {
            try arquivos.createDirectory(at: pastaBackups, withIntermediateDirectories: true)
            try arquivos.copyItem(at: arquivoDados, to: destino)
        } catch {
            return
        }
        let antigos = ((try? arquivos.contentsOfDirectory(at: pastaBackups, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("dados-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(Self.backupsGuardados)
        for antigo in antigos {
            try? arquivos.removeItem(at: antigo)
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
