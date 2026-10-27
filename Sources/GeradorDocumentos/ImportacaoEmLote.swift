import Foundation

/// Um arquivo encontrado na pasta escolhida para importação.
struct ArquivoParaImportar: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let nome: String
    /// Subpasta de onde veio (vira o tipo); nil = arquivo solto, tipo adivinhado pelo nome.
    let pasta: String?
}

/// Um local de atendimento (ou "Todos os locais") com os arquivos que serão importados para ele.
struct LocalParaImportar: Identifiable {
    let id = UUID()
    var nome: String
    /// Arquivos soltos na pasta principal: valem para todos os locais.
    var todosOsLocais = false
    var arquivos: [ArquivoParaImportar]
    var incluir = true

    /// "RX (3), LAUDO MÉDICO (2), soltos (4)"
    var resumo: String {
        var contagem: [(String, Int)] = []
        for arquivo in arquivos {
            let chave = arquivo.pasta ?? "arquivos soltos"
            if let i = contagem.firstIndex(where: { $0.0 == chave }) {
                contagem[i].1 += 1
            } else {
                contagem.append((chave, 1))
            }
        }
        return contagem.map { "\($0.0) (\($0.1))" }.joined(separator: ", ")
    }
}

struct ResultadoImportacao {
    var importados = 0
    var repetidos = 0
    var locaisCriados = 0
    var tiposCriados = 0
    var erros: [String] = []
}

/// Lê pastas no formato do usuário: Pasta principal → LOCAL → (arquivos soltos | TIPO → arquivos).
enum ImportacaoEmLote {
    static let extensoes: Set<String> = ["docx", "doc", "rtf", "odt"]
    private static let profundidadeMaxima = 4

    /// Cada subpasta é um local; arquivos soltos na pasta principal valem para todos os locais.
    static func lerPastaPrincipal(_ raiz: URL) -> [LocalParaImportar] {
        var locais: [LocalParaImportar] = []
        let soltos = documentos(em: raiz).map { ArquivoParaImportar(url: $0, nome: nomeLimpo($0), pasta: nil) }
        if !soltos.isEmpty {
            locais.append(LocalParaImportar(nome: "Todos os locais", todosOsLocais: true, arquivos: soltos))
        }
        for pasta in subpastas(de: raiz) {
            let arquivos = arquivos(emPastaDeLocal: pasta)
            if !arquivos.isEmpty {
                locais.append(LocalParaImportar(nome: pasta.lastPathComponent, arquivos: arquivos))
            }
        }
        return locais
    }

    /// A pasta escolhida é de um local só.
    static func lerPastaDeLocal(_ pasta: URL) -> [LocalParaImportar] {
        let arquivos = arquivos(emPastaDeLocal: pasta)
        return arquivos.isEmpty ? [] : [LocalParaImportar(nome: pasta.lastPathComponent, arquivos: arquivos)]
    }

    /// Se a pasta tem documentos soltos, provavelmente é a pasta de um local; senão, a principal.
    static func pareceSerPastaDeLocal(_ pasta: URL) -> Bool {
        !documentos(em: pasta).isEmpty
    }

    /// Arquivos soltos (tipo adivinhado) + cada subpasta como um tipo (subpastas internas entram no nome).
    private static func arquivos(emPastaDeLocal pasta: URL) -> [ArquivoParaImportar] {
        var resultado = documentos(em: pasta).map { ArquivoParaImportar(url: $0, nome: nomeLimpo($0), pasta: nil) }
        for subpasta in subpastas(de: pasta) {
            resultado += arquivos(em: subpasta, tipo: subpasta.lastPathComponent, prefixo: "", nivel: 1)
        }
        return resultado
    }

    private static func arquivos(em pasta: URL, tipo: String, prefixo: String, nivel: Int) -> [ArquivoParaImportar] {
        var resultado = documentos(em: pasta).map {
            ArquivoParaImportar(url: $0, nome: prefixo + nomeLimpo($0), pasta: tipo)
        }
        guard nivel < profundidadeMaxima else { return resultado }
        for subpasta in subpastas(de: pasta) {
            resultado += arquivos(em: subpasta, tipo: tipo, prefixo: prefixo + subpasta.lastPathComponent + " / ", nivel: nivel + 1)
        }
        return resultado
    }

