import Foundation

/// Capítulo (CID-10) ou grupo (SIGTAP), usado no filtro.
struct GrupoDaTabela: Identifiable, Hashable {
    let numero: Int
    let nome: String
    var id: Int { numero }
}

struct CodigoDaTabela: Identifiable, Hashable {
    /// Código como é escrito nos documentos: "M54.5", "03.01.01.007-2", "10101012".
    let codigo: String
    let descricao: String
    let grupo: Int
    /// Linha de título (categoria do CID, subgrupo do SIGTAP), mostrada em negrito.
    let ehTitulo: Bool
    /// Código + descrição sem acentos e em minúsculas, para a busca.
    let textoDeBusca: String
    /// Código só com letras e números ("m545", "0301010072"), para achar pelo começo do código.
    let codigoSimples: String
    var id: String { codigo }
    /// "M54.5 - Dor lombar baixa"
    var textoCompleto: String { "\(codigo) - \(descricao)" }

    init(codigo: String, descricao: String, grupo: Int, ehTitulo: Bool) {
        self.codigo = codigo
        self.descricao = descricao
        self.grupo = grupo
        self.ehTitulo = ehTitulo
        codigoSimples = TabelaDeCodigos.simplificar(codigo)
        textoDeBusca = TabelaDeCodigos.normalizar("\(codigo) \(codigoSimples) \(descricao)")
    }
}

/// Tabela de códigos embutida no app (funciona sem internet): CID-10, SIGTAP ou TUSS.
struct TabelaDeCodigos {
    let nome: String
    /// Texto curto sobre a origem e a versão dos dados.
    let fonte: String
    /// "capítulo", "grupo"…; vazio quando a tabela não tem filtro.
    let nomeDoGrupo: String
    let grupos: [GrupoDaTabela]
    let codigos: [CodigoDaTabela]
    let exemploDeBusca: String

    static func normalizar(_ texto: String) -> String {
        texto.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
    }

    static func simplificar(_ codigo: String) -> String {
        String(normalizar(codigo).filter { $0.isLetter || $0.isNumber })
    }

    /// Todas as palavras digitadas precisam aparecer (no código ou na descrição), em qualquer ordem.
    /// Códigos que começam com o que foi digitado vêm primeiro.
    func buscar(_ texto: String, grupo: Int?) -> [CodigoDaTabela] {
        let termos = Self.normalizar(texto).split(whereSeparator: \.isWhitespace).map(String.init)
        let filtrados = codigos.filter { codigo in
            (grupo == nil || codigo.grupo == grupo)
                && termos.allSatisfy { codigo.textoDeBusca.contains($0) }
        }
        guard termos.count == 1, let primeiro = termos.first else { return filtrados }
        let simples = Self.simplificar(primeiro)
        guard !simples.isEmpty else { return filtrados }
        let porCodigo = filtrados.filter { $0.codigoSimples.hasPrefix(simples) }
        guard !porCodigo.isEmpty else { return filtrados }
        let ids = Set(porCodigo.map(\.id))
        return porCodigo + filtrados.filter { !ids.contains($0.id) }
    }

    /// Linhas "a|b|c" de um texto embutido.
    fileprivate static func linhas(_ texto: String, partes: Int) -> [[String]] {
        texto.split(separator: "\n").compactMap { linha in
            let campos = linha.split(separator: "|", maxSplits: partes - 1, omittingEmptySubsequences: false).map(String.init)
            return campos.count == partes ? campos : nil
        }
    }
}

