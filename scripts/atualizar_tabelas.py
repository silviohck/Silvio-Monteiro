#!/usr/bin/env python3
"""Baixa as tabelas oficiais e gera os arquivos de dados embutidos no app.

- SIGTAP: Tabela Unificada de Procedimentos do SUS, do FTP do DATASUS
  (ftp2.datasus.gov.br/pub/sistemas/tup/downloads), versão mais recente.
- TUSS: tabela 22 (procedimentos e eventos em saúde), dos dados abertos da ANS
  (dadosabertos.ans.gov.br/FTP/PDA/terminologia_unificada_saude_suplementar_TUSS).

Uso: python3 scripts/atualizar_tabelas.py [sigtap] [tuss]   (sem argumentos: as duas)
"""
import csv
import datetime
import ftplib
import io
import re
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

DESTINO = Path(__file__).resolve().parent.parent / "Sources" / "GeradorDocumentos"
CABECALHO = (
    "// Gerado por scripts/atualizar_tabelas.py (GitHub Actions › Atualizar tabelas SIGTAP e TUSS).\n"
    "// Não edite à mão: rode a atualização de novo para trazer a versão mais recente.\n"
)


def limpar(texto):
    return re.sub(r"\s+", " ", texto.replace("|", "/")).strip()


def literal(linhas):
    corpo = "\n".join(linhas)
    assert '"""#' not in corpo
    return '#"""\n' + corpo + '\n"""#'


def baixar(url):
    pedido = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Orthck)"})
    with urllib.request.urlopen(pedido, timeout=300) as resposta:
        return resposta.read()


# MARK: SIGTAP

def ler_layout(zipf, nome):
    """tb_x_layout.txt: Coluna,Tamanho,Inicio,Fim,Tipo → {coluna: (inicio, fim)}."""
    candidatos = [n for n in zipf.namelist() if n.lower() == nome.lower().replace(".txt", "_layout.txt")]
    if not candidatos:
        return None
    texto = zipf.read(candidatos[0]).decode("latin-1")
    colunas = {}
    for linha in texto.splitlines()[1:]:
        partes = [p.strip() for p in linha.split(",")]
        if len(partes) >= 4 and partes[2].isdigit() and partes[3].isdigit():
            colunas[partes[0].upper()] = (int(partes[2]), int(partes[3]))
    return colunas


def ler_tabela(zipf, nome, codigo, descricao, padrao):
    arquivo = next(n for n in zipf.namelist() if n.lower() == nome)
    layout = ler_layout(zipf, nome) or {}
    ic, fc = layout.get(codigo, padrao[0])
    idsc, fd = layout.get(descricao, padrao[1])
    resultado = []
    for linha in zipf.read(arquivo).decode("latin-1").splitlines():
        cod = linha[ic - 1:fc].strip()
        desc = limpar(linha[idsc - 1:fd])
        if cod and desc:
            resultado.append((cod, desc))
    print(f"  {nome}: {len(resultado)} linhas (colunas {codigo} {ic}-{fc}, {descricao} {idsc}-{fd})")
    return resultado


