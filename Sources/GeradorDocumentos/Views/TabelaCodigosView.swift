import AppKit
import SwiftUI

/// Pesquisa numa tabela completa (CID-10, SIGTAP, TUSS), com cópia do código para colar nos documentos.
struct TabelaCodigosView: View {
    let tabela: TabelaDeCodigos
    /// Itens recuados sob as linhas de título (categorias, subgrupos), se a tabela tiver títulos.
    private let recuarItens: Bool
    @State private var busca = ""
    /// 0 = todos os grupos (capítulos).
    @AppStorage private var grupo: Int
    @State private var selecao: CodigoDaTabela.ID?
    @State private var copiado: String?
    @FocusState private var focoNaBusca: Bool

    /// `chaveDoFiltro`: onde o grupo escolhido fica guardado ("capituloCID" no CID-10).
    init(tabela: TabelaDeCodigos, chaveDoFiltro: String) {
        self.tabela = tabela
        recuarItens = tabela.codigos.contains(where: \.ehTitulo)
        _grupo = AppStorage(wrappedValue: 0, chaveDoFiltro)
    }

    private var resultados: [CodigoDaTabela] {
        tabela.buscar(busca, grupo: grupo == 0 ? nil : grupo)
    }

    var body: some View {
        let lista = resultados
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar por código ou descrição (ex.: \(tabela.exemploDeBusca))", text: $busca)
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
                    if !tabela.grupos.isEmpty {
                        Picker(tabela.nomeDoGrupo.capitalized, selection: $grupo) {
                            Text("Todos os \(tabela.nomeDoGrupo)s").tag(0)
                            ForEach(tabela.grupos) { grupo in
                                Text(grupo.nome).tag(grupo.numero)
                            }
                        }
                        .frame(maxWidth: 520)
                    }
                    Text(tabela.fonte)
                        .fonteApp(.legenda)
                        .foregroundStyle(.secondary)
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
                if tabela.codigos.isEmpty {
                    AvisoVazio(titulo: "Tabela \(tabela.nome) ainda não carregada", icone: "tray", mensagem: "Os dados oficiais entram na próxima versão do app.")
                } else if lista.isEmpty {
                    AvisoVazio(
                        titulo: "Nenhum código encontrado",
                        icone: "magnifyingglass",
                        mensagem: tabela.grupos.isEmpty ? "Tente outras palavras." : "Tente outras palavras ou escolha “Todos os \(tabela.nomeDoGrupo)s”."
                    )
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

    private func linha(_ codigo: CodigoDaTabela) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(codigo.codigo)
                .fonteApp(.codigo)
                .fontWeight(codigo.ehTitulo ? .bold : .regular)
                .frame(minWidth: 64, alignment: .leading)
            Text(codigo.descricao)
                .fontWeight(codigo.ehTitulo ? .semibold : .regular)
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
        .padding(.leading, codigo.ehTitulo || !recuarItens ? 0 : 20)
        .padding(.vertical, 1)
    }

    private func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
        copiado = texto
    }
}
