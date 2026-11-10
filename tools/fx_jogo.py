"""
fx_jogo.py
==========
Texturas de efeito do jogo -> assets/efeitos (fora do git): fumaça do escapamento
(fumaca.gd), sujeira do carro e do piloto e lama dos pneus (sujeira.gd).

O efeito "ExhaustSmokeTrail" (Effects/#3ffdac18, xml 01416) usa a textura
Sprites/Particles (.bog, 128x128) na caixa "Dust0". A caixa vem do
Sprites/Particles.bed: 4 cantos u32 (u, v x 100000) logo antes do nome; a
Dust0 dá (0, 0)-(0.497, 0.247) = pixels (0, 0)-(64, 32). Branca, com o alfa
de nuvem (PS2: 0x80 = 1.0, aqui x2).

Sujeira: a pista manda usar GEN_DIRT_DIRT (TrackProperties, Dirt
mDirtTextureName, igual em todas). Carro: Vehicles/Generic/Textures (128x128),
piloto: Characters/Textures/Dirt (256x256). Marrom com alfa de mancha.
Lama dos pneus: UNI_TyreOverlay (128x128, 4 bits; igual nos pneus do jogo),
só o alfa conta (o jogo troca a cor da paleta pela lama do chão).
Pedrinhas do pneu (pedras.gd): Sprites/dirt_rocks (atlas + caixas em pedras.json).
Lasquinhas da batida (lascas.gd): Particle_Debris.bantam + Debris -> lasca.json/png.
Poeira dos pneus (poeira.gd): Sprites/WorldFXdust (e o espirro na água,
Sprites/WorldFXwater_dust -> agua.png) (Setup/Dust.xml, tipos
Light/Medium/Heavy), 128x128, atlas de 6 nuvens (2 x 3), cinza com o alfa.

Uso:
    python tools/fx_jogo.py <unpacked> [saida=assets/efeitos]
"""

import json
import os
import struct
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gob_tex2png import convert  # noqa: E402


def ler_arquivos():
    out = {}
    for ln in open(os.path.join(PROJ, "data", "arquivos.tsv"), encoding="utf-8"):
        if ln.startswith("#"):
            continue
        cam, _, tam, _, fonte = ln.rstrip("\n").split("\t")
        out[cam.lower()] = (fonte, int(tam))
    return out


def caminho(unpacked, arqs, nome):
    fonte, tam = arqs[nome.lower()]
    arq, _, off = fonte.partition("+")
    return os.path.join(unpacked, arq), int(off or 0), tam


