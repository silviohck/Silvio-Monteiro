import SwiftUI

/// Sugestões da tabela CID-10 logo abaixo de um campo {{CID}}: digite o código ou palavras
/// ("lombalgia", "m54") e clique para preencher com o código.
struct SugestoesCID: View {
    let texto: String
    let escolher: (CodigoDaTabela) -> Void

    /// {{CID}}, {{CID_PRINCIPAL}}, {{CID2}}, {{OUTRO_CID}}…
    static func ehCampoCID(_ campo: String) -> Bool {
        // A palavra CID inteira (CID, CID_PRINCIPAL, OUTRO_CID) ou CID seguido de número (CID2);
        // não basta começar com "CID": CIDADE não é campo de CID.
        let partes = CamposAutomaticos.chave(campo).split(separator: "_")
        return partes.contains { parte in
            parte == "CID" || (parte.hasPrefix("CID") && parte.dropFirst(3).allSatisfy(\.isNumber))
        }
    }

    private var resultados: [CodigoDaTabela] {
        let termo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard termo.count >= 2 else { return [] }
        let tabela = TabelaDeCodigos.cid10
        // Já é um código da tabela: nada a sugerir.
        if tabela.codigos.contains(where: { $0.codigo.caseInsensitiveCompare(termo) == .orderedSame }) { return [] }
        return Array(tabela.buscar(termo, grupo: nil).prefix(6))
    }

    var body: some View {
        let lista = resultados
        if !lista.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lista) { codigo in
                    Button {
                        escolher(codigo)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(codigo.codigo)
                                .fonteApp(.codigo)
                                .fontWeight(.semibold)
                                .frame(minWidth: 52, alignment: .leading)
                            Text(codigo.descricao)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Usar \(codigo.textoCompleto)")
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Tema.destaqueSuave))
        }
    }
}
