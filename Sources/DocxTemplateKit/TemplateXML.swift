import Foundation

/// Localiza e substitui campos `{{CAMPO}}` no XML de um documento do Word.
///
/// O Word costuma dividir um texto digitado em vários "runs" (`<w:r>`) — por causa
/// da correção ortográfica, de formatação ou do histórico de edição — então
/// `{{NOME}}` pode aparecer como `{{`, `NOME` e `}}` em elementos `<w:t>` diferentes.
/// Por isso o texto de todos os `<w:t>` é concatenado, os campos são localizados no
/// texto completo e a substituição é distribuída de volta: o valor vai para o `<w:t>`
/// onde o campo começa (herdando a formatação dele) e o restante do campo é removido.
///
/// Negrito: no valor, o texto entre `**` (ex.: `DOR **INTENSA** À NOITE`) sai em negrito no Word;
/// as marcas não aparecem no documento.
enum TemplateXML {
    /// Marca de negrito nos valores: `**trecho**`.
    static let marcaNegrito = "**"

    private static let textElement = try! NSRegularExpression(
        pattern: #"<w:t((?:\s[^>]*)?)(?<!/)>(.*?)</w:t>"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let placeholder = try! NSRegularExpression(
        pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#
    )

    private struct TextNode {
        let range: NSRange
        let attributes: String
        let text: String
    }

    /// Nomes dos campos encontrados, na ordem em que aparecem, sem repetição.
    static func placeholders(in xml: String) -> [String] {
        let combined = textNodes(in: xml).map(\.text).joined() as NSString
        var seen = Set<String>()
        var result: [String] = []
        for match in placeholder.matches(in: combined as String, range: NSRange(location: 0, length: combined.length)) {
            let name = combined.substring(with: match.range(at: 1))
            if seen.insert(name).inserted {
                result.append(name)
            }
        }
        return result
    }

    /// Substitui os campos que têm valor em `values`; campos sem valor ficam como estão.
    static func fill(_ xml: String, values: [String: String]) -> String {
        let nodes = textNodes(in: xml)
        guard !nodes.isEmpty else { return xml }

        let lengths = nodes.map { ($0.text as NSString).length }
        var starts: [Int] = []
        var offset = 0
        for length in lengths {
            starts.append(offset)
            offset += length
        }

        let combined = nodes.map(\.text).joined() as NSString
        let texts = nodes.map { NSMutableString(string: $0.text) }
        var touched = Set<Int>()

        // De trás para frente, para que as posições dos campos anteriores continuem válidas.
        let matches = placeholder.matches(in: combined as String, range: NSRange(location: 0, length: combined.length))
        for match in matches.reversed() {
            guard let value = values[combined.substring(with: match.range(at: 1))] else { continue }
            let matchStart = match.range.location
            let matchEnd = NSMaxRange(match.range)
            var isFirst = true
            for i in nodes.indices {
                let nodeStart = starts[i]
                let nodeEnd = nodeStart + lengths[i]
                if nodeEnd <= matchStart { continue }
                if nodeStart >= matchEnd { break }
                let lower = max(matchStart, nodeStart)
                let upper = min(matchEnd, nodeEnd)
                let local = NSRange(location: lower - nodeStart, length: upper - lower)
                texts[i].replaceCharacters(in: local, with: isFirst ? value : "")
                isFirst = false
                touched.insert(i)
            }
        }

        guard !touched.isEmpty else { return xml }
        let result = NSMutableString(string: xml)
        for i in touched.sorted(by: >) {
            let texto = texts[i] as String
            let novo = texto.contains(marcaNegrito)
                ? elementWithBold(attributes: nodes[i].attributes, text: texto, runProperties: runProperties(before: nodes[i].range.location, in: xml))
                : element(attributes: nodes[i].attributes, text: texto)
            result.replaceCharacters(in: nodes[i].range, with: novo)
        }
        return result as String
    }

