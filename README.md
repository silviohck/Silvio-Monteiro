# Orthck

App para Mac com Apple Silicon (M1, M2, M3, M4…) que gera documentos do Word a partir de modelos, preenchendo automaticamente nome do paciente, CPF, datas e outros campos.

## Como funciona

1. **Prepare um modelo no Word.** Onde o texto deve mudar, escreva o nome do campo entre chaves duplas:

   > Atesto que **{{NOME_PACIENTE}}**, CPF {{CPF}}, esteve sob meus cuidados em {{DATA}}.

   A formatação do Word (negrito, fonte, tabelas, cabeçalho e rodapé) é mantida. Há um exemplo pronto em [`Exemplos/Atestado-Exemplo.docx`](Exemplos/Atestado-Exemplo.docx).

2. **Sincronize sua pasta de modelos** (recomendado): na aba *Modelos*, clique em *Sincronizar com uma pasta…* e escolha a pasta principal — uma subpasta para cada local (ex.: OPERA PB) e, dentro dela, uma subpasta para cada tipo (ex.: RX, LAUDO MÉDICO). Desmarque as subpastas que não são locais. A partir daí o app acompanha a pasta sozinho: **arquivo novo** vira modelo, **arquivo editado** no Word é atualizado e **arquivo apagado** sai do app — sempre que você volta para o app, ou no botão ⟳. Os arquivos nunca são alterados pelo app.

   Ou **importe modelos avulsos** na aba *Modelos*: escolha o local no filtro e clique em *Importar modelo para …*. Cada local tem seus próprios modelos (ou marque “Todos os locais” para um modelo comum). O app encontra os campos sozinho.
   Escolha também o **tipo** (Receitas, Atestados, Relatórios médicos, Radiografias…) no segundo filtro. Em *Gerenciar…* você cria, renomeia, exclui e reordena os tipos.
3. **Cadastre seus locais de atendimento** na aba *Locais de atendimento*: só o nome e, se quiser, a **pasta** onde os documentos dele são salvos.
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
| `{{LOCAL}}` | Nome do local de atendimento |
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

Para mudar onde os documentos são salvos, use **Alterar…** ao lado de “Será salvo em” (tela *Gerar documento*): a pasta do local, uma pasta padrão para todos os locais ou outra pasta só para aquele documento. Se o local não tiver pasta escolhida, o app usa a pasta padrão (de início, `Documentos/Orthck`) com uma subpasta com o nome do local. Se já existir um arquivo com o mesmo nome, o novo recebe "(2)", "(3)"… no final; nada é sobrescrito.

### Impressão

Escolha a impressora na barra lateral. Na tela *Gerar documento*, marque **Imprimir ao gerar** ou use o botão **Imprimir** depois de salvar; no *Histórico* também há um botão **Imprimir**. A impressão é feita pelo **Microsoft Word** (precisa estar instalado), e a impressora escolhida passa a ser a padrão do Mac. Na primeira vez, o macOS pergunta se o app pode controlar o Word: clique em **OK**.

No cadastro de cada modelo (aba *Modelos*), a seção **Impressão** define **páginas por folha** e **cópias**. Com **2 por folha** (ex.: receita de controle especial), o documento gerado já sai com a opção do próprio Word “2 páginas por folha” (Layout › Margens › Margens personalizadas › Várias páginas): no Word cada página aparece pela metade e a impressão — pelo app ou pelo próprio Word — sai com duas páginas em cada folha.

### Aparência

O app usa cores suaves (fundo creme no modo claro, grafite no escuro) e texto maior que o padrão do Mac. Em **Aparência e tamanho do texto** (barra lateral, ou ⌘,) você escolhe o tamanho do texto — Normal, Grande ou Muito grande — e o tema claro, escuro ou automático. Atalhos: ⌘+ aumenta, ⌘− diminui, ⌘0 volta ao normal.

### CID-10

A aba **CID-10** tem a tabela completa do DATASUS (capítulos, categorias e subcategorias — cerca de 14 mil códigos), funciona sem internet e busca por código (`M54.5`, `m545`) ou por palavras em qualquer ordem, sem precisar de acentos (`dor lombar`, `lombalgia`). Filtre por capítulo e copie com o botão ao lado, o clique direito ou ⌘C (“M54.5 - Dor lombar baixa”).

### Onde os dados ficam salvos

Tudo fica no próprio Mac, em `~/Library/Application Support/GeradorDocumentos/`: o arquivo `dados.json` (pacientes, locais e histórico) e a pasta `Modelos/` (cópias dos modelos). O botão *Pasta de dados* no app abre essa pasta. Para fazer backup, copie a pasta inteira.

## Instalar

### Opção 1: baixar o app pronto

1. No GitHub, abra a aba **Actions**, entre na execução mais recente de *Compilar app para Mac* e baixe o artefato `Orthck-AppleSilicon`.
2. Descompacte até aparecer **Orthck.app** e arraste para a pasta *Aplicativos*.
3. Como o app não é assinado com um certificado de desenvolvedor da Apple, o macOS bloqueia a primeira abertura. Para liberar, use um destes caminhos:
   - Clique com o botão direito no app → *Abrir* → *Abrir*. No macOS 15, tente abrir uma vez e depois vá em *Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim*.
   - Ou, no Terminal: `xattr -dr com.apple.quarantine "/Applications/Orthck.app"`

### Opção 2: compilar no seu Mac

Requer o Xcode (ou as Command Line Tools) instalado.

```bash
./scripts/build-app.sh                 # gera dist/Orthck.app
open "dist/Orthck.app"
```

Para editar o código, abra `Package.swift` no Xcode e rode com ⌘R.

## Estrutura

- `Sources/DocxTemplateKit/`: leitura e preenchimento dos `.docx`. Também trata campos que o Word divide em vários trechos internos.
- `Sources/GeradorDocumentos/`: o app SwiftUI (telas, cadastro e armazenamento).
- `Tests/`: testes automáticos (`swift test`).
