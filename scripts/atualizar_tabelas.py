#!/usr/bin/env python3
"""Baixa as tabelas oficiais e gera os arquivos de dados embutidos no app.

- SIGTAP: Tabela Unificada de Procedimentos do SUS, do FTP do DATASUS
  (ftp2.datasus.gov.br/pub/sistemas/tup/downloads), versão mais recente.

Uso: python3 scripts/atualizar_tabelas.py
"""
import ftplib
import io
import re
import sys
import zipfile
from pathlib import Path

DESTINO = Path(__file__).resolve().parent.parent / "Sources" / "GeradorDocumentos"
CABECALHO = (
    "// Gerado por scripts/atualizar_tabelas.py (GitHub Actions › Atualizar tabela SIGTAP).\n"
    "// Não edite à mão: rode a atualização de novo para trazer a versão mais recente.\n"
)


def limpar(texto):
    return re.sub(r"\s+", " ", texto.replace("|", "/")).strip()


def literal(linhas):
    corpo = "\n".join(linhas)
    assert '"""#' not in corpo
    return '#"""\n' + corpo + '\n"""#'


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


if __name__ == "__main__":
    pedidos = set(sys.argv[1:]) or {"sigtap"}
    falhas = []
    for nome, funcao in (("sigtap", sigtap),):
        if nome in pedidos:
            try:
                funcao()
            except BaseException as erro:  # segue para a outra tabela
                print(f"FALHOU {nome}: {erro!r}")
                falhas.append(nome)
    if falhas:
        sys.exit(1)
