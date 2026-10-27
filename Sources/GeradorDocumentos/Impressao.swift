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
            if paginasPorFolha > 1 {
                erro = imprimirVariasPorFolha(arquivo, impressora: impressora, manterAberto: manterAberto, paginasPorFolha: paginasPorFolha, copias: copias)
                DispatchQueue.main.async { concluir(erro) }
                return
            }
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

    /// O Word não tem comando de "páginas por folha"; então ele exporta um PDF (mantendo a formatação)
    /// e o sistema de impressão do Mac imprime esse PDF com várias páginas por folha (`lp -o number-up`).
    /// Se a exportação falhar, imprime normal pelo Word para não perder a impressão.
    private static func imprimirVariasPorFolha(
        _ arquivo: URL,
        impressora: String,
        manterAberto: Bool,
        paginasPorFolha: Int,
        copias: Int
    ) -> String? {
        let pasta = pastaDeImpressao
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        let pdf = pasta.appendingPathComponent("\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: pdf) }

        let exportacao = executar("/usr/bin/osascript", ["-e", scriptExportarPDF, arquivo.path, pdf.path, manterAberto ? "sim" : "nao"])
        guard exportacao.status == 0, FileManager.default.fileExists(atPath: pdf.path) else {
            if exportacao.erro.contains("-1743") {
                return mensagem(paraErroDoAppleScript: exportacao.erro)
            }
            if !impressora.isEmpty {
                _ = executar("/usr/bin/lpoptions", ["-d", impressora])
            }
            let normal = executar("/usr/bin/osascript", ["-e", script, arquivo.path, manterAberto ? "sim" : "nao", String(max(1, copias))])
            if normal.status != 0 {
                return mensagem(paraErroDoAppleScript: normal.erro)
            }
            return "O documento foi impresso, mas sem “\(paginasPorFolha) páginas por folha”: o Word não conseguiu gerar o PDF para impressão. Se o Word pediu acesso a uma pasta, clique em “Selecionar” e conceda o acesso, e tente imprimir de novo. (\(exportacao.erro))"
        }

        var argumentos = ["-n", String(max(1, copias)), "-o", "number-up=\(paginasPorFolha)", "-o", "number-up-layout=lrtb"]
        if !impressora.isEmpty {
            argumentos = ["-d", impressora] + argumentos
        }
        let impressao = executar("/usr/bin/lp", argumentos + [pdf.path])
        if impressao.status != 0 {
            return "Não foi possível enviar para a impressora. \(impressao.erro)"
        }
        return nil
    }

    /// Pasta fixa para os PDFs temporários, para o Word pedir acesso só uma vez.
    private static var pastaDeImpressao: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeradorDocumentos/Impressao", isDirectory: true)
    }

    private static let scriptExportarPDF = """
    on run argv
        set arquivo to (POSIX file (item 1 of argv)) as alias
        set destino to (POSIX file (item 2 of argv)) as text
        set manterAberto to item 3 of argv
        tell application "Microsoft Word"
            open arquivo
            save as active document file name destino file format format PDF
            if manterAberto is "nao" then close active document saving no
        end tell
    end run
    """

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
