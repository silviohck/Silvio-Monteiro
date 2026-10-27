import AppKit
import SwiftUI

/// Mostra o painel para escolher uma pasta.
@MainActor
func escolherPasta(mensagem: String) -> URL? {
    let painel = NSOpenPanel()
    painel.canChooseDirectories = true
    painel.canChooseFiles = false
    painel.allowsMultipleSelection = false
    painel.prompt = "Escolher"
    painel.message = mensagem
    return painel.runModal() == .OK ? painel.url : nil
}

/// Prévia e importação de uma pasta inteira de modelos, já separando por local e tipo.
struct ImportarPastaView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @Environment(\.dismiss) private var dismiss
    let pasta: URL
    @State private var pastaDeLocal: Bool
    @State private var locais: [LocalParaImportar] = []
    @State private var importando = false
    @State private var feitos = 0
    @State private var total = 0
    @State private var resultado: ResultadoImportacao?

    init(pasta: URL) {
        self.pasta = pasta
        _pastaDeLocal = State(initialValue: ImportacaoEmLote.pareceSerPastaDeLocal(pasta))
    }

    private var quantidade: Int { armazenamento.quantidadeParaImportar(locais) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Importar pasta de modelos").fonteApp(.titulo)
            Text((pasta.path as NSString).abbreviatingWithTildeInPath)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)

            if let resultado {
                resumo(resultado)
            } else if importando {
                ProgressView(value: Double(feitos), total: Double(max(total, 1))) {
                    Text("Importando \(feitos) de \(total)…")
                }
            } else {
                configuracao
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                if resultado != nil {
                    Button("Concluído") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancelar") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(importando)
                    Button("Importar \(quantidade) \(quantidade == 1 ? "modelo" : "modelos")") {
                        Task { await importar() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(quantidade == 0 || importando)
                }
            }
        }
        .padding(20)
        .frame(width: 640, height: 600)
        .background(Tema.fundo)
        .onAppear(perform: ler)
        .onChange(of: pastaDeLocal) { _ in ler() }
    }

    private var configuracao: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Esta pasta é", selection: $pastaDeLocal) {
                Text("A pasta principal: cada subpasta é um local de atendimento").tag(false)
                Text("A pasta de um local só").tag(true)
            }
            .pickerStyle(.radioGroup)

            if pastaDeLocal, !locais.isEmpty {
                TextField("Nome do local", text: $locais[0].nome)
                    .textFieldStyle(.roundedBorder)
            }

            if locais.isEmpty {
                Text("Nenhum documento do Word (.docx, .doc, .rtf, .odt) foi encontrado nesta pasta.")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach($locais) { $local in
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle(isOn: $local.incluir) {
                                Text(local.nome + situacao(local)).bold()
                            }
                            Text("\(local.arquivos.count) \(local.arquivos.count == 1 ? "modelo" : "modelos"): \(local.resumo)")
                                .fonteApp(.legenda)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .fundoSuave(Tema.lateral)
            }

            Text("Cada subpasta dentro do local (RX, LAUDO MÉDICO…) vira um tipo de documento; arquivos soltos têm o tipo adivinhado pelo nome. Os arquivos são copiados para o app e os originais não mudam. Modelos já importados (mesmo nome, local e tipo) são pulados.")
                .fonteApp(.legenda)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func situacao(_ local: LocalParaImportar) -> String {
        if local.todosOsLocais { return "  · arquivos soltos, valem para todos os locais" }
        return armazenamento.local(chamado: local.nome) == nil ? "  · novo local" : "  · local já cadastrado"
    }

    private func resumo(_ resultado: ResultadoImportacao) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "\(resultado.importados) \(resultado.importados == 1 ? "modelo importado" : "modelos importados")",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(Tema.sucesso)
            .fonteApp(.titulo)
            if resultado.repetidos > 0 {
                Text("\(resultado.repetidos) já tinham sido importados e foram pulados.")
            }
            if resultado.locaisCriados > 0 {
                Text("\(resultado.locaisCriados) \(resultado.locaisCriados == 1 ? "local de atendimento criado" : "locais de atendimento criados").")
            }
            if resultado.tiposCriados > 0 {
                Text("\(resultado.tiposCriados) \(resultado.tiposCriados == 1 ? "tipo novo criado" : "tipos novos criados") a partir das subpastas. Para juntar tipos parecidos (ex.: LAUDO MÉDICO e Laudos), use Modelos → Gerenciar… e renomeie um com o nome do outro.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !resultado.erros.isEmpty {
                Text("\(resultado.erros.count) \(resultado.erros.count == 1 ? "arquivo não pôde" : "arquivos não puderam") ser lido(s):")
                    .foregroundStyle(.orange)
                ScrollView {
                    Text(resultado.erros.joined(separator: "\n"))
                        .fonteApp(.legenda)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
        }
    }

    private func ler() {
        locais = pastaDeLocal ? ImportacaoEmLote.lerPastaDeLocal(pasta) : ImportacaoEmLote.lerPastaPrincipal(pasta)
    }

    private func importar() async {
        importando = true
        total = quantidade
        feitos = 0
        resultado = await armazenamento.importarEmLote(locais) { feitos = $0 }
        importando = false
    }
}
