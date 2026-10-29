import SwiftUI

/// Lateral da tela Gerar documento: os 5 últimos pacientes atendidos (pelo Histórico).
/// Um clique preenche o nome e o cadastro do paciente.
struct UltimosPacientes: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    let escolher: (DocumentoGerado) -> Void

    /// O documento mais recente de cada paciente, do mais novo para o mais antigo.
    private var recentes: [DocumentoGerado] {
        var vistos = Set<String>()
        var lista: [DocumentoGerado] = []
        for documento in armazenamento.dados.historico.sorted(by: { $0.data > $1.data }) {
            let nome = documento.paciente.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nome.isEmpty else { continue }
            let chave = documento.pacienteID?.uuidString ?? nome.uppercased()
            guard vistos.insert(chave).inserted else { continue }
            lista.append(documento)
            if lista.count == 5 { break }
        }
        return lista
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TituloSecao("Últimos pacientes", icone: "clock.arrow.circlepath")
            let lista = recentes
            if lista.isEmpty {
                Text("Os pacientes atendidos aparecem aqui.")
                    .fonteApp(.apoio)
                    .foregroundStyle(.secondary)
            }
            ForEach(lista) { documento in
                Button {
                    escolher(documento)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(documento.paciente.uppercased())
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text([documento.modelo, documento.local ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .fonteApp(.legenda)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(documento.data.formatted(date: .abbreviated, time: .shortened))
                            .fonteApp(.legenda)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Tema.lateral))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Usar \(documento.paciente)")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Tema.fundo)
    }
}
