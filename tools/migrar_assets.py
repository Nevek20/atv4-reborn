"""
migrar_assets.py
================
Arruma a pasta assets/ do jeito novo (nov/2026), sem gerar nada de novo:

    assets/carros/buggy_01..12, truck_01..12, truck_bonus, escort, rodas
    assets/piloto
    assets/pista/rx01, assets/pista/terreno
    assets/efeitos   (era fx)
    assets/sons      (era sfx)

renegade -> carros/buggy_10 e sphinx -> carros/buggy_04 (o número do jogo,
como os outros). Os nomes dos arquivos (número do bloco do archive) ficam.

Pode rodar quantas vezes quiser: o que já está no lugar fica. Arquivo que já
existe no destino (os poucos que o git traz) ganha do antigo. Os .import
movidos são apagados (apontam pro caminho velho): o Godot reimporta ao abrir
ou com  %GODOT% --headless --path . --import

Uso (na pasta do projeto, DEPOIS do git pull):
    python tools/migrar_assets.py            :: move
    python tools/migrar_assets.py --ver      :: só mostra o que faria
"""
import glob
import os
import re
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(PROJ, "assets")


def mapa() -> list:
    m = [("renegade", "carros/buggy_10"), ("sphinx", "carros/buggy_04"),
         ("escort", "carros/escort"), ("rodas", "carros/rodas"), ("truck_bonus", "carros/truck_bonus"),
         ("fx", "efeitos"), ("sfx", "sons"), ("rx01", "pista/rx01"), ("terrain", "pista/terreno")]
    for d in sorted(glob.glob(os.path.join(ASSETS, "buggy_*")) + glob.glob(os.path.join(ASSETS, "truck_[0-9]*"))):
        m.append((os.path.basename(d), "carros/" + os.path.basename(d)))
    return m


def import_velho(arq: str) -> bool:
    """.import cujo source_file não é o arquivo do lado dele"""
    try:
        txt = open(arq, encoding="utf-8", errors="replace").read()
    except OSError:
        return False
    m = re.search(r'source_file="res://([^"]+)"', txt)
    if not m:
        return False
    return os.path.normcase(os.path.join(PROJ, m.group(1))) != os.path.normcase(arq[:-len(".import")])


def main():
    so_ver = "--ver" in sys.argv
    movidos = mantidos = imports = 0
    for velho, novo in mapa():
        src = os.path.join(ASSETS, velho)
        dst = os.path.join(ASSETS, *novo.split("/"))
        if not os.path.isdir(src):
            continue
        print("  assets/%-12s -> assets/%s" % (velho, novo))
        for raiz, _, arqs in os.walk(src):
            for a in arqs:
                de = os.path.join(raiz, a)
                para = os.path.join(dst, os.path.relpath(de, src))
                if a.endswith(".import"):
                    imports += 1
                    if not so_ver:
                        os.remove(de)
                elif os.path.exists(para):
                    mantidos += 1
                    if not so_ver:
                        os.remove(de)
                else:
                    movidos += 1
                    if not so_ver:
                        os.makedirs(os.path.dirname(para), exist_ok=True)
                        os.replace(de, para)
        if not so_ver:
            for raiz, _, _ in sorted(os.walk(src), key=lambda x: -len(x[0])):
                try:
                    os.rmdir(raiz)
                except OSError:
                    pass
            if os.path.isdir(src):
                print("    [!] sobrou coisa em assets/%s (veja à mão)" % velho)
    # .import que ficou apontando pro lugar velho (os que o git moveu)
    for arq in glob.glob(os.path.join(ASSETS, "**", "*.import"), recursive=True):
        if import_velho(arq):
            imports += 1
            if not so_ver:
                os.remove(arq)
    print("[%s] %d movidos, %d já estavam no destino, %d .import velhos apagados" % (
        "ver" if so_ver else "ok", movidos, mantidos, imports))
    if not so_ver and (movidos or imports):
        print("    agora: %GODOT% --headless --path . --import   (ou abre o Godot e espera importar)")


if __name__ == "__main__":
    main()
