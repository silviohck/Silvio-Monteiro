import Foundation

/// Lacunas `___` que ficaram sem preencher num texto de prontuário (vindas dos modelos de atendimento).
/// Ao gerar o documento, saem do texto sem deixar frase quebrada:
/// - trecho curto que era só um campo vazio ("DERRAME ___", "TRAUMA: ___", "RETORNO EM ___") sai inteiro;
/// - em trecho maior, sai a lacuna e a palavra que a liga ("DOR NO JOELHO HÁ ___" → "DOR NO JOELHO").
/// Quebras de linha (`\n`) são mantidas, para o texto continuar nas mesmas linhas da ficha.
public enum Lacunas {
    /// Trechos com até este número de palavras (fora a lacuna) são campos e saem inteiros.
    static let palavrasDeUmCampo = 4

    public static func remover(_ texto: String) -> String {
        guard texto.contains("___") else { return texto }
        var resultado = ""
        var trecho = ""
        var parenteses = 0
        for caractere in texto {
            if caractere == "(" { parenteses += 1 }
            if caractere == ")" { parenteses = max(0, parenteses - 1) }
            // Dentro de parênteses não separa: "(FORTALECIMENTO DE QUADRÍCEPS, ALONGAMENTO)" fica junto.
            if parenteses == 0 && (caractere == "." || caractere == ";" || caractere == ",") {
                resultado += limpar(trecho, separador: String(caractere))
                trecho = ""
            } else {
                trecho.append(caractere)
            }
        }
        resultado += limpar(trecho, separador: "")
        return arrumar(resultado)
    }

    /// Títulos de seção do prontuário: ficam mesmo quando o que vem depois deles some.
    private static let titulo = try! NSRegularExpression(
        pattern: #"^\s*(EXAMES? F[IÍ]SICOS?|EXAMES COMPLEMENTARES|DIAGN[OÓ]STICO|CONDUTA|PROGRAMA[CÇ][AÃ]O TERAP[EÊ]UTICA|HIST[OÓ]RIA|ANAMNESE)\s*:"#
    )

    private static func limpar(_ trecho: String, separador: String) -> String {
        guard trecho.contains("___") else { return trecho + separador }
        let ns = trecho as NSString
        if let achado = titulo.firstMatch(in: trecho, range: NSRange(location: 0, length: ns.length)) {
            let prefixo = ns.substring(to: NSMaxRange(achado.range))
            let resto = limpar(ns.substring(from: NSMaxRange(achado.range)), separador: separador)
            return prefixo + resto
        }
        let quebras = String(repeating: "\n", count: trecho.filter { $0 == "\n" }.count)
        let palavras = trecho
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .filter { !$0.contains("___") && $0.contains(where: { $0.isLetter || $0.isNumber }) }
        if palavras.count <= palavrasDeUmCampo { return quebras }
        var limpo = trecho.replacingOccurrences(
            of: #"(?<![\p{L}\p{N}])(HÁ|EM|DE|DO|DA|DOS|DAS|POR|COM|A|AO|À|E|OU)\s+_{3,}[^\s,.;)]*"#,
            with: "", options: .regularExpression
        )
        limpo = limpo.replacingOccurrences(of: #"_{3,}[^\s,.;)]*"#, with: "", options: .regularExpression)
        return limpo + separador
    }

    /// Espaços repetidos, espaço antes de pontuação, pontuação repetida e pontuação no começo da linha.
    private static func arrumar(_ texto: String) -> String {
        texto.components(separatedBy: "\n").map { linha in
            var s = linha
            s = s.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            s = s.replacingOccurrences(of: #"\s+([.,;:)])"#, with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: #"\(\s*\)"#, with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: #"([.,;:])(\s*[.,;])+"#, with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: #"^[\s.,;]+"#, with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            return s.trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }
}
