import Foundation

/// Um modelo de atendimento: texto pronto para o prontuário (Q.P., H.D.A., exame físico, diagnóstico,
/// CID e programação terapêutica). `[LADO]` vira DIREITO, ESQUERDO ou BILATERAL; `___` se completa na consulta.
struct ModeloDeAtendimento: Identifiable, Codable, Hashable {
    var id = UUID()
    var grupo = "Meus modelos"
    var nome: String
    var cid: String
    var diagnostico: String
    var qp: String
    var hda: String
    var exame: String
    var conduta: String
    /// Modelo por tipo de CID (mais genérico, com mais ___).
    var generico = false
    /// Salvo pelo médico ("Salvar como meu modelo"): fica nos dados do app e vem primeiro na busca.
    var meu = false
}

enum ModelosDeAtendimento {
    static let lados = ["DIREITO", "ESQUERDO", "BILATERAL"]

    /// Os 1.050 modelos que vêm com o app (todos os CID ortopédicos).
    static let prontos: [ModeloDeAtendimento] = ModelosDeAtendimentoDados.texto
        .split(separator: "\n")
        .compactMap { linha in
            let partes = linha.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard partes.count == 9 else { return nil }
            return ModeloDeAtendimento(
                grupo: partes[0], nome: partes[1], cid: partes[2], diagnostico: partes[3], qp: partes[4],
                hda: partes[5], exame: partes[6], conduta: partes[7], generico: partes[8] == "1"
            )
        }

