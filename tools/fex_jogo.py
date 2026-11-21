"""
fex_jogo.py
===========
Telas do menu do jogo (.fex do UI_PS2) pro Godot. Por enquanto a tela de
resultados da corrida (cSRResultsPage: LAYER_RESULTS do PostRace.fex) com o
que ela puxa: LAYER_FAKE_HISTORY (título) e LAYER_IG_BUTTON_BAR (barra de
baixo) do Common.fex e LAYER_PAUSE_BACKGROUND (fundo) do NewPause.fex.

Formato .fex (binário, little endian): 00 00 03 00 e um bloco raiz. Bloco =
f0 0d ab cd, tamanho (bytes depois dele), tipo (hash) e depois, até o fim,
blocos filhos ou pares (chave, valor). Hash = CRC32 sem o xor final do nome
("mRect", "X"...; os nomes estão no exe). Valor: 4 bytes (int ou float), ou
string (tamanho + bytes + 0 + 0xcd até múltiplo de 4; com tamanho múltiplo
de 4 não tem o 0), ou um bloco. 0xbadcadde marca fim de lista.

Blocos (nov/2026, conferidos com a RAM do placar_final.p2s):
  Ingame.fpj: Font0 FE_FontSmall, Font1 FE_FontMedium, Font2 FE_FontLarge.
  PostRace.fex = other/16698, Common.fex = other/16690 (os nomes do
  archive são hash), NewPause.fex = other/16696.

Saída:
    data/fex_resultados.json   camadas (árvore: quadros, sprites, textos)
    assets/ui/<textura>.png + assets/ui/ui.json (caixas .bed, fonte grande,
    textos da tabela do jogo em en e pt)

Uso (na pasta do projeto):
    python tools/fex_jogo.py <unpacked>
"""

import json
import os
import struct
import sys
import zlib

AQUI = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(AQUI)
sys.path.insert(0, AQUI)
import hud_jogo  # noqa: E402
from gob_tex2png import convert  # noqa: E402

MAG = 0xCDAB0DF0
FIM = 0xBADCADDE
# nomes das chaves e classes usados nesses .fex (do exe)
NOMES = ['A', 'B', 'BoxName', 'Children', 'FileVersion', 'G', 'H', 'R', 'RX', 'RY', 'Rct', 'Root', 'Rot',
         'Shad', 'TexName', 'U0', 'U1', 'V0', 'V1', 'W', 'X', 'Y', '_DYN_CREATE_', '_DYN_HIERARCHY_',
         '_OBJECT_NAME_', 'cATVTextButton', 'cDOMenuSelector', 'cDOMovingSprite', 'cDOSelectorButton',
         'cDOSelectorSetting', 'cDOSprite', 'cDOString', 'cDOTransitionFrame', 'cDisplayLayer',
         'cDisplayObject', 'cDisplayReferenceLayer', 'mAlpha', 'mAspect', 'mChildList', 'mColour', 'mColour1',
         'mColour2', 'mColourBL', 'mColourBR', 'mColourTL', 'mColourTR', 'mDocument', 'mEndColour1',
         'mEndColour2', 'mEndXPos', 'mEndYPos', 'mFlags', 'mFont', 'mHotspotX', 'mHotspotY', 'mID',
         'mIncludeCopy', 'mJustify', 'mLayer', 'mLayerID', 'mLayers', 'mMoving', 'mpDSSprite', 'mpStringName',
         'mRect', 'mRotation', 'mScale', 'mScrollStyle', 'mSpacingMode', 'mStringNameInTable', 'mVelocityX',
         'mVelocityY', 'mVisible', 'mZedOffset', 'mType']
H = {zlib.crc32(n.encode()) ^ 0xFFFFFFFF: n for n in NOMES}

DOCS = {"PostRace": "other/16698_bloco.bin", "Common": "other/16690_bloco.bin",
        "NewPause": "other/16696_bloco.bin"}
CAMADAS = [("Common", "LAYER_FAKE_HISTORY"), ("NewPause", "LAYER_PAUSE_BACKGROUND"),
           ("PostRace", "LAYER_RESULTS"), ("Common", "LAYER_IG_BUTTON_BAR")]
