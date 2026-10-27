import AppKit
import SwiftUI

struct ModelosView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var modeloParaExcluir: ModeloDocumento?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ajuda

                if armazenamento.dados.modelos.isEmpty {
                    AvisoVazio(titulo: "Nenhum modelo importado", icone: "doc.text")
                        .frame(height: 200)
                }

                ForEach($armazenamento.dados.modelos) { $modelo in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Nome do modelo", text: $modelo.nome)
                                .textFieldStyle(.roundedBorder)
                                .font(.headline)
                            Text(modelo.campos.isEmpty ? "Nenhum campo encontrado." : "Campos: " + modelo.campos.joined(separator: ", "))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            HStack {
                                Button("Editar no Word") {
                                    NSWorkspace.shared.open(armazenamento.urlDoModelo(modelo))
                                }
                                .help("Abre o modelo salvo. Depois de editar e salvar no Word, clique em “Atualizar campos”.")
                                Button("Atualizar campos") { executar { try armazenamento.atualizarCampos(modelo) } }
                                Button("Substituir arquivo…") {
                                    if let url = escolherArquivosDocx(multiplos: false).first {
                                        executar { try armazenamento.substituirArquivo(modelo, por: url) }
                                    }
                                }
                                Spacer()
                                Button("Excluir", role: .destructive) { modeloParaExcluir = modelo }
                            }
                        }
                        .padding(6)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            Button {
                for url in escolherArquivosDocx(multiplos: true) {
                    executar { try armazenamento.importarModelo(de: url) }
                }
            } label: {
                Label("Importar modelo", systemImage: "square.and.arrow.down")
            }
        }
        .confirmationDialog(
            "Excluir o modelo “\(modeloParaExcluir?.nome ?? "")”?",
            isPresented: Binding(get: { modeloParaExcluir != nil }, set: { if !$0 { modeloParaExcluir = nil } }),
            presenting: modeloParaExcluir
        ) { modelo in
            Button("Excluir", role: .destructive) { armazenamento.removerModelo(modelo) }
        } message: { _ in
            Text("A cópia do modelo guardada pelo app será apagada. Seu arquivo original não é afetado.")
        }
    }

    private var ajuda: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("Como preparar um modelo").font(.headline)
                Text("No Word, escreva os campos entre chaves duplas onde o texto deve ser trocado, por exemplo: Declaro que {{NOME_PACIENTE}}, CPF {{CPF}}, compareceu em {{DATA}}. Depois clique em “Importar modelo”.")
                Text("Preenchidos automaticamente: NOME_PACIENTE (ou NOME), CPF, RG, DATA_NASCIMENTO, IDADE, TELEFONE, EMAIL, ENDERECO, CONVENIO, DATA (dd/mm/aaaa) e DATA_EXTENSO (27 de outubro de 2026). Qualquer outro nome vira um campo para digitar, e o valor fica salvo no cadastro do paciente.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func executar(_ acao: () throws -> Void) {
        do {
            try acao()
        } catch {
            armazenamento.erro = error.localizedDescription
        }
    }
}
