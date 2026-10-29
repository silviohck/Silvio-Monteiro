# Orthck

App para Mac com Apple Silicon (M1, M2, M3, M4…) que gera documentos do Word a partir de modelos, preenchendo automaticamente nome do paciente, CPF, datas e outros campos.

## Como funciona

1. **Prepare um modelo no Word.** Onde o texto deve mudar, escreva o nome do campo entre chaves duplas:

   > Atesto que **{{NOME_PACIENTE}}**, CPF {{CPF}}, esteve sob meus cuidados em {{DATA}}.

   A formatação do Word (negrito, fonte, tabelas, cabeçalho e rodapé) é mantida. Há um exemplo pronto em [`Exemplos/Atestado-Exemplo.docx`](Exemplos/Atestado-Exemplo.docx).

2. **Sincronize sua pasta de modelos** (recomendado): na aba *Modelos*, clique em *Sincronizar com uma pasta…* e escolha a pasta principal — uma subpasta para cada local (ex.: OPERA PB) e, dentro dela, uma subpasta para cada tipo (ex.: RX, LAUDO MÉDICO). Desmarque as subpastas que não são locais. A partir daí o app acompanha a pasta sozinho: **arquivo novo** vira modelo, **arquivo editado** no Word é atualizado e **arquivo apagado** sai do app — sempre que você volta para o app, ou no botão ⟳. **Pastas para todos os locais:** na ⚙️ da pasta sincronizada, cada subpasta pode ser **Local**, **Todos os locais** ou **Ignorar**. A **1 - APAC** já vem como *Todos os locais*: ela aparece como subpasta de cada local de atendimento (com as pastas de dentro dela), sem copiar nem criar atalhos, e os documentos gerados vão para uma pasta "1 - APAC" dentro da pasta do local. **Atalhos (alias) do Finder** dentro da pasta de um local são seguidos: um atalho "1 - APAC" dentro de ALAGOA GRANDE vira a subpasta "1 - APAC" desse local, com as pastas que houver dentro dela. Se a pasta original também estiver na pasta principal, desmarque-a na lista de locais. Pastas dentro do tipo também aparecem: um arquivo em `CAMPINA GRANDE/RX/Joelho/` fica na subpasta **RX / Joelho**, e o documento gerado com ele é salvo na mesma pasta (`…/CAMPINA GRANDE/RX/Joelho/`). Para levar a pasta a outro computador ou guardar uma cópia, use *Compactar (.zip)…* na barra lateral (ou na ⚙️): o app cria um .zip com todos os arquivos da pasta sincronizada, sem os arquivos temporários do Word (“~$…”). Modelos, tipos e subpastas aparecem sempre em ordem alfabética (use números, como "1 - RX", para pôr algo na frente). Os arquivos nunca são alterados pelo app.

   Ou **importe modelos avulsos** na aba *Modelos*: escolha o local no filtro e clique em *Importar modelo para …*. Cada local tem seus próprios modelos (ou marque “Todos os locais” para um modelo comum). O app encontra os campos sozinho.
   Escolha também o **tipo** (Receitas, Atestados, Relatórios médicos, Radiografias…) no segundo filtro. Em *Gerenciar…* você cria, renomeia, exclui e reordena os tipos.
3. **Cadastre seus locais de atendimento** na aba *Locais de atendimento*: só o nome e, se quiser, a **pasta** onde os documentos dele são salvos. Para excluir um local com modelos ou pacientes, o app pede antes que você os **transfira** para outro local ou os **desvincule**.
4. Na aba **Gerar documento**, escolha o modelo e o local, **digite o nome do paciente**, confira os valores e clique em *Gerar documento*. O `.docx` é salvo automaticamente na pasta do local, na subpasta do tipo, e aberto no Word.
   - Se o paciente já tem cadastro, o app sugere o nome e preenche CPF, nascimento etc. — mesmo que ele seja de outro local: a sugestão mostra onde ele já foi atendido, e o documento sai com o local escolhido na tela. Na aba *Pacientes*, ele passa a aparecer também nesse local.
   - Se é um paciente novo, o cadastro é criado sozinho com o que você digitou.
   - Ao gerar, o nome do paciente já fica copiado: é só colar (⌘V) em outro sistema.
   - Depois de gerar, **Próximo paciente** (⇧⌘N, no topo da janela e no quadro verde de documento pronto) recomeça do início: limpa paciente, subpasta, modelo e campos, e mantém só o local de atendimento.
   - Se houver **mais de um paciente com o mesmo nome**, o app não escolhe sozinho: mostra os cadastros com data de nascimento e CPF para você escolher (ou “É outro paciente”, com a data de nascimento para diferenciar). Os documentos ficam ligados ao cadastro escolhido.

