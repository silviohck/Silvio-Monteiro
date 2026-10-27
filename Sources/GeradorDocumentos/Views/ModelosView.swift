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

    /// Local cujos tipos aparecem no filtro: o local escolhido, nil para "todos os locais",
    /// ou .none quando o filtro mostra todos os modelos (sem um local específico).
    private var escopoDosTipos: UUID?? {
        switch filtroLocal {
        case "": return .none
        case Self.geral: return .some(nil)
        default:
            guard let local = localFiltrado else { return .none }
            return .some(local.id)
        }
    }

    /// Só os tipos do local escolhido; sem local, a junção de todos.
    private var tiposDoFiltro: [String] {
        if let escopo = escopoDosTipos {
            return armazenamento.tipos(doLocal: escopo)
        }
        var todos = armazenamento.tipos(doLocal: nil)
        for local in armazenamento.locaisOrdenados {
            for tipo in armazenamento.tipos(doLocal: local.id) where !todos.contains(tipo) {
                todos.append(tipo)
            }
        }
        return todos
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
            var tipos = tiposDoFiltro
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
                PainelSincronizacao()
                    .padding([.horizontal, .top], 8)
                Button(action: importarArquivos) {
                    Label(textoImportar, systemImage: "square.and.arrow.down")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .padding([.horizontal, .top], 8)
                .help("Importa arquivos avulsos, fora da pasta sincronizada")
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
                        ForEach(tiposDoFiltro, id: \.self) { tipo in
                            Text(tipo).tag(tipo)
                        }
                    }
                    .labelsHidden()
                    Button("Gerenciar…") { gerenciandoTipos = true }
                        .disabled(escopoDosTipos == nil)
                        .help(escopoDosTipos == nil
                            ? "Escolha um local acima para gerenciar os tipos dele"
                            : "Criar, renomear, excluir e ordenar os tipos deste local")
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
                                            NSWorkspace.shared.open(armazenamento.urlParaEditar(modelo))
                                        }
                                        if modelo.origem != nil {
                                            Button("Mostrar arquivo no Finder") {
                                                NSWorkspace.shared.activateFileViewerSelecting([armazenamento.urlParaEditar(modelo)])
                                            }
                                        } else {
                                            Button("Excluir modelo…", role: .destructive) {
                                                modeloParaExcluir = modelo
                                            }
                                        }
                                    }
                            }
                        }
                    }
                }
                .onDeleteCommand {
                    modeloParaExcluir = armazenamento.modelo(selecao).flatMap { $0.origem == nil ? $0 : nil }
                }
                .fundoSuave(Tema.lateral)
            }
            .background(Tema.lateral)
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
                    .stroke(Tema.destaque, style: StrokeStyle(lineWidth: 3, dash: [8]))
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
                modeloParaExcluir = armazenamento.modelo(selecao).flatMap { $0.origem == nil ? $0 : nil }
            } label: {
                Label("Excluir modelo", systemImage: "trash")
            }
            .disabled(selecao == nil)
        }
        .sheet(isPresented: $gerenciandoTipos) {
            GerenciarTiposView(localID: escopoDosTipos ?? nil)
                .environmentObject(armazenamento)
        }
        .onChange(of: tiposDoFiltro) { tipos in
            if !filtroTipo.isEmpty && !tipos.contains(filtroTipo) { filtroTipo = "" }
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
            HStack(spacing: 4) {
                Text(modelo.nome)
                if modelo.origem != nil {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .fonteApp(.legenda)
                        .foregroundStyle(.secondary)
                        .help("Vem da pasta sincronizada")
                }
            }
            Text(
                "\(modelo.categoria) · \(modelo.campos.count) \(modelo.campos.count == 1 ? "campo" : "campos")"
                    + (modelo.paginasPorFolha > 1 ? " · 2 por folha" : "")
            )
                .fonteApp(.legenda)
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

            if let origem = modelo.origem {
                Section {
                    LabeledContent("Arquivo") {
                        Text(origem).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                } header: {
                    Text("Vem da pasta sincronizada")
                } footer: {
                    Text("Edite o arquivo no Word: ao voltar para o app, as mudanças entram sozinhas. Para tirar este modelo do app, apague ou mova o arquivo na pasta.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if modelo.campos.isEmpty {
                    Text(modelo.origem == nil
                        ? "Nenhum campo {{...}} encontrado. Abra no Word, troque o nome do paciente por {{NOME_PACIENTE}} (e a data por {{DATA}}, etc.), salve e clique em “Atualizar campos”."
                        : "Nenhum campo {{...}} encontrado. Abra no Word, troque o nome do paciente por {{NOME_PACIENTE}} (e a data por {{DATA}}, etc.) e salve; o app atualiza sozinho.")
                        .foregroundStyle(.secondary)
                }
                ForEach(modelo.campos, id: \.self) { campo in
                    LabeledContent {
                        Text(descricao(campo)).foregroundStyle(.secondary)
                    } label: {
                        Text("{{\(campo)}}").fonteApp(.codigo)
                    }
                }
            } header: {
                Text("Campos do modelo (\(modelo.campos.count))")
            }

            Section {
                Picker("Páginas por folha", selection: Binding(
                    get: { min(modelo.paginasPorFolha, 2) },
                    set: { modelo.paginasPorFolha = $0 }
                )) {
                    Text("1 (normal)").tag(1)
                    Text("2 por folha").tag(2)
                }
                Stepper("Cópias: \(modelo.copias)", value: $modelo.copias, in: 1...10)
            } header: {
                Text("Impressão")
            } footer: {
                Text("Com “2 por folha”, os documentos gerados com este modelo já saem com a opção do Word “2 páginas por folha” ligada (Layout › Margens › Margens personalizadas › Várias páginas): no Word cada página aparece pela metade e a impressão sai com duas páginas em cada folha. Ex.: receita de controle especial. As cópias valem para a impressão pelo app.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Editar no Word") {
                        NSWorkspace.shared.open(armazenamento.urlParaEditar(modelo))
                    }
                    if modelo.origem != nil {
                        Button("Mostrar no Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([armazenamento.urlParaEditar(modelo)])
                        }
                    } else {
                        Button("Atualizar campos") {
                            executar { try armazenamento.atualizarCampos(modelo) }
                        }
                        .help("Depois de editar e salvar no Word, relê os campos do modelo")
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
        }
        .formStyle(.grouped)
        .fundoSuave()
        .alert("Novo tipo de documento", isPresented: $pedindoTipo) {
            TextField("Ex.: Atestados", text: $novoTipo)
            Button("Adicionar") {
                armazenamento.adicionarCategoria(novoTipo, local: modelo.localID)
                let nome = novoTipo.trimmingCharacters(in: .whitespacesAndNewlines)
                if !nome.isEmpty { modelo.categoria = nome }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O tipo é a subpasta onde os documentos gerados com este modelo são salvos, dentro da pasta do local.")
        }
    }

    /// Tipos do local deste modelo.
    private var tipos: [String] {
        let lista = armazenamento.tipos(doLocal: modelo.localID)
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
