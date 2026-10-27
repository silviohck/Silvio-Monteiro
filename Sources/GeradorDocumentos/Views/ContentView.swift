import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Secao: String, CaseIterable, Identifiable {
    case gerar = "Gerar documento"
    case pacientes = "Pacientes"
    case modelos = "Modelos"
    case historico = "Histórico"

    var id: Self { self }

    var icone: String {
        switch self {
        case .gerar: return "doc.badge.plus"
        case .pacientes: return "person.2"
        case .modelos: return "doc.text"
        case .historico: return "clock"
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
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) {
                Button {
                    armazenamento.abrirPastaDeDados()
                } label: {
                    Label("Pasta de dados", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                .padding()
            }
        } detail: {
            switch secao ?? .gerar {
            case .gerar: GerarView()
            case .pacientes: PacientesView()
            case .modelos: ModelosView()
            case .historico: HistoricoView()
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

extension UTType {
    static let documentoWord = UTType(filenameExtension: "docx") ?? .data
}

/// Mostra o painel de abertura de arquivos .docx.
@MainActor
func escolherArquivosDocx(multiplos: Bool) -> [URL] {
    let painel = NSOpenPanel()
    painel.allowedContentTypes = [.documentoWord]
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

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icone)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(titulo).font(.title3).bold()
            if !mensagem.isEmpty {
                Text(mensagem)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
