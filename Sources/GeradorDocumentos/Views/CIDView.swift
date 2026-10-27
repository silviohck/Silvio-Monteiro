import AppKit
import SwiftUI

/// Pesquisa na tabela CID-10 completa, com cópia do código para colar nos documentos.
struct CIDView: View {
    @State private var busca = ""
    /// 0 = todos os capítulos.
    @AppStorage("capituloCID") private var capitulo = 0
    @State private var selecao: CodigoCID.ID?
    @State private var copiado: String?
    @FocusState private var focoNaBusca: Bool

    private var resultados: [CodigoCID] {
        CID10.buscar(busca, capitulo: capitulo == 0 ? nil : capitulo)
    }

    var body: some View {
        let lista = resultados
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar por código ou descrição (ex.: M54.5, lombalgia, dor lombar)", text: $busca)
                        .textFieldStyle(.roundedBorder)
                        .focused($focoNaBusca)
                    if !busca.isEmpty {
                        Button {
                            busca = ""
                            focoNaBusca = true
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Picker("Capítulo", selection: $capitulo) {
                        Text("Todos os capítulos").tag(0)
                        ForEach(CID10.capitulos) { capitulo in
                            Text(capitulo.nome).tag(capitulo.numero)
                        }
                    }
                    .frame(maxWidth: 520)
                    Spacer()
                    Text("\(lista.count) \(lista.count == 1 ? "código" : "códigos")")
                        .fonteApp(.legenda)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)

            List(lista, selection: $selecao) { codigo in
                linha(codigo)
                    .tag(codigo.id)
                    .contextMenu {
                        Button("Copiar código e descrição") { copiar(codigo.textoCompleto) }
                        Button("Copiar só o código") { copiar(codigo.codigo) }
                    }
            }
            .fundoSuave()
            .onCopyCommand {
                guard let codigo = lista.first(where: { $0.id == selecao }) else { return [] }
                return [NSItemProvider(object: codigo.textoCompleto as NSString)]
            }
            .overlay {
                if lista.isEmpty {
                    AvisoVazio(titulo: "Nenhum código encontrado", icone: "magnifyingglass", mensagem: "Tente outras palavras ou escolha “Todos os capítulos”.")
                }
            }

            if let copiado {
                Label("Copiado: \(copiado)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Tema.sucesso)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .background(Tema.fundo)
        .onAppear { focoNaBusca = true }
    }

    private func linha(_ codigo: CodigoCID) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(codigo.codigo)
                .fonteApp(.codigo)
                .fontWeight(codigo.ehCategoria ? .bold : .regular)
                .frame(width: 64, alignment: .leading)
            Text(codigo.descricao)
                .fontWeight(codigo.ehCategoria ? .semibold : .regular)
                .textSelection(.enabled)
            Spacer()
            Button {
                copiar(codigo.textoCompleto)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Copiar “\(codigo.textoCompleto)”")
        }
        .padding(.leading, codigo.ehCategoria ? 0 : 20)
        .padding(.vertical, 1)
    }

    private func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
        copiado = texto
    }
}
