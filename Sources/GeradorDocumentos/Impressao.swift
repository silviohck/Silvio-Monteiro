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
    /// (o Word sempre imprime na impressora padrão). `concluir` recebe nil ou a mensagem de erro.
    static func imprimir(
        _ arquivo: URL,
        impressora: String,
        manterAberto: Bool,
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
                let resultado = executar("/usr/bin/osascript", ["-e", script] + argumentos)
                if resultado.status != 0 {
                    erro = mensagem(paraErroDoAppleScript: resultado.erro)
                }
            }
            DispatchQueue.main.async { concluir(erro) }
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
