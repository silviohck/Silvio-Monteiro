import AppKit

/// Atalho ⌘B: negrito no campo em que se está digitando. O trecho fica entre `**` na tela e sai em negrito
/// no Word (DocxTemplateKit). Vale para os campos do Prontuário e do Gerar documento.
enum Negrito {
    static let marca = "**"

    /// Põe `**` antes e depois do trecho selecionado; se ele já estiver em negrito, tira. Sem seleção,
    /// abre `****` com o cursor no meio, para digitar já em negrito.
    @MainActor
    static func alternar() {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable else {
            NSSound.beep()
            return
        }
        let texto = editor.string as NSString
        let selecao = editor.selectedRange()
        let selecionado = texto.substring(with: selecao)
        let tamanho = (marca as NSString).length

        // A seleção já inclui as marcas: **TRECHO** → TRECHO.
        if selecionado.hasPrefix(marca), selecionado.hasSuffix(marca), (selecionado as NSString).length >= 2 * tamanho {
            let interno = String(selecionado.dropFirst(marca.count).dropLast(marca.count))
            trocar(editor, selecao, por: interno, selecionar: NSRange(location: selecao.location, length: (interno as NSString).length))
            return
        }
        // As marcas estão logo antes e logo depois da seleção.
        if selecao.location >= tamanho, NSMaxRange(selecao) + tamanho <= texto.length,
           texto.substring(with: NSRange(location: selecao.location - tamanho, length: tamanho)) == marca,
           texto.substring(with: NSRange(location: NSMaxRange(selecao), length: tamanho)) == marca {
            let comMarcas = NSRange(location: selecao.location - tamanho, length: selecao.length + 2 * tamanho)
            trocar(editor, comMarcas, por: selecionado, selecionar: NSRange(location: comMarcas.location, length: selecao.length))
            return
        }
        trocar(editor, selecao, por: marca + selecionado + marca,
               selecionar: NSRange(location: selecao.location + tamanho, length: selecao.length))
    }

    private static func trocar(_ editor: NSTextView, _ faixa: NSRange, por novo: String, selecionar: NSRange) {
        // Avisa o campo da mudança, para o formulário (SwiftUI) receber o texto novo.
        guard editor.shouldChangeText(in: faixa, replacementString: novo) else { return }
        editor.replaceCharacters(in: faixa, with: novo)
        editor.didChangeText()
        editor.setSelectedRange(selecionar)
    }

    /// Fecha e reabre o negrito em cada linha de um campo com várias linhas (H.D.A., exame físico…),
    /// para que um trecho em negrito que passa de uma linha para a outra continue certo no Word.
    static func balancear(_ linhas: [String]) -> [String] {
        var aberto = false
        return linhas.map { linha in
            guard !linha.isEmpty else { return linha }
            let marcas = linha.components(separatedBy: marca).count - 1
            var nova = aberto ? marca + linha : linha
            let terminaAberto = aberto != (marcas % 2 == 1)
            if terminaAberto { nova += marca }
            aberto = terminaAberto
            return nova
        }
    }
}
