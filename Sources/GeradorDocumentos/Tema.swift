import AppKit
import SwiftUI

/// Cores e tamanhos de texto do app, pensados para uso prolongado: fundos suaves
/// (sem branco ou preto puros), destaque discreto e letras maiores que o padrão do Mac.
enum Tema {
    /// Azul-petróleo suave usado em botões, seleção e destaques.
    static let destaque = Color.adaptavel(claro: (0.23, 0.47, 0.52), escuro: (0.48, 0.72, 0.75))
    /// Verde calmo para mensagens de sucesso.
    static let sucesso = Color.adaptavel(claro: (0.24, 0.52, 0.36), escuro: (0.52, 0.76, 0.58))
    /// Fundo das telas: creme claro / grafite.
    static let fundo = Color.adaptavel(claro: (0.957, 0.949, 0.933), escuro: (0.125, 0.133, 0.141))
    /// Fundo da barra lateral e das listas, um tom diferente do fundo principal.
    static let lateral = Color.adaptavel(claro: (0.925, 0.918, 0.902), escuro: (0.153, 0.161, 0.169))
}

extension Color {
    static func adaptavel(claro: (Double, Double, Double), escuro: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { aparencia in
            let rgb = aparencia.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? escuro : claro
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

/// Tamanho do texto escolhido em Aparência (⌘,) ou com ⌘+ / ⌘−.
enum TamanhoTexto: Int, CaseIterable, Identifiable {
    case normal = 0
    case grande
    case muitoGrande

    var id: Int { rawValue }

    var nome: String {
        switch self {
        case .normal: return "Normal"
        case .grande: return "Grande"
        case .muitoGrande: return "Muito grande"
        }
    }

    /// Tamanho do texto comum, em pontos (o padrão do Mac é 13).
    var base: CGFloat {
        switch self {
        case .normal: return 15
        case .grande: return 17
        case .muitoGrande: return 19
        }
    }
}

enum Aparencia: String, CaseIterable, Identifiable {
    case automatica
    case clara
    case escura

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .automatica: return "Automática (igual ao Mac)"
        case .clara: return "Clara"
        case .escura: return "Escura"
        }
    }

    var esquema: ColorScheme? {
        switch self {
        case .automatica: return nil
        case .clara: return .light
        case .escura: return .dark
        }
    }
}

/// Estilos de texto proporcionais ao tamanho escolhido.
enum EstiloTexto {
    case legenda
    case apoio
    case titulo
    case codigo

    func fonte(base: CGFloat) -> Font {
        switch self {
        case .legenda: return .system(size: base - 2)
        case .apoio: return .system(size: base - 1)
        case .titulo: return .system(size: base + 4, weight: .semibold)
        case .codigo: return .system(size: base - 1, design: .monospaced)
        }
    }
}

private struct TamanhoBaseKey: EnvironmentKey {
    static let defaultValue: CGFloat = TamanhoTexto.normal.base
}

extension EnvironmentValues {
    var tamanhoBase: CGFloat {
        get { self[TamanhoBaseKey.self] }
        set { self[TamanhoBaseKey.self] = newValue }
    }
}

private struct FonteApp: ViewModifier {
    @Environment(\.tamanhoBase) private var base
    let estilo: EstiloTexto

    func body(content: Content) -> some View {
        content.font(estilo.fonte(base: base))
    }
}

extension View {
    func fonteApp(_ estilo: EstiloTexto) -> some View {
        modifier(FonteApp(estilo: estilo))
    }

    /// Aplica tema e tamanho de texto a uma janela inteira (janela principal, folhas e Ajustes).
    func temaDoApp(tamanho: TamanhoTexto, aparencia: Aparencia) -> some View {
        self
            .environment(\.tamanhoBase, tamanho.base)
            .font(.system(size: tamanho.base))
            .tint(Tema.destaque)
            .preferredColorScheme(aparencia.esquema)
    }

    /// Fundo suave no lugar do branco/preto padrão de formulários e listas.
    func fundoSuave(_ cor: Color = Tema.fundo) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(cor)
    }
}

/// Tela de Ajustes (⌘,): tamanho do texto e tema.
struct AjustesAparenciaView: View {
    @AppStorage("tamanhoTexto") private var tamanho = TamanhoTexto.normal.rawValue
    @AppStorage("aparencia") private var aparencia = Aparencia.automatica.rawValue

    var body: some View {
        Form {
            Picker("Tamanho do texto", selection: $tamanho) {
                ForEach(TamanhoTexto.allCases) { opcao in
                    Text(opcao.nome).tag(opcao.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
            Picker("Tema", selection: $aparencia) {
                ForEach(Aparencia.allCases) { opcao in
                    Text(opcao.nome).tag(opcao.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
            Text("Atalhos: ⌘+ aumenta o texto, ⌘− diminui e ⌘0 volta ao normal.")
                .fonteApp(.apoio)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .fundoSuave()
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .temaDoApp(
            tamanho: TamanhoTexto(rawValue: tamanho) ?? .normal,
            aparencia: Aparencia(rawValue: aparencia) ?? .automatica
        )
    }
}

/// Abre a janela de Ajustes (⌘,).
@MainActor
func abrirAjustes() {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}
