import SwiftUI

/// "Modelo de atendimento" no Prontuário: busca por doença ou CID, escolha do lado e preenchimento da
/// ficha; "Salvar como meu modelo" guarda o que está escrito para usar de novo.
extension ProntuarioView {
    // Campos da ficha que cada parte do modelo preenche (pelo nome do campo).
    func campo(_ ficha: ModeloDocumento, _ teste: (String) -> Bool) -> String? {
        camposClinicos(ficha).first { teste(CamposAutomaticos.chave($0)) }
    }
    func campoQP(_ f: ModeloDocumento) -> String? { campo(f) { $0 == "QP" || $0.contains("QUEIXA") } }
    func campoHDA(_ f: ModeloDocumento) -> String? { campo(f) { $0 == "HDA" || $0.contains("HISTORIA") || $0.contains("ANAMNESE") } }
    func campoExame(_ f: ModeloDocumento) -> String? { Self.campoDoExameFisico(f) ?? campo(f) { $0.contains("EXAME") } }
    func campoDiagnostico(_ f: ModeloDocumento) -> String? { campo(f) { $0.contains("DIAGNOSTICO") || $0.contains("HIPOTESE") } }
    func campoCID(_ f: ModeloDocumento) -> String? { camposClinicos(f).first(where: SugestoesCID.ehCampoCID) }
    func campoConduta(_ f: ModeloDocumento) -> String? {
        campo(f) { $0.contains("PROGRAMACAO") || $0.contains("CONDUTA") || $0.contains("PLANO") || $0.contains("TRATAMENTO") }
    }
    func campoPerfil(_ f: ModeloDocumento) -> String? { campo(f) { $0.contains("PERFIL") } }

    /// O campo e as linhas seguintes dele ({{HDA}}, {{HDA_LINHA_2}}…).
    func grupo(_ campo: String, _ ficha: ModeloDocumento) -> [String] { [campo] + Self.continuacoes(de: campo, em: ficha) }

    func alvos(_ ficha: ModeloDocumento) -> [String] {
        [campoQP(ficha), campoHDA(ficha), campoExame(ficha), campoDiagnostico(ficha), campoCID(ficha), campoConduta(ficha)]
            .compactMap { $0 }
            .flatMap { grupo($0, ficha) }
    }

    var resultadosDoModelo: [ModeloDeAtendimento] {
        ModelosDeAtendimento.buscar(buscaModelo, meus: [])
    }

    func pedirAplicar(_ modelo: ModeloDeAtendimento, _ ficha: ModeloDocumento) {
        let ocupado = alvos(ficha).contains { !valores[$0, default: ""].trimmingCharacters(in: .whitespaces).isEmpty }
        if ocupado { modeloParaAplicar = modelo } else { aplicar(modelo, ficha) }
    }

    /// Preenche a ficha com o modelo, no lado escolhido; textos longos ocupam as linhas em ordem.
    func aplicar(_ modelo: ModeloDeAtendimento, _ ficha: ModeloDocumento) {
        func por(_ campo: String?, _ texto: String) {
            guard let campo else { return }
            let final = GerarView.maiusculas(ModelosDeAtendimento.comLado(texto, ladoModelo))
            let linhas = grupo(campo, ficha)
            for linha in linhas { valores[linha] = "" }
            valores[campo] = final
            if linhas.count > 1 { fluir(linhas, aPartirDe: 0) }
        }
        por(campoQP(ficha), modelo.qp)
        por(campoHDA(ficha), modelo.hda)
        por(campoExame(ficha), modelo.exame)
        por(campoDiagnostico(ficha), modelo.diagnostico)
        por(campoCID(ficha), modelo.cid)
        por(campoConduta(ficha), modelo.conduta)
        if let perfil = campoPerfil(ficha), valores[perfil, default: ""].isEmpty { valores[perfil] = "FÍSICO" }
        geracaoConcluida = false
        aviso = nil
        ultimoDocumento = nil
        buscaModelo = ""
    }

