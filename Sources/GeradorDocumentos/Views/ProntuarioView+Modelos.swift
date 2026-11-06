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
        ModelosDeAtendimento.buscar(buscaModelo, meus: armazenamento.dados.modelosDeAtendimento)
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

    func secaoModeloDeAtendimento(_ ficha: ModeloDocumento) -> some View {
        Section {
            HStack(spacing: 12) {
                TextField("Buscar doença ou CID (ex.: gonartrose, túnel do carpo, M54)", text: $buscaModelo)
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
                    if modelo.meu {
                        Button("Apagar este modelo", role: .destructive) { armazenamento.apagarModeloDeAtendimento(modelo) }
                    }
                }
            }
            if buscaModelo.trimmingCharacters(in: .whitespaces).count >= 2 && resultados.isEmpty {
                Text("Nenhum modelo encontrado.").foregroundStyle(.secondary)
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
            TituloSecao("Modelo de atendimento", icone: "text.book.closed.fill")
        } footer: {
            Text("Escolha o lado e clique no modelo: Q.P., H.D.A., exame físico, diagnóstico, CID e programação são preenchidos nas linhas da ficha. Complete os ___ e ajuste o que precisar. Os textos são pontos de partida.")
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
