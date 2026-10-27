import Foundation

public enum DocxError: LocalizedError {
    case arquivoInvalido(String)
    case falhaAoCompactar(String)

    public var errorDescription: String? {
        switch self {
        case .arquivoInvalido(let nome):
            return "Não foi possível ler “\(nome)”. Verifique se é um documento do Word sem senha de proteção e se ele abre normalmente no Word."
        case .falhaAoCompactar(let detalhe):
            return "Não foi possível gerar o documento. \(detalhe)"
        }
    }
}

/// Lê campos e preenche modelos `.docx` (um .docx é um arquivo ZIP com XML dentro).
public enum DocxTemplate {
    /// Campos `{{CAMPO}}` do documento, do cabeçalho, do rodapé e das notas.
    public static func placeholders(in docx: URL) throws -> [String] {
        try withExtracted(docx) { dir in
            var seen = Set<String>()
            var result: [String] = []
            for part in try xmlParts(in: dir) {
                let xml = try String(contentsOf: part, encoding: .utf8)
                for name in TemplateXML.placeholders(in: xml) where seen.insert(name).inserted {
                    result.append(name)
                }
            }
            return result
        }
    }

    /// Gera `output` a partir de `template`, trocando cada `{{CAMPO}}` pelo valor correspondente.
    /// Com `twoPagesPerSheet`, liga no documento a opção do Word "2 páginas por folha"
    /// (Layout › Margens › Várias páginas), e o Word passa a imprimir duas páginas em cada folha.
    public static func fill(template: URL, values: [String: String], output: URL, twoPagesPerSheet: Bool = false) throws {
        try withExtracted(template) { dir in
            for part in try xmlParts(in: dir) {
                let xml = try String(contentsOf: part, encoding: .utf8)
                let filled = TemplateXML.fill(xml, values: values)
                if filled != xml {
                    try filled.write(to: part, atomically: true, encoding: .utf8)
                }
            }
            let settings = dir.appendingPathComponent("word/settings.xml")
            if twoPagesPerSheet, let xml = try? String(contentsOf: settings, encoding: .utf8) {
                try SettingsXML.withTwoPagesPerSheet(xml).write(to: settings, atomically: true, encoding: .utf8)
            }
            let temporary = dir.deletingLastPathComponent().appendingPathComponent("saida.docx")
            try Zip.compress(directory: dir, to: temporary)

            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: output.path) {
                try fileManager.removeItem(at: output)
            }
            try fileManager.copyItem(at: temporary, to: output)
        }
    }

    /// Converte .doc, .rtf, .odt e similares para .docx com o `textutil` do macOS.
    public static func convertToDocx(_ source: URL, output: URL) throws {
        do {
            try Zip.run("/usr/bin/textutil", ["-convert", "docx", "-output", output.path, source.path])
        } catch {
            throw DocxError.arquivoInvalido(source.lastPathComponent)
        }
    }

    private static func withExtracted<T>(_ docx: URL, _ body: (URL) throws -> T) throws -> T {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("docx-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("conteudo")
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        do {
            try Zip.extract(docx, to: dir)
        } catch {
            throw DocxError.arquivoInvalido(docx.lastPathComponent)
        }
        guard fileManager.fileExists(atPath: dir.appendingPathComponent("word/document.xml").path) else {
            throw DocxError.arquivoInvalido(docx.lastPathComponent)
        }
        return try body(dir)
    }

    private static func xmlParts(in dir: URL) throws -> [URL] {
        let word = dir.appendingPathComponent("word")
        let names = try FileManager.default.contentsOfDirectory(atPath: word.path)
        let extras = names.filter { name in
            name.hasSuffix(".xml") && (
                name.hasPrefix("header") || name.hasPrefix("footer")
                    || name == "footnotes.xml" || name == "endnotes.xml"
            )
        }
        return (["document.xml"] + extras.sorted()).map { word.appendingPathComponent($0) }
    }
}
