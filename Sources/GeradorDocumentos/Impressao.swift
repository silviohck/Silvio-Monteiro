import AppKit

/// Impressão dos documentos gerados pelo Microsoft Word, na impressora escolhida na barra lateral.
enum Impressao {
    /// Filas de impressão instaladas (nomes do CUPS, usados por `lp`/`lpoptions`).
    static func impressoras() -> [String] {
        let saida = executar("/usr/bin/lpstat", ["-e"]).saida
        return saida.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    /// "HP_LaserJet_Consultorio" → "HP LaserJet Consultorio"
    static func nomeAmigavel(_ fila: String) -> String {
        fila.replacingOccurrences(of: "_", with: " ")
    }

    static var wordInstalado: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Word") != nil
    }

    /// Imprime `arquivo` pelo Word. Com uma impressora escolhida, ela passa a ser a padrão do Mac
    /// (o Word sempre imprime na impressora padrão). `concluir` recebe nil ou a mensagem de erro/aviso.
    static func imprimir(
        _ arquivo: URL,
        impressora: String,
        manterAberto: Bool,
        paginasPorFolha: Int = 1,
        copias: Int = 1,
        concluir: @escaping (String?) -> Void
    ) {
        guard wordInstalado else {
            concluir("Para imprimir direto pelo app é preciso ter o Microsoft Word instalado.")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var erro: String?
            if !impressora.isEmpty {
                let resultado = executar("/usr/bin/lpoptions", ["-d", impressora])
                if resultado.status != 0 {
                    erro = "Não foi possível usar a impressora “\(nomeAmigavel(impressora))”. \(resultado.erro)"
                }
            }
            if erro == nil {
                let argumentos = [arquivo.path, manterAberto ? "sim" : "nao", String(max(1, copias))]
                let (colunas, linhas) = grade(paginasPorFolha)
                if colunas * linhas > 1 {
                    let resultado = executar("/usr/bin/osascript", ["-e", scriptVariasPorFolha] + argumentos + [String(colunas), String(linhas)])
                    if resultado.status != 0 {
                        // Se o Word não aceitar o ajuste, imprime normal para não perder a impressão.
                        let normal = executar("/usr/bin/osascript", ["-e", script] + argumentos)
                        erro = normal.status != 0
                            ? mensagem(paraErroDoAppleScript: normal.erro)
                            : "O documento foi impresso, mas o Word não aceitou “\(paginasPorFolha) páginas por folha”. Ajuste na janela de impressão do Word. (\(resultado.erro))"
                    }
                } else {
                    let resultado = executar("/usr/bin/osascript", ["-e", script] + argumentos)
                    if resultado.status != 0 {
                        erro = mensagem(paraErroDoAppleScript: resultado.erro)
                    }
                }
            }
            DispatchQueue.main.async { concluir(erro) }
        }
    }

    /// 2 por folha = 2 colunas × 1 linha; 4 por folha = 2 × 2.
    private static func grade(_ paginasPorFolha: Int) -> (colunas: Int, linhas: Int) {
        switch paginasPorFolha {
        case 2: return (2, 1)
        case 4: return (2, 2)
        default: return (1, 1)
        }
    }

    private static let script = """
    on run argv
        set arquivo to (POSIX file (item 1 of argv)) as alias
        set manterAberto to item 2 of argv
        set copias to (item 3 of argv) as integer
        tell application "Microsoft Word"
            open arquivo
            repeat copias times
                print out active document
            end repeat
            if manterAberto is "nao" then close active document saving no
        end tell
    end run
    """

    private static let scriptVariasPorFolha = """
    on run argv
        set arquivo to (POSIX file (item 1 of argv)) as alias
        set manterAberto to item 2 of argv
        set copias to (item 3 of argv) as integer
        set colunas to (item 4 of argv) as integer
        set linhas to (item 5 of argv) as integer
        tell application "Microsoft Word"
            open arquivo
            repeat copias times
                print out active document print zoom column colunas print zoom row linhas
            end repeat
            if manterAberto is "nao" then close active document saving no
        end tell
    end run
    """

    private static func mensagem(paraErroDoAppleScript erro: String) -> String {
        if erro.contains("-1743") {
            return "O macOS bloqueou o controle do Word. Libere em Ajustes do Sistema → Privacidade e Segurança → Automação → Orthck → Microsoft Word."
        }
        return "O Word não conseguiu imprimir o documento. \(erro)"
    }

    private static func executar(_ ferramenta: String, _ argumentos: [String]) -> (status: Int32, saida: String, erro: String) {
        let processo = Process()
        processo.executableURL = URL(fileURLWithPath: ferramenta)
        processo.arguments = argumentos
        let saida = Pipe()
        let erro = Pipe()
        processo.standardOutput = saida
        processo.standardError = erro
        do {
            try processo.run()
        } catch {
            return (-1, "", error.localizedDescription)
        }
        let dadosSaida = saida.fileHandleForReading.readDataToEndOfFile()
        let dadosErro = erro.fileHandleForReading.readDataToEndOfFile()
        processo.waitUntilExit()
        return (
            processo.terminationStatus,
            String(decoding: dadosSaida, as: UTF8.self),
            String(decoding: dadosErro, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