    static func simples(_ texto: String) -> String {
        texto.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    /// Busca pelo nome da doença, pelo diagnóstico ou pelo CID (com ou sem ponto). Primeiro os seus
    /// modelos, depois os escritos um a um e por último os modelos por tipo.
    static func buscar(_ termo: String, meus: [ModeloDeAtendimento], limite: Int = 12) -> [ModeloDeAtendimento] {
        let texto = simples(termo).trimmingCharacters(in: .whitespacesAndNewlines)
        guard texto.count >= 2 else { return [] }
        let palavras = texto.split(separator: " ").map(String.init)
        let codigo = texto.replacingOccurrences(of: ".", with: "")
        func nota(_ modelo: ModeloDeAtendimento) -> Int? {
            let cid = simples(modelo.cid).replacingOccurrences(of: ".", with: "")
            let onde = simples(modelo.nome + " " + modelo.diagnostico + " " + modelo.cid)
            var nota: Int
            if cid == codigo {
                nota = 0
            } else if codigo.first?.isLetter == true, codigo.dropFirst().first?.isNumber == true, cid.hasPrefix(codigo) {
                nota = 1
            } else if palavras.allSatisfy({ onde.contains($0) }) {
                nota = simples(modelo.nome).hasPrefix(texto) ? 2 : 3
            } else {
                return nil
            }
            if modelo.meu { nota -= 10 } else if modelo.generico { nota += 5 }
            return nota
        }
        return (meus + prontos)
            .compactMap { modelo in nota(modelo).map { (modelo, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.nome.localizedStandardCompare($1.0.nome) == .orderedAscending }
            .prefix(limite)
            .map(\.0)
    }

    // Partes do corpo, para o lado concordar: JOELHO DIREITO, MÃO DIREITA; outras palavras: À DIREITA.
    static let masculinas: Set<String> = [
        "JOELHO", "JOELHOS", "OMBRO", "PÉ", "QUADRIL", "PUNHO", "TORNOZELO", "COTOVELO", "BRAÇO", "ANTEBRAÇO",
        "MEMBRO", "DEDO", "POLEGAR", "HÁLUX", "FÊMUR", "ÚMERO", "RÁDIO", "CALCÂNEO", "TÁLUS", "ESCAFOIDE",
        "CALCANHAR", "TENDÃO", "NERVO", "MALÉOLO", "METACARPO", "METATARSO", "OLÉCRANO", "COTO", "LADO",
        "PLEXO", "MANGUITO", "SEMILUNAR", "CARPO", "TARSO", "ANTEPÉ", "RETROPÉ", "MEDIOPÉ", "HEMITÓRAX",
        "HEMICORPO", "GLÚTEO", "TRAPÉZIO", "BÍCEPS", "TRÍCEPS", "QUADRÍCEPS", "MENISCO", "LIGAMENTO", "ESTERNOCLEIDOMASTOIDEO",
    ]
    static let femininas: Set<String> = [
        "MÃO", "MÃOS", "PERNA", "COXA", "PATELA", "RÓTULA", "CLAVÍCULA", "ESCÁPULA", "TÍBIA", "FÍBULA", "ULNA",
        "NÁDEGA", "PANTURRILHA", "REGIÃO", "FACE", "ARTICULAÇÃO", "CABEÇA", "AXILA", "VIRILHA", "BORDA", "PLANTA",
        "SOLA", "PALMA", "FALANGE", "BACIA", "PELVE", "SACROILÍACA", "FÁSCIA", "BOLSA", "BAINHA", "COXOFEMORAL",
    ]

    enum Genero { case masculino, feminino, nenhum }

    /// Gênero da expressão antes do [LADO]: "JOELHO" → masculino, "MÃO" → feminino; adjetivos como
    /// INFERIOR/MEDIAL olham a palavra anterior ("MEMBRO INFERIOR" → masculino); outros → nenhum (À DIREITA).
    static func genero(antes texto: Substring) -> Genero {
        let palavras = texto.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "(" || $0 == "/" }).map(String.init)
        for palavra in palavras.reversed().prefix(3) {
            if masculinas.contains(palavra) { return .masculino }
            if femininas.contains(palavra) { return .feminino }
            if palavra.hasSuffix("O") || palavra.hasSuffix("OS") { return .masculino }
            if palavra.hasSuffix("A") || palavra.hasSuffix("AS") { return .feminino }
            // Adjetivo sem gênero (INFERIOR, MEDIAL, PLANTAR…): decide a palavra antes dele.
            if palavra.hasSuffix("R") || palavra.hasSuffix("L") { continue }
            return .nenhum
        }
        return .nenhum
    }

    /// Troca cada [LADO] pelo lado, concordando com o que vem antes: JOELHO DIREITO, MÃO DIREITA,
    /// GONARTROSE À DIREITA, POSITIVO À DIREITA / POSITIVO BILATERALMENTE.
    static func comLado(_ texto: String, _ lado: String) -> String {
        let feminino = lado == "DIREITO" ? "DIREITA" : lado == "ESQUERDO" ? "ESQUERDA" : lado
        var saida = ""
        var resto = Substring(texto)
        while let marca = resto.range(of: "[LADO]") {
            var antes = String(resto[..<marca.lowerBound])
            let palavra: String
            if antes.hasSuffix(" À ") || antes == "À " {
                if lado == "BILATERAL" {
                    antes.removeLast(2)
                    palavra = "BILATERALMENTE"
                } else {
                    palavra = feminino
                }
            } else if lado == "BILATERAL" {
                palavra = lado
            } else {
                switch genero(antes: Substring(antes)) {
                case .masculino: palavra = lado
                case .feminino: palavra = feminino
                case .nenhum: palavra = "À " + feminino
                }
            }
            saida += antes + palavra
            resto = resto[marca.upperBound...]
        }
        return saida + resto
    }

    /// O contrário de `comLado`, para salvar um texto como modelo: o lado volta a ser [LADO].
    static func semLado(_ texto: String, _ lado: String) -> String {
        let padrao: String
        switch lado {
        case "DIREITO": padrao = #"\b(À )?DIREIT[AO]\b"#
        case "ESQUERDO": padrao = #"\b(À )?ESQUERD[AO]\b"#
        default: padrao = #"\bBILATERAL(MENTE)?\b"#
        }
        return texto.replacingOccurrences(of: padrao, with: "[LADO]", options: .regularExpression)
    }
}

extension Armazenamento {
    /// Guarda o modelo nos seus modelos; com o mesmo nome, substitui o anterior.
    func salvarModeloDeAtendimento(_ modelo: ModeloDeAtendimento) {
        var novo = modelo
        novo.meu = true
        if let indice = dados.modelosDeAtendimento.firstIndex(where: {
            ModelosDeAtendimento.simples($0.nome) == ModelosDeAtendimento.simples(novo.nome)
        }) {
            novo.id = dados.modelosDeAtendimento[indice].id
            dados.modelosDeAtendimento[indice] = novo
        } else {
            dados.modelosDeAtendimento.append(novo)
        }
    }

    func apagarModeloDeAtendimento(_ modelo: ModeloDeAtendimento) {
        dados.modelosDeAtendimento.removeAll { $0.id == modelo.id }
    }
}
