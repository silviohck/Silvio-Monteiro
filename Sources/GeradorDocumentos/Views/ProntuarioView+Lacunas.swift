import AppKit
import SwiftUI

/// Guarda o campo com o cursor e o atalho Tab do Prontuário (um objeto, para o atalho ler o estado atual).
final class RastreioDoProntuario: ObservableObject {
    var campo: String?
    var monitor: Any?
    var irParaLacuna: ((_ paraTras: Bool) -> Bool)?

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

/// Tab pula para o próximo ___ (⇧Tab volta), já selecionado: é só digitar por cima.
extension ProntuarioView {
    func instalarAtalhoTab() {
        rastreio.irParaLacuna = { paraTras in irParaLacuna(paraTras: paraTras) }
        guard rastreio.monitor == nil else { return }
        let rastreio = self.rastreio
        rastreio.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { evento in
            // 48 = tecla Tab; com ⌘, ⌥ ou ⌃ fica o comportamento normal.
            guard evento.keyCode == 48,
                  evento.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                  rastreio.campo != nil,
                  let acao = rastreio.irParaLacuna else { return evento }
            return acao(evento.modifierFlags.contains(.shift)) ? nil : evento
        }
    }

    func removerAtalhoTab() {
        if let monitor = rastreio.monitor { NSEvent.removeMonitor(monitor) }
        rastreio.monitor = nil
    }

    /// Próxima lacuna no campo atual (depois do cursor) ou nos campos seguintes; sem lacuna, Tab normal.
    func irParaLacuna(paraTras: Bool) -> Bool {
        guard let ficha, let atual = rastreio.campo,
              let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        let ordem = camposClinicos(ficha).flatMap { grupo($0, ficha) }
        guard let posicao = ordem.firstIndex(of: atual) else { return false }
        let texto = editor.string as NSString
        let selecao = editor.selectedRange()
        let aqui = paraTras
            ? Self.lacuna(em: texto, antesDe: selecao.location)
            : Self.lacuna(em: texto, depoisDe: NSMaxRange(selecao))
        if let aqui {
            editor.setSelectedRange(aqui)
            editor.scrollRangeToVisible(aqui)
            return true
        }
        let outros = paraTras ? Array(ordem[..<posicao].reversed()) : Array(ordem[(posicao + 1)...])
        for campo in outros {
            let outro = valores[campo, default: ""] as NSString
            let achada = paraTras ? Self.lacuna(em: outro, antesDe: outro.length) : Self.lacuna(em: outro, depoisDe: 0)
            if let achada {
                focar(campo, cursor: achada.location, selecionar: achada.length)
                return true
            }
        }
        return false
    }

    /// A lacuna ___ (inteira, mesmo com mais traços) depois de `inicio`.
    static func lacuna(em texto: NSString, depoisDe inicio: Int) -> NSRange? {
        guard inicio <= texto.length else { return nil }
        let achado = texto.range(of: "___", options: [], range: NSRange(location: inicio, length: texto.length - inicio))
        return achado.location == NSNotFound ? nil : inteira(achado, em: texto)
    }

    /// A última lacuna ___ antes de `fim`.
    static func lacuna(em texto: NSString, antesDe fim: Int) -> NSRange? {
        let limite = min(max(fim, 0), texto.length)
        let achado = texto.range(of: "___", options: .backwards, range: NSRange(location: 0, length: limite))
        return achado.location == NSNotFound ? nil : inteira(achado, em: texto)
    }

    private static func inteira(_ faixa: NSRange, em texto: NSString) -> NSRange {
        var faixa = faixa
        let traco: unichar = 95 // "_"
        while faixa.location > 0 && texto.character(at: faixa.location - 1) == traco {
            faixa.location -= 1
            faixa.length += 1
        }
        while NSMaxRange(faixa) < texto.length && texto.character(at: NSMaxRange(faixa)) == traco {
            faixa.length += 1
        }
        return faixa
    }
}
