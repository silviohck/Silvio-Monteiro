import AppKit
import DocxTemplateKit
import SwiftUI

/// Seções da tela Gerar documento: local, documento pronto, subpasta e modelo, campos, salvar e imprimir.
extension GerarView {
    /// Quadro verde depois de gerar, com o atalho para o próximo paciente.
    @ViewBuilder
    var documentoPronto: some View {
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
    }

    /// Subpasta (menu em níveis) e modelo.
    var secaoDocumento: some View {
        Section {
            if armazenamento.modelos(para: local).isEmpty {
                Text("Nenhum modelo para este local. Importe na aba “Modelos”.")
                    .fonteApp(.apoio)
                    .foregroundStyle(.secondary)
            } else {
                let favoritos = armazenamento.favoritos(para: local)
                if !favoritos.isEmpty {
                    // Atalhos para os modelos mais usados (ex.: Retorno): um clique já escolhe subpasta e modelo.
                    // Em grade (todos à vista, do mesmo tamanho), em vez de uma fila que rola para o lado.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(favoritos) { favorito in
                            Button {
                                irParaFavorito(favorito)
                            } label: {
                                Label {
                                    Text(favorito.nome)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                } icon: {
                                    Image(systemName: "star.fill")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .tint(favorito.id.uuidString == modeloSelecionado ? Tema.destaque : nil)
                            .help("\(favorito.categoria.replacingOccurrences(of: Armazenamento.separadorDeSubpastas, with: " › ")) › \(favorito.nome) — arraste para mudar a ordem")
                            // Reorganizar: arrastar um favorito para cima de outro, ou pelo clique direito.
                            .draggable(favorito.id.uuidString)
                            .dropDestination(for: String.self) { ids, _ in
                                guard let id = ids.first, let arrastado = favoritos.first(where: { $0.id.uuidString == id }),
                                      arrastado.id != favorito.id else { return false }
                                let indiceArrastado = favoritos.firstIndex { $0.id == arrastado.id } ?? 0
                                let indiceAlvo = favoritos.firstIndex { $0.id == favorito.id } ?? 0
                                // Para a direita: entra depois do alvo; para a esquerda: antes.
                                let antesDe = indiceArrastado < indiceAlvo
                                    ? (indiceAlvo + 1 < favoritos.count ? favoritos[indiceAlvo + 1] : nil)
                                    : favorito
                                armazenamento.moverFavorito(arrastado, paraAntesDe: antesDe, noLocal: local)
                                return true
                            }
                            .contextMenu {
                                let indice = favoritos.firstIndex { $0.id == favorito.id } ?? 0
                                Button("Mover para a esquerda") {
                                    armazenamento.moverFavorito(favorito, paraAntesDe: favoritos[indice - 1], noLocal: local)
                                }
                                .disabled(indice == 0)
                                Button("Mover para a direita") {
                                    armazenamento.moverFavorito(
                                        favorito,
                                        paraAntesDe: indice + 2 < favoritos.count ? favoritos[indice + 2] : nil,
                                        noLocal: local
                                    )
                                }
                                .disabled(indice == favoritos.count - 1)
                                Button("Mover para o início") {
                                    armazenamento.moverFavorito(favorito, paraAntesDe: favoritos.first, noLocal: local)
                                }
                                .disabled(indice == 0)
                                Button("Mover para o fim") {
                                    armazenamento.moverFavorito(favorito, paraAntesDe: nil, noLocal: local)
                                }
                                .disabled(indice == favoritos.count - 1)
                                Divider()
                                Button("Tirar dos favoritos") {
                                    armazenamento.alternarFavorito(favorito, noLocal: local?.id)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                LabeledContent("Subpasta") {
                    // Menu em níveis, como no Finder: 1 - APAC › Fisioterapia › coluna.
                    Menu {
                        itensDoMenu(NoSubpasta.arvore(subpastasDisponiveis))
                    } label: {
                        Text(subpasta.isEmpty
                            ? "Escolha…"
                            : subpasta.replacingOccurrences(of: Armazenamento.separadorDeSubpastas, with: " › "))
                    }
                    .fixedSize()
                }
                HStack {
                    // Mostra o modelo que vale de verdade; se o guardado não é desta subpasta, mostra "Escolha…"
                    // (o macOS mostraria o primeiro da lista, e o documento sairia de outro modelo).
                    Picker("Modelo", selection: Binding(
                        get: { modelo?.id.uuidString ?? "" },
                        set: { modeloSelecionado = $0 }
                    )) {
                        if modelo == nil {
                            Text("Escolha…").tag("")
                        }
                        ForEach(modelosDaSubpasta) { modelo in
                            Text(modelo.nome).tag(modelo.id.uuidString)
                        }
                    }
                    if let modelo {
                        let favorito = armazenamento.ehFavorito(modelo, noLocal: local?.id)
                        Button {
                            armazenamento.alternarFavorito(modelo, noLocal: local?.id)
                        } label: {
                            Image(systemName: favorito ? "star.fill" : "star")
                                .foregroundStyle(favorito ? Color.yellow : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(favorito ? "Tirar “\(modelo.nome)” dos favoritos" : "Favoritar “\(modelo.nome)” em \(local?.nome ?? "este local"): vira um atalho acima da Subpasta")
                    }
                }
            }
        } header: {
            TituloSecao("Documento", icone: "doc.text.fill")
        }
    }

    /// Campos que o modelo pede, além do nome do paciente.
    @ViewBuilder
    func secaoCampos(_ modelo: ModeloDocumento) -> some View {
        let campos = modelo.campos.filter { !CamposAutomaticos.ehNomeDoPaciente($0) }
        Section {
            if campos.isEmpty {
                Text("Nenhum outro campo para preencher neste modelo.")
                    .foregroundStyle(.secondary)
            }
            ForEach(campos, id: \.self) { campo in
                TextField(campo, text: valor(campo), axis: .vertical)
                    .lineLimit(1...5)
                if SugestoesCID.ehCampoCID(campo) {
                    SugestoesCID(texto: valores[campo, default: ""]) { codigo in
                        valor(campo).wrappedValue = codigo.codigo
                    }
                }
            }
        } header: {
            TituloSecao("Campos do documento", icone: "list.bullet.rectangle.fill")
        } footer: {
            Text("Preenchidos com o cadastro do paciente, o local e a data de hoje. Você pode alterar qualquer valor. Só os dados gerais (CPF, nascimento, contato) ficam no cadastro; campos como CID valem só para este documento.")
                .foregroundStyle(.secondary)
        }
    }

    /// Onde salvar, o que fazer depois de gerar (fila, imprimir, só salvar) e o botão Gerar.
    func secaoSalvar(_ modelo: ModeloDocumento) -> some View {
        Section {
            Toggle("Abrir o documento depois de gerar", isOn: $abrirAoGerar)
            OpcaoRegistroPDF()
            HStack {
                Picker("Depois de gerar", selection: $acaoDepoisDeGerar) {
                    Text("Adicionar à fila de impressão").tag("fila")
                    Text("Imprimir agora").tag("imprimir")
                    Text("Só abrir").tag("salvar")
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
                Button("Gerar documento") { gerar() }
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

    /// Itens do menu de subpastas: pasta com subpastas vira um submenu; uma pasta que também tem
    /// modelos próprios ganha, no submenu, o item "Documentos em <pasta>".
    func itensDoMenu(_ nos: [NoSubpasta]) -> AnyView {
        AnyView(ForEach(nos) { no in
            if no.filhos.isEmpty {
                botaoDaSubpasta(no.nome, caminho: no.caminho)
            } else {
                Menu(no.nome) {
                    if no.temModelos {
                        botaoDaSubpasta("Documentos em \(no.nome)", caminho: no.caminho)
                        Divider()
                    }
                    itensDoMenu(no.filhos)
                }
            }
        })
    }

    func botaoDaSubpasta(_ titulo: String, caminho: String) -> some View {
        Button {
            subpasta = caminho
        } label: {
            if caminho == subpasta {
                Label(titulo, systemImage: "checkmark")
            } else {
                Text(titulo)
            }
        }
    }

    /// Quadro em destaque no topo: em qual local você está atendendo.
    var quadroDoLocal: some View {
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
}
