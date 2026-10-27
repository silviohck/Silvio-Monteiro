import Foundation

/// Uma pasta na árvore de subpastas ("1 - APAC" › "Fisioterapia" › "coluna").
struct NoSubpasta: Identifiable {
    let nome: String
    /// Caminho completo, como guardado nos modelos: "1 - APAC / Fisioterapia".
    let caminho: String
    /// Há modelos diretamente nesta pasta (não só nas de dentro).
    var temModelos = false
    var filhos: [NoSubpasta] = []
    var id: String { caminho }

    /// Monta a árvore a partir dos caminhos ("1 - APAC / Fisioterapia / coluna"…), em ordem alfabética.
    static func arvore(_ caminhos: [String]) -> [NoSubpasta] {
        var raizes: [NoSubpasta] = []
        for caminho in caminhos {
            inserir(caminho.components(separatedBy: Armazenamento.separadorDeSubpastas), prefixo: [], em: &raizes)
        }
        return ordenar(raizes)
    }

    private static func inserir(_ partes: [String], prefixo: [String], em nos: inout [NoSubpasta]) {
        guard let primeira = partes.first else { return }
        let caminho = (prefixo + [primeira]).joined(separator: Armazenamento.separadorDeSubpastas)
        let indice: Int
        if let existente = nos.firstIndex(where: { $0.nome == primeira }) {
            indice = existente
        } else {
            nos.append(NoSubpasta(nome: primeira, caminho: caminho))
            indice = nos.count - 1
        }
        if partes.count == 1 {
            nos[indice].temModelos = true
        } else {
            inserir(Array(partes.dropFirst()), prefixo: prefixo + [primeira], em: &nos[indice].filhos)
        }
    }

    private static func ordenar(_ nos: [NoSubpasta]) -> [NoSubpasta] {
        nos.sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
            .map { no in
                var no = no
                no.filhos = ordenar(no.filhos)
                return no
            }
    }
}
