# Gerador de Documentos

App para Mac com Apple Silicon (M1, M2, M3, M4…) que gera documentos do Word a partir de modelos, preenchendo automaticamente nome do paciente, CPF, datas e outros campos.

## Como funciona

O app usa a **sua pasta de modelos** do jeito que ela já está organizada:

```
Modelos/                          ← pasta principal (escolhida uma vez em "Modelos")
├── ALAGOA GRANDE/                ← local ou cidade
│   ├── 0 - atestado medico.docx  ← aparece em "Modelos gerais"
│   ├── LAUDO MÉDICO/             ← tipo de documento
│   │   └── laudo coluna.docx
│   └── RX/ …
├── OPERA PB/ …
└── ARARUNA/ …
```

1. **Prepare os modelos no Word.** Onde o texto deve mudar, escreva o nome do campo entre chaves duplas:

   > Atesto que **{{NOME_PACIENTE}}**, CPF {{CPF}}, esteve sob meus cuidados em {{DATA}}.

   A formatação do Word (negrito, fonte, tabelas, cabeçalho e rodapé) é mantida. Há um exemplo pronto em [`Exemplos/Atestado-Exemplo.docx`](Exemplos/Atestado-Exemplo.docx). Os modelos nunca são alterados pelo app.

2. Na aba **Modelos**, escolha a pasta principal.
3. Na aba **Locais de atendimento**, cadastre cada local (endereço, cidade, telefone…), escolha a **pasta onde os documentos gerados devem ficar** e, se o nome for diferente, a pasta de modelos ligada a ele.
4. Na aba **Gerar documento**, navegue como no Finder: **Local → Pasta → Modelo**. Digite o nome do paciente e clique em *Gerar documento*.
   - Se o paciente já tem cadastro, o app sugere o nome e preenche CPF, nascimento etc.; se é novo, o cadastro é criado sozinho.
   - O documento é salvo automaticamente em `<pasta do local>/<mesma pasta do modelo>/<Modelo> - <Paciente> - <data>.docx` e aberto no Word. Nada é sobrescrito.

Modelos avulsos, fora da pasta principal, também podem ser importados na aba *Modelos*.

### Campos preenchidos automaticamente

| Campo no modelo | Valor |
|---|---|
| `{{NOME_PACIENTE}}` ou `{{NOME}}` | Nome do paciente |
| `{{CPF}}`, `{{RG}}` | Documentos |
| `{{DATA_NASCIMENTO}}`, `{{IDADE}}` | Nascimento e idade calculada |
| `{{TELEFONE}}`, `{{EMAIL}}`, `{{ENDERECO}}`, `{{CONVENIO}}` | Contato |
| `{{LOCAL}}`, `{{LOCAL_ENDERECO}}`, `{{CIDADE}}` | Nome, endereço e cidade do local de atendimento |
| `{{LOCAL_TELEFONE}}`, `{{LOCAL_EMAIL}}`, `{{CNPJ}}` | Contato e CNPJ do local |
| `{{DATA}}` | Data de hoje (27/10/2026) |
| `{{DATA_EXTENSO}}` | Data por extenso (27 de outubro de 2026) |

Maiúsculas, acentos e espaços não importam (`{{Data de Nascimento}}` também funciona). Qualquer outro campo, como `{{CID}}` ou `{{DIAS_AFASTAMENTO}}`, aparece para ser digitado, e o valor fica salvo no cadastro do paciente para a próxima vez.

### Onde os dados ficam salvos

Tudo fica no próprio Mac, em `~/Library/Application Support/GeradorDocumentos/`: o arquivo `dados.json` (pacientes, locais e histórico) e a pasta `Modelos/` (cópias dos modelos). O botão *Pasta de dados* no app abre essa pasta. Para fazer backup, copie a pasta inteira.

## Instalar

### Opção 1: baixar o app pronto

1. No GitHub, abra a aba **Actions**, entre na execução mais recente de *Compilar app para Mac* e baixe o artefato `GeradorDocumentos-AppleSilicon`.
2. Descompacte até aparecer **Gerador de Documentos.app** e arraste para a pasta *Aplicativos*.
3. Como o app não é assinado com um certificado de desenvolvedor da Apple, o macOS bloqueia a primeira abertura. Para liberar, use um destes caminhos:
   - Clique com o botão direito no app → *Abrir* → *Abrir*. No macOS 15, tente abrir uma vez e depois vá em *Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim*.
   - Ou, no Terminal: `xattr -dr com.apple.quarantine "/Applications/Gerador de Documentos.app"`

### Opção 2: compilar no seu Mac

Requer o Xcode (ou as Command Line Tools) instalado.

```bash
./scripts/build-app.sh                 # gera dist/Gerador de Documentos.app
open "dist/Gerador de Documentos.app"
```

Para editar o código, abra `Package.swift` no Xcode e rode com ⌘R.

## Estrutura

- `Sources/DocxTemplateKit/`: leitura e preenchimento dos `.docx`. Também trata campos que o Word divide em vários trechos internos.
- `Sources/GeradorDocumentos/`: o app SwiftUI (telas, cadastro e armazenamento).
- `Tests/`: testes automáticos (`swift test`).
