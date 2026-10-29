import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Secao: String, CaseIterable, Identifiable {
    case gerar = "Gerar documento"
    case fila = "Fila de impressão"
    case pacientes = "Pacientes"
    case locais = "Locais de atendimento"
    case modelos = "Modelos"
    case historico = "Histórico"
    case cid = "CID-10"
    case sigtap = "SIGTAP (SUS)"

    var id: Self { self }

    var icone: String {
        switch self {
        case .gerar: return "doc.badge.plus"
        case .fila: return "printer"
        case .pacientes: return "person.2"
        case .locais: return "building.2"
        case .modelos: return "doc.text"
        case .historico: return "clock"
        case .cid: return "stethoscope"
        case .sigtap: return "cross.case"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var secao: Secao? = .gerar

    var body: some View {
        NavigationSplitView {
            List(Secao.allCases, selection: $secao) { item in
                Label(item.rawValue, systemImage: item.icone)
                    .badge(item == .fila ? armazenamento.pendentesNaFila : 0)
            }
            .fundoSuave(Tema.lateral)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 11) {
                    // A logo do Orthck (ícone do app).
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Orthck")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Documentos clínicos")
                            .fonteApp(.legenda)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tema.lateral)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Tema.borda.opacity(0.75)).frame(height: 1)
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 13) {
                    CompactarPastaBotao()
                    SeletorDeImpressora()
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tema.lateral)
                .overlay(alignment: .top) {
                    Rectangle().fill(Tema.borda.opacity(0.75)).frame(height: 1)
                }
            }
        } detail: {
            switch secao ?? .gerar {
            case .gerar: GerarView()
            case .fila: FilaImpressaoView()
            case .pacientes: PacientesView()
            case .locais: LocaisView()
            case .modelos: ModelosView()
            case .historico: HistoricoView()
            case .cid: TabelaCodigosView(tabela: .cid10, chaveDoFiltro: "capituloCID").id(Secao.cid)
            case .sigtap: TabelaCodigosView(tabela: .sigtap, chaveDoFiltro: "grupoSIGTAP").id(Secao.sigtap)
            }
        }
        // Ao abrir o app e sempre que ele volta para a frente, acompanha a pasta de modelos.
        // Antes, junta os dados da cópia no Google Drive, se ela mudou em outro computador.
        .task {
            await armazenamento.sincronizarDriveAoVoltar()
            await armazenamento.sincronizar()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await armazenamento.sincronizarDriveAoVoltar()
                await armazenamento.sincronizar()
            }
        }
        .alert(
            "Atenção",
            isPresented: Binding(get: { armazenamento.erro != nil }, set: { if !$0 { armazenamento.erro = nil } })
        ) {
            Button("OK") { armazenamento.erro = nil }
        } message: {
            Text(armazenamento.erro ?? "")
        }
    }
}

/// Cria um .zip com todos os arquivos da pasta sincronizada (para levar a outro computador ou guardar).
/// Backup na barra lateral: compactar a pasta (com os dados) e importar um arquivo de dados .json.
struct CompactarPastaBotao: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var arquivoParaImportar: URL?
    @State private var resultado: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TituloSecao("Backup", icone: "archivebox.fill")
            if armazenamento.urlPastaSincronizada != nil {
                Button {
                    Task { await armazenamento.compactarPastaSincronizada() }
                } label: {
                    Label(armazenamento.compactando ? "Compactando…" : "Compactar (.zip)…", systemImage: "doc.zipper")
                        .frame(maxWidth: .infinity)
                }
                .disabled(armazenamento.compactando)
                .help("Cria um .zip com todos os arquivos da pasta sincronizada e os dados do app")
            }
            Button {
                arquivoParaImportar = escolherArquivoDeDados()
            } label: {
                Label("Importar dados (.json)…", systemImage: "square.and.arrow.down.on.square")
                    .frame(maxWidth: .infinity)
            }
            .help("Traz pacientes, locais, histórico e fila de um backup (dados.json ou “Orthck - dados (backup).json”)")
            EnviarPastaAoDrive()
            CopiaNaNuvem()
                .padding(.top, 4)
        }
        .confirmationDialog(
            "Importar “\(arquivoParaImportar?.lastPathComponent ?? "")”?",
            isPresented: Binding(get: { arquivoParaImportar != nil }, set: { if !$0 { arquivoParaImportar = nil } }),
            presenting: arquivoParaImportar
        ) { url in
            Button("Juntar com os dados atuais") { importar(url, modo: .juntar) }
            Button("Substituir todos os dados", role: .destructive) { importar(url, modo: .substituir) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Juntar: entram os pacientes, locais e documentos que ainda não estão aqui. Substituir: os dados atuais são trocados pelos do arquivo (restaurar um backup). Antes, uma cópia dos dados atuais é guardada em Backups.")
        }
        .alert("Importação concluída", isPresented: Binding(get: { resultado != nil }, set: { if !$0 { resultado = nil } })) {
            Button("OK") { resultado = nil }
        } message: {
            Text(resultado ?? "")
        }
    }

    private func escolherArquivoDeDados() -> URL? {
        let painel = NSOpenPanel()
        painel.allowedContentTypes = [.json]
        painel.allowsMultipleSelection = false
        painel.canChooseDirectories = false
        painel.message = "Escolha o arquivo de dados do Orthck (dados.json, um backup da pasta Backups ou o “Orthck - dados (backup).json” do .zip)."
        painel.prompt = "Importar"
        painel.directoryURL = armazenamento.pastaBackups
        return painel.runModal() == .OK ? painel.url : nil
    }

    private func importar(_ url: URL, modo: Armazenamento.ModoDeImportacao) {
        do {
            resultado = try armazenamento.importarDados(de: url, modo: modo)
        } catch {
            armazenamento.erro = error.localizedDescription
        }
        arquivoParaImportar = nil
    }
}

