@testable import DocxTemplateKit
import XCTest

final class BibliotecaTests: XCTestCase {
    private var raiz: URL!

    override func setUpWithError() throws {
        raiz = FileManager.default.temporaryDirectory.appendingPathComponent("biblioteca-\(UUID().uuidString)")
        // Estrutura parecida com a do usuário.
        for caminho in [
            "ALAGOA GRANDE/0 - atestado medico.docx",
            "ALAGOA GRANDE/0 - retorno.docx",
            "ALAGOA GRANDE/~$retorno.docx",
            "ALAGOA GRANDE/LAUDO MÉDICO/laudo coluna.docx",
            "ALAGOA GRANDE/RX/Joelho/rx joelho.docx",
            "ALAGOA GRANDE/PRONTUÁRIO/anotacoes.pdf",
            "OPERA PB/0 - meu contato.docx",
            "TCLE/termo.pdf",
            "NFS-e.pdf",
        ] {
            let url = raiz.appendingPathComponent(caminho)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: raiz)
    }

    func testLeGruposTiposEModelos() throws {
        let grupos = Biblioteca.ler(raiz: raiz)
        XCTAssertEqual(grupos.map(\.nome), ["ALAGOA GRANDE", "OPERA PB"])

        let alagoa = try XCTUnwrap(grupos.first)
        XCTAssertEqual(alagoa.tipos, [Biblioteca.tipoGeral, "LAUDO MÉDICO", "RX"])
        XCTAssertEqual(alagoa.modelos(do: Biblioteca.tipoGeral).map(\.nome), ["atestado medico", "retorno"])
        XCTAssertEqual(alagoa.modelos(do: "LAUDO MÉDICO").map(\.nome), ["laudo coluna"])
        XCTAssertEqual(alagoa.modelos(do: "RX").map(\.nome), ["Joelho / rx joelho"])
    }

    func testNomeDeExibicao() {
        XCTAssertEqual(Biblioteca.nomeDeExibicao(URL(fileURLWithPath: "/x/0 - encaminhamento - urgencia.docx")), "encaminhamento - urgencia")
        XCTAssertEqual(Biblioteca.nomeDeExibicao(URL(fileURLWithPath: "/x/laudo.docx")), "laudo")
        XCTAssertEqual(Biblioteca.nomeDeExibicao(URL(fileURLWithPath: "/x/2026.docx")), "2026")
    }
}
