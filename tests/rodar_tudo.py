"""
rodar_tudo.py
=============
Roda TODOS os testes sem tela do projeto e mostra ok / FALHA / ERRO de cada
um. É a rede de segurança: rode antes e depois de qualquer arrumação ou
mudança grande e compare.

  - Testes de conferência: tests/teste_*.gd que terminam imprimindo
    "teste_x: ok" ou "teste_x: FALHA" (achados sozinhos pelo texto do arquivo).
  - Relatórios (--relatorios): os que só imprimem números pra comparar com o
    jogo (capota, de lado, entrada, extra, largada, truck do vídeo) e o
    tests/rodar_testes.py (física). Aqui só conta se rodaram sem erro.
  - ERRO = erro de script do Godot (Parse Error, SCRIPT ERROR com "Invalid"),
    saída sem a linha final ou estourou o tempo.

Precisa do Godot de console no PATH ou na variável GODOT, ex. (cmd):
    set GODOT=C:\\Godot\\Godot_v4.7-stable_win64_console.exe
Uso (na pasta do projeto):
    python tests/rodar_tudo.py                  :: os de conferência, em paralelo
    python tests/rodar_tudo.py --relatorios     :: + os relatórios e o rodar_testes
    python tests/rodar_tudo.py volante pedras   :: só os que têm esses nomes
    python tests/rodar_tudo.py -j 2             :: 2 de cada vez (padrão: núcleos / 2)
Os logs ficam em tests/.saida/<teste>.log (fora do git).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(PROJ, "tests")
SAIDA = os.path.join(TESTS, ".saida")
TEMPO = 900                       # s por teste

# relatórios: imprimem números pra comparar, sem ok/FALHA
RELATORIOS = ["teste_capota.gd", "teste_de_lado.gd", "teste_entrada.tscn", "teste_extra.gd",
              "teste_largada.gd", "teste_truck_video.gd"]
# variáveis que o teste precisa (o padrão de cada um já serve; aqui só os que
# o CLAUDE.md roda com um valor)
AMBIENTE = {"teste_batida.gd": {"VEL": "20"}, "teste_lascas.gd": {"VEL": "20"},
            "teste_entrada.tscn": {"VEL": "110"}}
# os que rodam com passo fixo (o CLAUDE.md passa --fixed-fps 50)
FIXO_50 = {"teste_treme.gd", "teste_ladeira.gd", "teste_ia.gd"}
ARGS = {"teste_treme.gd": ["--", "0"], "teste_ladeira.gd": ["--", "0"]}

RUIDO_RE = re.compile(r"^\s*at: |^ERROR: \d+ resources|^WARNING: \d+ ObjectDB|ObjectDB instances|^Godot Engine")
ERRO_RE = re.compile(r"Parse Error|Compile Error|Failed to load script|SCRIPT ERROR: (Invalid|Attempt|Out of bounds|Nonexistent)")


def godot() -> str:
    g = os.environ.get("GODOT", "godot")
    if not shutil.which(g) and not os.path.isfile(g):
        sys.exit("[!] não achei o Godot (%s). Ponha no PATH ou:\n"
                 "  set GODOT=C:\\caminho\\Godot_v4.x-stable_win64_console.exe" % g)
    return g


def conferencias() -> list:
    out = []
    for f in sorted(os.listdir(TESTS)):
        if f.startswith("teste_") and f.endswith(".gd") and f not in RELATORIOS:
            texto = open(os.path.join(TESTS, f), encoding="utf-8").read()
            if re.search(r'"%s:? ' % f[:-3], texto) or re.search(r'"%s:' % f[:-3], texto):
                out.append(f)
    return out


def rodar(g: str, arq: str, relatorio: bool) -> dict:
    nome = arq.rsplit(".", 1)[0]
    cmd = [g, "--headless", "--path", PROJ]
    if arq in FIXO_50:
        cmd += ["--fixed-fps", "50"]
    if arq.endswith(".tscn"):
        cmd.append("res://tests/" + arq)
    else:
        cmd += ["-s", "res://tests/" + arq]
    cmd += ARGS.get(arq, [])
    amb = dict(os.environ)
    amb.update(AMBIENTE.get(arq, {}))
    t0 = time.time()
    try:
        p = subprocess.run(cmd, cwd=PROJ, env=amb, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=TEMPO)
        saida = p.stdout + p.stderr
        estourou = False
    except subprocess.TimeoutExpired as e:
        saida = (e.stdout or "") + (e.stderr or "") if isinstance(e.stdout, str) else ""
        estourou = True
    dt = time.time() - t0
    with open(os.path.join(SAIDA, nome + ".log"), "w", encoding="utf-8") as f:
        f.write(saida)
    linhas = [l for l in saida.splitlines() if l.strip() and not RUIDO_RE.search(l)]
    final = ""
    for l in reversed(linhas):
        if re.match(r"\s*%s:? " % re.escape(nome), l) or l.startswith(nome + ":"):
            final = l.strip()
            break
    if estourou:
        estado = "ERRO"
        resumo = "estourou %d s" % TEMPO
    elif ERRO_RE.search(saida):
        estado = "ERRO"
        resumo = next((l.strip() for l in linhas if ERRO_RE.search(l)), "erro de script")
    elif relatorio:
        estado = "rodou"
        uteis = [l for l in linhas if not re.match(r"\s*(ERROR|WARNING|SCRIPT ERROR):|\s*GDScript backtrace|\s*\[\d+\] ", l)]
        resumo = uteis[-1].strip() if uteis else ""
    elif not final:
        estado = "ERRO"
        resumo = "sem a linha final (%s: ok/FALHA)" % nome
    elif re.match(r"\s*%s:? ok\b" % re.escape(nome), final):
        estado = "ok"
        resumo = final
    else:
        # "FALHA", "1 falhas" ou qualquer coisa que não seja "ok"
        estado = "FALHA"
        resumo = final
    return {"nome": nome, "estado": estado, "tempo": dt, "resumo": resumo}


def rodar_testes_py() -> dict:
    t0 = time.time()
    p = subprocess.run([sys.executable, os.path.join(TESTS, "rodar_testes.py")], cwd=PROJ,
                       capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=TEMPO)
    saida = p.stdout + p.stderr
    with open(os.path.join(SAIDA, "rodar_testes.log"), "w", encoding="utf-8") as f:
        f.write(saida)
    ok = p.returncode == 0 and not ERRO_RE.search(saida)
    linhas = [l for l in saida.splitlines() if l.strip()]
    return {"nome": "rodar_testes.py", "estado": "rodou" if ok else "ERRO",
            "tempo": time.time() - t0, "resumo": linhas[-1].strip() if linhas else ""}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("filtro", nargs="*", help="só os testes com esses pedaços de nome")
    ap.add_argument("--relatorios", action="store_true", help="roda também os relatórios e o rodar_testes.py")
    ap.add_argument("-j", type=int, default=max(1, (os.cpu_count() or 2) // 2), help="quantos de cada vez")
    a = ap.parse_args()
    g = godot()
    os.makedirs(SAIDA, exist_ok=True)
    lista = [(f, False) for f in conferencias()]
    if a.relatorios:
        lista += [(f, True) for f in RELATORIOS]
    if a.filtro:
        lista = [x for x in lista if any(k in x[0] for k in a.filtro)]
    print("[+] %d testes, %d de cada vez (logs em tests/.saida)" % (len(lista), a.j))
    t0 = time.time()
    res = []
    with ThreadPoolExecutor(a.j) as ex:
        for r in ex.map(lambda x: rodar(g, x[0], x[1]), lista):
            res.append(r)
            print("  %-6s %-24s %5.0f s  %s" % (r["estado"], r["nome"], r["tempo"], r["resumo"][:110]), flush=True)
    if a.relatorios and not a.filtro:
        r = rodar_testes_py()
        res.append(r)
        print("  %-6s %-24s %5.0f s  %s" % (r["estado"], r["nome"], r["tempo"], r["resumo"][:110]), flush=True)
    ruins = [r for r in res if r["estado"] in ("FALHA", "ERRO")]
    print("\n[%s] %d ok/rodou, %d com problema, %.0f s no total" % (
        "OK" if not ruins else "PROBLEMA", len(res) - len(ruins), len(ruins), time.time() - t0))
    for r in ruins:
        print("  %s %s: %s" % (r["estado"], r["nome"], r["resumo"]))
    sys.exit(1 if ruins else 0)


if __name__ == "__main__":
    main()
