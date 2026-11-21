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


def kerning(unpacked, arqs, cam):
    """kerning de uma fonte (cam sem extensão): o bloco Fonts/#hash logo
    depois do .bog dela (exe 0x2689c0, flag 0x40): cabeçalho (f32 ?, u32
    linhas, f32 base, f32 passo, f32 ?, f32 ?, u32 0), mapa de 192 bytes
    (caractere 0x40.. -> linha, 0xff = sem) e linhas de 0x60 bytes com um
    nibble por 2º caractere (0x40..). Avanço = largura do glifo - (base +
    nibble x passo); antes de '@' só a base. Unidade 1/320 = 1 pixel na
    referência de 640. None sem o bloco"""
    linhas = [ln.rstrip("\n").split("\t") for ln in open(os.path.join(PROJ, "data", "arquivos.tsv"), encoding="utf-8")
              if not ln.startswith("#")]
    bog = [l for l in linhas if l[0].lower() == (cam + ".bog").lower()]
    if not bog:
        return None
    off = int(bog[0][1])
    prox = sorted((int(l[1]), l) for l in linhas if l[0].startswith("Fonts/#") and int(l[1]) > off and l[4])
    if not prox:
        return None
    d = ler(unpacked, arqs, prox[0][1][0])
    if not d or len(d) < 0x1c + 192:
        return None
    _, nl, base, passo = struct.unpack_from("<fIff", d, 0)
    mapa = list(d[0x1c:0x1c + 192])
    tab = []
    for r in range(nl):
        row = d[0x1c + 192 + r * 0x60: 0x1c + 192 + (r + 1) * 0x60]
        tab.append([(row[c // 2] >> 4) if c & 1 else (row[c // 2] & 0xF) for c in range(192)])
    return {"base": round(base * 320.0, 3), "passo": round(passo * 320.0, 3), "mapa": mapa, "tabela": tab}


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
    for nome, cam in TEXTURAS.items():
        if not nome.startswith("FONT_") or nome not in info["texturas"]:
            continue
        k = kerning(unpacked, arqs, cam)
        if k:
            info["texturas"][nome]["kern"] = k
            print("[+] kerning %s: base %.2f px, passo %.2f px, %d linhas" % (nome, k["base"], k["passo"], len(k["tabela"])))
    lay = ler(unpacked, arqs, LAYOUT)
    # textos do layout (mText é a chave da tabela de tradução: LEAD, BEST_LAP_S...)
    import re
    chaves = set(re.findall(rb'mText="([^"]*)"', lay or b""))
    # mensagens da corrida (chaves que o exe passa pelos ids de texto:
    # largada 0x4796c0, voltas e avisos 0x47bb58; menu/hud_jogo.gd TEXTOS_CORRIDA)
    # e os nomes dos truques do Score
    chaves |= {b"Get_Ready", b"Go_", b"GET_ON_THE_GAS", b"Lap_Complete", b"Final_Lap", b"Race_Complete",
               b"Too_Fast_For_Respot", b"WRONG_WAY", b"Off_Track_Go_Back", b"MISSED_CHECKPOINT", b"Rolling_Start",
               b"Slide", b"AirTime"}       # nomes dos truques (0x1b5d08; pista/truques.gd)
    info["textos"] = {}
    for lingua, arq in (("en", "15205_en.txt"), ("pt", "15212_pt.txt")):
        t = {}
        for ln in open(os.path.join(unpacked, "text", arq), "rb").read().split(b"\n"):
            k, _, v = ln.rstrip(b"\r").partition(b"\t")
            if k in chaves and k.decode("latin-1") not in t:
                t[k.decode("latin-1")] = v.decode("latin-1")
        info["textos"][lingua] = t
    # minimapa do evento (HUD_PS2/MINIMAPS.xml): RX_01 RALLYCROSS = base x/z,
    # escala (/1000) e offset; o ponto do carro = canto do MINIMAP_CIRCUIT +
    # (offset - (x - base) x escala / 1000), em NDC 4:3 (RAM dos save states)
    mm = ler(unpacked, arqs, "HUD_PS2/MINIMAPS.xml")
    if mm:
        import re as _re
        t = mm.decode("latin-1")
        b = _re.search(r"<RX_01>\s*<RALLYCROSS ([^>]*)/>", t)
        if b:
            at = dict(_re.findall(r'(\w+)="([^"]*)"', b.group(1)))
            info["minimapa"] = {k: float(v) for k, v in at.items()}
            print("[+] minimapa RX_01: %s" % info["minimapa"])
    # seta 3D (OBJECT_3DARROW): o modelo UI_PS2/InGame/Models/ARROW.pingu (só
    # cor de vértice, ponta em -z) desenhado numa textura pelo HUD
    seta = ler(unpacked, arqs, "UI_PS2/InGame/Models/ARROW.pingu")
    if seta:
        from pingu2obj import parse, to_obj
        tiras = parse(seta)
        if tiras:
            txt, nv, nf = to_obj(tiras, "seta")
            open(os.path.join(out_dir, "seta.obj"), "w").write(txt)
            print("[+] seta.obj: %d vértices, %d triângulos" % (nv, nf))
    json.dump(info, open(os.path.join(out_dir, "hud.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    if lay:
        open(os.path.join(PROJ, "data", "hud_circuit.xml"), "wb").write(lay.replace(b"\r\n", b"\n"))
        print("[+] data/hud_circuit.xml")


if __name__ == "__main__":
    main()
