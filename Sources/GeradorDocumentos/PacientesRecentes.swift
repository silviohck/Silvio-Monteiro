import Foundation

/// Pacientes atendidos (pelo Histórico), para o painel lateral da tela Gerar documento.
extension Armazenamento {
    /// Dias em que houve documento gerado, do mais recente para o mais antigo.
    var diasComAtendimento: [Date] {
        let calendario = Calendar.current
        return Set(dados.historico.map { calendario.startOfDay(for: $0.data) }).sorted(by: >)
    }

    /// Os pacientes atendidos mais recentes, com o último documento de cada um.
    /// `local` nil = todos os locais; `dia` = só quem teve documento nesse dia.
    func pacientesRecentes(local: String?, dia: Date?, limite: Int) -> [(paciente: Paciente, ultimo: DocumentoGerado)] {
        var documentos = dados.historico
        if let local {
            documentos = documentos.filter { $0.local.map { Self.mesmoNome($0, local) } ?? false }
        }
        if let dia {
            documentos = documentos.filter { Calendar.current.isDate($0.data, inSameDayAs: dia) }
        }
        var vistos = Set<Paciente.ID>()
        var lista: [(paciente: Paciente, ultimo: DocumentoGerado)] = []
        for documento in documentos.sorted(by: { $0.data > $1.data }) {
            let paciente = paciente(documento.pacienteID)
                ?? dados.pacientes.first { $0.nome.caseInsensitiveCompare(documento.paciente) == .orderedSame }
            guard let paciente, vistos.insert(paciente.id).inserted else { continue }
            lista.append((paciente, documento))
            if lista.count == limite { break }
        }
        return lista
    }

    /// Documentos gerados para o paciente, do mais recente para o mais antigo.
    func documentos(de paciente: Paciente) -> [DocumentoGerado] {
        dados.historico
            .filter { documento in
                documento.pacienteID.map { $0 == paciente.id }
                    ?? (documento.paciente.caseInsensitiveCompare(paciente.nome) == .orderedSame)
            }
            .sorted { $0.data > $1.data }
    }
}
