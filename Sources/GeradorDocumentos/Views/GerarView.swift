import AppKit
import DocxTemplateKit
import SwiftUI
import UniformTypeIdentifiers

struct GerarView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var modeloID: ModeloDocumento.ID?
    @State private var pacienteID: Paciente.ID?
    @State private var valores: [String: String] = [:]
    @State private var abrirAoGerar = true
    @State private var aviso: String?

    private var modelo: ModeloDocumento? {
        armazenamento.dados.modelos.first { $0.id == modeloID }
    }

    var body: some View {
        if armazenamento.dados.modelos.isEmpty {
            AvisoVazio(
                titulo: "Nenhum modelo importado",
                icone: "doc.text",
                mensagem: "Vá em “Modelos” e importe um arquivo .docx com campos como {{NOME_PACIENTE}}."
            )
        } else {
            formulario
        }
    }

    private var formulario: some View {
        Form {
            Section("Modelo e paciente") {
                Picker("Modelo", selection: $modeloID) {
                    Text("Selecione…").tag(ModeloDocumento.ID?.none)
                    ForEach(armazenamento.dados.modelos) { modelo in
                        Text(modelo.nome).tag(Optional(modelo.id))
                    }
                }
                Picker("Paciente", selection: $pacienteID) {
                    Text("Nenhum (preencher à mão)").tag(Paciente.ID?.none)
                    ForEach(armazenamento.pacientesOrdenados) { paciente in
                        Text(paciente.nome.isEmpty ? "Sem nome" : paciente.nome).tag(Optional(paciente.id))
                    }
                }
            }

            if let modelo {
                Section {
                    if modelo.campos.isEmpty {
                        Text("Este modelo não tem campos {{...}}. O documento será gerado sem alterações.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(modelo.campos, id: \.self) { campo in
                        TextField(campo, text: valor(campo), axis: .vertical)
                            .lineLimit(1...5)
                    }
                } header: {
                    Text("Campos do documento")
                } footer: {
                    Text("Os campos são preenchidos com o cadastro do paciente e a data de hoje; você pode alterar qualquer valor antes de gerar.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Abrir o documento depois de gerar", isOn: $abrirAoGerar)
                    HStack {
                        if let aviso {
                            Label(aviso, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Button("Gerar documento…") { gerar(modelo) }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if modeloID == nil { modeloID = armazenamento.dados.modelos.first?.id }
            preencher()
        }
        .onChange(of: modeloID) { _ in preencher() }
        .onChange(of: pacienteID) { _ in preencher() }
    }

    private func valor(_ campo: String) -> Binding<String> {
        Binding(get: { valores[campo, default: ""] }, set: { valores[campo] = $0 })
    }

    private func preencher() {
        aviso = nil
        guard let modelo else { return }
        let paciente = armazenamento.paciente(pacienteID)
        var novos: [String: String] = [:]
        for campo in modelo.campos {
            novos[campo] = CamposAutomaticos.valor(para: campo, paciente: paciente) ?? ""
        }
        valores = novos
    }

    private func gerar(_ modelo: ModeloDocumento) {
        let paciente = armazenamento.paciente(pacienteID)
        let nomePaciente = paciente?.nome ?? valores.first { CamposAutomaticos.chave($0.key).contains("NOME") }?.value ?? ""

        let painel = NSSavePanel()
        painel.allowedContentTypes = [.documentoWord]
        painel.canCreateDirectories = true
        painel.nameFieldStringValue = nomeDoArquivo(modelo: modelo.nome, paciente: nomePaciente)
        guard painel.runModal() == .OK, let destino = painel.url else { return }

        do {
            try DocxTemplate.fill(template: armazenamento.urlDoModelo(modelo), values: valores, output: destino)
        } catch {
            armazenamento.erro = error.localizedDescription
            return
        }

        // Guarda no cadastro os valores digitados para campos que não são fixos (ex.: diagnóstico).
        if var paciente {
            for campo in modelo.campos where !CamposAutomaticos.ehAutomatico(campo) {
                let texto = valores[campo, default: ""]
                paciente.outrosCampos[campo] = texto.isEmpty ? nil : texto
            }
            armazenamento.atualizarPaciente(paciente)
        }
        armazenamento.registrar(DocumentoGerado(modelo: modelo.nome, paciente: nomePaciente, caminho: destino.path))
        aviso = "Documento salvo: \(destino.lastPathComponent)"
        if abrirAoGerar {
            NSWorkspace.shared.open(destino)
        }
    }

    private func nomeDoArquivo(modelo: String, paciente: String) -> String {
        let nome = paciente.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = nome.isEmpty ? modelo : "\(modelo) - \(nome)"
        return base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".docx"
    }
}
