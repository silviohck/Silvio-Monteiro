import SwiftUI

/// Procura impressoras (instaladas e na rede), com busca pelo nome, e define a padrão do Mac e do app.
struct ProcurarImpressorasView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("impressora") private var impressora = ""
    @AppStorage("tamanhoTexto") private var tamanhoTexto = TamanhoTexto.normal.rawValue
    @AppStorage("aparencia") private var aparencia = Aparencia.automatica.rawValue
    @State private var busca = ""
    @State private var instaladas: [String] = []
    @State private var padrao = ""
    @State private var naRede: [Impressao.ImpressoraEncontrada] = []
    @State private var procurandoNaRede = false
    @State private var trabalhando = false
    @State private var mensagem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Impressoras").fonteApp(.titulo)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar pelo nome", text: $busca)
                    .textFieldStyle(.roundedBorder)
            }

            List {
                Section {
                    if instaladasFiltradas.isEmpty {
                        Text("Nenhuma impressora instalada com esse nome.").foregroundStyle(.secondary)
                    }
                    ForEach(instaladasFiltradas, id: \.self) { fila in
                        HStack {
                            Image(systemName: "printer.fill").foregroundStyle(Tema.destaque)
                            Text(Impressao.nomeAmigavel(fila))
                            if fila == padrao {
                                Text("padrão")
                                    .fonteApp(.legenda)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Tema.destaqueSuave))
                            }
                            Spacer()
                            Button("Usar como padrão") { usar(fila) }
                                .disabled(trabalhando || (fila == padrao && fila == impressora))
                        }
                    }
                } header: {
                    TituloSecao("Instaladas neste Mac", icone: "printer")
                }

                Section {
                    if procurandoNaRede {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Procurando na rede e no USB…").foregroundStyle(.secondary)
                        }
                    } else if redeFiltrada.isEmpty {
                        Text("Nenhuma impressora nova encontrada.").foregroundStyle(.secondary)
                    }
                    ForEach(redeFiltrada) { encontrada in
                        HStack {
                            Image(systemName: "wifi").foregroundStyle(.secondary)
                            Text(encontrada.nome)
                            Spacer()
                            Button("Adicionar e usar") { adicionar(encontrada) }
                                .disabled(trabalhando)
                        }
                    }
                } header: {
                    HStack {
                        TituloSecao("Encontradas na rede", icone: "wifi")
                        Spacer()
                        Button {
                            procurarNaRede()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(procurandoNaRede)
                        .help("Procurar de novo")
                    }
                }
            }
            .fundoSuave(Tema.lateral)

            if let mensagem {
                Text(mensagem)
                    .fonteApp(.apoio)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Abrir Impressoras e Scanners…") { Impressao.abrirAjustesDeImpressoras() }
                Spacer()
                Button("Concluído") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 560)
        .background(Tema.fundo)
        .temaDoApp(
            tamanho: TamanhoTexto(rawValue: tamanhoTexto) ?? .normal,
            aparencia: Aparencia(rawValue: aparencia) ?? .automatica
        )
        .onAppear {
            atualizarInstaladas()
            procurarNaRede()
        }
    }

    private func combina(_ nome: String) -> Bool {
        let termo = busca.trimmingCharacters(in: .whitespaces)
        return termo.isEmpty || nome.range(of: termo, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private var instaladasFiltradas: [String] {
        instaladas.filter { combina(Impressao.nomeAmigavel($0)) }
    }

    /// Só as da rede que ainda não estão instaladas.
    private var redeFiltrada: [Impressao.ImpressoraEncontrada] {
        let jaInstaladas = Set(instaladas.map { Impressao.nomeAmigavel($0).lowercased() })
        return naRede.filter { combina($0.nome) && !jaInstaladas.contains($0.nome.lowercased()) }
    }

    private func atualizarInstaladas() {
        instaladas = Impressao.impressoras()
        padrao = Impressao.padraoDoSistema()
    }

    private func procurarNaRede() {
        procurandoNaRede = true
        DispatchQueue.global(qos: .userInitiated).async {
            let encontradas = Impressao.procurarNaRede()
            DispatchQueue.main.async {
                naRede = encontradas
                procurandoNaRede = false
            }
        }
    }

    private func usar(_ fila: String) {
        trabalhando = true
        DispatchQueue.global(qos: .userInitiated).async {
            let erro = Impressao.definirPadrao(fila)
            DispatchQueue.main.async {
                trabalhando = false
                if let erro {
                    mensagem = erro
                } else {
                    impressora = fila
                    mensagem = "“\(Impressao.nomeAmigavel(fila))” é a impressora padrão."
                }
                atualizarInstaladas()
            }
        }
    }

    private func adicionar(_ encontrada: Impressao.ImpressoraEncontrada) {
        trabalhando = true
        mensagem = "Adicionando “\(encontrada.nome)”…"
        DispatchQueue.global(qos: .userInitiated).async {
            let resultado = Impressao.instalar(encontrada)
            DispatchQueue.main.async {
                trabalhando = false
                switch resultado {
                case .success(let fila):
                    atualizarInstaladas()
                    usar(fila)
                case .failure(let erro):
                    mensagem = erro.localizedDescription + " Use “Abrir Impressoras e Scanners…” para adicionar pelo macOS; ela aparece aqui depois."
                }
            }
        }
    }
}
