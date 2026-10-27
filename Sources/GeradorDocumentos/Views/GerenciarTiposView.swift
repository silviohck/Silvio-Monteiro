import SwiftUI

/// Janela para criar, renomear, excluir e ordenar os tipos de documento (Receitas, Atestados…).
struct GerenciarTiposView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @Environment(\.dismiss) private var dismiss
    @State private var novoTipo = ""
    @State private var tipoParaExcluir: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tipos de documento").font(.title2).bold()
            Text("Cada tipo vira uma subpasta dentro da pasta do local, onde ficam os documentos gerados. Clique no nome para renomear e arraste para mudar a ordem.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(armazenamento.dados.categorias, id: \.self) { tipo in
                    LinhaDeTipo(
                        tipo: tipo,
                        quantidade: armazenamento.quantidadeDeModelos(doTipo: tipo),
                        podeExcluir: armazenamento.dados.categorias.count > 1,
                        aoRenomear: { armazenamento.renomearCategoria(tipo, para: $0) },
                        aoExcluir: { tipoParaExcluir = tipo }
                    )
                }
                .onMove { armazenamento.moverCategorias(de: $0, para: $1) }
            }
            .frame(minHeight: 260)

            HStack {
                TextField("Novo tipo (ex.: Radiografias)", text: $novoTipo)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(adicionar)
                Button("Adicionar", action: adicionar)
                    .disabled(novoTipo.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack {
                Spacer()
                Button("Concluído") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 520)
        .confirmationDialog(
            "Excluir o tipo “\(tipoParaExcluir ?? "")”?",
            isPresented: Binding(get: { tipoParaExcluir != nil }, set: { if !$0 { tipoParaExcluir = nil } }),
            presenting: tipoParaExcluir
        ) { tipo in
            Button("Excluir", role: .destructive) {
                armazenamento.removerCategoria(tipo, moverPara: destino(aoExcluir: tipo))
            }
        } message: { tipo in
            let quantidade = armazenamento.quantidadeDeModelos(doTipo: tipo)
            if quantidade == 0 {
                Text("Nenhum modelo usa este tipo.")
            } else {
                Text("\(quantidade) \(quantidade == 1 ? "modelo passará" : "modelos passarão") para “\(destino(aoExcluir: tipo))”. Documentos já gerados não são movidos.")
            }
        }
    }

    /// Para onde vão os modelos do tipo excluído: "Outros", se existir, senão o primeiro tipo restante.
    private func destino(aoExcluir tipo: String) -> String {
        let restantes = armazenamento.dados.categorias.filter { $0 != tipo }
        return restantes.first { $0.compare("Outros", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            ?? restantes.first ?? "Outros"
    }

    private func adicionar() {
        armazenamento.adicionarCategoria(novoTipo)
        novoTipo = ""
    }
}

private struct LinhaDeTipo: View {
    let tipo: String
    let quantidade: Int
    let podeExcluir: Bool
    let aoRenomear: (String) -> Void
    let aoExcluir: () -> Void
    @State private var texto = ""
    @FocusState private var editando: Bool

    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            TextField("Nome do tipo", text: $texto)
                .textFieldStyle(.plain)
                .focused($editando)
                .onSubmit(confirmar)
            Spacer()
            Text("\(quantidade) \(quantidade == 1 ? "modelo" : "modelos")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: aoExcluir) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(!podeExcluir)
            .help("Excluir este tipo")
        }
        .onAppear { texto = tipo }
        .onChange(of: editando) { focado in
            if !focado { confirmar() }
        }
    }

    private func confirmar() {
        let nome = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if nome.isEmpty {
            texto = tipo
        } else if nome != tipo {
            aoRenomear(nome)
        }
    }
}
