import AppKit
import CryptoKit
import Foundation

/// Credencial do Google (cliente OAuth do tipo "App para computador", criada pelo usuário no
/// Google Cloud Console) e a autorização dada no navegador. Fica só neste Mac, fora do GitHub.
struct ContaGoogle: Codable {
    var clientID = ""
    var clientSecret = ""
    var refreshToken: String?
}

/// Um arquivo no Drive: o identificador e a data de modificação (texto do Google, comparado como está).
struct ArquivoNoDrive {
    let id: String
    let modificado: String
}

enum ErroGoogle: LocalizedError {
    case semCredencial
    case semAutorizacao
    case cancelado
    case tempoEsgotado
    case resposta(String)

    var errorDescription: String? {
        switch self {
        case .semCredencial: return "Falta a credencial do Google (ID do cliente e chave secreta)."
        case .semAutorizacao: return "O acesso ao Google Drive não está autorizado. Conecte de novo."
        case .cancelado: return "O login no Google foi cancelado."
        case .tempoEsgotado: return "O login no Google não foi concluído a tempo. Tente de novo."
        case .resposta(let texto): return texto
        }
    }
}

/// Conversa direto com o Google Drive pela internet, sem o app do Google: login uma vez pelo
/// navegador e depois envio e leitura de um arquivo criado pelo próprio app. A permissão pedida
/// (drive.file) só alcança os arquivos que o app criou, nada mais do Drive.
@MainActor
final class GoogleDrive {
    static let escopo = "https://www.googleapis.com/auth/drive.file"

    private let arquivoConta: URL
    private(set) var conta: ContaGoogle
    private var tokenDeAcesso: (valor: String, validoAte: Date)?
    /// Login em andamento, esperando a volta do navegador.
    private var receptorAtual: ReceptorDeLogin?

    init(pasta: URL) {
        arquivoConta = pasta.appendingPathComponent("google.json")
        conta = (try? JSONDecoder().decode(ContaGoogle.self, from: Data(contentsOf: arquivoConta))) ?? ContaGoogle()
        if conta.clientID.isEmpty, let embutida = Self.credencialEmbutida {
            conta.clientID = embutida.clientID
            conta.clientSecret = embutida.clientSecret
        }
    }

    /// Credencial colocada no app pela compilação do GitHub (Secrets do repositório), se houver.
    static var credencialEmbutida: (clientID: String, clientSecret: String)? {
        let info = Bundle.main.infoDictionary
        guard let id = info?["GoogleClientID"] as? String, !id.isEmpty,
              let segredo = info?["GoogleClientSecret"] as? String, !segredo.isEmpty else { return nil }
        return (id, segredo)
    }

    var conectado: Bool { conta.refreshToken != nil }

    private func salvarConta() {
        guard let dados = try? JSONEncoder().encode(conta) else { return }
        try? dados.write(to: arquivoConta, options: .atomic)
        // Só o usuário deste Mac lê o arquivo.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: arquivoConta.path)
    }