/// Impressora usada pelos botões "Imprimir" (vazia = padrão do sistema).
struct SeletorDeImpressora: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @AppStorage("impressora") private var impressora = ""
    @State private var filas: [String] = []
    @State private var procurando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TituloSecao("Impressora", icone: "printer.fill")
            HStack(spacing: 4) {
                Picker("Impressora", selection: $impressora) {
                    Text("Padrão do sistema").tag("")
                    ForEach(opcoes, id: \.self) { fila in
                        Text(Impressao.nomeAmigavel(fila)).tag(fila)
                    }
                }
                .labelsHidden()
                Button {
                    filas = Impressao.impressoras()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Atualizar a lista de impressoras")
            }
            Button {
                procurando = true
            } label: {
                Label("Procurar impressoras…", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .help("Procura impressoras instaladas e na rede, e define a padrão")
            Button(role: .destructive) {
                armazenamento.pararImpressoes(impressora: impressora)
            } label: {
                Label("Parar todas as impressões", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
            .help("Cancela tudo o que está na fila de impressão do Mac para esta impressora e para a fila do app")
        }
        .onAppear { filas = Impressao.impressoras() }
        .onChange(of: impressora) { fila in
            // A escolhida passa a ser a padrão do Mac na hora (não só ao imprimir).
            guard !fila.isEmpty else { return }
            DispatchQueue.global(qos: .userInitiated).async { _ = Impressao.definirPadrao(fila) }
        }
        .sheet(isPresented: $procurando, onDismiss: { filas = Impressao.impressoras() }) {
            ProcurarImpressorasView()
        }
    }

    /// Mantém na lista a impressora escolhida mesmo se ela estiver desligada ou removida.
    private var opcoes: [String] {
        impressora.isEmpty || filas.contains(impressora) ? filas : filas + [impressora]
    }
}

extension UTType {
    static let documentoWord = UTType(filenameExtension: "docx") ?? .data

    /// .docx e formatos que o macOS converte para .docx (.doc antigo, .rtf, .odt).
    static let modelosImportaveis: [UTType] = {
        let tipos: [UTType?] = [
            documentoWord,
            UTType("com.microsoft.word.doc") ?? UTType(filenameExtension: "doc"),
            UTType.rtf,
            UTType(filenameExtension: "odt"),
        ]
        return tipos.compactMap { $0 }
    }()
}

/// Mostra o painel de abertura de documentos para usar como modelo.
@MainActor
func escolherArquivosDocx(multiplos: Bool) -> [URL] {
    let painel = NSOpenPanel()
    painel.allowedContentTypes = UTType.modelosImportaveis
    painel.allowsMultipleSelection = multiplos
    painel.canChooseDirectories = false
    painel.prompt = "Escolher"
    return painel.runModal() == .OK ? painel.urls : []
}

/// Texto exibido quando uma área está vazia (equivalente simples ao ContentUnavailableView).
struct AvisoVazio: View {
    let titulo: String
    let icone: String
    var mensagem: String = ""
    var botao: String?
    var acao: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icone)
                .font(.system(size: 29, weight: .light))
                .foregroundStyle(Tema.destaque)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 20).fill(Tema.destaqueSuave))
            Text(titulo)
                .fonteApp(.titulo)
                .foregroundStyle(.primary)
            if !mensagem.isEmpty {
                Text(mensagem)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            if let botao, let acao {
                Button(botao, action: acao)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 6)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tema.fundo)
    }
}
