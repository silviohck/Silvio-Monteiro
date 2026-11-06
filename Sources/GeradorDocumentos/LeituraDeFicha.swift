import AppKit
import Foundation
import Security

/// O que o Claude leu na foto de uma ficha (ex.: Avaliação ortopédica de Araruna).
struct FichaLida: Decodable {
    struct DadosDoPaciente: Decodable {
        var nome = ""
        var dataNascimento = ""
        var cpf = ""
        var rg = ""
        var telefone = ""
        var email = ""
        var endereco = ""
        var numero = ""
        var bairro = ""
        var cidade = ""
        var uf = ""
        var cep = ""
        var cns = ""
        var convenio = ""
    }

    struct Atendimento: Decodable {
        var dataAvaliacao = ""
        var cid = ""
        var queixaPrincipal = ""
        var hda = ""
        var exameFisico = ""
        var examesComplementares = ""
        var diagnostico = ""
        var programacaoTerapeutica = ""
        var perfilCerII = ""
    }

    var paciente = DadosDoPaciente()
    var atendimento = Atendimento()
    /// Nome do serviço impresso no cabeçalho da ficha (ex.: "Araruna CER II").
    var local = ""
    /// Campos com leitura duvidosa (chaves de `paciente` e `atendimento`).
    var duvidas: [String] = []
    var transcricao = ""
}

/// Chave de API da Anthropic, guardada nas Chaves (Keychain) do Mac — nunca no dados.json nem no Drive.
enum ChaveDaAnthropic {
    private static let servico = "com.silviomonteiro.GeradorDocumentos.anthropic"
    private static let conta = "api-key"