    /// Lê o ID do cliente e a chave secreta do arquivo .json baixado no Google Cloud Console.
    static func lerCredencial(de url: URL) throws -> (clientID: String, clientSecret: String) {
        let json = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any]
        let cliente = (json?["installed"] ?? json?["web"]) as? [String: Any]
        guard let id = cliente?["client_id"] as? String, let segredo = cliente?["client_secret"] as? String else {
            throw ErroGoogle.resposta("“\(url.lastPathComponent)” não é o arquivo da credencial do Google (client_secret….json).")
        }
        return (id, segredo)
    }

    /// Endereço colado da barra do navegador, quando ele não consegue voltar sozinho para o app.
    func entregarEndereco(_ texto: String) -> Bool {
        receptorAtual?.entregar(endereco: texto) ?? false
    }

    func cancelarLogin() {
        receptorAtual?.parar()
    }

    func desconectar() {
        conta.refreshToken = nil
        tokenDeAcesso = nil
        salvarConta()
    }

    // MARK: Login pelo navegador

    /// Abre o navegador para autorizar o app e guarda a autorização.
    func conectar(clientID: String, clientSecret: String) async throws {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty, !clientSecret.isEmpty else { throw ErroGoogle.semCredencial }
        conta.clientID = clientID
        conta.clientSecret = clientSecret
        salvarConta()

        let verificador = Self.textoAleatorio()
        let desafio = Self.base64URL(Data(SHA256.hash(data: Data(verificador.utf8))))
        let estado = Self.textoAleatorio()
        receptorAtual?.parar()
        let receptor = try ReceptorDeLogin()
        receptorAtual = receptor
        defer {
            receptor.parar()
            if receptorAtual === receptor { receptorAtual = nil }
        }
        let enderecoDeVolta = "http://127.0.0.1:\(receptor.porta)"

        var endereco = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        endereco.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: enderecoDeVolta),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.escopo),
            URLQueryItem(name: "code_challenge", value: desafio),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: estado),
        ]
        guard let url = endereco.url else { throw ErroGoogle.semCredencial }
        NSWorkspace.shared.open(url)

        let parametros = try await receptor.aguardarResposta()
        if parametros["error"] == "access_denied" { throw ErroGoogle.cancelado }
        guard parametros["state"] == estado, let codigo = parametros["code"] else {
            throw ErroGoogle.resposta("O Google não devolveu a autorização (\(parametros["error"] ?? "resposta inválida")).")
        }
        let resposta = try await pedirToken([
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": codigo,
            "code_verifier": verificador,
            "grant_type": "authorization_code",
            "redirect_uri": enderecoDeVolta,
        ])
        guard let renovacao = resposta["refresh_token"] as? String else {
            throw ErroGoogle.resposta("O Google não devolveu a autorização permanente. Tente conectar de novo.")
        }
        conta.refreshToken = renovacao
        salvarConta()
    }

    private func token() async throws -> String {
        if let tokenDeAcesso, tokenDeAcesso.validoAte > Date() { return tokenDeAcesso.valor }
        guard let renovacao = conta.refreshToken else { throw ErroGoogle.semAutorizacao }
        _ = try await pedirToken([
            "client_id": conta.clientID,
            "client_secret": conta.clientSecret,
            "refresh_token": renovacao,
            "grant_type": "refresh_token",
        ])
        guard let tokenDeAcesso else { throw ErroGoogle.semAutorizacao }
        return tokenDeAcesso.valor
    }

    private func pedirToken(_ campos: [String: String]) async throws -> [String: Any] {
        var pedido = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        pedido.httpMethod = "POST"
        pedido.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        pedido.httpBody = Data(Self.formulario(campos).utf8)
        let (dados, resposta) = try await URLSession.shared.data(for: pedido)
        let json = ((try? JSONSerialization.jsonObject(with: dados)) as? [String: Any]) ?? [:]
        guard (resposta as? HTTPURLResponse)?.statusCode == 200 else {
            if json["error"] as? String == "invalid_grant" {
                // Autorização revogada ou expirada: precisa conectar de novo.
                desconectar()
                throw ErroGoogle.semAutorizacao
            }
            throw ErroGoogle.resposta(
                "O Google recusou o pedido: \(json["error_description"] as? String ?? json["error"] as? String ?? "erro desconhecido")."
            )
        }
        if let valor = json["access_token"] as? String {
            let segundos = (json["expires_in"] as? Double) ?? 3600
            tokenDeAcesso = (valor, Date().addingTimeInterval(segundos - 60))
        }
        return json
    }

    // MARK: Arquivos

    /// O arquivo mais recente com este nome criado pelo app (em qualquer computador com a mesma credencial).
    func procurarArquivo(nome: String) async throws -> ArquivoNoDrive? {
        var endereco = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let nomeSeguro = nome.replacingOccurrences(of: "'", with: "\\'")
        endereco.queryItems = [
            URLQueryItem(name: "q", value: "name = '\(nomeSeguro)' and trashed = false"),
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
            URLQueryItem(name: "pageSize", value: "1"),
            URLQueryItem(name: "fields", value: "files(id,modifiedTime)"),
        ]
        let (dados, status) = try await chamar(URLRequest(url: endereco.url!))
        guard status == 200 else { throw Self.erro(dados, status) }
        let json = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any]
        return ((json?["files"] as? [[String: Any]]) ?? []).first.flatMap(Self.arquivo)
    }

    /// Dados atuais do arquivo; nil se ele foi apagado (ou foi para a lixeira).
    func metadados(id: String) async throws -> ArquivoNoDrive? {
        var endereco = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(id)")!
        endereco.queryItems = [URLQueryItem(name: "fields", value: "id,modifiedTime,trashed")]
        let (dados, status) = try await chamar(URLRequest(url: endereco.url!))
        if status == 404 { return nil }
        guard status == 200 else { throw Self.erro(dados, status) }
        let json = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any]
        if json?["trashed"] as? Bool == true { return nil }
        return json.flatMap(Self.arquivo)
    }

    func baixar(id: String) async throws -> Data {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(id)?alt=media")!
        let (dados, status) = try await chamar(URLRequest(url: url))
        guard status == 200 else { throw Self.erro(dados, status) }
        return dados
    }

    /// Cria o arquivo (id nil) ou troca o conteúdo dele.
    func enviar(_ conteudo: Data, nome: String, id: String?) async throws -> ArquivoNoDrive {
        var pedido: URLRequest
        if let id {
            pedido = URLRequest(url: URL(string:
                "https://www.googleapis.com/upload/drive/v3/files/\(id)?uploadType=media&fields=id,modifiedTime")!)
            pedido.httpMethod = "PATCH"
            pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
            pedido.httpBody = conteudo
        } else {
            pedido = URLRequest(url: URL(string:
                "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,modifiedTime")!)
            pedido.httpMethod = "POST"
            let divisa = "orthck-\(UUID().uuidString)"
            pedido.setValue("multipart/related; boundary=\(divisa)", forHTTPHeaderField: "Content-Type")
            let info = try JSONSerialization.data(withJSONObject: ["name": nome, "mimeType": "application/json"])
            var corpo = Data()
            corpo.append(Data("--\(divisa)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
            corpo.append(info)
            corpo.append(Data("\r\n--\(divisa)\r\nContent-Type: application/json\r\n\r\n".utf8))
            corpo.append(conteudo)
            corpo.append(Data("\r\n--\(divisa)--\r\n".utf8))
            pedido.httpBody = corpo
        }
        let (dados, status) = try await chamar(pedido)
        guard status == 200,
              let json = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any],
              let arquivo = Self.arquivo(json) else { throw Self.erro(dados, status) }
        return arquivo
    }

    /// Envio "retomável" do Google, para arquivos grandes (como o .zip da pasta de modelos): cria o
    /// arquivo (id nil) ou troca o conteúdo dele.
    func enviarArquivoGrande(_ conteudo: Data, nome: String, tipo: String, id: String?) async throws -> ArquivoNoDrive {
        let endereco = id.map { "https://www.googleapis.com/upload/drive/v3/files/\($0)?uploadType=resumable&fields=id,modifiedTime" }
            ?? "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,modifiedTime"
        var inicio = URLRequest(url: URL(string: endereco)!)
        inicio.httpMethod = id == nil ? "POST" : "PATCH"
        inicio.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        inicio.setValue(tipo, forHTTPHeaderField: "X-Upload-Content-Type")
        inicio.setValue(String(conteudo.count), forHTTPHeaderField: "X-Upload-Content-Length")
        let info: [String: Any] = id == nil ? ["name": nome, "mimeType": tipo] : [:]
        inicio.httpBody = try JSONSerialization.data(withJSONObject: info)
        inicio.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        let (dadosDoInicio, respostaDoInicio) = try await URLSession.shared.data(for: inicio)
        let http = respostaDoInicio as? HTTPURLResponse
        guard http?.statusCode == 200, let sessao = http?.value(forHTTPHeaderField: "Location"), let url = URL(string: sessao) else {
            if http?.statusCode == 401 { tokenDeAcesso = nil }
            throw Self.erro(dadosDoInicio, http?.statusCode ?? 0)
        }
        var envio = URLRequest(url: url)
        envio.httpMethod = "PUT"
        envio.setValue(tipo, forHTTPHeaderField: "Content-Type")
        envio.timeoutInterval = 600
        let (dados, resposta) = try await URLSession.shared.upload(for: envio, from: conteudo)
        let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 201,
              let json = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any],
              let arquivo = Self.arquivo(json) else { throw Self.erro(dados, status) }
        return arquivo
    }

    private func chamar(_ pedido: URLRequest) async throws -> (Data, Int) {
        var pedido = pedido
        pedido.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        let (dados, resposta) = try await URLSession.shared.data(for: pedido)
        let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { tokenDeAcesso = nil }
        return (dados, status)
    }

    // MARK: Auxiliares

    private static func arquivo(_ json: [String: Any]) -> ArquivoNoDrive? {
        guard let id = json["id"] as? String else { return nil }
        return ArquivoNoDrive(id: id, modificado: json["modifiedTime"] as? String ?? "")
    }

    private static func erro(_ dados: Data, _ status: Int) -> ErroGoogle {
        let json = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any]
        let mensagem = (json?["error"] as? [String: Any])?["message"] as? String
        return .resposta("Google Drive respondeu \(status)\(mensagem.map { ": \($0)" } ?? ".")")
    }

    private static func formulario(_ campos: [String: String]) -> String {
        var permitidos = CharacterSet.alphanumerics
        permitidos.insert(charactersIn: "-._~")
        return campos.map { chave, valor in
            "\(chave)=\(valor.addingPercentEncoding(withAllowedCharacters: permitidos) ?? valor)"
        }.joined(separator: "&")
    }

    private static func textoAleatorio() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ dados: Data) -> String {
        dados.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Recebe no próprio Mac (127.0.0.1, porta livre) a volta do navegador depois do login no Google.
/// Atende várias conexões ao mesmo tempo (navegadores abrem conexões extras sem pedido) e aceita
/// também o endereço colado à mão, caso o navegador não consiga voltar sozinho.
final class ReceptorDeLogin: @unchecked Sendable {
    private let soquete: Int32
    let porta: UInt16
    private let trava = NSLock()
    private var parado = false
    private var resultado: Result<[String: String], Error>?
    private var continuacao: CheckedContinuation<[String: String], Error>?

    init() throws {
        let novo = socket(AF_INET, SOCK_STREAM, 0)
        guard novo >= 0 else { throw ErroGoogle.resposta("Não foi possível preparar o login no Google.") }
        var endereco = sockaddr_in()
        endereco.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        endereco.sin_family = sa_family_t(AF_INET)
        endereco.sin_port = 0
        endereco.sin_addr.s_addr = inet_addr("127.0.0.1")
        let ligado = withUnsafePointer(to: &endereco) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(novo, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard ligado == 0, listen(novo, 16) == 0 else {
            close(novo)
            throw ErroGoogle.resposta("Não foi possível preparar o login no Google.")
        }
        var tamanho = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &endereco) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(novo, $0, &tamanho) }
        }
        soquete = novo
        porta = UInt16(bigEndian: endereco.sin_port)
    }

    /// Fecha a porta; quem estiver esperando recebe "cancelado".
    func parar() {
        trava.lock()
        let fechar = !parado
        parado = true
        trava.unlock()
        if fechar { close(soquete) }
        concluir(.failure(ErroGoogle.cancelado))
    }

    /// Endereço copiado da barra do navegador (http://127.0.0.1:…/?code=…); false se não for a volta do login.
    func entregar(endereco: String) -> Bool {
        let parametros = Self.parametros(URLComponents(string: endereco.trimmingCharacters(in: .whitespacesAndNewlines)))
        guard parametros["code"] != nil || parametros["error"] != nil else { return false }
        concluir(.success(parametros))
        return true
    }

    /// Espera a volta do navegador (até 10 minutos) e devolve os parâmetros do endereço (code, state, error).
    func aguardarResposta() async throws -> [String: String] {
        DispatchQueue.global(qos: .userInitiated).async { self.escutar() }
        return try await withCheckedThrowingContinuation { continuacao in
            trava.lock()
            if let resultado {
                trava.unlock()
                continuacao.resume(with: resultado)
            } else {
                self.continuacao = continuacao
                trava.unlock()
            }
        }
    }

    private var concluido: Bool {
        trava.lock()
        defer { trava.unlock() }
        return resultado != nil
    }

    private func concluir(_ resposta: Result<[String: String], Error>) {
        trava.lock()
        guard resultado == nil else {
            trava.unlock()
            return
        }
        resultado = resposta
        let esperando = continuacao
        continuacao = nil
        trava.unlock()
        esperando?.resume(with: resposta)
    }

    private func escutar() {
        var clientes: [Int32] = []
        defer { clientes.forEach { close($0) } }
        let limite = Date().addingTimeInterval(600)
        while Date() < limite, !concluido {
            var lista = [pollfd(fd: soquete, events: Int16(POLLIN), revents: 0)]
                + clientes.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
            let pronto = poll(&lista, nfds_t(lista.count), 500)
            if pronto < 0 {
                concluir(.failure(ErroGoogle.cancelado))
                return
            }
            if pronto == 0 { continue }
            if lista[0].revents & Int16(POLLIN) != 0 {
                let cliente = accept(soquete, nil, nil)
                if cliente >= 0 { clientes.append(cliente) }
            } else if lista[0].revents != 0 {
                // A porta foi fechada (cancelado).
                concluir(.failure(ErroGoogle.cancelado))
                return
            }
            for item in lista.dropFirst() where item.revents != 0 {
                clientes.removeAll { $0 == item.fd }
                if let parametros = responder(item.fd) {
                    concluir(.success(parametros))
                    return
                }
            }
        }
        concluir(.failure(ErroGoogle.tempoEsgotado))
    }

    /// Lê o pedido do navegador, mostra a página final e fecha a conexão; devolve os parâmetros
    /// se for a volta do login (pedidos como o do ícone da página são ignorados).
    private func responder(_ cliente: Int32) -> [String: String]? {
        defer { close(cliente) }
        let capacidade = 16_384
        var buffer = [UInt8](repeating: 0, count: capacidade)
        let lidos = read(cliente, &buffer, capacidade)
        guard lidos > 0 else { return nil }
        let pedido = String(decoding: buffer[0..<lidos], as: UTF8.self)
        let caminho = pedido.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let parametros = Self.parametros(URLComponents(string: "http://127.0.0.1\(caminho)"))
        let ehVolta = parametros["code"] != nil || parametros["error"] != nil
        let html = """
        <!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>Orthck</title>
        <body style="font-family:-apple-system,sans-serif;text-align:center;padding:60px">
        <h2>\(parametros["code"] != nil ? "Google Drive autorizado ✓" : "Login não concluído")</h2>
        <p>Pode fechar esta janela e voltar para o Orthck.</p></body></html>
        """
        let resposta = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n" + html
        let bytes = Array(resposta.utf8)
        _ = bytes.withUnsafeBytes { write(cliente, $0.baseAddress, bytes.count) }
        return ehVolta ? parametros : nil
    }

    private static func parametros(_ endereco: URLComponents?) -> [String: String] {
        var parametros: [String: String] = [:]
        for item in endereco?.queryItems ?? [] {
            parametros[item.name] = item.value ?? ""
        }
        return parametros
    }
}