**Favoritos:** na tela *Gerar documento*, a ⭐ ao lado do modelo (ou *Favorito* no cadastro do modelo) cria um atalho acima da Subpasta — ex.: **Retorno**. Um clique já escolhe a subpasta e o modelo. O favorito vale pelo nome, em todos os locais que tenham um modelo com esse nome.

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

Maiúsculas, acentos e espaços não importam (`{{Data de Nascimento}}` também funciona). Qualquer outro campo, como `{{CID}}` ou `{{DIAS_AFASTAMENTO}}`, aparece para ser digitado e vale só para aquele documento (não fica no cadastro do paciente).

### Organização dos documentos gerados

```
OPERA PB/                      ← pasta escolhida para o local
├── Receitas/
│   └── Receita - Silvio Romero - Opera PB - 27-10-2026.docx
├── Laudos/
└── Relatórios médicos/
```

Na tela *Gerar documento*, **Escolher pasta principal…** define a pasta onde tudo é guardado. Ao salvar, o app procura dentro dela a **pasta do local** (sem diferenciar maiúsculas e acentos — “CAMPINA GRANDE” serve para “Campina Grande”) e, dentro desta, a **pasta do tipo** do modelo; o que não existir é criado. Em **Mais opções** dá para usar outra pasta só para um local ou só para aquele documento. Sem pasta escolhida, a pasta principal é `Documentos/Orthck`. Se já existir um arquivo com o mesmo nome, o novo recebe "(2)", "(3)"… no final; nada é sobrescrito.

### Impressão

**Parar todas as impressões** (barra lateral, embaixo da impressora, e na aba Fila): se um documento começar a sair sem parar, esse botão cancela tudo o que está na fila de impressão do Mac para a impressora escolhida e interrompe a fila do app. O mesmo arquivo também não é enviado duas vezes em menos de 20 segundos.

**Fila de impressão:** na tela *Gerar documento*, em **Depois de gerar**, escolha **Adicionar à fila de impressão** (padrão), **Imprimir agora** ou **Só salvar**. Os documentos vão se acumulando na aba **Fila de impressão** (o número de pendentes aparece na barra lateral) e, ao fim dos atendimentos, **Imprimir todos** manda um por vez para o Word, na ordem em que foram gerados. Depois de enviado para imprimir, cada documento fica 2 minutos na fila como “Enviado” e então sai sozinho. Dá para mudar as cópias de cada item, imprimir só os marcados ou tirar um item da fila (o arquivo continua salvo). A fila continua lá se o app for fechado; um envio interrompido fica como “Conferir” e só é reenviado com sua confirmação. No *Histórico*, **Pôr na fila** coloca de novo um documento antigo.

Escolha a impressora na barra lateral. Na tela *Gerar documento*, marque **Imprimir ao gerar** (ao lado, escolha quantas **cópias**) ou use o botão **Imprimir** depois de salvar; no *Histórico* também há um botão **Imprimir**. A impressão é feita pelo **Microsoft Word** (precisa estar instalado), e a impressora escolhida passa a ser a padrão do Mac. Em **Procurar impressoras…** (barra lateral) você busca pelo nome entre as instaladas e as encontradas na rede ou no USB, adiciona uma nova e define a padrão com um clique. Na primeira vez, o macOS pergunta se o app pode controlar o Word: clique em **OK**.

No cadastro de cada modelo (aba *Modelos*), a seção **Impressão** define o número de **cópias** que já vem marcado ao escolher o modelo em *Gerar documento*.

### Aparência