    /// `<w:rPr>…</w:rPr>` do run (`<w:r>`) que contém o texto na posição `location` (vazio se não houver).
    static func runProperties(before location: Int, in xml: String) -> String {
        let ns = xml as NSString
        let antes = ns.substring(to: location) as NSString
        // Último início de run: "<w:r>" ou "<w:r " (não "<w:rPr" nem "<w:rFonts").
        let inicio = max(antes.range(of: "<w:r>", options: .backwards).location.notFoundAsMinusOne,
                         antes.range(of: "<w:r ", options: .backwards).location.notFoundAsMinusOne)
        guard inicio >= 0 else { return "" }
        let trecho = antes.substring(from: inicio) as NSString
        let abre = trecho.range(of: "<w:rPr>")
        let fecha = trecho.range(of: "</w:rPr>")
        guard abre.location != NSNotFound, fecha.location != NSNotFound, fecha.location > abre.location else { return "" }
        return trecho.substring(with: NSRange(location: abre.location, length: NSMaxRange(fecha) - abre.location))
    }

    /// As mesmas propriedades do run, com negrito (`<w:b/><w:bCs/>` depois de rStyle/rFonts, na ordem do Word).
    static func boldRunProperties(_ rPr: String) -> String {
        guard !rPr.isEmpty else { return "<w:rPr><w:b/><w:bCs/></w:rPr>" }
        var interno = String(rPr.dropFirst("<w:rPr>".count).dropLast("</w:rPr>".count))
        // Tira negrito já existente (ex.: <w:b w:val="0"/>) para não haver dois.
        interno = interno.replacingOccurrences(of: #"<w:b(?:Cs)?(?:\s[^>]*)?/>"#, with: "", options: .regularExpression)
        let ns = interno as NSString
        var posicao = 0
        for padrao in [#"<w:rStyle[^>]*/>"#, #"<w:rFonts[^>]*/>"#] {
            let achado = ns.range(of: padrao, options: .regularExpression)
            if achado.location != NSNotFound { posicao = max(posicao, NSMaxRange(achado)) }
        }
        let resultado = NSMutableString(string: interno)
        resultado.insert("<w:b/><w:bCs/>", at: posicao)
        return "<w:rPr>\(resultado)</w:rPr>"
    }

    /// Texto com trechos em negrito: fecha o run atual, abre um run em negrito para o trecho e reabre o
    /// run original (mesma formatação) para o resto. Marcas `**` sem par são removidas.
    private static func elementWithBold(attributes: String, text: String, runProperties rPr: String) -> String {
        let partes = text.components(separatedBy: marcaNegrito)
        var saida = ""
        for (indice, parte) in partes.enumerated() {
            let negrito = indice % 2 == 1 && indice < partes.count - (partes.count % 2 == 0 ? 1 : 0)
            if negrito {
                guard !parte.isEmpty else { continue }
                saida += "</w:r><w:r>\(boldRunProperties(rPr))\(element(attributes: attributes, text: parte))</w:r><w:r>\(rPr)"
            } else {
                saida += element(attributes: attributes, text: parte)
            }
        }
        return saida
    }

    private static func textNodes(in xml: String) -> [TextNode] {
        let ns = xml as NSString
        return textElement.matches(in: xml, range: NSRange(location: 0, length: ns.length)).map { match in
            TextNode(
                range: match.range,
                attributes: ns.substring(with: match.range(at: 1)),
                text: decodeEntities(ns.substring(with: match.range(at: 2)))
            )
        }
    }

    /// Recria o `<w:t>`; quebras de linha no valor viram `<w:br/>` dentro do mesmo run.
    private static func element(attributes: String, text: String) -> String {
        let attrs = attributes.contains("xml:space") ? attributes : attributes + #" xml:space="preserve""#
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        return lines.map { "<w:t\(attrs)>\(escape($0))</w:t>" }.joined(separator: "<w:br/>")
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var output = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "&",
               let semicolon = text[i...].firstIndex(of: ";"),
               text.distance(from: i, to: semicolon) <= 10,
               let decoded = decodeEntity(String(text[text.index(after: i)..<semicolon])) {
                output.append(decoded)
                i = text.index(after: semicolon)
            } else {
                output.append(text[i])
                i = text.index(after: i)
            }
        }
        return output
    }

    private static func decodeEntity(_ entity: String) -> Character? {
        switch entity {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        default: break
        }
        var code: UInt32?
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            code = UInt32(entity.dropFirst(2), radix: 16)
        } else if entity.hasPrefix("#") {
            code = UInt32(entity.dropFirst())
        }
        guard let code, let scalar = Unicode.Scalar(code) else { return nil }
        return Character(scalar)
    }
}

private extension Int {
    /// `NSNotFound` vira -1, para comparar posições com `max`.
    var notFoundAsMinusOne: Int { self == NSNotFound ? -1 : self }
}
