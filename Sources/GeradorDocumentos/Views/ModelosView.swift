import AppKit
import SwiftUI

struct ModelosView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var selecao: ModeloDocumento.ID?
    @State private var busca = ""
    @State private var modeloParaExcluir: ModeloDocumento?
    @State private var arrastando = false
    /// "" = todos, "geral" = modelos de todos os locais, ou o id do local.
    @AppStorage("filtroLocalModelos") private var filtroLocal = ""
    /// "" = todos os tipos, ou o nome do tipo.
    @AppStorage("filtroTipoModelos") private var filtroTipo = ""
    @State private var gerenciandoTipos = false

    private static let geral = "geral"

    private struct Grupo: Identifiable {
        let id: String
        let titulo: String
        let modelos: [ModeloDocumento]
    }

    private var localFiltrado: LocalAtendimento? {
        armazenamento.dados.locais.first { $0.id.uuidString == filtroLocal }
    }

    private var textoImportar: String {
        let tipo = filtroTipo.isEmpty ? "modelo" : filtroTipo
        guard let local = localFiltrado else { return "Importar \(tipo)" }
        return "Importar \(tipo) para \(local.nome.isEmpty ? "este local" : local.nome)"
    }

    private func doFiltroDeLocal(_ modelo: ModeloDocumento) -> Bool {
        switch filtroLocal {
        case "": return true
        case Self.geral: return armazenamento.localDoModelo(modelo) == nil
        default: return modelo.localID?.uuidString == filtroLocal
        }
    }

    /// Sem local escolhido: agrupa por local. Com local escolhido: agrupa por tipo.
    private var grupos: [Grupo] {
        let termo = busca.trimmingCharacters(in: .whitespaces)
        let modelos = armazenamento.dados.modelos
            .filter { termo.isEmpty || $0.nome.localizedCaseInsensitiveContains(termo) }
            .filter { filtroTipo.isEmpty || $0.categoria == filtroTipo }
            .filter(doFiltroDeLocal)
            .sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }

        if !filtroLocal.isEmpty {
            var tipos = armazenamento.dados.categorias
            for modelo in modelos where !tipos.contains(modelo.categoria) {
                tipos.append(modelo.categoria)
            }
            return tipos.compactMap { tipo in
                let doTipo = modelos.filter { $0.categoria == tipo }
                return doTipo.isEmpty ? nil : Grupo(id: tipo, titulo: tipo, modelos: doTipo)
            }
        }

        var grupos: [Grupo] = []
        for local in armazenamento.locaisOrdenados {
            let doLocal = modelos.filter { $0.localID == local.id }
            if !doLocal.isEmpty {
                grupos.append(Grupo(id: local.id.uuidString, titulo: local.nome.isEmpty ? "Local sem nome" : local.nome, modelos: doLocal))
            }
        }
        let gerais = modelos.filter { armazenamento.localDoModelo($0) == nil }
        if !gerais.isEmpty {
            grupos.append(Grupo(id: Self.geral, titulo: "Todos os locais", modelos: gerais))
        }
        return grupos
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                Button(action: importarArquivos) {
                    Label(textoImportar, systemImage: "square.and.arrow.down")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding([.horizontal, .top], 8)
                Picker("Local", selection: $filtroLocal) {
                    Text("Todos os modelos").tag("")
                    ForEach(armazenamento.locaisOrdenados) { local in
                        Text(local.nome.isEmpty ? "Local sem nome" : local.nome).tag(local.id.uuidString)
                    }
                    Text("Modelos de todos os locais").tag(Self.geral)
                }
                .labelsHidden()
                .padding([.horizontal, .top], 8)
                HStack {
                    Picker("Tipo", selection: $filtroTipo) {
                        Text("Todos os tipos").tag("")
                        ForEach(armazenamento.dados.categorias, id: \.self) { tipo in
                            Text(tipo).tag(tipo)
                        }
                    }
                    .labelsHidden()
                    Button("Gerenciar…") { gerenciandoTipos = true }
                        .help("Criar, renomear, excluir e ordenar os tipos de documento")
                }
                .padding([.horizontal, .top], 8)
                TextField("Buscar modelo", text: $busca)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                List(selection: $selecao) {
                    ForEach(grupos) { grupo in
                        Section("\(grupo.titulo) (\(grupo.modelos.count))") {
                            ForEach(grupo.modelos) { modelo in
                                linha(modelo)
                                    .tag(modelo.id)
                                    .contextMenu {
                                        Button("Abrir no Word") {
                                            NSWorkspace.shared.open(armazenamento.urlDoModelo(modelo))
                                        }
                                        Button("Excluir modelo…", role: .destructive) {
                                            modeloParaExcluir = modelo
                                        }
                                    }
                            }
                        }
                    }
                }
                .onDeleteCommand {
                    modeloParaExcluir = armazenamento.modelo(selecao)
                }
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)

            Group {
                if let modelo = armazenamento.modelo(selecao) {
                    ModeloEditor(
                        modelo: Binding(
                            get: { armazenamento.modelo(modelo.id) ?? modelo },
                            set: { armazenamento.atualizarModelo($0) }
                        ),
                        aoExcluir: { modeloParaExcluir = modelo }
                    )
                    .id(modelo.id)
                } else {
                    AvisoVazio(
                        titulo: armazenamento.dados.modelos.isEmpty ? "Nenhum modelo importado" : "Nenhum modelo selecionado",
                        icone: "doc.text",
                        mensagem: "Escolha o local no filtro à esquerda e importe os modelos dele. No Word, escreva os campos entre chaves duplas onde o texto deve mudar, por exemplo: Atesto que {{NOME_PACIENTE}}, CPF {{CPF}}, esteve aqui em {{DATA}}. Você também pode arrastar arquivos .docx para esta janela.",
                        botao: textoImportar,
                        acao: importarArquivos
                    )
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if arrastando {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            importar(urls)
            return true
        } isTargeted: { arrastando = $0 }
        .toolbar {
            Button(action: importarArquivos) {
                Label("Importar modelo", systemImage: "square.and.arrow.down")
            }
            Button(role: .destructive) {
                modeloParaExcluir = armazenamento.modelo(selecao)
            } label: {
                Label("Excluir modelo", systemImage: "trash")
            }
            .disabled(selecao == nil)
        }
        .sheet(isPresented: $gerenciandoTipos) {
            GerenciarTiposView()
                .environmentObject(armazenamento)
        }
        .onChange(of: armazenamento.dados.categorias) { categorias in
            if !filtroTipo.isEmpty && !categorias.contains(filtroTipo) { filtroTipo = "" }
        }
        .confirmationDialog(
            "Excluir o modelo “\(modeloParaExcluir?.nome ?? "")”?",
            isPresented: Binding(get: { modeloParaExcluir != nil }, set: { if !$0 { modeloParaExcluir = nil } }),
            presenting: modeloParaExcluir
        ) { modelo in
            Button("Excluir", role: .destructive) {
                if selecao == modelo.id { selecao = nil }
                armazenamento.removerModelo(modelo)
            }
        } message: { _ in
            Text("A cópia do modelo guardada pelo app será apagada. Seu arquivo original não é afetado.")
        }
    }

    private func linha(_ modelo: ModeloDocumento) -> some View {
        VStack(alignment: .leading) {
            Text(modelo.nome)
            Text("\(modelo.categoria) · \(modelo.campos.count) \(modelo.campos.count == 1 ? "campo" : "campos")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func importarArquivos() {
        importar(escolherArquivosDocx(multiplos: true))
    }

    /// Importa para o local e o tipo escolhidos nos filtros.
    private func importar(_ urls: [URL]) {
        var erros: [String] = []
        for url in urls {
            do {
                let modelo = try armazenamento.importarModelo(
                    de: url,
                    localID: localFiltrado?.id,
                    tipo: filtroTipo.isEmpty ? nil : filtroTipo
                )
                selecao = modelo.id
            } catch {
                erros.append(error.localizedDescription)
            }
        }
        if !erros.isEmpty {
            armazenamento.erro = erros.joined(separator: "\n\n")
        }
    }
}

struct ModeloEditor: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @Binding var modelo: ModeloDocumento
    let aoExcluir: () -> Void
    @State private var pedindoTipo = false
    @State private var novoTipo = ""

    var body: some View {
        Form {
            Section("Modelo") {
                TextField("Nome", text: $modelo.nome)
                Picker("Local de atendimento", selection: $modelo.localID) {
                    Text("Todos os locais").tag(UUID?.none)
                    ForEach(armazenamento.locaisOrdenados) { local in
                        Text(local.nome.isEmpty ? "Local sem nome" : local.nome).tag(Optional(local.id))
                    }
                }
                HStack {
                    Picker("Tipo", selection: $modelo.categoria) {
                        ForEach(tipos, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Novo tipo…") {
                        novoTipo = ""
                        pedindoTipo = true
                    }
                }
            }

            Section {
                if modelo.campos.isEmpty {
                    Text("Nenhum campo {{...}} encontrado. Abra no Word, troque o nome do paciente por {{NOME_PACIENTE}} (e a data por {{DATA}}, etc.), salve e clique em “Atualizar campos”.")
                        .foregroundStyle(.secondary)
                }
                ForEach(modelo.campos, id: \.self) { campo in
                    LabeledContent {
                        Text(descricao(campo)).foregroundStyle(.secondary)
                    } label: {
                        Text("{{\(campo)}}").font(.system(.body, design: .monospaced))
                    }
                }
            } header: {
                Text("Campos do modelo (\(modelo.campos.count))")
            }

            Section {
                HStack {
                    Button("Editar no Word") {
                        NSWorkspace.shared.open(armazenamento.urlDoModelo(modelo))
                    }
                    .help("Abre o modelo salvo. Depois de editar e salvar no Word, clique em “Atualizar campos”.")
                    Button("Atualizar campos") {
                        executar { try armazenamento.atualizarCampos(modelo) }
                    }
                    Button("Substituir arquivo…") {
                        if let url = escolherArquivosDocx(multiplos: false).first {
                            executar { try armazenamento.substituirArquivo(modelo, por: url) }
                        }
                    }
                    Spacer()
                    Button(role: .destructive, action: aoExcluir) {
                        Label("Excluir modelo…", systemImage: "trash")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Novo tipo de documento", isPresented: $pedindoTipo) {
            TextField("Ex.: Atestados", text: $novoTipo)
            Button("Adicionar") {
                armazenamento.adicionarCategoria(novoTipo)
                let nome = novoTipo.trimmingCharacters(in: .whitespacesAndNewlines)
                if !nome.isEmpty { modelo.categoria = nome }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O tipo é a subpasta onde os documentos gerados com este modelo são salvos, dentro da pasta do local.")
        }
    }

    private var tipos: [String] {
        let lista = armazenamento.dados.categorias
        return lista.contains(modelo.categoria) ? lista : lista + [modelo.categoria]
    }

    private func descricao(_ campo: String) -> String {
        if CamposAutomaticos.ehNomeDoPaciente(campo) { return "nome digitado na hora" }
        switch CamposAutomaticos.mapa[CamposAutomaticos.chave(campo)] {
        case .paciente: return "cadastro do paciente"
        case .local: return "cadastro do local"
        case .idade: return "calculada pelo nascimento"
        case .dataHoje, .dataExtenso: return "data de hoje"
        case nil: return "digitado na hora (fica salvo no paciente)"
        }
    }

    private func executar(_ acao: () throws -> Void) {
        do {
            try acao()
        } catch {
            armazenamento.erro = error.localizedDescription
        }
    }
}