def sigtap():
    print("SIGTAP: procurando a versão mais recente no FTP do DATASUS…")
    ftp = ftplib.FTP("ftp2.datasus.gov.br", timeout=120)
    ftp.login()
    ftp.cwd("/pub/sistemas/tup/downloads")
    arquivos = sorted(n for n in ftp.nlst() if re.match(r"TabelaUnificada_\d{6}_v\d+\.zip$", n, re.I))
    if not arquivos:
        raise SystemExit("Nenhum TabelaUnificada_*.zip encontrado")
    nome = arquivos[-1]
    print(f"  baixando {nome}")
    dados = io.BytesIO()
    ftp.retrbinary(f"RETR {nome}", dados.write)
    ftp.quit()
    competencia = re.search(r"_(\d{4})(\d{2})_", nome)
    competencia = f"{competencia.group(2)}/{competencia.group(1)}"

    with zipfile.ZipFile(dados) as zipf:
        print("  arquivos:", ", ".join(sorted(zipf.namelist())[:60]))
        grupos = ler_tabela(zipf, "tb_grupo.txt", "CO_GRUPO", "NO_GRUPO", ((1, 2), (3, 102)))
        # tb_sub_grupo tem CO_GRUPO + CO_SUB_GRUPO: junta para o código de 4 dígitos.
        arquivo = next(n for n in zipf.namelist() if n.lower() == "tb_sub_grupo.txt")
        layout = ler_layout(zipf, "tb_sub_grupo.txt") or {}
        ig, fg = layout.get("CO_GRUPO", (1, 2))
        isg, fsg = layout.get("CO_SUB_GRUPO", (3, 4))
        ins, fns = layout.get("NO_SUB_GRUPO", (5, 104))
        subgrupos = []
        for linha in zipf.read(arquivo).decode("latin-1").splitlines():
            cod = linha[ig - 1:fg].strip() + linha[isg - 1:fsg].strip()
            desc = limpar(linha[ins - 1:fns])
            if len(cod) == 4 and desc:
                subgrupos.append((cod, desc))
        procedimentos = ler_tabela(zipf, "tb_procedimento.txt", "CO_PROCEDIMENTO", "NO_PROCEDIMENTO", ((1, 10), (11, 260)))

    procedimentos = sorted({c: d for c, d in procedimentos if len(c) == 10 and c.isdigit()}.items())
    if len(procedimentos) < 1000:
        raise SystemExit(f"Poucos procedimentos ({len(procedimentos)}): algo mudou no formato do arquivo")
    texto = (
        CABECALHO
        + f"// Fonte: DATASUS, {nome} (competência {competencia}). Formato: \"código|descrição\".\n\n"
        + "enum SIGTAPDados {\n"
        + f'    static let competencia = "{competencia}"\n'
        + "    static let grupos = " + literal(f"{c}|{d}" for c, d in sorted(grupos)) + "\n"
        + "    static let subgrupos = " + literal(f"{c}|{d}" for c, d in sorted(subgrupos)) + "\n"
        + "    static let procedimentos = " + literal(f"{c}|{d}" for c, d in procedimentos) + "\n"
        + "}\n"
    )
    (DESTINO / "SIGTAPDados.swift").write_text(texto, encoding="utf-8")
    print(f"  SIGTAP {competencia}: {len(grupos)} grupos, {len(subgrupos)} subgrupos, {len(procedimentos)} procedimentos")


# MARK: TUSS

RAIZ_PDA = "https://dadosabertos.ans.gov.br/FTP/PDA/"


def links(url):
    html = baixar(url).decode("utf-8", "replace")
    return [l for l in re.findall(r'href="([^"?#]+)"', html) if not l.startswith(("/", "..", "http"))]


def pasta_tuss():
    """Pasta da TUSS nos dados abertos da ANS (o nome já mudou antes; procura pelo nome)."""
    itens = links(RAIZ_PDA)
    candidatas = [i for i in itens if i.endswith("/") and ("tuss" in i.lower() or "terminologia" in i.lower())]
    print("  pastas candidatas:", candidatas or itens)
    if not candidatas:
        raise SystemExit("Pasta da TUSS não encontrada nos dados abertos da ANS")
    return RAIZ_PDA + sorted(candidatas, key=lambda i: "tuss" not in i.lower())[0]


def data(texto):
    texto = texto.strip()
    for formato in ("%d/%m/%Y", "%Y-%m-%d", "%d/%m/%y", "%Y%m%d"):
        try:
            return datetime.datetime.strptime(texto[:10], formato).date()
        except ValueError:
            pass
    return None


