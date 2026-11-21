"""
resultados_ram.py
=================
Referência da tela de resultados (menu/resultados.gd) tirada da RAM de um
save state PAL em cima dela (placar_final.p2s): cada texto do .fex
(objeto cDOString, vtable 0x588158: fonte +8, string +0xc, flags +0x20,
canto de cima à esquerda em NDC +0x30, escala +0x40/+0x44, cor de cima
+0x50 e de baixo +0x60, vértices +0x74) com o retângulo das letras na tela
640 x 480 de referência. Vértices: 0x30 bytes cada (cor, st, xyz), 2 por
letra (canto de cima à esquerda e de baixo à direita) nos textos sem giro;
x da tela = (X/16 - 1792) x 1.25, y = (Y/16 - 1792) x 480 / 512.

O nome do perfil do jogador fica de fora: os nomes que não são de pilotos
do AIPlayers.xml (data/ia.json) não vão pro arquivo.

Grava tests/ref_resultados.json. Uso:
    python re/resultados_ram.py placar_final.p2s
"""
import json
import os
import struct
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(AQUI)
sys.path.insert(0, os.path.join(PROJ, "tools"))
from ler_savestate import ler_ram  # noqa: E402

VT = 0x588158


def main():
    m = ler_ram(sys.argv[1])
    u = lambda a: struct.unpack_from("<I", m, a)[0]
    f = lambda a: struct.unpack_from("<f", m, a)[0]
    pilotos = {p["nome"] for p in json.load(open(os.path.join(PROJ, "data", "ia.json")))["pilotos"]}
    out = []
    pat = struct.pack("<I", VT)
    i = m.find(pat)
    while i >= 0:
        o = i - 0x1C
        i = m.find(pat, i + 1)
        fonte, sp, vp = u(o + 8), u(o + 0xC), u(o + 0x74)
        if fonte == 0 or not (0x100000 < sp < len(m)) or not (0x100000 < vp < len(m)):
            continue
        s = m[sp:m.find(b"\0", sp)].decode("latin-1")
        n = len(s.replace(" ", ""))
        if not 0 < n < 40:
            continue
        gx = lambda a: (u(a) / 16.0 - 1792.0) * 1.25
        gy = lambda a: (u(a) / 16.0 - 1792.0) * 480.0 / 512.0
        e = {"txt": s, "pos": [round(f(o + 0x30), 5), round(f(o + 0x34), 5)],
             "esc": round(f(o + 0x40), 4), "flags": u(o + 0x20),
             "cor": [round(f(o + 0x50 + 4 * k), 4) for k in range(8)]}
        if s == "Race Results":
            # título girado: 4 vértices por letra (baixo esq, cima esq, baixo dir, cima dir)
            e["letra0"] = [[round(gx(vp + k * 0x30 + 0x20), 2), round(gy(vp + k * 0x30 + 0x24), 2)] for k in range(4)]
        else:
            e["x"] = [[round(gx(vp + k * 0x60 + 0x20), 2), round(gx(vp + k * 0x60 + 0x50), 2)] for k in range(n)]
            e["y"] = [round(gy(vp + 0x24), 2), round(gy(vp + 0x54), 2)]
        if "x" in e and not all(0.0 <= a <= 640.0 and 0.0 <= b <= 640.0 for a, b in e["x"]) \
                or "y" in e and not all(0.0 <= y <= 480.0 for y in e["y"]):
            continue                    # objeto velho de outra tela (vértices de lixo)
        nome_col = abs(e["pos"][0] + 0.6) < 0.05 and e["esc"] == 0.65 and not s.isdigit()
        if nome_col and s not in pilotos:
            continue                    # o nome do perfil não vai pro repositório
        out.append(e)
    out.sort(key=lambda e: (-e["pos"][1], e["pos"][0]))
    json.dump({"fonte": os.path.basename(sys.argv[1]) + " (re/resultados_ram.py)", "textos": out},
              open(os.path.join(PROJ, "tests", "ref_resultados.json"), "w", encoding="utf-8"), indent=1)
    print("[+] %d textos em tests/ref_resultados.json" % len(out))
    for e in out:
        print("   %-14s pos (%.4f, %.4f) esc %.2f %s" % (e["txt"], e["pos"][0], e["pos"][1], e["esc"],
                                                       e.get("x", [[0, 0]])[0]), flush=True)


if __name__ == "__main__":
    main()
