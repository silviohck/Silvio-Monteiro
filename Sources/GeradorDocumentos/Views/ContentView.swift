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
    case tuss = "TUSS"

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
        case .tuss: return "list.bullet.rectangle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var secao: Secao? = .gerar

    var body: some View {
        NavigationSplitView {
            List(Secao.allCases, selection: $secao) { item in
                if item == .fila {
                    Label("\(item.rawValue) (\(armazenamento.pendentesNaFila))", systemImage: item.icone)
                } else {
                    Label(item.rawValue, systemImage: item.icone)
                }
            }
            .fundoSuave(Tema.lateral)
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 14) {
                    CompactarPastaBotao()
                    SeletorDeImpressora()
                }
                .padding()
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
            case .tuss: TabelaCodigosView(tabela: .tuss, chaveDoFiltro: "grupoTUSS").id(Secao.tuss)
            }
        }
        // Ao abrir o app e sempre que ele volta para a frente, acompanha a pasta de modelos.
        .task { await armazenamento.sincronizar() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await armazenamento.sincronizar() }
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
struct CompactarPastaBotao: View {
    @EnvironmentObject private var armazenamento: Armazenamento

    var body: some View {
        if armazenamento.urlPastaSincronizada != nil {
            VStack(alignment: .leading, spacing: 4) {
                TituloSecao("Pasta de modelos", icone: "archivebox.fill")
                Button {
                    Task { await armazenamento.compactarPastaSincronizada() }
                } label: {
                    Label(armazenamento.compactando ? "Compactando…" : "Compactar (.zip)…", systemImage: "doc.zipper")
                        .frame(maxWidth: .infinity)
                }
                .disabled(armazenamento.compactando)
                .help("Cria um .zip com todos os arquivos da pasta sincronizada")
            }
        }
    }
}

/// Impressora usada pelos botões "Imprimir" (vazia = padrão do sistema).
struct SeletorDeImpressora: View {
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
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(titulo).fonteApp(.titulo)
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
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tema.fundo)
    }
}