    private static var consulta: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: servico,
         kSecAttrAccount as String: conta]
    }

    static var valor: String? {
        var pedido = consulta
        pedido[kSecReturnData as String] = true
        pedido[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultado: AnyObject?
        guard SecItemCopyMatching(pedido as CFDictionary, &resultado) == errSecSuccess,
              let dados = resultado as? Data, let texto = String(data: dados, encoding: .utf8),
              !texto.isEmpty else { return nil }
        return texto
    }

    static var configurada: Bool { valor != nil }

    @discardableResult
    static func guardar(_ chave: String) -> Bool {
        let texto = chave.trimmingCharacters(in: .whitespacesAndNewlines)
        apagar()
        guard !texto.isEmpty else { return true }
        var novo = consulta
        novo[kSecValueData as String] = Data(texto.utf8)
        novo[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(novo as CFDictionary, nil) == errSecSuccess
    }

    static func apagar() {
        SecItemDelete(consulta as CFDictionary)
    }
}

/// Lê a foto de uma ficha com o Claude (API da Anthropic) e devolve os campos para conferir.
enum LeituraDeFicha {
    static let modelo = "claude-opus-5-5"
    private static let endereco = URL(string: "https://api.anthropic.com/v1/messages")!

    enum Falha: LocalizedError, Equatable {
        case semChave
        case imagemInvalida
        case recusa(String)
        case incompleta
        case resposta(Int, String)
        case formato

        var errorDescription: String? {
            switch self {
            case .semChave:
                return "Informe a chave de API da Anthropic em Orthck › Ajustes… › Leitura de fichas."
            case .imagemInvalida:
                return "Não foi possível abrir esta imagem. Use uma foto JPG, PNG ou HEIC."
            case .recusa(let motivo):
                return "O Claude não leu esta imagem\(motivo.isEmpty ? "" : " (\(motivo))")."
            case .incompleta:
                return "A leitura ficou incompleta. Tente de novo."
            case .resposta(let status, let mensagem):
                switch status {
                case 401: return "Chave de API inválida. Confira em Orthck › Ajustes… › Leitura de fichas."
                case 403: return "Esta chave não tem permissão para usar o modelo."
                case 429: return "Limite de uso da API atingido. Aguarde um pouco e tente de novo."
                case 529, 500...599: return "A API da Anthropic está indisponível agora. Tente de novo em instantes."
                default: return "A API recusou o pedido (\(status)): \(mensagem)"
                }
            case .formato:
                return "A resposta não veio no formato esperado. Tente de novo."
            }
        }
    }

    static func ler(imagem url: URL) async throws -> FichaLida {
        guard let chave = ChaveDaAnthropic.valor else { throw Falha.semChave }
        let jpeg = try jpeg(de: url)
        let corpo: [String: Any] = [
            "model": modelo,
            "max_tokens": 16000,
            // Se o modelo recusar, a própria API tenta o modelo recomendado para o caso.
            "fallbacks": "default",
            "output_config": [
                "effort": "high",
                "format": ["type": "json_schema", "schema": esquema],
            ],
            "system": instrucoes,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image",
                     "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
                    ["type": "text", "text": "Transcreva esta ficha e preencha os campos."],
                ],
            ]],
        ]
        var pedido = URLRequest(url: endereco, timeoutInterval: 300)
        pedido.httpMethod = "POST"
        pedido.setValue("application/json", forHTTPHeaderField: "content-type")
        pedido.setValue(chave, forHTTPHeaderField: "x-api-key")
        pedido.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        pedido.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        pedido.httpBody = try JSONSerialization.data(withJSONObject: corpo)

        let (dados, resposta) = try await URLSession.shared.data(for: pedido)
        let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let mensagem = (json["error"] as? [String: Any])?["message"] as? String ?? ""
            throw Falha.resposta(status, mensagem)
        }
        switch json["stop_reason"] as? String {
        case "refusal":
            let detalhes = json["stop_details"] as? [String: Any]
            throw Falha.recusa(detalhes?["explanation"] as? String ?? "")
        case "max_tokens":
            throw Falha.incompleta
        default:
            break
        }
        let texto = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard let conteudo = texto.data(using: .utf8),
              let ficha = try? JSONDecoder().decode(FichaLida.self, from: conteudo) else { throw Falha.formato }
        return ficha
    }

    /// Reduz a foto para no máximo 2000 px e JPEG (abaixo do limite de 5 MB por imagem da API).
    static func jpeg(de url: URL, ladoMaximo: CGFloat = 2000) throws -> Data {
        guard let imagem = NSImage(contentsOf: url),
              let original = imagem.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw Falha.imagemInvalida
        }
        let largura = CGFloat(original.width), altura = CGFloat(original.height)
        let fator = min(1, ladoMaximo / max(largura, altura))
        let tamanho = CGSize(width: max(1, (largura * fator).rounded()), height: max(1, (altura * fator).rounded()))
        guard let contexto = CGContext(
            data: nil, width: Int(tamanho.width), height: Int(tamanho.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw Falha.imagemInvalida }
        contexto.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        contexto.fill(CGRect(origin: .zero, size: tamanho))
        contexto.interpolationQuality = .high
        contexto.draw(original, in: CGRect(origin: .zero, size: tamanho))
        guard let reduzida = contexto.makeImage(),
              let dados = NSBitmapImageRep(cgImage: reduzida).representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        else { throw Falha.imagemInvalida }
        return dados
    }

    static let camposDoPaciente = ["nome", "dataNascimento", "cpf", "rg", "telefone", "email", "endereco", "numero",
                                   "bairro", "cidade", "uf", "cep", "cns", "convenio"]
    static let camposDoAtendimento = ["dataAvaliacao", "cid", "queixaPrincipal", "hda", "exameFisico",
                                      "examesComplementares", "diagnostico", "programacaoTerapeutica", "perfilCerII"]

    private static func objeto(_ campos: [String]) -> [String: Any] {
        ["type": "object", "additionalProperties": false, "required": campos,
         "properties": Dictionary(uniqueKeysWithValues: campos.map { ($0, ["type": "string"]) })]
    }

    static var esquema: [String: Any] {
        ["type": "object", "additionalProperties": false,
         "required": ["paciente", "atendimento", "local", "duvidas", "transcricao"],
         "properties": [
            "paciente": objeto(camposDoPaciente),
            "atendimento": objeto(camposDoAtendimento),
            "local": ["type": "string"],
            "duvidas": ["type": "array", "items": ["type": "string", "enum": camposDoPaciente + camposDoAtendimento]],
            "transcricao": ["type": "string"],
         ]]
    }

    static let instrucoes = """
    Você transcreve fichas médicas em português (muitas preenchidas à mão) para cadastrar pacientes no Orthck, um app de consultório de ortopedia.
    A ficha mais comum é a “Avaliação ortopédica” do CER II de Araruna (PB): 1. Identificação (Nome, D/N, Endereço, nº, CPF, Bairro, Cidade, UF, CEP, Diagnóstico, Data da Avaliação, Tel, CNS), 2. Q.P., 3. H.D.A., 4. Exame físico, 5. Programação terapêutica, CID 10 e Perfil CER II. Outras fichas também podem aparecer: use os mesmos campos.
    Regras:
    - Transcreva só o que está escrito. Nunca invente nem complete nomes, números ou datas. Campo em branco ou ausente: string vazia.
    - Trecho que você não consegue ler: escreva [ilegível] no lugar e inclua a chave do campo em duvidas. Inclua também em duvidas qualquer campo em que você hesitou entre leituras (ex.: um dígito do CPF).
    - Os rótulos impressos do formulário (como “Nome:”) não são valores.
    - Datas no formato DD/MM/AAAA quando estiverem completas; se o ano estiver com 2 dígitos, mantenha como escrito.
    - CPF, CNS, CEP e telefone: só os dígitos que estão na ficha, sem adivinhar os que faltam.
    - local: nome do serviço/cidade impresso no cabeçalho da ficha (ex.: “Araruna CER II”), ou vazio.
    - examesComplementares: exames citados (RX, RM, USG…) quando estiverem separados; se estiverem dentro do exame físico, deixe-os lá.
    - transcricao: todo o texto escrito à mão na ficha, na ordem em que aparece, com quebras de linha.
    """

    // MARK: Formatação no padrão do Orthck

    static func digitos(_ texto: String) -> String { texto.filter(\.isNumber) }

    static func data(_ texto: String) -> String {
        let partes = texto.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { "/.-".contains($0) }).map(String.init)
        guard partes.count == 3, partes.allSatisfy({ Int($0) != nil }), partes[0].count <= 2, partes[1].count <= 2 else {
            return texto.trimmingCharacters(in: .whitespaces)
        }
        var ano = partes[2]
        if ano.count == 2, let numero = Int(ano) {
            let atual = Calendar(identifier: .gregorian).component(.year, from: Date()) % 100
            ano = (numero > atual ? "19" : "20") + ano
        }
        guard ano.count == 4 else { return texto.trimmingCharacters(in: .whitespaces) }
        return String(repeating: "0", count: 2 - partes[0].count) + partes[0] + "/"
            + String(repeating: "0", count: 2 - partes[1].count) + partes[1] + "/" + ano
    }

    static func cpf(_ texto: String) -> String {
        let d = Array(digitos(texto))
        guard d.count == 11 else { return texto.trimmingCharacters(in: .whitespaces) }
        return "\(String(d[0..<3])).\(String(d[3..<6])).\(String(d[6..<9]))-\(String(d[9..<11]))"
    }

    static func cep(_ texto: String) -> String {
        let d = Array(digitos(texto))
        guard d.count == 8 else { return texto.trimmingCharacters(in: .whitespaces) }
        return "\(String(d[0..<5]))-\(String(d[5..<8]))"
    }

    static func cpfValido(_ texto: String) -> Bool {
        let d = digitos(texto).compactMap { Int(String($0)) }
        guard d.count == 11, Set(d).count > 1 else { return false }
        func digito(_ quantos: Int) -> Int {
            let soma = (0..<quantos).reduce(0) { $0 + d[$1] * (quantos + 1 - $1) }
            let resto = (soma * 10) % 11
            return resto == 10 ? 0 : resto
        }
        return digito(9) == d[9] && digito(10) == d[10]
    }

    /// Dados do paciente lidos, já no formato do cadastro (MAIÚSCULAS, datas DD/MM/AAAA, CPF e CEP formatados).
    static func cadastro(de lida: FichaLida.DadosDoPaciente) -> Paciente {
        func m(_ texto: String) -> String {
            texto.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: Locale(identifier: "pt_BR"))
        }
        var paciente = Paciente()
        paciente.nome = m(lida.nome)
        paciente.dataNascimento = data(lida.dataNascimento)
        paciente.cpf = cpf(lida.cpf)
        paciente.rg = m(lida.rg)
        paciente.telefone = m(lida.telefone)
        paciente.email = lida.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        paciente.endereco = m(lida.endereco)
        paciente.numero = m(lida.numero)
        paciente.bairro = m(lida.bairro)
        paciente.cidade = m(lida.cidade)
        paciente.uf = m(lida.uf)
        paciente.cep = cep(lida.cep)
        paciente.cns = digitos(lida.cns).count == 15 ? digitos(lida.cns) : m(lida.cns)
        paciente.convenio = m(lida.convenio)
        return paciente
    }

    /// Campos do cadastro que podem vir da ficha (o nome é tratado à parte).
    static let caminhosDoCadastro: [(String, WritableKeyPath<Paciente, String>)] = [
        ("dataNascimento", \.dataNascimento), ("cpf", \.cpf), ("rg", \.rg), ("telefone", \.telefone),
        ("email", \.email), ("endereco", \.endereco), ("numero", \.numero), ("bairro", \.bairro),
        ("cidade", \.cidade), ("uf", \.uf), ("cep", \.cep), ("cns", \.cns), ("convenio", \.convenio),
    ]
}
