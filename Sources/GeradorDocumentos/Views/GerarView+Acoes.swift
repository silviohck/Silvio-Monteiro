import AppKit
import DocxTemplateKit
import SwiftUI

/// O que a tela Gerar documento faz: escolher subpasta e modelo, preencher campos, gerar e imprimir.
extension GerarView {
    /// Tipos que têm modelos para o local escolhido, na ordem cadastrada.
    var subpastasDisponiveis: [String] {
        var tipos: [String] = []
        for modelo in armazenamento.modelos(para: local) where !tipos.contains(modelo.categoria) {
            tipos.append(modelo.categoria)
        }
        return tipos
    }

    var modelosDaSubpasta: [ModeloDocumento] {
        armazenamento.modelos(para: local)
            .filter { $0.categoria == subpasta }
            .sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
    }

    /// Mantém subpasta e modelo coerentes com o local: a subpasta precisa ter modelos
    /// e o modelo precisa ser dessa subpasta.
    /// Subpasta vazia = ainda não escolhida (depois de "Próximo paciente").
    func validarModelo() {
        let tipos = subpastasDisponiveis
        if !subpasta.isEmpty && !tipos.contains(subpasta) {
            subpasta = modeloEscolhido.map(\.categoria).flatMap { tipos.contains($0) ? $0 : nil } ?? ""
        }
        let modelos = modelosDaSubpasta
        guard !subpasta.isEmpty else {
            modeloSelecionado = ""
            return
        }
        if !modelos.contains(where: { $0.id.uuidString == modeloSelecionado }) {
            // Ao trocar de local, fica com o modelo de mesmo nome deste local, se houver.
            let mesmoNome = modeloEscolhido.flatMap { anterior in modelos.first { $0.nome == anterior.nome } }
            modeloSelecionado = (mesmoNome ?? modelos.first)?.id.uuidString ?? ""
        }
    }

    /// Imprime já, com o número de cópias escolhido, passando pela fila (sem concorrer com "Imprimir todos").
    /// Impressão manual usa a mesma fila, evitando concorrência com "Imprimir todos".
    func imprimir(_ arquivo: URL) {
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

    func valor(_ campo: String) -> Binding<String> {
        Binding(
            get: { valores[campo, default: ""] },
            set: { novoValor in
                valores[campo] = GerarView.maiusculas(novoValor)
                geracaoConcluida = false
                aviso = nil
                ultimoDocumento = nil
            }
        )
    }

    /// Clique num paciente da lista "Últimos pacientes": preenche o nome e escolhe o cadastro dele.
    func usarPacienteRecente(_ documento: DocumentoGerado) {
        if let id = documento.pacienteID, let paciente = armazenamento.paciente(id) {
            nomePaciente = GerarView.maiusculas(paciente.nome)
            pacienteEscolhido = paciente.id
        } else {
            nomePaciente = GerarView.maiusculas(documento.paciente)
        }
        focoNoNome = true
    }

    /// Atalho de favorito: escolhe de uma vez a subpasta e o modelo.
    func irParaFavorito(_ favorito: ModeloDocumento) {
        // O nome do paciente continua: o favorito só troca o documento.
        let nome = nomePaciente
        modeloSelecionado = favorito.id.uuidString
        subpasta = favorito.categoria
        DispatchQueue.main.async {
            if nomePaciente.isEmpty && !nome.isEmpty { nomePaciente = nome }
        }
    }

    /// Recomeça do início para o próximo atendimento: limpa paciente, subpasta e modelo;
    /// só o local de atendimento (e as opções de abrir e imprimir) continuam.
    func proximoPaciente() {
        geracaoConcluida = false
        subpasta = ""
        modeloSelecionado = ""
        limparPaciente()
    }

    /// Limpa nome, identificação e campos clínicos.
    func limparPaciente() {
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
    func preencher(_ escopo: Escopo) {
        guard let modelo else { return }
        for campo in modelo.campos where !CamposAutomaticos.ehNomeDoPaciente(campo) {
            var doLocal = false
            if case .local = CamposAutomaticos.mapa[CamposAutomaticos.chave(campo)] {
                doLocal = true
            }
            let atualizar = escopo == .tudo || (escopo == .local) == doLocal
            if atualizar {
                valores[campo] = GerarView.maiusculas(
                    CamposAutomaticos.valor(para: campo, paciente: pacienteCadastrado, local: local) ?? ""
                )
            }
        }
    }

    /// Gera o modelo que está na tela no momento do clique. Não recebe o modelo como parâmetro de
    /// propósito: o botão pode ter sido desenhado antes de uma troca de modelo, e usaria o anterior.
    func gerar() {
        guard !geracaoConcluida, !precisaEscolherPaciente else { return }
        guard let modelo else {
            armazenamento.erro = "Escolha a subpasta e o modelo antes de gerar o documento."
            return
        }
        // Sempre da versão mais nova do modelo: se ele foi editado e a sincronização ainda não passou,
        // copia agora. Se os campos mudaram, o formulário é refeito antes de gerar.
        let atualizado = armazenamento.atualizarModeloDaPasta(modelo)
        if atualizado.campos != modelo.campos {
            preencher(.tudo)
            armazenamento.erro = "O modelo “\(modelo.nome)” foi atualizado e tem campos diferentes. Confira os campos e clique em Gerar de novo."
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
}
