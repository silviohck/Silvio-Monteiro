import Foundation

/// Um documento encontrado na pasta sincronizada.
struct ArquivoDaPasta {
    let url: URL
    /// Caminho dentro da pasta sincronizada, usado para reconhecer o mesmo arquivo depois.
    let caminho: String
    let nome: String
    /// Subpasta principal (o local); nil = arquivo solto, vale para todos os locais.
    let local: String?
    /// Subpasta dentro do local (o tipo); nil = tipo adivinhado pelo nome do arquivo.
    let tipo: String?
    /// Pastas dentro do tipo até o arquivo (ex.: ["Joelho"] em RX/Joelho/arquivo.docx).
    let subpastas: [String]
    let modificadoEm: Date
}

/// Situação da sincronização, mostrada na aba Modelos.
struct EstadoSincronizacao {
    var emAndamento = false
    var feitos = 0
    var total = 0
    var ultima: Date?
    var novos = 0
    var atualizados = 0
    var removidos = 0
    var erros: [String] = []
}

/// Lê a pasta no formato: Pasta → LOCAL → (arquivos soltos | TIPO → arquivos [→ subpastas]).
/// Dentro da pasta de um local, atalhos (alias) do Finder para outras pastas são seguidos:
/// o atalho "1 - APAC" dentro de ALAGOA GRANDE vira o tipo "1 - APAC" desse local, com as subpastas dele.
enum LeituraDaPasta {
    static let extensoes: Set<String> = ["docx", "doc", "rtf", "odt"]
    private static let profundidadeMaxima = 4

    static func ler(raiz: URL, ignorar: Set<String>) -> [ArquivoDaPasta] {
        var resultado = documentos(em: raiz).map { arquivo($0, raiz: raiz, local: nil, tipo: nil, subpastas: []) }
        for pastaDoLocal in subpastas(de: raiz) where !ignorar.contains(pastaDoLocal.lastPathComponent) {
            let local = pastaDoLocal.lastPathComponent
            resultado += documentos(em: pastaDoLocal).map { arquivo($0, raiz: raiz, local: local, tipo: nil, subpastas: []) }
            for pastaDoTipo in pastasEAtalhos(de: pastaDoLocal) {
                resultado += arquivos(
                    em: pastaDoLocal.appendingPathComponent(pastaDoTipo.nome), real: pastaDoTipo.real,
                    raiz: raiz, local: local, tipo: pastaDoTipo.nome, caminho: [], nivel: 1
                )
            }
        }
        return resultado
    }

    /// Nomes das subpastas principais (candidatas a local de atendimento).
    static func subpastasPrincipais(_ raiz: URL) -> [String] {
        subpastas(de: raiz).map(\.lastPathComponent)
    }

    /// `pasta`: caminho como aparece dentro da pasta sincronizada (passando pelos atalhos);
    /// `real`: a pasta de verdade, para ler os arquivos. `caminho`: pastas entre a pasta do tipo e `pasta`.
    private static func arquivos(
        em pasta: URL, real: URL, raiz: URL, local: String, tipo: String, caminho: [String], nivel: Int
    ) -> [ArquivoDaPasta] {
        var resultado = documentos(em: real).map {
            arquivo($0, caminhoNaPasta: pasta.appendingPathComponent($0.lastPathComponent), raiz: raiz, local: local, tipo: tipo, subpastas: caminho)
        }
        guard nivel < profundidadeMaxima else { return resultado }
        for subpasta in pastasEAtalhos(de: real) {
            resultado += arquivos(
                em: pasta.appendingPathComponent(subpasta.nome), real: subpasta.real, raiz: raiz, local: local, tipo: tipo,
                caminho: caminho + [subpasta.nome], nivel: nivel + 1
            )
        }
        return resultado
    }

