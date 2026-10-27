import AppKit
import DocxTemplateKit
import SwiftUI
import UniformTypeIdentifiers

struct GerarView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @AppStorage("modeloSelecionado") private var modeloSelecionado = ""
    @AppStorage("localSelecionado") private var localSelecionado = ""
    @State private var nomePaciente = ""
    @State private var valores: [String: String] = [:]
    @State private var abrirAoGerar = false
    /// Padrão: guardar para impressão ao final dos atendimentos.
    @AppStorage("acaoDepoisDeGerar") private var acaoDepoisDeGerar = "fila"
    /// Cópias a imprimir; começa com o número definido no modelo e pode ser mudado aqui.
    @State private var copias = 1
    @AppStorage("impressora") private var impressora = ""
    @State private var imprimindo = false
    @State private var aviso: String?
    @State private var ultimoDocumento: URL?
    /// Impede uma segunda geração idêntica por engano após concluir o documento.
    @State private var geracaoConcluida = false
    /// Pasta escolhida em "Só este documento…"; volta para nil depois de gerar.
    @State private var pastaAvulsa: URL?
    /// Subpasta = tipo do modelo (Receitas, Atestados…); filtra os modelos e é onde o documento é salvo.
    @AppStorage("subpastaSelecionada") private var subpasta = ""
    @State private var mostrandoCadastro = false
    @State private var pacienteEmEdicao: Paciente.ID?
    @FocusState private var focoNoNome: Bool
    /// Paciente escolhido quando há mais de um cadastro com o mesmo nome.
    @State private var pacienteEscolhido: Paciente.ID?
    /// "É outro paciente": cria um cadastro novo mesmo com o nome já existente.
    @State private var outroPaciente = false
    @State private var nascimentoDoNovo = ""

    private enum Escopo { case tudo, paciente, local }

    private var modelo: ModeloDocumento? {
        armazenamento.dados.modelos.first { $0.id.uuidString == modeloSelecionado }
    }

    private var local: LocalAtendimento? {
        armazenamento.dados.locais.first { $0.id.uuidString == localSelecionado }
    }

    private var nomeDigitado: String {
        nomePaciente.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cadastros com exatamente o nome digitado (pode haver mais de um: homônimos).
    private var homonimos: [Paciente] {
        armazenamento.pacientes(chamados: nomeDigitado)
    }

    /// O paciente escolhido; com nome repetido, só depois de você escolher qual é.
    private var pacienteCadastrado: Paciente? {
        if outroPaciente { return nil }
        if let id = pacienteEscolhido, let escolhido = homonimos.first(where: { $0.id == id }) {
            return escolhido
        }
        return homonimos.count == 1 ? homonimos[0] : nil
    }

    /// Nome repetido e ainda não foi dito qual paciente é.
    private var precisaEscolherPaciente: Bool {
        homonimos.count > 1 && pacienteCadastrado == nil && !outroPaciente
    }

    private var sugestoes: [Paciente] {
        guard nomeDigitado.count >= 2, homonimos.isEmpty else { return [] }
        // Pacientes de todos os locais; os já atendidos no local escolhido vêm primeiro.
        let encontrados = armazenamento.pacientesOrdenados.filter {
            $0.nome.range(of: nomeDigitado, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        let daqui = encontrados.filter { paciente in
            armazenamento.locaisDoPaciente(paciente).contains { $0.id == local?.id }
        }
        let ids = Set(daqui.map(\.id))
        return Array((daqui + encontrados.filter { !ids.contains($0.id) }).prefix(8))
    }

    var body: some View {
        if armazenamento.dados.modelos.isEmpty {
            AvisoVazio(
                titulo: "Nenhum modelo importado",
                icone: "doc.text",
                mensagem: "Vá em “Modelos” e importe um arquivo .docx com campos como {{NOME_PACIENTE}}."
            )
        } else {
            formulario
        }
    }

    private var formulario: some View {
        Form {
            Section {
                quadroDoLocal
            }

            if let ultimoDocumento {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(Tema.sucesso)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Documento pronto").bold()
                            Text(ultimoDocumento.lastPathComponent)
                                .fonteApp(.apoio)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button(action: proximoPaciente) {
                            Label("Próximo paciente", systemImage: "arrow.uturn.left.circle.fill")
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Tema.sucesso)
                        .controlSize(.large)
                        .help("Recomeça do início para o próximo paciente (⇧⌘N). Só o local de atendimento continua.")
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                if armazenamento.modelos(para: local).isEmpty {
                    Text("Nenhum modelo para este local. Importe na aba “Modelos”.")
                        .fonteApp(.apoio)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Subpasta", selection: $subpasta) {
                        Text("Escolha…").tag("")
                        ForEach(subpastasDisponiveis, id: \.self) { tipo in
                            Text(tipo).tag(tipo)
                        }
                    }
                    Picker("Modelo", selection: $modeloSelecionado) {
                        if modeloSelecionado.isEmpty {
                            Text("Escolha…").tag("")
                        }
                        ForEach(modelosDaSubpasta) { modelo in
                            Text(modelo.nome).tag(modelo.id.uuidString)
                        }
                    }
                }
            } header: {
                TituloSecao("Documento", icone: "doc.text.fill")
            }

            Section {
                HStack {
                    TextField("Nome do paciente", text: $nomePaciente)
                        .focused($focoNoNome)
                    if !nomePaciente.isEmpty {
                        Button(action: limparPaciente) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Limpar o nome e os campos do paciente")
                    }
                    Button {
                        // Cola o nome copiado de outro lugar (sistema da clínica, mensagem…), numa linha só.
                        if let texto = NSPasteboard.general.string(forType: .string) {
                            nomePaciente = texto.components(separatedBy: .newlines)
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .first { !$0.isEmpty } ?? ""
                            focoNoNome = true
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .help("Colar o nome copiado")
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(nomeDigitado, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .disabled(nomeDigitado.isEmpty)
                    .help("Copiar o nome do paciente")
                    Button(action: abrirCadastro) {
                        Label("Cadastro", systemImage: pacienteCadastrado == nil ? "person.badge.plus" : "person.text.rectangle")
                    }
                    .controlSize(.small)
                    .disabled(nomeDigitado.isEmpty || precisaEscolherPaciente)
                    .help(pacienteCadastrado == nil ? "Criar o cadastro deste paciente e acrescentar informações" : "Abrir o cadastro do paciente para acrescentar informações")
                }
                if precisaEscolherPaciente {
                    escolhaDeHomonimo
                } else if let paciente = pacienteCadastrado {
                    Label(
                        "Paciente cadastrado · \(Armazenamento.identificacao(paciente)) — dados preenchidos abaixo",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                    .foregroundStyle(Tema.sucesso)
                    if let outro = localDeOrigem(paciente) {
                        Label("Paciente de \(outro) — o documento sai como \(local?.nome ?? "sem local") e fica na pasta deste local.", systemImage: "arrow.left.arrow.right")
                            .fonteApp(.apoio)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        if homonimos.count > 1 {
                            Button("Trocar de paciente") { pacienteEscolhido = nil }
                        }
                        Button("É outro paciente com o mesmo nome") { outroPaciente = true }
                    }
                    .buttonStyle(.link)
                    .fonteApp(.apoio)
                } else if outroPaciente {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Novo cadastro, diferente dos que já têm este nome.", systemImage: "person.badge.plus")
                        TextField("Data de nascimento (dd/mm/aaaa) — ajuda a diferenciar", text: $nascimentoDoNovo)
                        Button("Cancelar: é um paciente já cadastrado") {
                            outroPaciente = false
                            nascimentoDoNovo = ""
                        }
                        .buttonStyle(.link)
                        .fonteApp(.apoio)
                    }
                } else if !nomeDigitado.isEmpty {
                    ForEach(sugestoes) { paciente in
                        Button {
                            nomePaciente = paciente.nome
                            pacienteEscolhido = paciente.id
                        } label: {
                            Label(textoDaSugestao(paciente), systemImage: "person.crop.circle")
                        }
                        .buttonStyle(.link)
                    }
                    Text("Paciente novo: o cadastro será criado ao gerar o documento.")
                        .fonteApp(.apoio)
                        .foregroundStyle(.secondary)
                }
            } header: {
                TituloSecao("Paciente", icone: "person.fill")
            }

            if let modelo {
                let campos = modelo.campos.filter { !CamposAutomaticos.ehNomeDoPaciente($0) }
                Section {
                    if campos.isEmpty {
                        Text("Nenhum outro campo para preencher neste modelo.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(campos, id: \.self) { campo in
                        TextField(campo, text: valor(campo), axis: .vertical)
                            .lineLimit(1...5)
                    }
                } header: {
                    TituloSecao("Campos do documento", icone: "list.bullet.rectangle.fill")
                } footer: {
                    Text("Preenchidos com o cadastro do paciente, o local e a data de hoje. Você pode alterar qualquer valor. Só os dados gerais (CPF, nascimento, contato) ficam no cadastro; campos como CID valem só para este documento.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Será salvo em")
                            if pastaAvulsa != nil {
                                Text("(só este documento)").fonteApp(.legenda).foregroundStyle(.secondary)
                            }
                        }
                        Text(caminhoAbreviado(pastaDeDestino))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(pastaDeDestino.path)
                        if pastaAvulsa == nil {
                            Text(situacaoDasPastas)
                                .fonteApp(.legenda)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Button {
                                if let url = escolherPasta(mensagem: "Escolha a pasta principal. Dentro dela, o app usa (ou cria) uma pasta para cada local e, dentro desta, uma pasta para cada tipo de documento.") {
                                    armazenamento.dados.pastaDocumentos = url.path
                                    if let local, !local.pasta.isEmpty {
                                        // A pasta principal passa a valer também para este local.
                                        var semPastaPropria = local
                                        semPastaPropria.pasta = ""
                                        armazenamento.atualizarLocal(semPastaPropria)
                                    }
                                    pastaAvulsa = nil
                                }
                            } label: {
                                Label("Escolher pasta principal…", systemImage: "folder.badge.gearshape")
                            }
                            .buttonStyle(.bordered)
                            Menu("Mais opções") {
                                if let local {
                                    Button("Usar outra pasta só para \(local.nome.isEmpty ? "este local" : local.nome)…") {
                                        if let url = escolherPasta(mensagem: "Escolha a pasta de \(local.nome.isEmpty ? "este local" : local.nome). Se ela não tiver o nome do local, o app cria a pasta do local dentro dela.") {
                                            armazenamento.definirPasta(url, doLocal: local.id)
                                            pastaAvulsa = nil
                                        }
                                    }
                                    if !local.pasta.isEmpty {
                                        Button("Voltar a usar a pasta principal") {
                                            var semPastaPropria = local
                                            semPastaPropria.pasta = ""
                                            armazenamento.atualizarLocal(semPastaPropria)
                                        }
                                    }
                                }
                                Button("Só este documento…") {
                                    pastaAvulsa = escolherPasta(mensagem: "Escolha onde salvar só este documento.")
                                }
                                if pastaAvulsa != nil {
                                    Button("Voltar para a pasta do local") { pastaAvulsa = nil }
                                }
                            }
                            .fixedSize()
                            Button("Abrir no Finder") { abrirPasta(pastaDeDestino) }
                        }
                    }
                    .padding(.vertical, 4)
                    Toggle("Abrir o documento depois de gerar", isOn: $abrirAoGerar)
                    HStack {
                        Picker("Depois de gerar", selection: $acaoDepoisDeGerar) {
                            Text("Adicionar à fila de impressão").tag("fila")
                            Text("Imprimir agora").tag("imprimir")
                            Text("Só salvar").tag("salvar")
                        }
                        .pickerStyle(.menu)
                        Spacer()
                        Stepper(value: $copias, in: 1...20) {
                            Text("\(copias) \(copias == 1 ? "cópia" : "cópias")")
                                .monospacedDigit()
                        }
                        .fixedSize()
                        .help("Quantas cópias guardar na fila ou enviar à impressora")
                    }
                    if acaoDepoisDeGerar == "fila" {
                        Text("O Word será salvo normalmente e ficará aguardando na aba Fila de impressão.")
                            .fonteApp(.apoio)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        if let aviso {
                            Label(aviso, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Tema.sucesso)
                            if let ultimoDocumento {
                                Button("Mostrar no Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([ultimoDocumento])
                                }
                                .buttonStyle(.link)
                                Button(imprimindo ? "Enviando…" : "Imprimir agora") {
                                    imprimir(ultimoDocumento)
                                }
                                .buttonStyle(.link)
                                .disabled(imprimindo || armazenamento.processandoFila
                                    || armazenamento.dados.filaImpressao.contains(where: {
                                        $0.caminho == ultimoDocumento.path && $0.situacao != .pendente
                                    }))
                            }
                        }
                        Spacer()
                        Button(action: proximoPaciente) {
                            Label("Próximo paciente", systemImage: "arrow.uturn.left.circle.fill")
                        }
                        .controlSize(.large)
                        .tint(Tema.sucesso)
                        .buttonStyle(.borderedProminent)
                        .opacity(ultimoDocumento == nil ? 0.6 : 1)
                        .help("Recomeça do início para o próximo paciente (⇧⌘N). Só o local de atendimento continua.")
                        Button("Gerar documento") { gerar(modelo) }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(
                                geracaoConcluida
                                    || precisaEscolherPaciente
                                    || (nomeDigitado.isEmpty && modelo.campos.contains(where: CamposAutomaticos.ehNomeDoPaciente))
                            )
                            .help(geracaoConcluida
                                ? "Este documento já foi gerado. Altere os dados, escolha outro modelo ou clique em Próximo paciente."
                                : (precisaEscolherPaciente ? "Escolha qual dos pacientes com este nome é o certo" : ""))
                            .controlSize(.large)
                    }
                } header: {
                    TituloSecao("Salvar e imprimir", icone: "square.and.arrow.down.fill")
                }
            }
        }
        .formStyle(.grouped)
        .fundoSuave()
        .onAppear {
            if local == nil { localSelecionado = "" }
            validarModelo()
            preencher(.tudo)
            copias = armazenamento.dados.modelos.first { $0.id.uuidString == modeloSelecionado }?.copias ?? 1
            focoNoNome = true
        }
        .onChange(of: nomePaciente) { _ in
            // Outro nome depois de gerar = outro paciente: os campos do documento anterior não seguem
            // (o cadastro pode continuar nil entre dois pacientes novos). Antes de gerar, corrigir
            // o nome não apaga o que já foi digitado nos campos.
            let acabouDeGerar = geracaoConcluida || ultimoDocumento != nil
            aviso = nil
            ultimoDocumento = nil
            geracaoConcluida = false
            if acabouDeGerar {
                valores = [:]
                preencher(.tudo)
            }
            // Nome mudou: a escolha entre homônimos só vale se ainda for o mesmo nome.
            if let id = pacienteEscolhido, !homonimos.contains(where: { $0.id == id }) {
                pacienteEscolhido = nil
            }
            if homonimos.isEmpty {
                outroPaciente = false
                nascimentoDoNovo = ""
            }
        }
        .onChange(of: modeloSelecionado) { id in
            geracaoConcluida = false
            aviso = nil
            ultimoDocumento = nil
            valores = [:]
            preencher(.tudo)
            copias = armazenamento.dados.modelos.first { $0.id.uuidString == id }?.copias ?? 1
        }
        .onChange(of: subpasta) { _ in
            geracaoConcluida = false
            aviso = nil
            ultimoDocumento = nil
            valores = [:]
            validarModelo()
            preencher(.tudo)
        }
        .sheet(isPresented: $mostrandoCadastro, onDismiss: voltarDoCadastro) {
            if let id = pacienteEmEdicao {
                CadastroPacienteSheet(id: id)
                    .environmentObject(armazenamento)
            }
        }
        .onChange(of: pacienteCadastrado?.id) { _ in preencher(.paciente) }
        .onChange(of: localSelecionado) { _ in
            // Um local diferente inicia novo contexto; evita carregar campos do documento anterior.
            aviso = nil
            ultimoDocumento = nil
            geracaoConcluida = false
            valores = [:]
            validarModelo()
            preencher(.tudo)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: proximoPaciente) {
                    Label("Próximo paciente", systemImage: "arrow.uturn.left.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Próximo paciente (⇧⌘N): recomeça do início, mantendo só o local de atendimento")
            }
        }
    }

    /// Tipos que têm modelos para o local escolhido, na ordem cadastrada.
    private var subpastasDisponiveis: [String] {
        var tipos: [String] = []
        for modelo in armazenamento.modelos(para: local) where !tipos.contains(modelo.categoria) {
            tipos.append(modelo.categoria)
        }
        return tipos
    }

    private var modelosDaSubpasta: [ModeloDocumento] {
        armazenamento.modelos(para: local)
            .filter { $0.categoria == subpasta }
            .sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
    }

    /// Mantém subpasta e modelo coerentes com o local: a subpasta precisa ter modelos
    /// e o modelo precisa ser dessa subpasta.
    /// Subpasta vazia = ainda não escolhida (depois de "Próximo paciente").
    private func validarModelo() {
        let tipos = subpastasDisponiveis
        if !subpasta.isEmpty && !tipos.contains(subpasta) {
            subpasta = modelo.map(\.categoria).flatMap { tipos.contains($0) ? $0 : nil } ?? ""
        }
        let modelos = modelosDaSubpasta
        guard !subpasta.isEmpty else {
            modeloSelecionado = ""
            return
        }
        if !modelos.contains(where: { $0.id.uuidString == modeloSelecionado }) {
            // Ao trocar de local, fica com o modelo de mesmo nome deste local, se houver.
            let mesmoNome = modelo.flatMap { anterior in modelos.first { $0.nome == anterior.nome } }
            modeloSelecionado = (mesmoNome ?? modelos.first)?.id.uuidString ?? ""
        }
    }

    /// Imprime já, com o número de cópias escolhido, passando pela fila (sem concorrer com "Imprimir todos").
    /// Impressão manual usa a mesma fila, evitando concorrência com "Imprimir todos".
    private func imprimir(_ arquivo: URL) {
        guard !imprimindo, !armazenamento.processandoFila else { return }
        guard let documento = armazenamento.dados.historico.first(where: { $0.caminho == arquivo.path }) else { return }
        let id = armazenamento.adicionarAFila(documento, copias: copias)
        guard armazenamento.dados.filaImpressao.contains(where: { $0.id == id && $0.situacao == .pendente }) else {
            armazenamento.erro = "Este documento já foi enviado ou precisa de confirmação de reenvio. Veja a aba Fila de impressão."
            return
        }
        imprimindo = true
        Task {
            await armazenamento.imprimirFila(ids: Set([id]), impressora: impressora)
            imprimindo = false
        }
    }

    /// Quadro em destaque no topo: em qual local você está atendendo.
    private var quadroDoLocal: some View {
        HStack(spacing: 14) {
            Image(systemName: "building.2")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(local == nil ? Color.orange : Tema.destaque)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Tema.superficie.opacity(0.74)))
            VStack(alignment: .leading, spacing: 3) {
                Text("LOCAL DE ATENDIMENTO")
                    .fonteApp(.legenda)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text(local.map { $0.nome.isEmpty ? "Local sem nome" : $0.nome } ?? "Escolha o local")
                    .fonteApp(.destaque)
                    .fontWeight(.bold)
                    // O local continua bem marcado: é o que mais importa conferir antes de gerar.
                    .foregroundStyle(local == nil ? Color.orange : Tema.destaque)
                    .lineLimit(1)
                if armazenamento.dados.locais.isEmpty {
                    Text("Cadastre seus locais na aba “Locais de atendimento”.")
                        .fonteApp(.apoio)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("Trocar local", selection: $localSelecionado) {
                Text("Nenhum").tag("")
                ForEach(armazenamento.locaisOrdenados) { local in
                    Text(local.nome.isEmpty ? "Sem nome" : local.nome).tag(local.id.uuidString)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
            .help("Trocar o local de atendimento")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Tema.destaqueSuave))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tema.borda.opacity(0.7), lineWidth: 1))
    }

    /// "Pastas já existentes" ou quais serão criadas (pasta do local e/ou do tipo).
    private var situacaoDasPastas: String {
        let fm = FileManager.default
        let pastaDoLocal = armazenamento.pastaDoLocal(local)
        var novas: [String] = []
        if !fm.fileExists(atPath: pastaDoLocal.path) { novas.append("“\(pastaDoLocal.lastPathComponent)”") }
        if pastaDeDestino != pastaDoLocal, !fm.fileExists(atPath: pastaDeDestino.path) {
            novas.append("“\(pastaDeDestino.lastPathComponent)”")
        }
        if novas.isEmpty { return "Pasta do local e do tipo já existem; o arquivo vai direto para lá." }
        return "Será criada ao gerar: " + novas.joined(separator: " e ") + "."
    }

    private var pastaDeDestino: URL {
        pastaAvulsa ?? armazenamento.pastaDosDocumentos(subpasta: modelo?.categoria ?? subpasta, local: local)
    }

    /// Nome repetido: lista os cadastros com data de nascimento e CPF para escolher o certo.
    private var escolhaDeHomonimo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Há \(homonimos.count) pacientes chamados “\(nomeDigitado)”. Qual deles é?", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            ForEach(homonimos) { paciente in
                Button {
                    pacienteEscolhido = paciente.id
                } label: {
                    Label(
                        [Armazenamento.identificacao(paciente), armazenamento.nomesDosLocais(paciente)]
                            .filter { !$0.isEmpty }.joined(separator: " · "),
                        systemImage: "person.crop.circle"
                    )
                }
                .buttonStyle(.link)
            }
            Button("É outro paciente (novo cadastro)") { outroPaciente = true }
                .buttonStyle(.link)
            if homonimos.contains(where: { $0.dataNascimento.trimmingCharacters(in: .whitespaces).isEmpty }) {
                Text("Dica: cadastre a data de nascimento desses pacientes para diferenciá-los com segurança.")
                    .fonteApp(.apoio)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Nome do local do cadastro, quando o paciente é de outro local.
    private func localDeOrigem(_ paciente: Paciente) -> String? {
        guard let origem = armazenamento.local(paciente.localID), origem.id != local?.id else { return nil }
        return origem.nome.isEmpty ? "outro local" : origem.nome
    }

    private func textoDaSugestao(_ paciente: Paciente) -> String {
        var texto = "Usar o cadastro de \(paciente.nome) (\(Armazenamento.identificacao(paciente)))"
        let locais = armazenamento.nomesDosLocais(paciente)
        if !locais.isEmpty { texto += " · \(locais)" }
        return texto
    }

    /// Cadastro novo com o nome digitado (e a data de nascimento informada, se for homônimo).
    private func criarPaciente() -> Paciente {
        var paciente = armazenamento.novoPaciente(nome: nomeDigitado)
        paciente.localID = local?.id
        let nascimento = nascimentoDoNovo.trimmingCharacters(in: .whitespaces)
        if !nascimento.isEmpty { paciente.dataNascimento = nascimento }
        armazenamento.atualizarPaciente(paciente)
        pacienteEscolhido = paciente.id
        outroPaciente = false
        nascimentoDoNovo = ""
        return paciente
    }

    /// Abre o cadastro do paciente digitado, criando-o se ainda não existir.
    private func abrirCadastro() {
        guard !precisaEscolherPaciente else { return }
        let paciente = pacienteCadastrado ?? criarPaciente()
        pacienteEmEdicao = paciente.id
        mostrandoCadastro = true
    }

    /// Depois de editar o cadastro: acompanha mudança de nome e recarrega os dados no formulário.
    private func voltarDoCadastro() {
        if let id = pacienteEmEdicao, let paciente = armazenamento.paciente(id), !paciente.nome.isEmpty {
            nomePaciente = paciente.nome
            pacienteEscolhido = id
        }
        pacienteEmEdicao = nil
        preencher(.paciente)
    }

    private func valor(_ campo: String) -> Binding<String> {
        Binding(
            get: { valores[campo, default: ""] },
            set: { novoValor in
                valores[campo] = novoValor
                geracaoConcluida = false
                aviso = nil
                ultimoDocumento = nil
            }
        )
    }

    /// Recomeça do início para o próximo atendimento: limpa paciente, subpasta e modelo;
    /// só o local de atendimento (e as opções de abrir e imprimir) continuam.
    private func proximoPaciente() {
        geracaoConcluida = false
        subpasta = ""
        modeloSelecionado = ""
        limparPaciente()
    }

    /// Limpa nome, identificação e campos clínicos.
    private func limparPaciente() {
        geracaoConcluida = false
        nomePaciente = ""
        pacienteEscolhido = nil
        outroPaciente = false
        nascimentoDoNovo = ""
        pastaAvulsa = nil
        aviso = nil
        ultimoDocumento = nil
        valores = [:]
        preencher(.tudo)
        copias = modelo?.copias ?? 1
        focoNoNome = true
    }

    /// Recalcula os campos; ao trocar o paciente, os dados do local não são apagados (e vice-versa).
    private func preencher(_ escopo: Escopo) {
        guard let modelo else { return }
        for campo in modelo.campos where !CamposAutomaticos.ehNomeDoPaciente(campo) {
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

    private func gerar(_ modelo: ModeloDocumento) {
        guard !geracaoConcluida, !precisaEscolherPaciente else { return }
        // O documento vai para a subpasta do próprio modelo; a caixa "Subpasta" pode estar
        // desatualizada (ex.: a sincronização reorganizou as pastas) sem que o modelo esteja errado.
        guard armazenamento.modelos(para: local).contains(where: { $0.id == modelo.id }) else {
            armazenamento.erro = "Este modelo não é do local escolhido. Escolha a subpasta e o modelo de novo."
            return
        }
        let nome = nomeDigitado
        var valoresFinais = valores
        for campo in modelo.campos where CamposAutomaticos.ehNomeDoPaciente(campo) {
            valoresFinais[campo] = nome
        }

        let destino: URL
        do {
            destino = try armazenamento.caminhoParaNovoDocumento(
                modelo: modelo, subpasta: modelo.categoria, local: local, paciente: nome, pastaAvulsa: pastaAvulsa
            )
            try DocxTemplate.fill(template: armazenamento.urlDoModelo(modelo), values: valoresFinais, output: destino)
        } catch {
            armazenamento.erro = error.localizedDescription
            return
        }

        var pacienteID: UUID?
        if !nome.isEmpty {
            var paciente = pacienteCadastrado ?? criarPaciente()
            pacienteID = paciente.id
            if armazenamento.local(paciente.localID) == nil {
                paciente.localID = local?.id
            }
            CamposAutomaticos.guardar(valoresFinais, campos: modelo.campos, em: &paciente)
            armazenamento.atualizarPaciente(paciente)
        }
        let documento = DocumentoGerado(
            modelo: modelo.nome, modeloID: modelo.id, paciente: nome, pacienteID: pacienteID,
            local: local?.nome, caminho: destino.path
        )
        armazenamento.registrar(documento)
        // O nome do paciente fica copiado, pronto para colar (⌘V) em outro sistema.
        if !nome.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(nome, forType: .string)
        }
        aviso = nome.isEmpty ? "Salvo: \(destino.lastPathComponent)" : "Salvo: \(destino.lastPathComponent) · nome copiado"
        ultimoDocumento = destino
        geracaoConcluida = true
        pastaAvulsa = nil
        let copiado = nome.isEmpty ? "" : " · nome copiado"
        if acaoDepoisDeGerar == "fila" || acaoDepoisDeGerar == "imprimir" {
            let jaImprimindo = armazenamento.processandoFila
            let id = armazenamento.adicionarAFila(documento, copias: copias)
            if acaoDepoisDeGerar == "imprimir" && !jaImprimindo {
                aviso = "Salvo e enviado para impressão\(copiado)"
                let manterAberto = abrirAoGerar
                Task {
                    await armazenamento.imprimirFila(ids: Set([id]), impressora: impressora, manterAberto: manterAberto)
                }
            } else if acaoDepoisDeGerar == "imprimir" {
                aviso = "Salvo; a fila está imprimindo, este entra na fila (\(armazenamento.pendentesNaFila) aguardando)\(copiado)"
            } else {
                aviso = "Salvo e na fila de impressão (\(armazenamento.pendentesNaFila) aguardando)\(copiado)"
            }
        }
        if abrirAoGerar {
            NSWorkspace.shared.open(destino)
        }
    }

    /// "/Users/silvio/Documents/…" → "~/Documents/…"
    private func caminhoAbreviado(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func abrirPasta(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