    /// O que está escrito na ficha vira um modelo seu (o lado escolhido volta a ser [LADO]).
    func salvarComoMeuModelo(_ ficha: ModeloDocumento) {
        let nome = nomeNovoModelo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nome.isEmpty else { return }
        func texto(_ campo: String?) -> String {
            guard let campo else { return "" }
            let junto = grupo(campo, ficha)
                .map { valores[$0, default: ""].trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return ModelosDeAtendimento.semLado(junto, ladoModelo)
        }
        armazenamento.salvarModeloDeAtendimento(ModeloDeAtendimento(
            nome: nome, cid: texto(campoCID(ficha)), diagnostico: texto(campoDiagnostico(ficha)),
            qp: texto(campoQP(ficha)), hda: texto(campoHDA(ficha)), exame: texto(campoExame(ficha)),
            conduta: texto(campoConduta(ficha))
        ))
    }

    /// Atalhos para os modelos mais usados neste local: um clique preenche a ficha. Em grade; arrastar
    /// ou o clique direito mudam a ordem.
    @ViewBuilder
    func gradeDeFavoritos(_ ficha: ModeloDocumento) -> some View {
        let favoritos = armazenamento.favoritosDeAtendimento(para: local)
        if !favoritos.isEmpty {
            HStack {
                Text("Favoritos deste local").fonteApp(.legenda).foregroundStyle(.secondary)
                Spacer()
                Button(organizandoFavoritos ? "Pronto" : "Reorganizar") {
                    withAnimation(.easeInOut(duration: 0.15)) { organizandoFavoritos.toggle() }
                }
                .buttonStyle(.link)
                .help("Mudar a ordem dos favoritos com as setas, ou tirar um deles")
            }
            if organizandoFavoritos {
                organizarFavoritos(favoritos)
            } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(favoritos, id: \.self) { favorito in
                    Button {
                        pedirAplicar(favorito, ficha)
                    } label: {
                        Label {
                            Text(favorito.nome).lineLimit(1).truncationMode(.middle)
                        } icon: {
                            Image(systemName: "star.fill")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .help("\(favorito.cid) · \(favorito.nome) (\(ladoModelo.lowercased())) — arraste para mudar a ordem")
                    .draggable(ModelosDeAtendimento.chave(favorito))
                    .dropDestination(for: String.self) { chaves, _ in
                        guard let chave = chaves.first,
                              let arrastado = favoritos.first(where: { ModelosDeAtendimento.chave($0) == chave }),
                              arrastado != favorito else { return false }
                        let deOnde = favoritos.firstIndex(of: arrastado) ?? 0
                        let paraOnde = favoritos.firstIndex(of: favorito) ?? 0
                        // Para a direita: entra depois do alvo; para a esquerda: antes.
                        let antesDe = deOnde < paraOnde
                            ? (paraOnde + 1 < favoritos.count ? favoritos[paraOnde + 1] : nil)
                            : favorito
                        armazenamento.moverFavoritoDeAtendimento(arrastado, paraAntesDe: antesDe, noLocal: local)
                        return true
                    }
                    .contextMenu {
                        let indice = favoritos.firstIndex(of: favorito) ?? 0
                        Button("Mover para a esquerda") {
                            armazenamento.moverFavoritoDeAtendimento(favorito, paraAntesDe: favoritos[indice - 1], noLocal: local)
                        }
                        .disabled(indice == 0)
                        Button("Mover para a direita") {
                            armazenamento.moverFavoritoDeAtendimento(
                                favorito, paraAntesDe: indice + 2 < favoritos.count ? favoritos[indice + 2] : nil, noLocal: local
                            )
                        }
                        .disabled(indice == favoritos.count - 1)
                        Button("Mover para o início") {
                            armazenamento.moverFavoritoDeAtendimento(favorito, paraAntesDe: favoritos.first, noLocal: local)
                        }
                        .disabled(indice == 0)
                        Button("Mover para o fim") {
                            armazenamento.moverFavoritoDeAtendimento(favorito, paraAntesDe: nil, noLocal: local)
                        }
                        .disabled(indice == favoritos.count - 1)
                        Divider()
                        Button("Tirar dos favoritos") {
                            armazenamento.alternarFavoritoDeAtendimento(favorito, noLocal: local)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            }
        }
    }

    /// Modo "Reorganizar": cada favorito com setas para a esquerda/direita e um X para tirar.
    func organizarFavoritos(_ favoritos: [ModeloDeAtendimento]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(Array(favoritos.enumerated()), id: \.element) { indice, favorito in
                HStack(spacing: 6) {
                    Button {
                        armazenamento.moverFavoritoDeAtendimento(favorito, paraAntesDe: favoritos[indice - 1], noLocal: local)
                    } label: { Image(systemName: "chevron.left") }
                    .disabled(indice == 0)
                    .help("Mover para a esquerda")
                    Text("\(indice + 1). \(favorito.nome)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        armazenamento.moverFavoritoDeAtendimento(
                            favorito, paraAntesDe: indice + 2 < favoritos.count ? favoritos[indice + 2] : nil, noLocal: local
                        )
                    } label: { Image(systemName: "chevron.right") }
                    .disabled(indice == favoritos.count - 1)
                    .help("Mover para a direita")
                    Button {
                        armazenamento.alternarFavoritoDeAtendimento(favorito, noLocal: local)
                    } label: { Image(systemName: "xmark") }
                    .help("Tirar dos favoritos")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).stroke(Tema.borda))
            }
        }
        .padding(.vertical, 2)
    }

    /// Uma linha da busca: estrela (favorito) e o modelo (clique preenche a ficha).
    func linhaDoResultado(_ modelo: ModeloDeAtendimento, _ ficha: ModeloDocumento) -> some View {
        HStack(spacing: 8) {
                let favorito = armazenamento.ehFavoritoDeAtendimento(modelo, noLocal: local)
                Button {
                    armazenamento.alternarFavoritoDeAtendimento(modelo, noLocal: local)
                } label: {
                    Image(systemName: favorito ? "star.fill" : "star")
                        .foregroundStyle(favorito ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(favorito ? "Tirar dos favoritos" : "Favoritar em \(local?.nome ?? "este local"): vira um atalho acima da busca")
                Button {
                    pedirAplicar(modelo, ficha)
                } label: {
                    HStack(spacing: 10) {
                        Text(modelo.cid.isEmpty ? "—" : modelo.cid)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Tema.destaque)
                            .frame(width: 60, alignment: .leading)
                        Text(modelo.nome).lineLimit(1)
                        Spacer()
                        if modelo.meu {
                            Text("meu").fonteApp(.legenda).foregroundStyle(Tema.sucesso)
                        } else if modelo.generico {
                            Text("por tipo").fonteApp(.legenda).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Preencher a ficha com este modelo (\(ladoModelo.lowercased()))")
                .contextMenu {
                    Button(armazenamento.ehFavoritoDeAtendimento(modelo, noLocal: local) ? "Tirar dos favoritos" : "Adicionar aos favoritos") {
                        armazenamento.alternarFavoritoDeAtendimento(modelo, noLocal: local)
                    }
                    if modelo.meu {
                        Button("Apagar este modelo", role: .destructive) { armazenamento.apagarModeloDeAtendimento(modelo) }
                    }
                }
        }
    }

    /// Os modelos que você salvou, separados dos que vêm no app.
    func secaoMeusModelos(_ ficha: ModeloDocumento) -> some View {
        let meus = armazenamento.dados.modelosDeAtendimento
            .filter { buscaMeusModelos.count < 2 || ModelosDeAtendimento.simples($0.nome + " " + $0.cid).contains(ModelosDeAtendimento.simples(buscaMeusModelos)) }
            .sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
        return Section {
            if armazenamento.dados.modelosDeAtendimento.count > 6 {
                TextField("Buscar", text: $buscaMeusModelos, prompt: Text("Buscar nos meus modelos"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
            }
            if armazenamento.dados.modelosDeAtendimento.isEmpty {
                Text("Você ainda não salvou nenhum modelo. Escreva o atendimento (ou parta de um modelo do app), ajuste e clique em “Salvar o que está escrito…”.")
                    .foregroundStyle(.secondary)
            }
            ForEach(meus) { modelo in
                linhaDoResultado(modelo, ficha)
            }
            HStack {
                Spacer()
                Button("Salvar o que está escrito como meu modelo…") {
                    nomeNovoModelo = valores[campoDiagnostico(ficha) ?? "", default: ""]
                    salvandoModelo = true
                }
                .buttonStyle(.link)
            }
        } header: {
            TituloSecao("Meus modelos", icone: "person.text.rectangle")
        } footer: {
            Text("Só os modelos que você salvou. Com o mesmo nome, substitui o anterior; clique direito para apagar. Não salve dados de um paciente específico.")
                .foregroundStyle(.secondary)
        }
    }

    func secaoModeloDeAtendimento(_ ficha: ModeloDocumento) -> some View {
        Section {
            gradeDeFavoritos(ficha)
            HStack(spacing: 12) {
                TextField("Buscar", text: $buscaModelo, prompt: Text("Buscar doença ou CID (ex.: gonartrose, túnel do carpo, M54)"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                Picker("Lado", selection: $ladoModelo) {
                    ForEach(ModelosDeAtendimento.lados, id: \.self) { lado in
                        Text(lado.capitalized).tag(lado)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                .help("O [LADO] do modelo sai como este lado")
            }
            let resultados = resultadosDoModelo
            ForEach(resultados) { modelo in
                linhaDoResultado(modelo, ficha)
            }
            if buscaModelo.trimmingCharacters(in: .whitespaces).count >= 2 && resultados.isEmpty {
                Text("Nenhum modelo encontrado.").foregroundStyle(.secondary)
            }
        } header: {
            TituloSecao("Modelos de atendimento do app", icone: "text.book.closed.fill")
        } footer: {
            Text("A estrela ★ põe o modelo nos favoritos deste local (atalhos acima da busca). Escolha o lado e clique no modelo: Q.P., H.D.A., exame físico, diagnóstico, CID e programação são preenchidos nas linhas da ficha. Complete os ___ e ajuste o que precisar. Os textos são pontos de partida.")
                .foregroundStyle(.secondary)
        }
        .alert(
            "Substituir o que já está escrito?",
            isPresented: Binding(get: { modeloParaAplicar != nil }, set: { if !$0 { modeloParaAplicar = nil } })
        ) {
            Button("Substituir", role: .destructive) {
                if let modelo = modeloParaAplicar { aplicar(modelo, ficha) }
                modeloParaAplicar = nil
            }
            Button("Cancelar", role: .cancel) { modeloParaAplicar = nil }
        } message: {
            Text("A queixa, a história, o exame, o diagnóstico, o CID e a programação serão trocados pelo modelo “\(modeloParaAplicar?.nome ?? "")”.")
        }
        .alert("Salvar como meu modelo", isPresented: $salvandoModelo) {
            TextField("Nome do modelo", text: $nomeNovoModelo)
            Button("Salvar") { salvarComoMeuModelo(ficha) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Fica nos seus modelos e aparece primeiro na busca. Com o mesmo nome, substitui o anterior.")
        }
    }
}
