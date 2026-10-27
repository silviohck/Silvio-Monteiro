import AppKit
import DocxTemplateKit
import SwiftUI

struct ModelosView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var modeloParaExcluir: ModeloDocumento?
    @State private var arrastando = false
    @State private var aviso: String?
    @State private var pedindoCategoria = false
    @State private var novaCategoria = ""

    var body: some View {
        Form {
            pastaPrincipal
            if !armazenamento.biblioteca.isEmpty {
                Section("Modelos encontrados na pasta") {
                    ForEach(armazenamento.biblioteca) { grupo in
                        DisclosureGroup {
                            ForEach(grupo.tipos, id: \.self) { tipo in
                                DisclosureGroup {
                                    ForEach(grupo.modelos(do: tipo)) { modelo in
                                        linhaDoModelo(modelo)
                                    }
                                } label: {
                                    Label("\(tipo) (\(grupo.modelos(do: tipo).count))", systemImage: "folder")
                                }
                            }
                        } label: {
                            Label("\(grupo.nome) — \(grupo.modelos.count) modelos", systemImage: "folder.fill")
                        }
                    }
                }
            }
            ajuda
            importados
        }
        .formStyle(.grouped)
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
        .alert("Novo tipo de documento", isPresented: $pedindoCategoria) {
            TextField("Ex.: Atestados", text: $novaCategoria)
            Button("Adicionar") { armazenamento.adicionarCategoria(novaCategoria) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O tipo vira a subpasta onde os documentos gerados com o modelo são salvos.")
        }
        .confirmationDialog(
            "Excluir o modelo “\(modeloParaExcluir?.nome ?? "")”?",
            isPresented: Binding(get: { modeloParaExcluir != nil }, set: { if !$0 { modeloParaExcluir = nil } }),
            presenting: modeloParaExcluir
        ) { modelo in
            Button("Excluir", role: .destructive) { armazenamento.removerModelo(modelo) }
        } message: { _ in
            Text("A cópia do modelo guardada pelo app será apagada. Seu arquivo original não é afetado.")
        }
    }

    private var pastaPrincipal: some View {
        Section {
            LabeledContent("Pasta") {
                Text(armazenamento.urlPastaModelos.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Nenhuma pasta escolhida")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Button(armazenamento.urlPastaModelos == nil ? "Escolher pasta de modelos…" : "Trocar pasta…") {
                    if let url = escolherPasta(mensagem: "Escolha a pasta principal dos modelos.") {
                        armazenamento.definirPastaModelos(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                if let url = armazenamento.urlPastaModelos {
                    Button("Abrir no Finder") { NSWorkspace.shared.open(url) }
                    Button("Atualizar") { armazenamento.recarregarBiblioteca() }
                }
            }
        } header: {
            Text("Pasta de modelos")
        } footer: {
            Text("Cada subpasta da pasta principal é um local (ex.: OPERA PB, ARARUNA). Os arquivos .docx soltos nela aparecem como “Modelos gerais” e cada subpasta (LAUDO MÉDICO, RX…) vira um tipo. Os documentos gerados são salvos na pasta escolhida no cadastro do local, na subpasta do mesmo tipo; seus modelos nunca são alterados.")
                .foregroundStyle(.secondary)
        }
    }

    private func linhaDoModelo(_ modelo: ModeloDaPasta) -> some View {
        HStack {
            Label(modelo.nome, systemImage: "doc.text")
            Spacer()
            Button("Abrir no Word") { NSWorkspace.shared.open(modelo.url) }
                .buttonStyle(.link)
        }
    }

    private var ajuda: some View {
        Section("Como preparar um modelo") {
            Text("No Word, escreva os campos entre chaves duplas onde o texto deve ser trocado, por exemplo: Declaro que {{NOME_PACIENTE}}, CPF {{CPF}}, compareceu em {{DATA}}. Salve como .docx.")
            Text("Preenchidos automaticamente — paciente: NOME_PACIENTE (ou NOME), CPF, RG, DATA_NASCIMENTO, IDADE, TELEFONE, EMAIL, ENDERECO, CONVENIO; local de atendimento: LOCAL, LOCAL_ENDERECO, CIDADE, LOCAL_TELEFONE, LOCAL_EMAIL, CNPJ; data: DATA (dd/mm/aaaa) e DATA_EXTENSO (27 de outubro de 2026). Qualquer outro nome vira um campo para digitar, e o valor fica salvo no cadastro do paciente.")
                .foregroundStyle(.secondary)
        }
    }

    private var importados: some View {
        Section {
            HStack {
                Button {
                    importar(escolherArquivosDocx(multiplos: true))
                } label: {
                    Label("Importar modelo avulso…", systemImage: "square.and.arrow.down")
                }
                Button("Novo tipo de documento…") {
                    novaCategoria = ""
                    pedindoCategoria = true
                }
                Spacer()
                if let aviso {
                    Label(aviso, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            ForEach($armazenamento.dados.modelos) { $modelo in
                HStack {
                    TextField("Nome", text: $modelo.nome)
                        .labelsHidden()
                    Picker("Tipo", selection: $modelo.categoria) {
                        ForEach(categorias(incluindo: modelo.categoria), id: \.self) { categoria in
                            Text(categoria).tag(categoria)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                    Button("Abrir no Word") { NSWorkspace.shared.open(armazenamento.urlDoModelo(modelo)) }
                        .buttonStyle(.link)
                    Button("Excluir", role: .destructive) { modeloParaExcluir = modelo }
                        .buttonStyle(.link)
                }
            }
        } header: {
            Text("Modelos importados no app")
        } footer: {
            Text("Opcional: modelos avulsos, fora da pasta de modelos. Aparecem em “\(Armazenamento.grupoImportados)” na tela Gerar documento. Você também pode arrastar arquivos para esta janela.")
                .foregroundStyle(.secondary)
        }
    }

    private func categorias(incluindo atual: String) -> [String] {
        let lista = armazenamento.dados.categorias
        return lista.contains(atual) ? lista : lista + [atual]
    }

    private func importar(_ urls: [URL]) {
        aviso = nil
        var erros: [String] = []
        var importados: [String] = []
        for url in urls {
            do {
                try armazenamento.importarModelo(de: url)
                if let modelo = armazenamento.dados.modelos.last {
                    let campos = modelo.campos.count
                    importados.append("“\(modelo.nome)” (\(campos) \(campos == 1 ? "campo" : "campos"))")
                }
            } catch {
                erros.append(error.localizedDescription)
            }
        }
        if !importados.isEmpty {
            aviso = "Importado: " + importados.joined(separator: ", ")
        }
        if !erros.isEmpty {
            armazenamento.erro = erros.joined(separator: "\n\n")
        }
    }
}
