# Gerador de Documentos

App para Mac com Apple Silicon (M1, M2, M3, M4…) que gera documentos do Word a partir de modelos, preenchendo automaticamente nome do paciente, CPF, datas e outros campos.

## Como funciona

1. **Prepare um modelo no Word.** Onde o texto deve mudar, escreva o nome do campo entre chaves duplas:

   > Atesto que **{{NOME_PACIENTE}}**, CPF {{CPF}}, esteve sob meus cuidados em {{DATA}}.

   A formatação do Word (negrito, fonte, tabelas, cabeçalho e rodapé) é mantida. Há um exemplo pronto em [`Exemplos/Atestado-Exemplo.docx`](Exemplos/Atestado-Exemplo.docx).

2. **Importe os modelos** na aba *Modelos*: escolha o local no filtro e clique em *Importar modelo para …*. Cada local tem seus próprios modelos (ou marque “Todos os locais” para um modelo comum). O app encontra os campos sozinho.
   Escolha o **tipo** de cada modelo (Receitas, Laudos, Relatórios médicos ou outro que você criar).
3. **Cadastre seus locais de atendimento** na aba *Locais de atendimento* (clínica, hospital, consultório) e escolha a **pasta** de cada um.
4. Na aba **Gerar documento**, escolha o modelo e o local, **digite o nome do paciente**, confira os valores e clique em *Gerar documento*. O `.docx` é salvo automaticamente na pasta do local, na subpasta do tipo, e aberto no Word.
   - Se o paciente já tem cadastro, o app sugere o nome e preenche CPF, nascimento etc.
   - Se é um paciente novo, o cadastro é criado sozinho com o que você digitou.

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

### Organização dos documentos gerados

```
OPERA PB/                      ← pasta escolhida para o local
├── Receitas/
│   └── Receita - Silvio Romero - 27-10-2026.docx
├── Laudos/
└── Relatórios médicos/
```

Se o local não tiver pasta escolhida, o app usa `Documentos/Gerador de Documentos/<nome do local>`. Se já existir um arquivo com o mesmo nome, o novo recebe "(2)", "(3)"… no final; nada é sobrescrito.

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
