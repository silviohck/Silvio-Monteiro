@testable import DocxTemplateKit
import XCTest

final class LacunasTests: XCTestCase {
    func testTextoSemLacunaNaoMuda() {
        XCTAssertEqual(Lacunas.remover("DOR NO JOELHO DIREITO HÁ 6 MESES."), "DOR NO JOELHO DIREITO HÁ 6 MESES.")
    }

    func testLacunaComPalavraDeLigacao() {
        XCTAssertEqual(Lacunas.remover("Q.P.: DOR NO JOELHO DIREITO HÁ ___."), "Q.P.: DOR NO JOELHO DIREITO.")
        XCTAssertEqual(
            Lacunas.remover("DOR MECÂNICA EM JOELHO DIREITO HÁ ___, PIORA EM ESCADAS E AO LEVANTAR."),
            "DOR MECÂNICA EM JOELHO DIREITO, PIORA EM ESCADAS E AO LEVANTAR."
        )
    }

    func testCampoVazioSaiInteiro() {
        XCTAssertEqual(
            Lacunas.remover("EXAME FÍSICO: MARCHA ___. CREPITAÇÃO PRESENTE. DERRAME ___. ADM 0° A 110°."),
            "EXAME FÍSICO: CREPITAÇÃO PRESENTE. ADM 0° A 110°."
        )
        XCTAssertEqual(Lacunas.remover("FISIOTERAPIA MOTORA 10 SESSÕES. RETORNO EM ___."), "FISIOTERAPIA MOTORA 10 SESSÕES.")
    }

    func testMantemAsLinhas() {
        let texto = "DOR NO OMBRO HÁ 3 MESES. TRAUMA: ___.\nFORÇA: ___. JOBE POSITIVO."
        let saida = Lacunas.remover(texto)
        XCTAssertEqual(saida.components(separatedBy: "\n").count, 2)
        XCTAssertEqual(saida, "DOR NO OMBRO HÁ 3 MESES.\nJOBE POSITIVO.")
    }

    func testVirgulaDentroDeParentesesNaoCorta() {
        XCTAssertEqual(
            Lacunas.remover("FISIOTERAPIA MOTORA (FORTALECIMENTO DE QUADRÍCEPS, ALONGAMENTO) ___ SESSÕES. RETORNO EM ___."),
            "FISIOTERAPIA MOTORA (FORTALECIMENTO DE QUADRÍCEPS, ALONGAMENTO) SESSÕES."
        )
    }

    func testTituloDaSecaoFica() {
        XCTAssertEqual(
            Lacunas.remover("EXAMES COMPLEMENTARES: RX COM CARGA:\nKELLGREN-LAWRENCE ___."),
            "EXAMES COMPLEMENTARES:\n"
        )
    }

    func testPreenchidoFicaEPreenchimentoParcial() {
        XCTAssertEqual(
            Lacunas.remover("FISIOTERAPIA MOTORA (FORTALECIMENTO DE QUADRÍCEPS) ___ SESSÕES. AVALIAR INFILTRAÇÃO."),
            "FISIOTERAPIA MOTORA (FORTALECIMENTO DE QUADRÍCEPS) SESSÕES. AVALIAR INFILTRAÇÃO."
        )
    }
}
