"""
alfa_texturas.py
================
Põe de volta o alfa nas texturas dos carros que têm furo de verdade no jogo.

O gob_tex2png.py salva sem alfa (no PS2 o alfa muitas vezes é brilho, não
transparência). Nos carros só 3 texturas têm alfa "furado" (binário, parte
em 0): mesh_grey (as redes das janelas, 54% furada), Buggy_05_framework
(a treliça do Trident, 71%) e driver (7%, nas bordas). Esse script acha o
.gob de cada PNG de assets/carros/<carro>/ pelo número e, se o alfa do jogo tem
mais de 1% de pixels transparentes, regrava o PNG com alfa. O car.gd liga a
transparência por recorte nos materiais com textura de alfa.

Uso:
    python tools/alfa_texturas.py <unpacked> [pasta=assets]
"""

import glob
import os
import sys

import numpy as np

AQUI = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(AQUI)
sys.path.insert(0, AQUI)
from gob_tex2png import convert  # noqa: E402

FURO_MIN = 1.0      # % de pixels com alfa < 20 pra contar como textura furada


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    gobs = os.path.join(sys.argv[1], "gob")
    pasta = sys.argv[2] if len(sys.argv) > 2 else os.path.join(PROJ, "assets", "carros")
    cache = {}
    feitas = 0
    for png in sorted(glob.glob(os.path.join(pasta, "*", "*.png"))):
        base = os.path.basename(png)
        num = base.split("_", 1)[0]
        if not num.isdigit():
            continue
        if num not in cache:
            achados = glob.glob(os.path.join(gobs, num + "_*.gob"))
            im = None
            if achados:
                try:
                    im, _ = convert(achados[0])
                except Exception:
                    im = None
            furo = 0.0
            if im is not None:
                al = np.asarray(im.convert("RGBA"))[..., 3]
                furo = (al < 20).mean() * 100
            cache[num] = (im, furo)
        im, furo = cache[num]
        if im is None or furo <= FURO_MIN:
            continue
        im.convert("RGBA").save(png)
        feitas += 1
        print("%-50s %5.1f%% transparente" % (os.path.relpath(png, pasta), furo))
    print("%d texturas com alfa" % feitas)


if __name__ == "__main__":
    main()
