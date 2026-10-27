import Foundation

struct CapituloCID: Identifiable, Hashable {
    let numero: Int
    let inicio: String
    let fim: String
    let nome: String
    var id: Int { numero }
}

struct CodigoCID: Identifiable, Hashable {
    /// "M54" (categoria) ou "M54.5" (subcategoria).
    let codigo: String
    let descricao: String
    let capitulo: Int
    /// Código + descrição sem acentos e em minúsculas, para a busca.
    let textoDeBusca: String
    var id: String { codigo }
    var ehCategoria: Bool { !codigo.contains(".") }
    /// "M54.5 - Dor lombar baixa"
    var textoCompleto: String { "\(codigo) - \(descricao)" }
}

/// Tabela CID-10 do DATASUS embutida no app (funciona sem internet).
enum CID10 {
    static let capitulos: [CapituloCID] = CID10Dados.capitulos
        .split(separator: "\n")
        .enumerated()
        .compactMap { indice, linha in
            let partes = linha.split(separator: "|", maxSplits: 2).map(String.init)
            guard partes.count == 3 else { return nil }
            return CapituloCID(numero: indice + 1, inicio: partes[0], fim: partes[1], nome: partes[2])
        }

    static let codigos: [CodigoCID] = CID10Dados.codigos
        .split(separator: "\n")
        .compactMap { linha in
            let partes = linha.split(separator: "|", maxSplits: 1).map(String.init)
            guard partes.count == 2 else { return nil }
            let codigo = partes[0]
            let categoria = String(codigo.prefix(3))
            let capitulo = capitulos.first { $0.inicio <= categoria && categoria <= $0.fim }?.numero ?? 0
            let semPonto = codigo.replacingOccurrences(of: ".", with: "")
            return CodigoCID(
                codigo: codigo,
                descricao: partes[1],
                capitulo: capitulo,
                textoDeBusca: normalizar("\(codigo) \(semPonto) \(partes[1])")
            )
        }

    static func normalizar(_ texto: String) -> String {
        texto.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
    }

    /// Todas as palavras digitadas precisam aparecer (no código ou na descrição), em qualquer ordem.
    /// Códigos que começam com o que foi digitado vêm primeiro.
    static func buscar(_ texto: String, capitulo: Int?) -> [CodigoCID] {
        let termos = normalizar(texto).split(whereSeparator: \.isWhitespace).map(String.init)
        let filtrados = codigos.filter { codigo in
            (capitulo == nil || codigo.capitulo == capitulo)
                && termos.allSatisfy { codigo.textoDeBusca.contains($0) }
        }
        guard let primeiro = termos.first, termos.count == 1 else { return filtrados }
        let porCodigo = filtrados.filter {
            normalizar($0.codigo).hasPrefix(primeiro) || normalizar($0.codigo.replacingOccurrences(of: ".", with: "")).hasPrefix(primeiro)
        }
        guard !porCodigo.isEmpty else { return filtrados }
        let ids = Set(porCodigo.map(\.id))
        return porCodigo + filtrados.filter { !ids.contains($0.id) }
    }
}