O app usa a paleta “Sereno”: cinzas neutros e azul-petróleo suave, sem branco ou preto puros (modo claro e escuro) e texto maior que o padrão do Mac. Em **Orthck › Ajustes…** (⌘,) você escolhe o tamanho do texto — Normal, Grande ou Muito grande — e o tema claro, escuro ou automático. Atalhos: ⌘+ aumenta, ⌘− diminui, ⌘0 volta ao normal.

### CID-10

A aba **CID-10** tem a tabela completa do DATASUS (capítulos, categorias e subcategorias — cerca de 14 mil códigos), funciona sem internet e busca por código (`M54.5`, `m545`) ou por palavras em qualquer ordem, sem precisar de acentos (`dor lombar`, `lombalgia`). Filtre por capítulo e copie com o botão ao lado, o clique direito ou ⌘C (“M54.5 - Dor lombar baixa”).

No campo `{{CID}}` da tela *Gerar documento* (e em `{{CID_PRINCIPAL}}`, `{{CID2}}`…), basta digitar o código ou palavras: o app sugere da tabela CID-10 e um clique preenche o código.

### SIGTAP

A aba **SIGTAP (SUS)** funciona como a do CID-10: busca por código (`03.01.01.007-2`, `0301010072`) ou por palavras, sem acentos, filtro por grupo e cópia com o botão ao lado da descrição, o clique direito ou ⌘C. Traz a Tabela de Procedimentos do SUS (DATASUS).

Para atualizar (o SIGTAP muda todo mês), abra no GitHub *Actions › Atualizar tabela SIGTAP › Run workflow*: a rotina baixa a versão oficial, grava no projeto e compila um app novo.

### Onde os dados ficam salvos

Tudo fica no próprio Mac, em `~/Library/Application Support/GeradorDocumentos/`: o arquivo `dados.json` (pacientes, locais, histórico e fila) e a pasta `Modelos/` (cópias dos modelos). O menu *Arquivo › Abrir pasta de dados (backup)* abre essa pasta.

**Backup automático:** uma vez por dia o app guarda uma cópia do `dados.json` em `Backups/` (as últimas 30). Para restaurar ou levar os dados a outro Mac, use **Importar dados (.json)…** na barra lateral: escolha o backup e depois **Juntar** (entram os pacientes, locais e documentos que faltam) ou **Substituir** (volta tudo para o que está no arquivo). Antes de importar, o app guarda uma cópia dos dados atuais em `Backups/`. Além disso, **Compactar (.zip)…** na barra lateral leva junto o arquivo `Orthck - dados (backup).json` — guarde esse .zip no iCloud, OneDrive ou pendrive para ter uma cópia fora do Mac.

**Enviar ao OneDrive:** em *Backup*, o botão copia a pasta sincronizada para `OneDrive/Orthck/<pasta>` (deixando igual à daqui, sem os arquivos temporários do Word) e, ao lado, o `Orthck - dados (backup).json`. O app do OneDrive precisa estar instalado no Mac — é ele que leva para a nuvem; o Orthck acha a pasta do OneDrive sozinho, ou você escolhe em “…”.

**Cópia no Google Drive (sem instalar o app do Google):** em *Backup*, **Conectar ao Google Drive…** abre o navegador para entrar na conta Google e autorizar, uma vez por computador. A credencial do Google (cliente *App para computador*, escopo `drive.file`) entra no app na compilação, pelos Secrets `GOOGLE_CLIENT_ID` e `GOOGLE_CLIENT_SECRET` do repositório; sem eles, a janela pede o `client_secret….json`. Depois, o app envia `Orthck - dados.json` ao Drive (até 2 minutos depois de cada mudança e ao fechar) e, ao abrir ou voltar para o app, junta o que mudou nele em outro computador (pacientes, locais, histórico e favoritos; a fila de impressão é de cada computador). A credencial e a autorização ficam só neste Mac (`google.json` na pasta de dados), nunca no repositório. Apagar um paciente não se propaga: a junção só acrescenta.

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
- `Recursos/`: ícone do app (`AppIcon.png` e `AppIcon.icns`).
- `Tests/`: testes automáticos (`swift test`).
