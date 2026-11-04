import SwiftUI
import UniformTypeIdentifiers

/// Barra lateral: cópia automática dos dados no Google Drive, direto pela internet.
/// O app envia a cópia a cada mudança e, ao abrir, junta o que mudou nela em outro computador.
struct CopiaNaNuvem: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @State private var conectando = false

    var body: some View {
        Group {
            if armazenamento.googleConectado {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Label("Google Drive", systemImage: armazenamento.sincronizandoDrive ? "arrow.triangle.2.circlepath" : "icloud.fill")
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Menu {
                            Button("Sincronizar agora") {
                                Task { await armazenamento.sincronizarDrive() }
                            }
                            if let endereco = armazenamento.enderecoNoDrive {
                                Button("Abrir no navegador") { NSWorkspace.shared.open(endereco) }
                            }
                            Divider()
                            Button("Desconectar") { armazenamento.desconectarGoogle() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    if !armazenamento.situacaoNuvem.isEmpty {
                        Text(armazenamento.situacaoNuvem)
                            .fonteApp(.legenda)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    if armazenamento.envioPendente {
                        Text("Mudanças vão para o Drive em até 2 minutos (ou ao fechar o app).")
                            .fonteApp(.legenda)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } else {
                Button {
                    conectando = true
                } label: {
                    Label("Conectar ao Google Drive…", systemImage: "icloud.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .help("Guarda os dados no seu Google Drive e, ao abrir o app, traz o que mudou em outro computador")
                if !armazenamento.situacaoNuvem.isEmpty {
                    Text(armazenamento.situacaoNuvem)
                        .fonteApp(.legenda)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .sheet(isPresented: $conectando) {
            ConectarGoogleView()
                .environmentObject(armazenamento)
        }
    }
}

/// Janela para informar a credencial do Google (o arquivo .json baixado ou o ID e a chave) e autorizar.
struct ConectarGoogleView: View {
    @EnvironmentObject private var armazenamento: Armazenamento
    @Environment(\.dismiss) private var fechar
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var aguardando = false
    @State private var erro: String?
    @State private var enderecoColado = ""
    /// Com a credencial já no app, os campos dela ficam escondidos.
    @State private var mostrarCredencial = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conectar ao Google Drive").font(.title3).bold()
            Text("Ao clicar em Conectar, o navegador abre a página do Google: entre com o e-mail e a senha da sua conta e clique em Permitir. O app nunca vê a sua senha e só enxerga o arquivo que ele mesmo cria no seu Drive.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Credencial do Google", isExpanded: $mostrarCredencial) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Arquivo client_secret….json baixado no Google Cloud Console, ou o ID do cliente e a chave secreta.")
                        .fonteApp(.legenda)
                        .foregroundStyle(.secondary)
                    Button {
                        escolherArquivo()
                    } label: {
                        Label("Escolher arquivo da credencial (.json)…", systemImage: "doc.badge.gearshape")
                    }
                    TextField("ID do cliente", text: $clientID)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Chave secreta do cliente", text: $clientSecret)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.top, 4)
            }
            if aguardando {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Aguardando a autorização no navegador…").foregroundStyle(.secondary)
                }
                Text("Se, depois de clicar em Permitir, o navegador mostrar um erro ou não voltar para o app, copie o endereço da barra do navegador (começa com http://127.0.0.1) e cole aqui:")
                    .fonteApp(.legenda)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField("http://127.0.0.1:…/?…code=…", text: $enderecoColado)
                        .textFieldStyle(.roundedBorder)
                    Button("Usar endereço") {
                        if armazenamento.drive.entregarEndereco(enderecoColado) {
                            erro = nil
                        } else {
                            erro = "Esse endereço não é a volta do login do Google. Copie o endereço inteiro da página que abriu depois de clicar em Permitir."
                        }
                    }
                    .disabled(enderecoColado.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let erro {
                Label(erro, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancelar") {
                    armazenamento.drive.cancelarLogin()
                    fechar()
                }
                    .keyboardShortcut(.cancelAction)
                Button("Conectar") { conectar() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(aguardando || clientID.trimmingCharacters(in: .whitespaces).isEmpty
                        || clientSecret.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            clientID = armazenamento.drive.conta.clientID
            clientSecret = armazenamento.drive.conta.clientSecret
            mostrarCredencial = clientID.isEmpty || clientSecret.isEmpty
        }
    }

    private func escolherArquivo() {
        let painel = NSOpenPanel()
        painel.allowedContentTypes = [.json]
        painel.allowsMultipleSelection = false
        painel.message = "Escolha o arquivo da credencial baixado no Google Cloud Console (client_secret….json)."
        painel.prompt = "Escolher"
        painel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard painel.runModal() == .OK, let url = painel.url else { return }
        do {
            let credencial = try GoogleDrive.lerCredencial(de: url)
            clientID = credencial.clientID
            clientSecret = credencial.clientSecret
            erro = nil
        } catch {
            erro = error.localizedDescription
        }
    }

    private func conectar() {
        aguardando = true
        erro = nil
        Task {
            do {
                try await armazenamento.conectarGoogle(clientID: clientID, clientSecret: clientSecret)
                aguardando = false
                fechar()
            } catch {
                aguardando = false
                erro = error.localizedDescription
            }
        }
    }
}