def tabela22(nome_arquivo, conteudo):
    for codificacao in ("utf-8-sig", "latin-1"):
        try:
            texto = conteudo.decode(codificacao)
            break
        except UnicodeDecodeError:
            continue
    primeira = texto.splitlines()[0]
    separador = max(";,\t|", key=primeira.count)
    linhas = list(csv.reader(io.StringIO(texto), delimiter=separador))
    cabecalho = [c.strip().lower() for c in linhas[0]]
    print(f"  {nome_arquivo}: colunas {cabecalho}")

    def coluna(*pedacos, evitar=()):
        for i, nome in enumerate(cabecalho):
            if any(p in nome for p in pedacos) and not any(e in nome for e in evitar):
                return i
        return None

    i_codigo = coluna("cd_termo", "código", "codigo", "cod_termo")
    i_termo = coluna("nm_termo", "descri", "termo", "nome", evitar=("cd_", "código", "codigo", "cod"))
    i_fim = coluna("fim de vig", "fim_vig", "dt_fim_vig", "fim vig")
    if i_codigo is None or i_termo is None:
        raise SystemExit(f"Colunas de código/termo não encontradas em {nome_arquivo}")
    hoje = datetime.date.today()
    termos = {}
    for linha in linhas[1:]:
        if len(linha) <= max(i_codigo, i_termo):
            continue
        codigo = re.sub(r"\D", "", linha[i_codigo])
        termo = limpar(linha[i_termo])
        if not codigo or not termo:
            continue
        if i_fim is not None and i_fim < len(linha):
            fim = data(linha[i_fim])
            if fim and fim < hoje:
                continue
        termos[codigo] = termo
    return termos


def tuss():
    print("TUSS: procurando a tabela 22 nos dados abertos da ANS…")
    pasta = pasta_tuss()
    itens = links(pasta)
    print("  itens:", itens)
    arquivos = []  # (nome, url)
    for item in itens:
        url = pasta + item
        if item.endswith("/"):
            for sub in links(url):
                if sub.lower().endswith((".zip", ".csv")):
                    arquivos.append((item + sub, url + sub))
        elif item.lower().endswith((".zip", ".csv")):
            arquivos.append((item, url))
    print("  arquivos:", [a for a, _ in arquivos])

    def eh_tabela22(nome):
        nome = urllib.parse.unquote(nome).lower()
        return re.search(r"(^|[^0-9])22([^0-9]|$)", nome) is not None or "procedimentos_e_eventos" in nome

    termos = {}
    versao = ""
    for nome, url in sorted(arquivos, key=lambda a: (not eh_tabela22(a[0]), a[0])):
        conteudo = baixar(url)
        if nome.lower().endswith(".zip"):
            with zipfile.ZipFile(io.BytesIO(conteudo)) as zipf:
                internos = [n for n in zipf.namelist() if n.lower().endswith(".csv")]
                print(f"  {nome}: {internos}")
                for interno in internos:
                    if eh_tabela22(interno.rsplit("/", 1)[-1]):
                        termos = tabela22(interno, zipf.read(interno))
                        versao = nome
                        break
        elif eh_tabela22(nome):
            termos = tabela22(nome, conteudo)
            versao = nome
        if termos:
            break
    if len(termos) < 1000:
        raise SystemExit(f"Tabela 22 não encontrada ou incompleta ({len(termos)} termos)")
    versao = f"atualizada em {datetime.date.today():%m/%Y}"
    texto = (
        CABECALHO
        + f"// Fonte: ANS, dados abertos da TUSS ({pasta}), tabela 22 (termos vigentes).\n"
        + "// Formato: \"código|termo\".\n\n"
        + "enum TUSSDados {\n"
        + f'    static let versao = "{versao}"\n'
        + "    static let procedimentos = " + literal(f"{c}|{t}" for c, t in sorted(termos.items())) + "\n"
        + "}\n"
    )
    (DESTINO / "TUSSDados.swift").write_text(texto, encoding="utf-8")
    print(f"  TUSS: {len(termos)} termos vigentes")


if __name__ == "__main__":
    pedidos = set(sys.argv[1:]) or {"sigtap", "tuss"}
    falhas = []
    for nome, funcao in (("sigtap", sigtap), ("tuss", tuss)):
        if nome in pedidos:
            try:
                funcao()
            except BaseException as erro:  # segue para a outra tabela
                print(f"FALHOU {nome}: {erro!r}")
                falhas.append(nome)
    if falhas:
        sys.exit(1)
