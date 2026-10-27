import AppKit
import DocxTemplateKit
import SwiftUI

struct GerarView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @AppStorage("grupoSelecionado") private var grupoSelecionado = ""
    @AppStorage("tipoSelecionado") private var tipoSelecionado = ""
    @AppStorage("modeloDaPastaSelecionado") private var modeloSelecionado = ""
    @AppStorage("localSelecionado") private var localSelecionado = ""
    @State private var nomePaciente = ""
    @State private var campos: [String] = []
    @State private var erroCampos: String?
    @State private var valores: [String: String] = [:]
    @State private var abrirAoGerar = true
    @State private var aviso: String?
    @State private var ultimoDocumento: URL?
    @FocusState private var focoNoNome: Bool

    private enum Escopo { case tudo, paciente, local }

    private var grupo: GrupoDeModelos? { armazenamento.grupo(grupoSelecionado) }

    private var modelo: ModeloDaPasta? {
        grupo?.modelos.first { $0.id == modeloSelecionado }
    }

    private var local: LocalAtendimento? {
        armazenamento.dados.locais.first { $0.id.uuidString == localSelecionado }
    }

    private var nomeDigitado: String {
        nomePaciente.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pacienteCadastrado: Paciente? {
        armazenamento.paciente(chamado: nomeDigitado)
    }

    private var sugestoes: [Paciente] {
        guard nomeDigitado.count >= 2, pacienteCadastrado == nil else { return [] }
        return Array(armazenamento.pacientesOrdenados.filter {
            $0.nome.range(of: nomeDigitado, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }.prefix(6))
    }

    var body: some View {
        if armazenamento.grupos.isEmpty {
            AvisoVazio(
                titulo: "Escolha a pasta dos seus modelos",
                icone: "folder",
                mensagem: "Selecione a pasta principal onde ficam os modelos do Word, organizados em subpastas por local (ex.: OPERA PB, ARARUNA) e por tipo (ex.: LAUDO MÉDICO, RX).",
                botao: "Escolher pasta de modelos…",
                acao: {
                    if let url = escolherPasta(mensagem: "Escolha a pasta principal dos modelos.") {
                        armazenamento.definirPastaModelos(url)
                    }
                }
            )
        } else {
            HSplitView {
                navegador
                    .frame(minWidth: 480, idealWidth: 560)
                formulario
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                validarSelecao()
                carregarCampos()
                focoNoNome = true
            }
            .onChange(of: grupoSelecionado) { _ in
                if let vinculado = armazenamento.local(doGrupo: grupoSelecionado) {
                    localSelecionado = vinculado.id.uuidString
                }
                validarSelecao()
            }
            .onChange(of: tipoSelecionado) { _ in validarSelecao() }
            .onChange(of: modeloSelecionado) { _ in carregarCampos() }
            .onChange(of: pacienteCadastrado?.id) { _ in preencher(.paciente) }
            .onChange(of: localSelecionado) { _ in preencher(.local) }
            .onChange(of: nomePaciente) { _ in
                aviso = nil
                ultimoDocumento = nil
            }
            .toolbar {
                Button {
                    armazenamento.recarregarBiblioteca()
                    validarSelecao()
                    carregarCampos()
                } label: {
                    Label("Atualizar modelos", systemImage: "arrow.clockwise")
                }
                .help("Lê de novo a pasta de modelos (depois de criar ou editar modelos no Finder ou no Word)")
            }
        }
    }

    // MARK: Colunas (como no Finder)

    private var navegador: some View {
        HStack(spacing: 0) {
            coluna("Local") {
                List(armazenamento.grupos, selection: selecao($grupoSelecionado)) { grupo in
                    Label(grupo.nome, systemImage: grupo.nome == Armazenamento.grupoImportados ? "tray" : "folder")
                }
            }
            Divider()
            coluna("Pasta") {
                List(grupo?.tipos ?? [], id: \.self, selection: selecao($tipoSelecionado)) { tipo in
                    Label(tipo, systemImage: tipo == Biblioteca.tipoGeral ? "doc.on.doc" : "folder")
                }
            }
            Divider()
            coluna("Modelo") {
                List(grupo?.modelos(do: tipoSelecionado) ?? [], selection: selecao($modeloSelecionado)) { modelo in
                    Label(modelo.nome, systemImage: "doc.text")
                        .help(modelo.url.lastPathComponent)
                }
            }
        }
    }

    private func coluna<Conteudo: View>(_ titulo: String, @ViewBuilder _ conteudo: () -> Conteudo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(titulo.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            conteudo()
        }
        .frame(minWidth: 150, maxWidth: .infinity)
    }

    private func selecao(_ valor: Binding<String>) -> Binding<String?> {
        Binding(
            get: { valor.wrappedValue.isEmpty ? nil : valor.wrappedValue },
            set: { valor.wrappedValue = $0 ?? "" }
        )
    }

    // MARK: Formulário

    private var formulario: some View {
        Form {
            Section("Paciente") {
                HStack {
                    TextField("Nome do paciente", text: $nomePaciente)
                        .focused($focoNoNome)
                    if !nomePaciente.isEmpty {
                        Button {
                            nomePaciente = ""
                            focoNoNome = true
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Limpar para o próximo paciente")
                    }
                }
                if let paciente = pacienteCadastrado {
                    Label(
                        "Paciente cadastrado" + (paciente.cpf.isEmpty ? "" : " · CPF \(paciente.cpf)") + " — dados preenchidos abaixo",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                    .foregroundStyle(.green)
                } else if !nomeDigitado.isEmpty {
                    ForEach(sugestoes) { paciente in
                        Button {
                            nomePaciente = paciente.nome
                        } label: {
                            Label("Usar o cadastro de \(paciente.nome)", systemImage: "person.crop.circle")
                        }
                        .buttonStyle(.link)
                    }
                    Text("Paciente novo: o cadastro será criado ao gerar o documento.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Local de atendimento") {
                Picker("Local", selection: $localSelecionado) {
                    Text("Nenhum").tag("")
                    ForEach(armazenamento.locaisOrdenados) { local in
                        Text(local.nome.isEmpty ? "Sem nome" : local.nome).tag(local.id.uuidString)
                    }
                }
                if local == nil {
                    Text("Sem local, os campos {{LOCAL}}, {{CIDADE}} etc. ficam vazios. Cadastre seus locais na aba “Locais de atendimento”.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let modelo {
                camposDoModelo(modelo)
                salvar(modelo)
            } else {
                Section {
                    Text("Escolha um modelo nas colunas ao lado.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func camposDoModelo(_ modelo: ModeloDaPasta) -> some View {
        let visiveis = campos.filter { !CamposAutomaticos.ehNomeDoPaciente($0) }
        Section {
            if let erroCampos {
                Label(erroCampos, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else if campos.isEmpty {
                Text("Este modelo ainda não tem campos {{...}}: o documento será uma cópia sem alterações. Abra o modelo no Word e troque o nome do paciente por {{NOME_PACIENTE}} (e a data por {{DATA}}, etc.).")
                    .foregroundStyle(.secondary)
            }
            ForEach(visiveis, id: \.self) { campo in
                TextField(campo, text: valor(campo), axis: .vertical)
                    .lineLimit(1...5)
            }
            HStack {
                Button("Abrir modelo no Word") { NSWorkspace.shared.open(modelo.url) }
                Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([modelo.url]) }
            }
            .buttonStyle(.link)
        } header: {
            Text(modelo.nome)
        } footer: {
            if !visiveis.isEmpty {
                Text("Preenchidos com o cadastro do paciente, o local e a data de hoje. O que você digitar fica salvo no cadastro do paciente.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func salvar(_ modelo: ModeloDaPasta) -> some View {
        let pasta = armazenamento.pastaDosDocumentos(modelo: modelo, grupo: grupoSelecionado, local: local)
        return Section {
            LabeledContent("Será salvo em") {
                HStack {
                    Text((pasta.path as NSString).abbreviatingWithTildeInPath)
                        .foregroundStyle(.secondary)
                        .truncationMode(.head)
                        .lineLimit(1)
                        .help(pasta.path)
                    Button {
                        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(pasta)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Abrir esta pasta no Finder")
                }
            }
            Toggle("Abrir o documento depois de gerar", isOn: $abrirAoGerar)
            HStack {
                if let aviso {
                    Label(aviso, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let ultimoDocumento {
                        Button("Mostrar no Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([ultimoDocumento])
                        }
                        .buttonStyle(.link)
                    }
                }
                Spacer()
                Button("Gerar documento") { gerar(modelo) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(nomeDigitado.isEmpty && campos.contains(where: CamposAutomaticos.ehNomeDoPaciente))
            }
        }
    }

    private func valor(_ campo: String) -> Binding<String> {
        Binding(get: { valores[campo, default: ""] }, set: { valores[campo] = $0 })
    }

    // MARK: Ações

    /// Garante que local, pasta e modelo escolhidos existem (a pasta pode ter mudado no Finder).
    private func validarSelecao() {
        guard let primeiro = armazenamento.grupos.first else { return }
        if grupo == nil { grupoSelecionado = primeiro.nome }
        guard let grupo else { return }
        if !grupo.tipos.contains(tipoSelecionado) { tipoSelecionado = grupo.tipos.first ?? "" }
        if !grupo.modelos(do: tipoSelecionado).contains(where: { $0.id == modeloSelecionado }) {
            modeloSelecionado = ""
        }
        if local == nil, let vinculado = armazenamento.local(doGrupo: grupo.nome) {
            localSelecionado = vinculado.id.uuidString
        }
    }

    private func carregarCampos() {
        aviso = nil
        ultimoDocumento = nil
        if let modelo {
            do {
                campos = try armazenamento.campos(de: modelo)
                erroCampos = nil
            } catch {
                campos = []
                erroCampos = error.localizedDescription
            }
        } else {
            campos = []
            erroCampos = nil
        }
        preencher(.tudo)
    }

    /// Recalcula os campos; ao trocar o local, os dados do paciente já digitados não são apagados (e vice-versa).
    private func preencher(_ escopo: Escopo) {
        for campo in campos where !CamposAutomaticos.ehNomeDoPaciente(campo) {
            var doLocal = false
            if case .local = CamposAutomaticos.mapa[CamposAutomaticos.chave(campo)] {
                doLocal = true
            }
            let atualizar = escopo == .tudo || (escopo == .local) == doLocal
            if atualizar {
                valores[campo] = CamposAutomaticos.valor(para: campo, paciente: pacienteCadastrado, local: local) ?? ""
            }
        }
    }

    private func gerar(_ modelo: ModeloDaPasta) {
        let nome = nomeDigitado
        var valoresFinais = valores
        for campo in campos where CamposAutomaticos.ehNomeDoPaciente(campo) {
            valoresFinais[campo] = nome
        }

        let destino: URL
        do {
            destino = try armazenamento.caminhoParaNovoDocumento(modelo: modelo, grupo: grupoSelecionado, local: local, paciente: nome)
            try armazenamento.gerarDocumento(modelo, valores: valoresFinais, destino: destino)
        } catch {
            armazenamento.erro = error.localizedDescription
            return
        }

        if !nome.isEmpty {
            var paciente = pacienteCadastrado ?? armazenamento.novoPaciente(nome: nome)
            CamposAutomaticos.guardar(valoresFinais, campos: campos, em: &paciente)
            armazenamento.atualizarPaciente(paciente)
        }
        armazenamento.registrar(DocumentoGerado(
            modelo: modelo.nome,
            paciente: nome,
            local: local?.nome ?? grupoSelecionado,
            caminho: destino.path
        ))
        aviso = "Salvo: \(destino.lastPathComponent)"
        ultimoDocumento = destino
        if abrirAoGerar {
            NSWorkspace.shared.open(destino)
        }
    }
}
