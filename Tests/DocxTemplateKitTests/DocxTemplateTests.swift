@testable import DocxTemplateKit
import XCTest

final class DocxTemplateTests: XCTestCase {
    private var pasta: URL!

    override func setUpWithError() throws {
        pasta = FileManager.default.temporaryDirectory.appendingPathComponent("testes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: pasta)
    }

    func testPreencheDocumentoECabecalho() throws {
        let modelo = try criarDocx(
            corpo: "<w:p><w:r><w:t>Atesto que {{NOME_</w:t></w:r><w:r><w:t>PACIENTE}} esteve aqui em {{DATA}}.</w:t></w:r></w:p>",
            cabecalho: "<w:p><w:r><w:t>Clínica — {{NOME_PACIENTE}}</w:t></w:r></w:p>"
        )
        XCTAssertEqual(try DocxTemplate.placeholders(in: modelo), ["NOME_PACIENTE", "DATA"])

        let saida = pasta.appendingPathComponent("saida.docx")
        try DocxTemplate.fill(template: modelo, values: ["NOME_PACIENTE": "Ana Souza", "DATA": "27/10/2026"], output: saida)
        XCTAssertEqual(try DocxTemplate.placeholders(in: saida), [])

        let extraida = pasta.appendingPathComponent("extraida")
        try Zip.extract(saida, to: extraida)
        let documento = try String(contentsOf: extraida.appendingPathComponent("word/document.xml"), encoding: .utf8)
        let cabecalho = try String(contentsOf: extraida.appendingPathComponent("word/header1.xml"), encoding: .utf8)
        XCTAssertTrue(documento.contains("Atesto que Ana Souza"))
        XCTAssertTrue(documento.contains("esteve aqui em 27/10/2026."))
        XCTAssertTrue(cabecalho.contains("Clínica — Ana Souza"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extraida.appendingPathComponent("[Content_Types].xml").path))
    }

    func testSobrescreveArquivoExistente() throws {
        let modelo = try criarDocx(corpo: "<w:p><w:r><w:t>{{A}}</w:t></w:r></w:p>")
        let saida = pasta.appendingPathComponent("saida.docx")
        try Data("antigo".utf8).write(to: saida)
        try DocxTemplate.fill(template: modelo, values: ["A": "novo"], output: saida)
        XCTAssertEqual(try DocxTemplate.placeholders(in: saida), [])
    }

    func testArquivoQueNaoEDocx() throws {
        let falso = pasta.appendingPathComponent("falso.docx")
        try Data("não sou um zip".utf8).write(to: falso)
        XCTAssertThrowsError(try DocxTemplate.placeholders(in: falso)) { erro in
            guard case DocxError.arquivoInvalido = erro else { return XCTFail("erro inesperado: \(erro)") }
        }
    }

    func testConverteRtfParaDocx() throws {
        let rtf = pasta.appendingPathComponent("modelo.rtf")
        try #"{\rtf1\ansi Paciente: \{\{NOME_PACIENTE\}\} - CPF \{\{CPF\}\}\par}"#.write(to: rtf, atomically: true, encoding: .utf8)
        let docx = pasta.appendingPathComponent("convertido.docx")
        try DocxTemplate.convertToDocx(rtf, output: docx)
        XCTAssertEqual(try DocxTemplate.placeholders(in: docx), ["NOME_PACIENTE", "CPF"])
    }

    private func criarDocx(corpo: String, cabecalho: String? = nil) throws -> URL {
        let raiz = pasta.appendingPathComponent("fonte-\(UUID().uuidString)")
        let ns = #"xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main""#
        var arquivos = [
            "[Content_Types].xml": #"<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>"#,
            "word/document.xml": #"<?xml version="1.0" encoding="UTF-8"?><w:document \#(ns)><w:body>\#(corpo)</w:body></w:document>"#,
        ]
        if let cabecalho {
            arquivos["word/header1.xml"] = #"<?xml version="1.0" encoding="UTF-8"?><w:hdr \#(ns)>\#(cabecalho)</w:hdr>"#
        }
        for (caminho, conteudo) in arquivos {
            let url = raiz.appendingPathComponent(caminho)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try conteudo.write(to: url, atomically: true, encoding: .utf8)
        }
        let docx = pasta.appendingPathComponent("modelo-\(UUID().uuidString).docx")
        try Zip.compress(directory: raiz, to: docx)
        return docx
    }
}
