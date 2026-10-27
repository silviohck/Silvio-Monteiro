@testable import DocxTemplateKit
import XCTest

final class TemplateXMLTests: XCTestCase {
    /// "{{NOME_PACIENTE}}" dividido em três runs, como o Word costuma salvar.
    private let xmlDividido = """
    <w:body><w:p><w:r><w:t xml:space="preserve">Paciente: {{</w:t></w:r><w:proofErr w:type="spellStart"/>\
    <w:r><w:rPr><w:b/></w:rPr><w:t>NOME_</w:t></w:r><w:r><w:t>PACIENTE}} - CPF {{ CPF }}</w:t></w:r></w:p></w:body>
    """

    func testEncontraCamposDivididosEntreRuns() {
        XCTAssertEqual(TemplateXML.placeholders(in: xmlDividido), ["NOME_PACIENTE", "CPF"])
    }

    func testSubstituiCampoDivididoMantendoFormatacaoDoInicio() {
        let resultado = TemplateXML.fill(xmlDividido, values: ["NOME_PACIENTE": "Maria & José", "CPF": "123"])
        XCTAssertEqual(
            resultado,
            """
            <w:body><w:p><w:r><w:t xml:space="preserve">Paciente: Maria &amp; José</w:t></w:r><w:proofErr w:type="spellStart"/>\
            <w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve"></w:t></w:r><w:r><w:t xml:space="preserve"> - CPF 123</w:t></w:r></w:p></w:body>
            """
        )
        XCTAssertEqual(TemplateXML.placeholders(in: resultado), [])
    }

    func testCampoSemValorPermanece() {
        let xml = "<w:p><w:r><w:t>{{A}} e {{B}}</w:t></w:r></w:p>"
        XCTAssertEqual(
            TemplateXML.fill(xml, values: ["B": "2"]),
            #"<w:p><w:r><w:t xml:space="preserve">{{A}} e 2</w:t></w:r></w:p>"#
        )
    }

    func testValorComVariasLinhasViraQuebraDeLinha() {
        let xml = "<w:r><w:t>{{ENDERECO}}</w:t></w:r>"
        XCTAssertEqual(
            TemplateXML.fill(xml, values: ["ENDERECO": "Rua A, 1\nCentro"]),
            #"<w:r><w:t xml:space="preserve">Rua A, 1</w:t><w:br/><w:t xml:space="preserve">Centro</w:t></w:r>"#
        )
    }

    func testIgnoraElementosParecidosComWT() {
        let xml = #"<w:tbl><w:tr><w:tc><w:p><w:r><w:tab/><w:t xml:space="preserve"/><w:t>{{X}}</w:t></w:r></w:p></w:tc></w:tr></w:tbl>"#
        XCTAssertEqual(TemplateXML.placeholders(in: xml), ["X"])
        XCTAssertEqual(
            TemplateXML.fill(xml, values: ["X": "ok"]),
            #"<w:tbl><w:tr><w:tc><w:p><w:r><w:tab/><w:t xml:space="preserve"/><w:t xml:space="preserve">ok</w:t></w:r></w:p></w:tc></w:tr></w:tbl>"#
        )
    }

    func testDecodificaEntidades() {
        XCTAssertEqual(TemplateXML.decodeEntities("a &amp; b &lt;&#123;&#x7D;&gt; &desconhecida;"), "a & b <{}> &desconhecida;")
    }
}
