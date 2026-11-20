"""
hud_jogo.py
===========
Extrai o HUD do jogo (HUD_PS2) pro Godot: as texturas com alfa, as caixas
do .bed de cada uma (fração da textura) e as fontes (FE_FontSmall/Medium,
glifos no .bed). O layout é o HUD_CIRCUIT.xml (xml 01476, nome pelo CRC:
/%s/HUD_%s, cFEXHUDManager_CIRCUIT), copiado pra data/hud_circuit.xml.

Saída: assets/hud/<nome>.png + assets/hud/hud.json
    {"texturas": {nome: {"png", "w", "h", "caixas": {caixa: [x0, y0, x1, y1]}}}}

Uso (na pasta do projeto):
    python tools/hud_jogo.py <unpacked>
"""

import json
import os
import struct
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(AQUI)
sys.path.insert(0, AQUI)
from gob_tex2png import convert  # noqa: E402

BED_ESCALA = 100000.0
# nome no layout -> caminho no archive (sem extensão)
TEXTURAS = {
    "hud_tpage_rev9000": "HUD_PS2/Textures/CURwR3nT.ani/hud_tpage_rev9000",
    "hud_tpage_rev10000": "HUD_PS2/Textures/CURwR3nT.ani/hud_tpage_rev10000",
    "hud_tpage_rev12000": "HUD_PS2/Textures/CURwR3nT.ani/hud_tpage_rev12000",
    "hud_tpage_bar": "HUD_PS2/Textures/hud_tpage_bar",
    "HUD_Flag": "HUD_PS2/Textures/HUD_Flag",
    "HUD_FlagGreen": "HUD_PS2/Textures/HUD_FlagGreen",
    "HUD_FlagWhite": "HUD_PS2/Textures/HUD_FlagWhite",
    "HUD_StartBoard": "HUD_PS2/Textures/HUD_StartBoard",
    "song_bkgr": "HUD_PS2/Textures/song_bkgr",
    "RX_01_RALLYCROSS": "HUD_PS2/Textures/Minimaps/RX_01_RALLYCROSS",
    "FONT_SMALL": "Fonts/FE_FontSmall",
    "FONT_MEDIUM": "Fonts/FE_FontMedium",
    "HUD_Numbers": "Fonts/HUD_Numbers",
    "HUD_Digital": "Fonts/HUD_Digital",
}
LAYOUT = "HUD_PS2/#3ca67004"            # HUD_CIRCUIT.xml


def ler_arquivos():
    out = {}
    for ln in open(os.path.join(PROJ, "data", "arquivos.tsv"), encoding="utf-8"):
        if ln.startswith("#"):
            continue
        cam, _, tam, cu, fonte = ln.rstrip("\n").split("\t")
        out[cam.lower()] = (int(tam), fonte)
    return out


def ler(unpacked, arqs, caminho):
    """bytes de um arquivo do archive (bloco próprio ou pedaço de um raw)"""
    f = arqs.get(caminho.lower())
    if not f or not f[1]:
        return None
    arq, _, off = f[1].partition("+")
    d = open(os.path.join(unpacked, arq), "rb").read()
    if off:
        d = d[int(off):int(off) + f[0]]
    return d


