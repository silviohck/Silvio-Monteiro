import DocxTemplateKit
import Foundation

/// Fichas do Prontuário: modelos .docx próprios da aba Prontuário (separados dos modelos de documentos).
extension Armazenamento {
    /// Fichas deste local mais as de todos os locais, em ordem alfabética.
    func fichas(para local: LocalAtendimento?) -> [ModeloDocumento] {
        dados.fichas
            .filter { $0.localID == nil || $0.localID == local?.id }
            .sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
    }

    /// Grava as fichas que vêm com o app (se faltarem) e as liga ao local de mesmo nome (Araruna).
    func instalarFichasProntas() {
        let arquivos = FileManager.default
        let url = pastaModelos.appendingPathComponent(FichasProntas.arquivoAraruna)
        if !arquivos.fileExists(atPath: url.path), let conteudo = FichasProntas.araruna {
            try? conteudo.write(to: url, options: .atomic)
        }
        guard arquivos.fileExists(atPath: url.path) else { return }
        let campos = (try? DocxTemplate.placeholders(in: url)) ?? []
        let localDeAraruna = dados.locais.first {
            $0.nome.range(of: "araruna", options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        if let indice = dados.fichas.firstIndex(where: { $0.id == FichasProntas.idAraruna }) {
            var ficha = dados.fichas[indice]
            // Versão nova da ficha embutida: passa a usar o arquivo novo.
            if ficha.arquivo != FichasProntas.arquivoAraruna {
                let antigo = urlDoModelo(ficha)
                ficha.arquivo = FichasProntas.arquivoAraruna
                ficha.campos = campos
                try? arquivos.removeItem(at: antigo)
            }
            if ficha.localID == nil, let localDeAraruna { ficha.localID = localDeAraruna.id }
            if ficha != dados.fichas[indice] { dados.fichas[indice] = ficha }
            return
        }
        dados.fichas.append(ModeloDocumento(
            id: FichasProntas.idAraruna, nome: FichasProntas.nomeAraruna, arquivo: FichasProntas.arquivoAraruna,
            campos: campos, categoria: "Prontuário", localID: localDeAraruna?.id
        ))
    }

    /// Acrescenta uma ficha (.docx com {{CAMPOS}}) do local escolhido (nil = todos os locais).
    @discardableResult
    func importarFicha(de origem: URL, localID: UUID?) throws -> ModeloDocumento {
        let arquivo = "\(UUID().uuidString).docx"
        let campos = try Self.copiarModelo(origem, para: pastaModelos.appendingPathComponent(arquivo))
        let ficha = ModeloDocumento(
            nome: origem.deletingPathExtension().lastPathComponent, arquivo: arquivo, campos: campos,
            categoria: "Prontuário", localID: localID
        )
        dados.fichas.append(ficha)
        return ficha
    }

    /// As fichas que vêm com o app não são apagadas (voltariam ao abrir).
    func removerFicha(_ ficha: ModeloDocumento) {
        guard ficha.id != FichasProntas.idAraruna else { return }
        try? FileManager.default.removeItem(at: urlDoModelo(ficha))
        dados.fichas.removeAll { $0.id == ficha.id }
    }
}