TEXTURAS = {
    "4_bit_generics": ("UI_PS2/FrontEnd/Textures/fex_new/#657f9b86", "UI_PS2/FrontEnd/Textures/fex_new/#069922b6"),
    "FE_extras": ("UI_PS2/FrontEnd/Textures/fex_new/FE_extras.bog", "UI_PS2/FrontEnd/Textures/fex_new/FE_extras.bed"),
    "pause_bits": ("UI_PS2/InGame/Textures/pause_bits.bog", "UI_PS2/InGame/Textures/pause_bits.bed"),
    "new_buttons_4bit_en_GB": ("UI_PS2/FrontEnd/Textures/fex_new/new_buttons_4bit_en_GB.bog",
                               "UI_PS2/FrontEnd/Textures/fex_new/new_buttons_4bit_en_GB.bed"),
    "FONT_LARGE": ("Fonts/FE_FontLarge.bog", "Fonts/FE_FontLarge.bed"),
}
CHAVES_TEXTO = ["RACE_RESULTS", "POSITION", "NAME", "TOTAL_TIME", "BEST_LAP", "STUNT_SCORE", "CONTINUE"]


def ler_fex(d):
    u = lambda o: struct.unpack_from("<I", d, o)[0]

    def nome(x):
        return H.get(x, "#%08x" % x)

    def bloco(o):
        fim = o + 8 + u(o + 4)
        no = {"tipo": nome(u(o + 8)), "props": [], "filhos": []}
        p = o + 12
        while p < fim:
            if u(p) == MAG:
                c, p = bloco(p)
                no["filhos"].append(c)
                continue
            k = u(p)
            p += 4
            if k == FIM or p >= fim:
                continue
            v = u(p)
            if v == MAG:
                c, p = bloco(p)
                no["props"].append((nome(k), c))
                continue
            if 0 < v < 400 and p + 4 + v <= fim and (v % 4 == 0 or d[p + 4 + v] == 0) \
                    and all(32 <= c < 127 for c in d[p + 4:p + 4 + v]):
                no["props"].append((nome(k), d[p + 4:p + 4 + v].decode("latin-1")))
                p += 4 + (v + 3) // 4 * 4
                continue
            if v in H and v > 0xFFFF:
                val = H[v]
            elif v < 0x100000 or v > 0xFFF00000:
                val = struct.unpack_from("<i", d, p)[0]
            else:
                val = round(struct.unpack_from("<f", d, p)[0], 6)
            p += 4
            no["props"].append((nome(k), val))
        return no, fim
    return bloco(4)[0]


def _cor(no):
    p = dict(no["props"])
    return [p.get("R", 0), p.get("G", 0), p.get("B", 0), p.get("A", 0)]


def _rect(no):
    p = dict(no["props"])
    return [p.get("X", 0), p.get("Y", 0), p.get("W", 0), p.get("H", 0)]


CORES = ("mColour", "mColour1", "mColour2", "mEndColour1", "mEndColour2",
         "mColourTL", "mColourTR", "mColourBL", "mColourBR")


def simplificar(no):
    """bloco do .fex -> nó do layout (nome, classe, rect, cores, props, filhos)"""
    p = {}
    for k, v in no["props"]:
        if not isinstance(v, dict):
            p.setdefault(k, v)
    out = {"nome": p.get("mID", no["tipo"])}
    for k in ("mVisible", "mAlpha", "mRotation", "mHotspotX", "mHotspotY", "BoxName", "TexName", "mFont",
              "mFlags", "mJustify", "mSpacingMode", "mScale", "mAspect", "mpStringName", "mStringNameInTable",
              "mVelocityX", "mVelocityY", "mMoving", "mScrollStyle", "mEndXPos", "mEndYPos", "mIncludeCopy"):
        if k in p:
            out[k] = p[k]
    filhos = []
    for c in no["filhos"]:
        t = c["tipo"]
        if t == "mRect":
            out["rect"] = _rect(c)
        elif t in CORES:
            out[t] = _cor(c)
        elif t == "mpDSSprite":
            q = dict(c["props"])
            out["uv"] = [q.get("U0", 0), q.get("V0", 0), q.get("U1", 1), q.get("V1", 1)]
        elif t == "mLayerID":
            q = dict(c["props"])
            out["ref"] = [q.get("mDocument", ""), q.get("mLayer", "")]
        elif t in ("mChildList", "Children"):
            filhos += _lista(c)
        else:
            filhos.append(simplificar(c))
    if filhos:
        out["filhos"] = filhos
    # tipo pelo conteúdo (a classe vem em hash no _DYN_CREATE_): cDOSprite
    # (mpDSSprite com U0..V1: V0 = baixo, V1 = cima da caixa do .bed),
    # cDOMovingSprite (+ velocidade), cDOString, cDisplayReferenceLayer, quadro
    if "uv" in out:
        out["tipo"] = "sprite_movel" if "mVelocityX" in out else "sprite"
    elif "mpStringName" in out:
        out["tipo"] = "texto"
    elif "ref" in out:
        out["tipo"] = "ref"
    else:
        out["tipo"] = "quadro"
    return out


