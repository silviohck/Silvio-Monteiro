import AppKit
import SwiftUI

/// Paleta "Sereno": cinzas minerais e azul-petróleo dessaturado.
/// Menos contraste entre áreas grandes, sem sacrificar a leitura em ambos os modos.
enum Tema {
    /// Reservado para ações principais, links e ícones pequenos.
    static let destaque = Color.adaptavel(claro: (0.19, 0.38, 0.43), escuro: (0.58, 0.78, 0.80))
    /// Confirmações discretas, sem verde fluorescente.
    static let sucesso = Color.adaptavel(claro: (0.23, 0.44, 0.35), escuro: (0.59, 0.78, 0.65))
    /// Plano de fundo neutro, sem branco ou preto puro.
    static let fundo = Color.adaptavel(claro: (0.965, 0.972, 0.976), escuro: (0.110, 0.125, 0.141))
    /// Área de navegação um pouco mais marcada, mas sem faixa escura.
    static let lateral = Color.adaptavel(claro: (0.932, 0.947, 0.955), escuro: (0.145, 0.162, 0.177))
    /// Cartões para informações que merecem destaque sem recorrer a blocos saturados.
    static let superficie = Color.adaptavel(claro: (0.993, 0.996, 0.997), escuro: (0.177, 0.193, 0.209))
    static let borda = Color.adaptavel(claro: (0.848, 0.883, 0.898), escuro: (0.285, 0.310, 0.334))
    /// Faixa levemente azulada, usada apenas para contextualizar o local.
    static let destaqueSuave = Color.adaptavel(claro: (0.908, 0.946, 0.949), escuro: (0.184, 0.281, 0.301))
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
    /// Títulos de seção (Paciente, Documento…): negrito, um pouco maior.
    case secao
    /// Nome em grande destaque (ex.: local de atendimento).
    case destaque

    func fonte(base: CGFloat) -> Font {
        switch self {
        case .legenda: return .system(size: base - 2)
        case .apoio: return .system(size: base - 1)
        case .titulo: return .system(size: base + 4, weight: .semibold)
        case .codigo: return .system(size: base - 1, design: .monospaced)
        case .secao: return .system(size: base, weight: .semibold)
        case .destaque: return .system(size: base + 6, weight: .semibold)
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

/// Título de seção com ícone, negrito e cor de destaque, para achar cada parte da tela rápido.
struct TituloSecao: View {
    let texto: String
    let icone: String

    init(_ texto: String, icone: String) {
        self.texto = texto
        self.icone = icone
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icone)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Tema.destaque)
                .frame(width: 18)
            Text(texto)
                .fonteApp(.secao)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
        .textCase(nil)
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
            Text("Paleta suave com azul-petróleo, cinzas neutros e contraste confortável. O modo automático segue a aparência do Mac.")
                .fonteApp(.apoio)
                .foregroundStyle(.secondary)
            Text("Atalhos: ⌘+ aumenta o texto, ⌘− diminui e ⌘0 volta ao normal.")
                .fonteApp(.legenda)
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