def caixa(bed, nome):
    """(u0, v0, u1, v1) da caixa no .bed: 8 u32 antes do nome"""
    i = bed.find(nome.encode() + b"\0")
    if i < 32:
        raise ValueError("caixa %s não achada" % nome)
    c = struct.unpack_from("<8I", bed, i - 32)
    us, vs = c[0::2], c[1::2]
    return min(us) / 1e5, min(vs) / 1e5, max(us) / 1e5, max(vs) / 1e5


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    unpacked = sys.argv[1]
    saida = sys.argv[2] if len(sys.argv) > 2 else os.path.join(PROJ, "assets", "efeitos")
    os.makedirs(saida, exist_ok=True)
    arqs = ler_arquivos()
    gob, _, _ = caminho(unpacked, arqs, "Sprites/Particles.bog")
    bed_arq, off, tam = caminho(unpacked, arqs, "Sprites/Particles.bed")
    with open(bed_arq, "rb") as f:
        f.seek(off)
        bed = f.read(tam)
    im, info = convert(gob)
    if im is None:
        raise SystemExit("Particles.bog: " + str(info))
    w, h = im.size
    u0, v0, u1, v1 = caixa(bed, "Dust0")
    box = (round(u0 * w), round(v0 * h), round(u1 * w), round(v1 * h))
    im.crop(box).save(os.path.join(saida, "fumaca.png"))
    print("Dust0", box, "->", os.path.join(saida, "fumaca.png"))
    # palha do fardo: sistema BailedHay (Effects/WorldFX.xml) pede a caixa
    # "snow", que não existe no Particles.bed (tem Snow0 e Snow1): a 1ª que
    # começa com "snow" sem diferenciar maiúscula (nossa leitura)
    u0, v0, u1, v1 = caixa(bed, "Snow0")
    box = (round(u0 * w), round(v0 * h), round(u1 * w), round(v1 * h))
    im.crop(box).save(os.path.join(saida, "palha.png"))
    print("Snow0", box, "->", os.path.join(saida, "palha.png"))

    # pedrinhas do pneu (pedras.gd, 0x3bade8): Sprites/dirt_rocks (128x128),
    # Dirt01..04 = 4 pedras cinza, Dirt05 = borrifo de terra; o atlas inteiro
    # + as caixas do .bed em pedras.json
    gob, _, _ = caminho(unpacked, arqs, "Sprites/dirt_rocks.bog")
    bed_arq, off, tam = caminho(unpacked, arqs, "Sprites/dirt_rocks.bed")
    with open(bed_arq, "rb") as f:
        f.seek(off)
        bed_p = f.read(tam)
    im, info = convert(gob)
    if im is None:
        raise SystemExit("dirt_rocks.bog: " + str(info))
    im.convert("RGBA").save(os.path.join(saida, "pedras.png"))
    caixas = {n: list(caixa(bed_p, n)) for n in ("Dirt01", "Dirt02", "Dirt03", "Dirt04", "Dirt05")}
    with open(os.path.join(saida, "pedras.json"), "w", encoding="utf-8") as f:
        json.dump(caixas, f, indent=1)
    print("dirt_rocks", im.size, caixas, "->", os.path.join(saida, "pedras.png"))

    # lasquinhas da batida (lascas.gd, 0x3bbd60): Particle_Debris.bantam (tiras
    # com a cor assada no vértice, 0x80 = 1.0) + textura Debris -> lasca.json
    # (triângulos já montados: posição, uv, cor) e lasca.png
    import rx01_objetos
    arq, off, tam = caminho(unpacked, arqs, "Levels/Grass/Models/Bantams/Particle_Debris.bantam")
    with open(arq, "rb") as f:
        f.seek(off)
        d = f.read(tam) if off else f.read()   # bloco comprimido ("c"): o arquivo todo
    tris = []
    for verts, uvs, cores, adc, slot in rx01_objetos.bantam(d):
        for i in range(2, len(verts)):
            if adc[i]:
                continue
            a, b, c = i - 2, i - 1, i
            if i % 2:
                a, b = b, a
            for k in (a, c, b):           # a ordem do obj_bantam
                tris.append([round(x, 5) for x in verts[k]] + [round(x, 5) for x in uvs[k]]
                            + [round(x, 4) for x in cores[k]])
    with open(os.path.join(saida, "lasca.json"), "w", encoding="utf-8") as f:
        json.dump({"fonte": "Levels/Grass/Models/Bantams/Particle_Debris.bantam", "tris": tris}, f)
    gob, _, _ = caminho(unpacked, arqs, "Levels/Grass/Models/Textures/Debris.bog")
    im, info = convert(gob)
    if im is None:
        raise SystemExit("Debris.bog: " + str(info))
    im.convert("RGBA").save(os.path.join(saida, "lasca.png"))
    print("Particle_Debris", len(tris) // 3, "triângulos, Debris", im.size, "->", os.path.join(saida, "lasca.png"))

    for nome, png in (("Vehicles/Generic/Textures/GEN_DIRT_DIRT.bog", "sujeira.png"),
                      ("Characters/Textures/Dirt/GEN_DIRT_DIRT.bog", "sujeira_piloto.png"),
                      ("Vehicles/Buggy/Models_4K/Wheel/#0678de18/UNI_TyreOverlay.bog", "lama_pneu.png"),
                      ("Sprites/WorldFXdust.bog", "poeira.png"),
                      ("Sprites/WorldFXwater_dust.bog", "agua.png")):
        gob, _, _ = caminho(unpacked, arqs, nome)
        im, info = convert(gob)
        if im is None:
            raise SystemExit(nome + ": " + str(info))
        im.convert("RGBA").save(os.path.join(saida, png))
        print(nome, im.size, "->", os.path.join(saida, png))


if __name__ == "__main__":
    main()