def _lista(c):
    out = []
    for cc in c["filhos"]:
        if cc["tipo"] in ("mChildList", "Children"):
            out += _lista(cc)
        else:
            out.append(simplificar(cc))
    return out


def camada(raiz, nome):
    for ls in raiz["filhos"]:
        if ls["tipo"] == "mLayers":
            for c in ls["filhos"]:
                if c["tipo"] in (nome, "#%08x" % (zlib.crc32(nome.encode()) ^ 0xFFFFFFFF)):
                    return simplificar(c)
    return None


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    unpacked = sys.argv[1]
    arqs = hud_jogo.ler_arquivos()
    raizes = {k: ler_fex(open(os.path.join(unpacked, v), "rb").read()) for k, v in DOCS.items()}
    lay = {"fonte": "UI_PS2/InGame (tools/fex_jogo.py)", "fontes": ["FONT_SMALL", "FONT_MEDIUM", "FONT_LARGE"],
           "camadas": {}}
    for doc, nome in CAMADAS:
        c = camada(raizes[doc], nome)
        if c is None:
            print("[!] sem %s em %s" % (nome, doc))
            continue
        lay["camadas"][nome] = c
        print("[+] %s/%s" % (doc, nome))
    json.dump(lay, open(os.path.join(PROJ, "data", "fex_resultados.json"), "w", encoding="utf-8"), indent=1)
    print("[+] data/fex_resultados.json")
    out_dir = os.path.join(PROJ, "assets", "ui")
    os.makedirs(out_dir, exist_ok=True)
    info = {"texturas": {}}
    tmp = os.path.join(out_dir, "_tmp.gob")
    for nome, (bog, bed) in TEXTURAS.items():
        g = hud_jogo.ler(unpacked, arqs, bog)
        if g is None:
            print("[!] sem %s" % bog)
            continue
        open(tmp, "wb").write(g)
        im, err = convert(tmp)
        if im is None:
            print("[!] %s: %s" % (bog, err))
            continue
        im = im.convert("RGBA")
        im.save(os.path.join(out_dir, nome + ".png"))
        b = hud_jogo.ler(unpacked, arqs, bed)
        info["texturas"][nome] = {"png": nome + ".png", "w": im.width, "h": im.height,
                                  "caixas": hud_jogo.ler_bed(b) if b else {}}
        if nome.startswith("FONT_"):
            k = hud_jogo.kerning(unpacked, arqs, bog[:-4])
            if k:
                info["texturas"][nome]["kern"] = k
        print("[+] %s %dx%d, %d caixas" % (nome, im.width, im.height, len(info["texturas"][nome]["caixas"])))
    os.remove(tmp)
    info["textos"] = {}
    for lingua, arq in (("en", "15205_en.txt"), ("pt", "15212_pt.txt")):
        t = {}
        for ln in open(os.path.join(unpacked, "text", arq), "rb").read().split(b"\n"):
            k, _, v = ln.rstrip(b"\r").partition(b"\t")
            k = k.decode("latin-1")
            if k in CHAVES_TEXTO and k not in t:
                t[k] = v.decode("latin-1")
        info["textos"][lingua] = t
    json.dump(info, open(os.path.join(out_dir, "ui.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print("[+] assets/ui/ui.json")


if __name__ == "__main__":
    main()
