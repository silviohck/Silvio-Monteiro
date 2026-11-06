import AppKit
import SwiftUI

/// "Salvar PDF de registro" e a pasta Registro de arquivos (mesma opção no Gerar e no Prontuário).
struct OpcaoRegistroPDF: View {
    @AppStorage("salvarRegistroPDF") private var salvar = true
    @AppStorage("pastaRegistroPDF") private var pasta = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Salvar uma cópia em PDF para registro", isOn: $salvar)
            if salvar {
                HStack(spacing: 10) {
                    Text("\(RegistroPDF.pasta(pasta).path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) › local › paciente")
                        .fonteApp(.legenda)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Escolher pasta…", action: escolher).buttonStyle(.link)
                    Button("Abrir") {
                        let url = RegistroPDF.pasta(pasta)
                        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                }
                Text("PDF reduzido, só para registro: o documento continua saindo em Word para imprimir.")
                    .fonteApp(.legenda)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func escolher() {
        let painel = NSOpenPanel()
        painel.canChooseDirectories = true
        painel.canChooseFiles = false
        painel.canCreateDirectories = true
        painel.prompt = "Usar esta pasta"
        painel.message = "Onde criar as pastas de registro (uma por local, dentro uma por paciente)?"
        if painel.runModal() == .OK, let url = painel.url { pasta = url.path }
    }
}

extension Armazenamento {
    /// Salva o PDF de registro do documento, se a opção estiver ligada; `depois` roda ao terminar
    /// (com o aviso a mostrar), para abrir o documento só depois que o Word o fechou.
    func salvarRegistroSeLigado(_ docx: URL, local: String?, paciente: String, depois: @escaping (String?) -> Void) {
        let padroes = UserDefaults.standard
        let ligado = padroes.object(forKey: "salvarRegistroPDF") as? Bool ?? true
        guard ligado else { depois(nil); return }
        let base = RegistroPDF.pasta(padroes.string(forKey: "pastaRegistroPDF") ?? "")
        RegistroPDF.salvar(docx, base: base, local: local, paciente: paciente) { [weak self] resultado in
            switch resultado {
            case .success: depois(" · PDF de registro salvo")
            case .failure(let falha):
                self?.erro = "O documento foi gerado, mas o PDF de registro não foi salvo. \(falha.localizedDescription)"
                depois(nil)
            }
        }
    }
}
