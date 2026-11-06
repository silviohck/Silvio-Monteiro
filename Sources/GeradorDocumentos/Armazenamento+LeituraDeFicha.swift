import Foundation

/// Cadastro do paciente a partir da foto da ficha (aba Prontuário › Ler ficha por foto).
extension Armazenamento {
    enum PacienteDaFicha {
        /// Mesmo CPF, mesmo CNS, ou o único com este nome (e nascimento que não contradiz).
        case encontrado(Paciente)
        /// Mais de um paciente com este nome e nada que diferencie: quem escolhe é a pessoa.
        case homonimos([Paciente])
        case novo
    }

    func procurar(_ lido: Paciente) -> PacienteDaFicha {
        let cpf = LeituraDeFicha.digitos(lido.cpf)
        if cpf.count == 11, let mesmo = dados.pacientes.first(where: { LeituraDeFicha.digitos($0.cpf) == cpf }) {
            return .encontrado(mesmo)
        }
        let cns = LeituraDeFicha.digitos(lido.cns)
        if cns.count == 15, let mesmo = dados.pacientes.first(where: { LeituraDeFicha.digitos($0.cns) == cns }) {
            return .encontrado(mesmo)
        }
        let nascimento = lido.dataNascimento.trimmingCharacters(in: .whitespaces)
        let mesmoNome = pacientes(chamados: lido.nome)
        if !nascimento.isEmpty, let mesmo = mesmoNome.first(where: { $0.dataNascimento.trimmingCharacters(in: .whitespaces) == nascimento }) {
            return .encontrado(mesmo)
        }
        // Mesmo nome, mas outro CPF ou outra data de nascimento no cadastro: não é a mesma pessoa.
        let compativeis = mesmoNome.filter { paciente in
            let outroCPF = LeituraDeFicha.digitos(paciente.cpf)
            let outroNascimento = paciente.dataNascimento.trimmingCharacters(in: .whitespaces)
            return !(cpf.count == 11 && outroCPF.count == 11) && (nascimento.isEmpty || outroNascimento.isEmpty)
        }
        if compativeis.count == 1 && mesmoNome.count == 1 { return .encontrado(compativeis[0]) }
        if mesmoNome.isEmpty { return .novo }
        return .homonimos(mesmoNome)
    }

    struct CadastroDaFicha {
        var paciente: Paciente
        var novo: Bool
        /// Campos que estavam vazios no cadastro e foram completados com a ficha.
        var completados: [String] = []
        /// Campos em que a ficha diz outra coisa: fica o que já estava no cadastro.
        var diferentes: [String] = []
    }

    /// Cria o cadastro (paciente novo) ou completa os campos vazios do cadastro existente. O que já estava
    /// no cadastro não é trocado.
    @discardableResult
    func cadastrar(_ lido: Paciente, em existente: Paciente?, local: LocalAtendimento?) -> CadastroDaFicha {
        guard var paciente = existente else {
            var novo = novoPaciente(nome: lido.nome)
            for (_, caminho) in LeituraDeFicha.caminhosDoCadastro where !Self.ilegivel(lido[keyPath: caminho]) {
                novo[keyPath: caminho] = lido[keyPath: caminho]
            }
            novo.localID = local?.id
            atualizarPaciente(novo)
            return CadastroDaFicha(paciente: novo, novo: true)
        }
        var resultado = CadastroDaFicha(paciente: paciente, novo: false)
        for (chave, caminho) in LeituraDeFicha.caminhosDoCadastro {
            let daFicha = lido[keyPath: caminho].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !daFicha.isEmpty, !Self.ilegivel(daFicha) else { continue }
            let atual = paciente[keyPath: caminho].trimmingCharacters(in: .whitespacesAndNewlines)
            if atual.isEmpty {
                paciente[keyPath: caminho] = daFicha
                resultado.completados.append(chave)
            } else if !Self.mesmoValor(atual, daFicha, numerico: Self.camposNumericos.contains(chave)) {
                resultado.diferentes.append(chave)
            }
        }
        if paciente.localID == nil || self.local(paciente.localID) == nil { paciente.localID = local?.id }
        atualizarPaciente(paciente)
        resultado.paciente = paciente
        return resultado
    }

    private static let camposNumericos: Set<String> = ["cpf", "cns", "cep", "telefone", "numero", "dataNascimento"]

    /// "(83) 99999-0000" e "83999990000" são o mesmo telefone; nos outros campos, sem diferenciar maiúsculas e acentos.
    private static func mesmoValor(_ a: String, _ b: String, numerico: Bool) -> Bool {
        if numerico, !LeituraDeFicha.digitos(a).isEmpty { return LeituraDeFicha.digitos(a) == LeituraDeFicha.digitos(b) }
        return a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    static func ilegivel(_ texto: String) -> Bool {
        texto.range(of: "[ilegível]", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