extension TabelaDeCodigos {
    /// CID-10 do DATASUS: capítulos, categorias (em negrito) e subcategorias.
    static let cid10: TabelaDeCodigos = {
        let capitulos = linhas(CID10Dados.capitulos, partes: 3)
        let grupos = capitulos.enumerated().map { GrupoDaTabela(numero: $0.offset + 1, nome: $0.element[2]) }
        let codigos = linhas(CID10Dados.codigos, partes: 2).map { campos -> CodigoDaTabela in
            let codigo = campos[0]
            let categoria = String(codigo.prefix(3))
            let capitulo = capitulos.firstIndex { $0[0] <= categoria && categoria <= $0[1] }.map { $0 + 1 } ?? 0
            return CodigoDaTabela(codigo: codigo, descricao: campos[1], grupo: capitulo, ehTitulo: !codigo.contains("."))
        }
        return TabelaDeCodigos(
            nome: "CID-10",
            fonte: "Tabela CID-10 do DATASUS",
            nomeDoGrupo: "capítulo",
            grupos: grupos,
            codigos: codigos,
            exemploDeBusca: "M54.5, lombalgia, dor lombar"
        )
    }()

    /// SIGTAP (Tabela de Procedimentos do SUS): subgrupos (em negrito) e procedimentos, filtrados por grupo.
    static let sigtap: TabelaDeCodigos = {
        let grupos = linhas(SIGTAPDados.grupos, partes: 2).compactMap { campos in
            Int(campos[0]).map { GrupoDaTabela(numero: $0, nome: "\(campos[0]) - \(campos[1])") }
        }
        var codigos: [CodigoDaTabela] = []
        let subgrupos = Dictionary(
            linhas(SIGTAPDados.subgrupos, partes: 2).map { ($0[0], $0[1]) },
            uniquingKeysWith: { primeiro, _ in primeiro }
        )
        var subgrupoAtual = ""
        for campos in linhas(SIGTAPDados.procedimentos, partes: 2) {
            let numero = campos[0]
            guard numero.count == 10 else { continue }
            let grupo = Int(numero.prefix(2)) ?? 0
            let subgrupo = String(numero.prefix(4))
            if subgrupo != subgrupoAtual {
                subgrupoAtual = subgrupo
                if let nome = subgrupos[subgrupo] {
                    codigos.append(CodigoDaTabela(codigo: formatarSIGTAP(subgrupo), descricao: nome, grupo: grupo, ehTitulo: true))
                }
            }
            codigos.append(CodigoDaTabela(codigo: formatarSIGTAP(numero), descricao: campos[1], grupo: grupo, ehTitulo: false))
        }
        return TabelaDeCodigos(
            nome: "SIGTAP",
            fonte: SIGTAPDados.competencia.isEmpty
                ? "Tabela de Procedimentos do SUS (DATASUS)"
                : "Tabela de Procedimentos do SUS (DATASUS), competência \(SIGTAPDados.competencia)",
            nomeDoGrupo: "grupo",
            grupos: grupos,
            codigos: codigos,
            exemploDeBusca: "03.01.01.007-2, consulta, artroplastia joelho"
        )
    }()

    /// TUSS (ANS), tabela 22: procedimentos e eventos em saúde.
    static let tuss: TabelaDeCodigos = {
        let codigos = linhas(TUSSDados.procedimentos, partes: 2).map {
            CodigoDaTabela(codigo: $0[0], descricao: $0[1], grupo: 0, ehTitulo: false)
        }
        return TabelaDeCodigos(
            nome: "TUSS",
            fonte: TUSSDados.versao.isEmpty
                ? "TUSS da ANS, tabela 22 (procedimentos e eventos em saúde)"
                : "TUSS da ANS, tabela 22 (procedimentos e eventos em saúde), \(TUSSDados.versao)",
            nomeDoGrupo: "",
            grupos: [],
            codigos: codigos,
            exemploDeBusca: "10101012, consulta, ressonância joelho"
        )
    }()

    /// "0301010072" → "03.01.01.007-2"; "0301" → "03.01".
    static func formatarSIGTAP(_ numero: String) -> String {
        let n = Array(numero)
        guard n.count == 10 else {
            return stride(from: 0, to: n.count, by: 2).map { String(n[$0..<min($0 + 2, n.count)]) }.joined(separator: ".")
        }
        return "\(String(n[0..<2])).\(String(n[2..<4])).\(String(n[4..<6])).\(String(n[6..<9]))-\(n[9])"
    }
}
