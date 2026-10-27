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
enum LeituraDaPasta {
    static let extensoes: Set<String> = ["docx", "doc", "rtf", "odt"]
    private static let profundidadeMaxima = 4

    static func ler(raiz: URL, ignorar: Set<String>) -> [ArquivoDaPasta] {
        var resultado = documentos(em: raiz).map { arquivo($0, raiz: raiz, local: nil, tipo: nil, prefixo: "") }
        for pastaDoLocal in subpastas(de: raiz) where !ignorar.contains(pastaDoLocal.lastPathComponent) {
            let local = pastaDoLocal.lastPathComponent
            resultado += documentos(em: pastaDoLocal).map { arquivo($0, raiz: raiz, local: local, tipo: nil, prefixo: "") }
            for pastaDoTipo in subpastas(de: pastaDoLocal) {
                resultado += arquivos(em: pastaDoTipo, raiz: raiz, local: local, tipo: pastaDoTipo.lastPathComponent, prefixo: "", nivel: 1)
            }
        }
        return resultado
    }

    /// Nomes das subpastas principais (candidatas a local de atendimento).
    static func subpastasPrincipais(_ raiz: URL) -> [String] {
        subpastas(de: raiz).map(\.lastPathComponent)
    }

    private static func arquivos(em pasta: URL, raiz: URL, local: String, tipo: String, prefixo: String, nivel: Int) -> [ArquivoDaPasta] {
        var resultado = documentos(em: pasta).map { arquivo($0, raiz: raiz, local: local, tipo: tipo, prefixo: prefixo) }
        guard nivel < profundidadeMaxima else { return resultado }
        for subpasta in subpastas(de: pasta) {
            resultado += arquivos(
                em: subpasta, raiz: raiz, local: local, tipo: tipo,
                prefixo: prefixo + subpasta.lastPathComponent + " / ", nivel: nivel + 1
            )
        }
        return resultado
    }

    private static func arquivo(_ url: URL, raiz: URL, local: String?, tipo: String?, prefixo: String) -> ArquivoDaPasta {
        let modificado = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        let caminho = String(url.standardizedFileURL.path.dropFirst(raiz.standardizedFileURL.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return ArquivoDaPasta(url: url, caminho: caminho, nome: prefixo + nomeLimpo(url), local: local, tipo: tipo, modificadoEm: modificado)
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
                        categoria: tipo(para: arquivo, local: local),
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
