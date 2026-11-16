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
        let resultado = executar("/usr/sbin/lpadmin", ["-p", fila, "-E", "-v", impressora.endereco, "-m", "everywhere", "-D", impressora.nome,
            // Se um trabalho falhar, descarta em vez de tentar de novo sem parar.
            "-o", "printer-error-policy=abort-job"])
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

    /// Um pedido ao Word por vez, na ordem em que foram feitos.
    static let filaDoWord = DispatchQueue(label: "Orthck.Word", qos: .userInitiated)

    static var wordInstalado: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Word") != nil
    }

    /// Último arquivo mandado para o Word e quando: o mesmo arquivo de novo em menos de 20 segundos
    /// (clique duplo, dois caminhos ao mesmo tempo) não é reenviado.
    private static var ultimoEnvio: (caminho: String, quando: Date)?
    private static let travaDoEnvio = NSLock()

    /// Cancela todos os trabalhos de impressão esperando na fila do Mac para esta impressora
    /// (vazia = impressora padrão). Para parar um documento que está saindo sem parar.
    static func cancelarTudo(impressora: String) -> String? {
        let fila = impressora.isEmpty ? padraoDoSistema() : impressora
        let resultado = executar("/usr/bin/cancel", fila.isEmpty ? ["-a"] : ["-a", fila])
        return resultado.status == 0 ? nil : "Não foi possível cancelar as impressões. \(resultado.erro)"
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
        travaDoEnvio.lock()
        if let ultimo = ultimoEnvio, ultimo.caminho == arquivo.path, Date().timeIntervalSince(ultimo.quando) < 20 {
            travaDoEnvio.unlock()
            concluir("“\(arquivo.lastPathComponent)” acabou de ser enviado para a impressora; não foi enviado de novo.")
            return
        }
        ultimoEnvio = (arquivo.path, Date())
        travaDoEnvio.unlock()
        filaDoWord.async {
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
    -- Fora do "tell Word": as palavras aqui são do AppleScript (dentro do Word, algumas, como "case",
    -- são propriedades dele e o script não compila).
    on outraPasta(caminhoAberto, caminhoPOSIX)
        try
            set caminhoEsperado to (POSIX file caminhoPOSIX) as text
            set AppleScript's text item delimiters to ":"
            set partesAbertas to text items of caminhoAberto
            set partesEsperadas to text items of caminhoEsperado
            set AppleScript's text item delimiters to ""
            if (count of partesAbertas) < 2 or (count of partesEsperadas) < 2 then return false
            -- Comparação de texto do AppleScript já ignora maiúsculas.
            return (item -2 of partesAbertas) is not (item -2 of partesEsperadas)
        on error
            set AppleScript's text item delimiters to ""
            return false
        end try
    end outraPasta

    on run argv
        set arquivo to (POSIX file (item 1 of argv)) as alias
        set manterAberto to item 2 of argv
        set copias to (item 3 of argv) as integer
        set nomeDoArquivo to item 4 of argv
        tell application "Microsoft Word"
          with timeout of 300 seconds
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
            -- Confere a pasta também: um documento de mesmo nome aberto de outra pasta não é impresso no lugar.
            set caminhoAberto to ""
            try
                set caminhoAberto to (full name of alvo) as text
            end try
            if my outraPasta(caminhoAberto, (item 1 of argv)) then error "ORTHCK_OUTRO_DOCUMENTO"
            -- O Word imprime o documento que está à frente, mesmo indicando outro. Antes de imprimir, o
            -- documento certo tem de ser o ativo: abrir de novo um documento já aberto o traz para a frente.
            set ativo to false
            repeat 20 times
                try
                    if (name of active document) is nomeDoArquivo then
                        set ativo to true
                        exit repeat
                    end if
                end try
                open arquivo
                delay 0.25
            end repeat
            if not ativo then error "ORTHCK_NAO_ATIVO"
            repeat copias times
                -- Confere de novo a cada cópia: se outro documento passou para a frente, para.
                if (name of active document) is not nomeDoArquivo then error "ORTHCK_NAO_ATIVO"
                print out active document
            end repeat
            if manterAberto is "nao" then close alvo saving no
          end timeout
        end tell
    end run
    """

    private static func mensagem(paraErroDoAppleScript erro: String) -> String {
        if erro.contains("ORTHCK_NAO_ATIVO") {
            return "O Word não deixou o documento à frente para imprimir (outro documento estava ativo). Nada foi impresso, para não sair o documento errado. Feche os documentos abertos no Word e reenvie."
        }
        if erro.contains("ORTHCK_OUTRO_DOCUMENTO") {
            return "O Word já tinha aberto outro documento com o mesmo nome, de outra pasta. Nada foi impresso, para não sair o documento errado. Feche os documentos abertos no Word e imprima de novo."
        }
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
