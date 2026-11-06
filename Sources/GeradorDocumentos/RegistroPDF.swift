import AppKit
import PDFKit
import Quartz

/// Cópia em PDF de cada documento gerado, só para registro: Registro de arquivos › Local › Paciente.
/// O PDF é feito pelo próprio Word (fica igual ao documento) e depois reduzido (filtro "Reduzir
/// Tamanho do Arquivo" do macOS), para ocupar pouco espaço.
enum RegistroPDF {
    /// Pasta padrão: Documentos › Registro de arquivos.
    static var pastaPadrao: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Registro de arquivos", isDirectory: true)
    }

    static func pasta(_ escolhida: String) -> URL {
        escolhida.isEmpty ? pastaPadrao : URL(fileURLWithPath: escolhida, isDirectory: true)
    }

    /// Registro de arquivos / <Local> / <Paciente> / <nome do documento>.pdf, sem sobrescrever.
    static func destino(para docx: URL, base: URL, local: String?, paciente: String) -> URL {
        let nomeDoLocal = Armazenamento.nomeSeguro(local?.isEmpty == false ? local! : "Sem local")
        let nomeDoPaciente = Armazenamento.nomeSeguro(paciente.isEmpty ? "Sem nome" : paciente)
        let pasta = base.appendingPathComponent(nomeDoLocal, isDirectory: true)
            .appendingPathComponent(nomeDoPaciente, isDirectory: true)
        let nome = docx.deletingPathExtension().lastPathComponent
        var url = pasta.appendingPathComponent(nome + ".pdf")
        var numero = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = pasta.appendingPathComponent("\(nome) (\(numero)).pdf")
            numero += 1
        }
        return url
    }

    /// Salva o PDF de registro. Roda na fila do Word (um pedido ao Word por vez, junto com as
    /// impressões). `concluir` recebe o PDF salvo ou a mensagem de erro, na thread principal.
    static func salvar(
        _ docx: URL,
        base: URL,
        local: String?,
        paciente: String,
        concluir: @escaping (Result<URL, Error>) -> Void
    ) {
        guard Impressao.wordInstalado else {
            concluir(.failure(erro("Para salvar o PDF de registro é preciso ter o Microsoft Word instalado.")))
            return
        }
        let final = destino(para: docx, base: base, local: local, paciente: paciente)
        Impressao.filaDoWord.async {
            let resultado = Result<URL, Error> {
                let arquivos = FileManager.default
                // O Word só grava sem pedir permissão dentro da pasta dele; depois o PDF é movido.
                let pastaDoWord = arquivos.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Containers/com.microsoft.Word/Data/tmp", isDirectory: true)
                let temporaria = arquivos.fileExists(atPath: pastaDoWord.path) ? pastaDoWord : arquivos.temporaryDirectory
                let bruto = temporaria.appendingPathComponent("orthck-\(UUID().uuidString).pdf")
                defer { try? arquivos.removeItem(at: bruto) }
                if let falha = Impressao.salvarComoPDF(docx, em: bruto) { throw erro(falha) }
                try arquivos.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
                try reduzir(bruto, para: final)
                return final
            }
            DispatchQueue.main.async { concluir(resultado) }
        }
    }

    /// Grava o PDF com qualidade reduzida; sem o filtro do macOS, grava como veio do Word.
    static func reduzir(_ origem: URL, para destino: URL) throws {
        let filtroURL = URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")
        let existeFiltro = FileManager.default.fileExists(atPath: filtroURL.path)
        let filtro: QuartzFilter? = existeFiltro ? QuartzFilter(url: filtroURL) : nil
        if let documento = PDFDocument(url: origem),
           let filtro,
           let dados = documento.dataRepresentation(options: ["QuartzFilter": filtro]),
           !dados.isEmpty {
            try dados.write(to: destino, options: .atomic)
        } else {
            try FileManager.default.copyItem(at: origem, to: destino)
        }
    }

    private static func erro(_ mensagem: String) -> NSError {
        NSError(domain: "Orthck", code: 1, userInfo: [NSLocalizedDescriptionKey: mensagem])
    }
}
