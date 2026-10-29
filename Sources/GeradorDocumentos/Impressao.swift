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

    /// Impressora padrão do Mac (vazia se não houver).
    static func padraoDoSistema() -> String {
        // "destino padrão do sistema: HP_LaserJet" / "system default destination: HP_LaserJet"
        let saida = executar("/usr/bin/lpstat", ["-d"]).saida
        guard let doisPontos = saida.lastIndex(of: ":") else { return "" }
        return saida[saida.index(after: doisPontos)...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Torna a fila a impressora padrão do Mac; devolve a mensagem de erro, se houver.
    static func definirPadrao(_ fila: String) -> String? {
        let resultado = executar("/usr/bin/lpoptions", ["-d", fila])
        return resultado.status == 0 ? nil : "Não foi possível tornar “\(nomeAmigavel(fila))” a impressora padrão. \(resultado.erro)"
    }

    /// Impressora encontrada na rede (Wi-Fi/cabo) ou no USB, ainda não instalada no Mac.
    struct ImpressoraEncontrada: Identifiable, Hashable {
        let nome: String
        let endereco: String
        var id: String { endereco }
    }

    /// Procura impressoras na rede e no USB (leva alguns segundos).
    static func procurarNaRede() -> [ImpressoraEncontrada] {
        let saida = executar("/usr/sbin/lpinfo", ["--timeout", "8", "--include-schemes", "dnssd,usb,ipp,ipps", "-v"]).saida
        var vistas = Set<String>()
        return saida.split(whereSeparator: \.isNewline).compactMap { linha in
            // "network dnssd://HP%20LaserJet%20M15._ipp._tcp.local./?uuid=…"
            guard let endereco = linha.split(separator: " ").last.map(String.init), endereco.contains("://") else { return nil }
            var nome = String(endereco.split(separator: "/").dropFirst().first ?? "")
            nome = nome.removingPercentEncoding ?? nome
            if let fim = nome.range(of: "._ipp") ?? nome.range(of: "._pdl") ?? nome.range(of: "._printer") {
                nome = String(nome[..<fim.lowerBound])
            }
            if endereco.hasPrefix("usb://") {
                nome = (endereco.dropFirst("usb://".count).split(separator: "?").first.map(String.init) ?? nome)
                    .replacingOccurrences(of: "/", with: " ")
                nome = nome.removingPercentEncoding ?? nome
            }
            guard !nome.isEmpty, vistas.insert(nome.lowercased()).inserted else { return nil }
            return ImpressoraEncontrada(nome: nome, endereco: endereco)
        }
        .sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
    }

    /// Instala a impressora encontrada (driver genérico AirPrint/IPP Everywhere) e devolve o nome da fila,
    /// ou a mensagem de erro.
    static func instalar(_ impressora: ImpressoraEncontrada) -> Result<String, Error> {
        let fila = String(impressora.nome.map { $0.isLetter || $0.isNumber ? $0 : "_" })
            .folding(options: .diacriticInsensitive, locale: nil)
        let resultado = executar("/usr/sbin/lpadmin", ["-p", fila, "-E", "-v", impressora.endereco, "-m", "everywhere", "-D", impressora.nome])
        guard resultado.status == 0 else {
            return .failure(NSError(domain: "Orthck", code: Int(resultado.status), userInfo: [
                NSLocalizedDescriptionKey: "O Mac não deixou instalar “\(impressora.nome)” por aqui. \(resultado.erro)",
            ]))
        }
        return .success(fila)
    }

    /// Abre Ajustes do Sistema › Impressoras e Scanners.
    static func abrirAjustesDeImpressoras() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
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
                let argumentos = [arquivo.path, manterAberto ? "sim" : "nao", String(max(1, copias)), arquivo.lastPathComponent]
                let resultado = executar("/usr/bin/osascript", ["-e", script] + argumentos)
                if resultado.status != 0 {
                    erro = mensagem(paraErroDoAppleScript: resultado.erro)
                }
            }
            DispatchQueue.main.async { concluir(erro) }
        }
    }

    /// Abre o arquivo e imprime exatamente ele, achado pelo nome — não o "documento ativo", que pode
    /// ainda ser o anterior enquanto o Word abre o novo.
    private static let script = """
    on run argv
        set arquivo to (POSIX file (item 1 of argv)) as alias
        set manterAberto to item 2 of argv
        set copias to (item 3 of argv) as integer
        set nomeDoArquivo to item 4 of argv
        tell application "Microsoft Word"
            open arquivo
            set alvo to missing value
            repeat 60 times
                -- Confere o nome do documento achado: "document <nome>" sozinho não garante que
                -- ele já abriu, e o Word imprimiria outro.
                try
                    set candidato to document nomeDoArquivo
                    if (name of candidato) is nomeDoArquivo then
                        set alvo to candidato
                        exit repeat
                    end if
                end try
                -- Plano B: percorre os documentos abertos pela posição.
                try
                    repeat with i from 1 to (count of documents)
                        if (name of document i) is nomeDoArquivo then
                            set alvo to document i
                            exit repeat
                        end if
                    end repeat
                end try
                if alvo is not missing value then exit repeat
                delay 0.25
            end repeat
            if alvo is missing value then error "O Word não abriu " & nomeDoArquivo
            repeat copias times
                print out alvo
            end repeat
            if manterAberto is "nao" then close alvo saving no
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