    private static func conteudo(de pasta: URL) -> [URL] {
        let itens = (try? FileManager.default.contentsOfDirectory(
            at: pasta,
            includingPropertiesForKeys: [.isDirectoryKey, .isAliasFileKey],
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
    /// Importa os arquivos marcados: cria locais e tipos que faltarem, pula modelos já importados
    /// (mesmo nome, local e tipo) e copia os arquivos em segundo plano.
    func importarEmLote(_ locais: [LocalParaImportar], progresso: @escaping (Int) -> Void) async -> ResultadoImportacao {
        var resultado = ResultadoImportacao()
        var pendentes: [(arquivo: ArquivoParaImportar, localID: UUID?, tipo: String)] = []

        for grupo in locais where grupo.incluir {
            var localID: UUID?
            if !grupo.todosOsLocais {
                if let existente = local(chamado: grupo.nome) {
                    localID = existente.id
                } else {
                    var novo = novoLocal()
                    novo.nome = grupo.nome
                    atualizarLocal(novo)
                    localID = novo.id
                    resultado.locaisCriados += 1
                }
            }
            for arquivo in grupo.arquivos {
                let tipo = tipo(para: arquivo, resultado: &resultado)
                let repetido = dados.modelos.contains {
                    $0.localID == localID && $0.categoria == tipo
                        && $0.nome.compare(arquivo.nome, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                } || pendentes.contains {
                    $0.localID == localID && $0.tipo == tipo && $0.arquivo.nome == arquivo.nome
                }
                if repetido {
                    resultado.repetidos += 1
                } else {
                    pendentes.append((arquivo, localID, tipo))
                }
            }
        }

        var novos: [ModeloDocumento] = []
        for (indice, item) in pendentes.enumerated() {
            let nomeArquivo = "\(UUID().uuidString).docx"
            let destino = pastaModelos.appendingPathComponent(nomeArquivo)
            let origem = item.arquivo.url
            do {
                let campos = try await Task.detached(priority: .userInitiated) {
                    try Armazenamento.copiarModelo(origem, para: destino)
                }.value
                novos.append(ModeloDocumento(
                    nome: item.arquivo.nome,
                    arquivo: nomeArquivo,
                    campos: campos,
                    categoria: item.tipo,
                    localID: item.localID
                ))
            } catch {
                resultado.erros.append("\(origem.lastPathComponent): \(error.localizedDescription)")
            }
            progresso(indice + 1)
        }
        dados.modelos.append(contentsOf: novos)
        resultado.importados = novos.count
        return resultado
    }

    /// Quantos arquivos serão realmente copiados (para a barra de progresso).
    func quantidadeParaImportar(_ locais: [LocalParaImportar]) -> Int {
        locais.filter(\.incluir).reduce(0) { $0 + $1.arquivos.count }
    }

    func local(chamado nome: String) -> LocalAtendimento? {
        dados.locais.first {
            $0.nome.trimmingCharacters(in: .whitespaces)
                .compare(nome.trimmingCharacters(in: .whitespaces), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    /// Subpasta → tipo já existente com o mesmo nome (RECEITA → Receitas) ou um tipo novo com o nome da pasta.
    /// Arquivo solto → tipo adivinhado pelo nome do arquivo.
    private func tipo(para arquivo: ArquivoParaImportar, resultado: inout ResultadoImportacao) -> String {
        guard let pasta = arquivo.pasta else {
            return ModeloDocumento.categoriaSugerida(para: arquivo.nome, entre: dados.categorias)
        }
        if let existente = tipoParecido(com: pasta) {
            return existente
        }
        adicionarCategoria(pasta)
        resultado.tiposCriados += 1
        return pasta
    }

    /// Mesmo nome sem diferenciar maiúsculas, acentos e plural ("RECEITA" = "Receitas").
    private func tipoParecido(com pasta: String) -> String? {
        func simples(_ texto: String) -> String {
            var texto = texto.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespaces)
            if texto.hasSuffix("s") { texto.removeLast() }
            return texto
        }
        let alvo = simples(pasta)
        return dados.categorias.first { simples($0) == alvo }
    }
}
