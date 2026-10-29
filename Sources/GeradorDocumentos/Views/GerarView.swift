import AppKit
import DocxTemplateKit
import SwiftUI
import UniformTypeIdentifiers

struct GerarView: View {
    @EnvironmentObject var armazenamento: Armazenamento
    @AppStorage("modeloSelecionado") var modeloSelecionado = ""
    @AppStorage("localSelecionado") var localSelecionado = ""
    @State var nomePaciente = ""
    @State var valores: [String: String] = [:]
    @State var abrirAoGerar = false
    /// Padrão: guardar para impressão ao final dos atendimentos.
    @AppStorage("acaoDepoisDeGerar") var acaoDepoisDeGerar = "fila"
    /// Cópias a imprimir; começa com o número definido no modelo e pode ser mudado aqui.
    @State var copias = 1
    @AppStorage("impressora") var impressora = ""
    @State var imprimindo = false
    @State var aviso: String?
    @State var ultimoDocumento: URL?
    /// Impede uma segunda geração idêntica por engano após concluir o documento.
    @State var geracaoConcluida = false
    /// Pasta escolhida em "Só este documento…"; volta para nil depois de gerar.
    @State var pastaAvulsa: URL?
    /// Subpasta = tipo do modelo (Receitas, Atestados…); filtra os modelos e é onde o documento é salvo.
    @AppStorage("subpastaSelecionada") var subpasta = ""
    @State var mostrandoCadastro = false
    @State var pacienteEmEdicao: Paciente.ID?
    @FocusState var focoNoNome: Bool
    /// Paciente escolhido quando há mais de um cadastro com o mesmo nome.
    @State var pacienteEscolhido: Paciente.ID?
    /// "É outro paciente": cria um cadastro novo mesmo com o nome já existente.
    @State var outroPaciente = false
    @State var nascimentoDoNovo = ""

    enum Escopo { case tudo, paciente, local }

    /// Nome e campos dos documentos vão sempre em maiúsculas (como com o Caps Lock ligado).
    static func maiusculas(_ texto: String) -> String {
        texto.uppercased(with: Locale(identifier: "pt_BR"))
    }

    /// O modelo guardado como escolhido, mesmo que não seja da subpasta mostrada.
    var modeloEscolhido: ModeloDocumento? {
        armazenamento.dados.modelos.first { $0.id.uuidString == modeloSelecionado }
    }

    /// O modelo que vale para gerar e imprimir: só o que está na tela — da subpasta mostrada e do local.
    /// Assim nunca sai um documento diferente do que aparece em "Modelo".
    var modelo: ModeloDocumento? {
        guard let escolhido = modeloEscolhido,
              escolhido.categoria == subpasta,
              armazenamento.modelos(para: local).contains(where: { $0.id == escolhido.id }) else { return nil }
        return escolhido
    }

    var local: LocalAtendimento? {
        armazenamento.dados.locais.first { $0.id.uuidString == localSelecionado }
    }

    var nomeDigitado: String {
        nomePaciente.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cadastros com exatamente o nome digitado (pode haver mais de um: homônimos).
    var homonimos: [Paciente] {
        armazenamento.pacientes(chamados: nomeDigitado)
    }

    /// O paciente escolhido; com nome repetido, só depois de você escolher qual é.
    var pacienteCadastrado: Paciente? {
        if outroPaciente { return nil }
        if let id = pacienteEscolhido, let escolhido = homonimos.first(where: { $0.id == id }) {
            return escolhido
        }
        return homonimos.count == 1 ? homonimos[0] : nil
    }

    /// Nome repetido e ainda não foi dito qual paciente é.
    var precisaEscolherPaciente: Bool {
        homonimos.count > 1 && pacienteCadastrado == nil && !outroPaciente
    }

    var sugestoes: [Paciente] {
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
            HStack(alignment: .top, spacing: 0) {
                formulario
                Divider()
                UltimosPacientes { documento in usarPacienteRecente(documento) }
                    .frame(width: 250)
            }
        }
    }

    var formulario: some View {
        Form {
            Section {
                quadroDoLocal
            }
            documentoPronto
            secaoDocumento
            secaoPaciente
            if let modelo {
                secaoCampos(modelo)
                secaoSalvar(modelo)
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
        .onChange(of: nomePaciente) { novo in
            // Sempre em maiúsculas, como nos documentos; a troca chama este onChange de novo.
            let emMaiusculas = GerarView.maiusculas(novo)
            if novo != emMaiusculas {
                nomePaciente = emMaiusculas
                return
            }
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
}
