"""
hud_ref.py
==========
Referência do layout do HUD tirada da RAM de um save state (4:3, PAL): pra
cada objeto do data/hud_circuit.xml acha o quadro dele na RAM pelos 8 valores
do Frame (alinhamentos, offsets, offset absoluto, escalas, modo; quadro+8) e
grava a matriz (quadro+0x30: escala x/y e posição em NDC, y pra cima) em
tests/ref_hud_4x3.json. Quadro com dados repetidos (2 objetos iguais) fica de
fora. O tests/teste_hud.gd compara com o menu/hud_jogo.gd a 640x480.

Uso: python re/hud_ref.py arquivo.p2s
"""
import json
import os
import re
import struct
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(AQUI)
sys.path.insert(0, os.path.join(PROJ, "tools"))
from ler_savestate import ler_ram  # noqa: E402

AX = {"ALIGN_LEFT": 0, "ALIGN_RIGHT": 1, "ALIGN_CENTRE": 2}
AY = {"ALIGN_BOTTOM": 0, "ALIGN_TOP": 1, "ALIGN_CENTRE": 2}
MODO = {"SCALE_RELATIVE": 0, "SCALE_UNIT_RELATIVE": 1, "SCALE_ABSOLUTE": 2}


def main():
    m = ler_ram(sys.argv[1])
    s = open(os.path.join(PROJ, "data", "hud_circuit.xml"), encoding="latin-1").read()
    out = {}
    for mm in re.finditer(r"<(\w+)[^>]*>\s*(?:<mColour[^>]*/>\s*)?<Frame ([^>]*)/>", s):
        nome = mm.group(1)
        a = dict(re.findall(r'(\w+)="([^"]*)"', mm.group(2)))
        try:
            dados = struct.pack("<IIffIffI", AX[a["mAlignX"]], AY[a["mAlignY"]], float(a["mOffsetX"]),
                                float(a["mOffsetY"]), int(a["mOffsetAbsolute"]), float(a["mScaleX"]),
                                float(a["mScaleY"]), MODO[a["mScaleMode"]])
        except KeyError:
            continue
        achados = [i.start() for i in re.finditer(re.escape(dados), m)]
        if len(achados) != 1 or nome in out:
            continue
        mt = struct.unpack_from("<16f", m, achados[0] - 8 + 0x30)
        out[nome] = [round(mt[0], 5), round(mt[5], 5), round(mt[12], 5), round(mt[13], 5)]
    json.dump(out, open(os.path.join(PROJ, "tests", "ref_hud_4x3.json"), "w"), indent=1)
    print("[+] %d quadros em tests/ref_hud_4x3.json" % len(out))


if __name__ == "__main__":
    main()