    private static func arquivo(
        _ url: URL, caminhoNaPasta: URL? = nil, raiz: URL, local: String?, tipo: String?, subpastas: [String]
    ) -> ArquivoDaPasta {
        let modificado = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        let caminho = String((caminhoNaPasta ?? url).standardizedFileURL.path.dropFirst(raiz.standardizedFileURL.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return ArquivoDaPasta(url: url, caminho: caminho, nome: nomeLimpo(url), local: local, tipo: tipo, subpastas: subpastas, modificadoEm: modificado)
    }

    /// Subpastas e atalhos para pastas: nome que aparece no Finder e a pasta de verdade.
    private static func pastasEAtalhos(de pasta: URL) -> [(nome: String, real: URL)] {
        conteudo(de: pasta).compactMap { url in
            let valores = try? url.resourceValues(forKeys: [.isDirectoryKey, .isAliasFileKey, .isSymbolicLinkKey])
            if valores?.isAliasFile == true || valores?.isSymbolicLink == true {
                guard let destino = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]),
                      (try? destino.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                else { return nil }
                return (url.lastPathComponent, destino)
            }
            return valores?.isDirectory == true ? (url.lastPathComponent, url) : nil
        }
    }

    private static func conteudo(de pasta: URL) -> [URL] {
        let itens = (try? FileManager.default.contentsOfDirectory(
            at: pasta,
            includingPropertiesForKeys: [.isDirectoryKey, .isAliasFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return itens.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func subpastas(de pasta: URL) -> [URL] {
        conteudo(de: pasta).filter { url in
            let valores = try? url.resourceValues(forKeys: [.isDirectoryKey, .isAliasFileKey])
            return valores?.isDirectory == true && valores?.isAliasFile != true
        }
    }

    private static func documentos(em pasta: URL) -> [URL] {
        conteudo(de: pasta).filter {
            extensoes.contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.hasPrefix("~$")
        }
    }

    /// "0 - atestado medico.docx" → "atestado medico"
    static func nomeLimpo(_ url: URL) -> String {
        let nome = url.deletingPathExtension().lastPathComponent
        guard let intervalo = nome.range(of: #"^\d+\s*-\s*"#, options: .regularExpression) else { return nome }
        let limpo = String(nome[intervalo.upperBound...])
        return limpo.isEmpty ? nome : limpo
    }
}

extension Armazenamento {
    var urlPastaSincronizada: URL? {
        dados.pastaSincronizada.isEmpty ? nil : URL(fileURLWithPath: dados.pastaSincronizada, isDirectory: true)
    }

    /// Arquivo original na pasta sincronizada (para editar no Word) ou a cópia guardada pelo app.
    func urlParaEditar(_ modelo: ModeloDocumento) -> URL {
        if let origem = modelo.origem, let raiz = urlPastaSincronizada {
            let original = raiz.appendingPathComponent(origem)
            if FileManager.default.fileExists(atPath: original.path) { return original }
        }
        return urlDoModelo(modelo)
    }

    func definirPastaSincronizada(_ url: URL?) {
        dados.pastaSincronizada = url?.path ?? ""
        if url == nil {
            // Modelos que vieram da pasta continuam no app, como modelos comuns.
            for i in dados.modelos.indices where dados.modelos[i].origem != nil {
                dados.modelos[i].origem = nil
                dados.modelos[i].origemModificadaEm = nil
            }
        }
    }

    /// Deixa o app igual à pasta: adiciona arquivos novos, atualiza os alterados e remove os apagados.
    /// Modelos importados um a um não são tocados.
    func sincronizar() async {
        guard let raiz = urlPastaSincronizada, !sincronizacao.emAndamento else { return }
        guard FileManager.default.fileExists(atPath: raiz.path) else {
            sincronizacao.erros = ["A pasta sincronizada não foi encontrada: \(raiz.path)"]
            return
        }

        var estado = EstadoSincronizacao(emAndamento: true, ultima: sincronizacao.ultima)
        let arquivos = LeituraDaPasta.ler(raiz: raiz, ignorar: Set(dados.pastasIgnoradas))
        let caminhos = Set(arquivos.map(\.caminho))
        if arquivos.isEmpty && dados.modelos.contains(where: { $0.origem != nil }) {
            // Pasta vazia de repente (iCloud carregando, disco desconectado): não apaga nada.
            sincronizacao.erros = ["Nenhum documento encontrado na pasta sincronizada agora. Nada foi removido; tente “Sincronizar agora” daqui a pouco."]
            return
        }

        ajustarSubpastas(arquivos)

        let pendentes = arquivos.filter { arquivo in
            guard let existente = dados.modelos.first(where: { $0.origem == arquivo.caminho }),
                  let copiadoEm = existente.origemModificadaEm else { return true }
            return abs(copiadoEm.timeIntervalSince(arquivo.modificadoEm)) > 1
                || !FileManager.default.fileExists(atPath: urlDoModelo(existente).path)
        }
        estado.total = pendentes.count
        sincronizacao = estado

        for arquivo in pendentes {
            let nomeCopia = "\(UUID().uuidString).docx"
            let destino = pastaModelos.appendingPathComponent(nomeCopia)
            let origem = arquivo.url
            do {
                let campos = try await Task.detached(priority: .userInitiated) {
                    try Armazenamento.copiarModelo(origem, para: destino)
                }.value
                if let indice = dados.modelos.firstIndex(where: { $0.origem == arquivo.caminho }) {
                    try? FileManager.default.removeItem(at: urlDoModelo(dados.modelos[indice]))
                    dados.modelos[indice].arquivo = nomeCopia
                    dados.modelos[indice].campos = campos
                    dados.modelos[indice].origemModificadaEm = arquivo.modificadoEm
                    estado.atualizados += 1
                } else {
                    let local = localID(paraPasta: arquivo.local)
                    dados.modelos.append(ModeloDocumento(
                        nome: arquivo.nome,
                        arquivo: nomeCopia,
                        campos: campos,
                        categoria: Armazenamento.subpasta(tipo(para: arquivo, local: local), dentro: arquivo.subpastas),
                        localID: local,
                        origem: arquivo.caminho,
                        origemModificadaEm: arquivo.modificadoEm
                    ))
                    estado.novos += 1
                }
            } catch {
                estado.erros.append("\(arquivo.caminho): \(error.localizedDescription)")
            }
            estado.feitos += 1
            sincronizacao = estado
        }

        let apagados = dados.modelos.filter { modelo in
            guard let origem = modelo.origem else { return false }
            return !caminhos.contains(origem)
        }
        for modelo in apagados {
            try? FileManager.default.removeItem(at: urlDoModelo(modelo))
        }
        if !apagados.isEmpty {
            let ids = Set(apagados.map(\.id))
            dados.modelos.removeAll { ids.contains($0.id) }
        }
        estado.removidos = apagados.count
        estado.emAndamento = false
        estado.ultima = Date()
        sincronizacao = estado
    }

    /// Deixa local, subpasta e nome dos modelos sincronizados de acordo com o lugar do arquivo na pasta.
    /// Corrige modelos de versões anteriores (tipo "RX" com nome "Joelho / …", ou "todos os locais" por engano).
    private func ajustarSubpastas(_ arquivos: [ArquivoDaPasta]) {
        let separador = Armazenamento.separadorDeSubpastas
        for arquivo in arquivos {
            guard let indice = dados.modelos.firstIndex(where: { $0.origem == arquivo.caminho }) else { continue }
            let modelo = dados.modelos[indice]
            let local = localID(paraPasta: arquivo.local)
            let fimEsperado = arquivo.subpastas.isEmpty ? "" : separador + arquivo.subpastas.joined(separator: separador)
            let subpastaCerta = arquivo.tipo == nil
                || (fimEsperado.isEmpty ? !modelo.categoria.contains(separador) : modelo.categoria.hasSuffix(fimEsperado))
            if modelo.localID != local || !subpastaCerta {
                dados.modelos[indice].localID = local
                if arquivo.tipo != nil {
                    dados.modelos[indice].categoria = Armazenamento.subpasta(tipo(para: arquivo, local: local), dentro: arquivo.subpastas)
                }
            }
            if modelo.nome != arquivo.nome && modelo.nome.contains(separador) {
                dados.modelos[indice].nome = arquivo.nome
            }
        }
    }

    /// Local ligado à subpasta: o que já foi ligado antes, um com o mesmo nome, ou um novo.
    private func localID(paraPasta pasta: String?) -> UUID? {
        guard let pasta else { return nil }
        if let ligado = dados.locais.first(where: { $0.pastaSincronizada == pasta }) {
            return ligado.id
        }
        if let indice = dados.locais.firstIndex(where: {
            $0.pastaSincronizada == nil
                && $0.nome.trimmingCharacters(in: .whitespaces).compare(pasta, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            dados.locais[indice].pastaSincronizada = pasta
            return dados.locais[indice].id
        }
        var novo = LocalAtendimento(nome: pasta)
        novo.pastaSincronizada = pasta
        dados.locais.append(novo)
        return novo.id
    }

    /// Subpasta → tipo do local com o mesmo nome (sem diferenciar maiúsculas, acentos e plural)
    /// ou um tipo novo só desse local; arquivo solto → tipo adivinhado pelo nome.
    private func tipo(para arquivo: ArquivoDaPasta, local: UUID?) -> String {
        let doLocal = tipos(doLocal: local)
        guard let pasta = arquivo.tipo else {
            let tipo = ModeloDocumento.categoriaSugerida(para: arquivo.nome, entre: doLocal.isEmpty ? dados.categorias : doLocal)
            adicionarCategoria(tipo, local: local)
            return tipo
        }
        func simples(_ texto: String) -> String {
            var texto = texto.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespaces)
            if texto.hasSuffix("s") { texto.removeLast() }
            return texto
        }
        if let existente = doLocal.first(where: { simples($0) == simples(pasta) }) {
            return existente
        }
        adicionarCategoria(pasta, local: local)
        return pasta
    }
}
