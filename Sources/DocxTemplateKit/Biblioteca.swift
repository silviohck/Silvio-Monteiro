import Foundation

/// Um modelo .docx encontrado na pasta de modelos (ou importado no app).
public struct ModeloDaPasta: Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let nome: String
    /// Subpasta onde o modelo está (LAUDO MÉDICO, RX…); também é a subpasta dos documentos gerados.
    public let tipo: String

    public init(url: URL, nome: String, tipo: String) {
        self.url = url
        self.nome = nome
        self.tipo = tipo
    }
}

/// Uma pasta de primeiro nível (cidade ou local de atendimento) com os modelos dela.
public struct GrupoDeModelos: Identifiable, Hashable {
    public var id: String { nome }
    public let nome: String
    public let modelos: [ModeloDaPasta]

    public init(nome: String, modelos: [ModeloDaPasta]) {
        self.nome = nome
        self.modelos = modelos
    }

    /// "Modelos gerais" primeiro, depois as subpastas em ordem alfabética.
    public var tipos: [String] {
        let nomes = Set(modelos.map(\.tipo))
        let outros = nomes.subtracting([Biblioteca.tipoGeral]).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return (nomes.contains(Biblioteca.tipoGeral) ? [Biblioteca.tipoGeral] : []) + outros
    }

    public func modelos(do tipo: String) -> [ModeloDaPasta] {
        modelos.filter { $0.tipo == tipo }
    }
}

/// Lê a estrutura de pastas do usuário:
///
///     Pasta principal/
///     ├── OPERA PB/                  ← grupo (local ou cidade)
///     │   ├── 0 - atestado.docx      ← modelo em "Modelos gerais"
///     │   └── LAUDO MÉDICO/          ← tipo
///     │       └── laudo coluna.docx
///     └── ARARUNA/ …
public enum Biblioteca {
    public static let tipoGeral = "Modelos gerais"
    private static let profundidadeMaxima = 5

    public static func ler(raiz: URL) -> [GrupoDeModelos] {
        var grupos: [GrupoDeModelos] = []
        let soltos = modelos(em: raiz, tipo: tipoGeral, prefixo: "", nivel: 99)
        if !soltos.isEmpty {
            grupos.append(GrupoDeModelos(nome: raiz.lastPathComponent, modelos: soltos))
        }
        for pasta in subpastas(de: raiz) {
            let encontrados = modelos(em: pasta, tipo: nil, prefixo: "", nivel: 1)
            if !encontrados.isEmpty {
                grupos.append(GrupoDeModelos(nome: pasta.lastPathComponent, modelos: encontrados))
            }
        }
        return grupos
    }

    /// `tipo == nil` indica a pasta do grupo: cada subpasta dela vira um tipo.
    private static func modelos(em pasta: URL, tipo: String?, prefixo: String, nivel: Int) -> [ModeloDaPasta] {
        var resultado = arquivosDocx(em: pasta).map {
            ModeloDaPasta(url: $0, nome: prefixo + nomeDeExibicao($0), tipo: tipo ?? tipoGeral)
        }
        guard nivel < profundidadeMaxima else { return resultado }
        for subpasta in subpastas(de: pasta) {
            let nomeSubpasta = subpasta.lastPathComponent
            if let tipo {
                resultado += modelos(em: subpasta, tipo: tipo, prefixo: prefixo + nomeSubpasta + " / ", nivel: nivel + 1)
            } else {
                resultado += modelos(em: subpasta, tipo: nomeSubpasta, prefixo: "", nivel: nivel + 1)
            }
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

    private static func arquivosDocx(em pasta: URL) -> [URL] {
        conteudo(de: pasta).filter {
            $0.pathExtension.lowercased() == "docx" && !$0.lastPathComponent.hasPrefix("~$")
        }
    }

    /// "0 - atestado medico.docx" → "atestado medico"
    public static func nomeDeExibicao(_ url: URL) -> String {
        let nome = url.deletingPathExtension().lastPathComponent
        guard let intervalo = nome.range(of: #"^\d+\s*-\s*"#, options: .regularExpression) else { return nome }
        let limpo = String(nome[intervalo.upperBound...])
        return limpo.isEmpty ? nome : limpo
    }
}