def ler_bed(d):
    """.bed -> {nome: [x0, y0, x1, y1]} (fração; cantos 0 e 2, como o jogo)"""
    p = d.index(b"\0", 2) + 1
    n = struct.unpack_from("<HHH", d, p)[2]
    p += 6
    out = {}
    for _ in range(n):
        nv = struct.unpack_from("<H", d, p)[0]
        pts = [struct.unpack_from("<ii", d, p + 2 + 8 * k) for k in range(nv)]
        p += 2 + 8 * nv
        q = d.index(b"\0", p)
        nome = d[p:q].decode("latin-1")
        p = q + 3
        if nv < 3:
            continue
        (x0, y0), (x1, y1) = pts[0], pts[2]
        out[nome] = [x0 / BED_ESCALA, y0 / BED_ESCALA, x1 / BED_ESCALA, y1 / BED_ESCALA]
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    unpacked = sys.argv[1]
    arqs = ler_arquivos()
    out_dir = os.path.join(PROJ, "assets", "hud")
    os.makedirs(out_dir, exist_ok=True)
    info = {"texturas": {}}
    tmp = os.path.join(out_dir, "_tmp.gob")
    for nome, cam in TEXTURAS.items():
        g = ler(unpacked, arqs, cam + ".bog")
        if g is None:
            print("[!] sem %s.bog" % cam)
            continue
        open(tmp, "wb").write(g)
        im, err = convert(tmp)
        if im is None:
            print("[!] %s: %s" % (cam, err))
            continue
        idx = im.info.get("indices")
        im = im.convert("RGBA")
        im.save(os.path.join(out_dir, nome + ".png"))
        if nome == "hud_tpage_bar" and idx:
            # barras que acendem trocando cores da CLUT (OBJECT_FILLBAR): o
            # índice de cada pixel numa imagem cinza (o Godot pinta por bloco)
            from PIL import Image
            ii = Image.new("L", im.size)
            ii.putdata(idx)
            ii.save(os.path.join(out_dir, nome + "_idx.png"))
        b = ler(unpacked, arqs, cam + ".bed")
        info["texturas"][nome] = {"png": nome + ".png", "w": im.width, "h": im.height,
                                  "caixas": ler_bed(b) if b else {}}
        print("[+] %s %dx%d, %d caixas" % (nome, im.width, im.height, len(info["texturas"][nome]["caixas"])))
    os.remove(tmp)
    # kerning das fontes: o bloco Fonts/#hash logo depois do .bog de cada uma
    # (exe 0x2689c0, flag 0x40): cabeçalho (f32 ?, u32 linhas, f32 base, f32
    # passo, f32 ?, f32 ?, u32 0), mapa de 192 bytes (caractere 0x40.. -> linha,
    # 0xff = sem) e linhas de 0x60 bytes com um nibble por 2º caractere
    # (0x40..). Avanço = largura do glifo - (base + nibble x passo); antes de
    # '@' só a base. Unidade 1/320 = 1 pixel na referência de 640
    linhas = [ln.rstrip("\n").split("\t") for ln in open(os.path.join(PROJ, "data", "arquivos.tsv"), encoding="utf-8")
              if not ln.startswith("#")]
    for nome, cam in TEXTURAS.items():
        if not nome.startswith("FONT_") or nome not in info["texturas"]:
            continue
        bog = [l for l in linhas if l[0].lower() == (cam + ".bog").lower()]
        if not bog:
            continue
        off = int(bog[0][1])
        prox = sorted((int(l[1]), l) for l in linhas if l[0].startswith("Fonts/#") and int(l[1]) > off and l[4])
        if not prox:
            continue
        d = ler(unpacked, arqs, prox[0][1][0])
        if not d or len(d) < 0x1c + 192:
            continue
        _, nl, base, passo = struct.unpack_from("<fIff", d, 0)
        mapa = list(d[0x1c:0x1c + 192])
        tab = []
        for r in range(nl):
            row = d[0x1c + 192 + r * 0x60: 0x1c + 192 + (r + 1) * 0x60]
            tab.append([(row[c // 2] >> 4) if c & 1 else (row[c // 2] & 0xF) for c in range(192)])
        info["texturas"][nome]["kern"] = {"base": round(base * 320.0, 3), "passo": round(passo * 320.0, 3),
                                         "mapa": mapa, "tabela": tab}
        print("[+] kerning %s: base %.2f px, passo %.2f px, %d linhas" % (nome, base * 320, passo * 320, nl))
    lay = ler(unpacked, arqs, LAYOUT)
    # textos do layout (mText é a chave da tabela de tradução: LEAD, BEST_LAP_S...)
    import re
    chaves = set(re.findall(rb'mText="([^"]*)"', lay or b""))
    info["textos"] = {}
    for lingua, arq in (("en", "15205_en.txt"), ("pt", "15212_pt.txt")):
        t = {}
        for ln in open(os.path.join(unpacked, "text", arq), "rb").read().split(b"\n"):
            k, _, v = ln.rstrip(b"\r").partition(b"\t")
            if k in chaves and k.decode("latin-1") not in t:
                t[k.decode("latin-1")] = v.decode("latin-1")
        info["textos"][lingua] = t
    json.dump(info, open(os.path.join(out_dir, "hud.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    if lay:
        open(os.path.join(PROJ, "data", "hud_circuit.xml"), "wb").write(lay.replace(b"\r\n", b"\n"))
        print("[+] data/hud_circuit.xml")


if __name__ == "__main__":
    main()
