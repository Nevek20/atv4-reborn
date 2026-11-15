"""
piloto_pintura.py
=================
Textura do piloto montada como o jogo (Garage -> Rider: Gear e Paint Shop).

O jogo monta a textura do piloto (512x512) pelo
/Setup/CharacterComposite/Textures/COMPOSITOR.xml: uma caixa por parte (o
RIDER.bed diz onde) e, em cada uma, as camadas do conjunto escolhido
(Characters/Textures/#.../<Parte>/RIDER_NN_<CAMADA>_<PARTE>.bog, NN =
mTextureNum do CLOTHING.xml):

    BASE       Blend Off: a textura (branca) x a cor BASE do perfil
    PRIMARY    x a cor PRIMARY, por cima pelo alfa
    SECONDARY  x a cor SECONDARY, por cima pelo alfa
    OVERLAY    a DETAIL (já colorida), por cima pelo alfa
    WRINKLE    Multiply só no RGB (dobras do tecido)

Partes: CLOTHING, ARMS e LEGS seguem a roupa (Gear), HELMET o capacete,
GOGGLES os óculos, GLOVES as luvas, BOOTS as botas; FACE e HAIR são uma
textura só (Blend Off); PLAYER_NAME (fonte FE_FontMedium) e PLAYER_NUMBER
(HUD_Numbers) no fim, na cor TEXT. As cores valem pro piloto todo.
Perfil (save states gear.p2s e Paint_Shop.p2s do Matheus, docs Piloto): 5
modelos (roupa, capacete, óculos, luva, bota), base, primária, secundária e
texto em float RGBA, depois rosto, cabelo, sexo, nome e número.

O Godot (carro/piloto_pintura.gd) monta de novo com as escolhas do jogador:
aqui as camadas já saem no tamanho da caixa (camadas/<parte>_<NN>_<camada>.png)
e a conta é inteira (a mesma do C++ FisicaCarro.compor_piloto), pra sair igual
pixel a pixel (tests/teste_piloto_pintura.gd).

Uso (o tools/piloto.py já chama):
    python tools/piloto_pintura.py <unpacked> [--out assets/piloto]
"""

import json
import os
import sys
import xml.etree.ElementTree as ET

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gob_tex2png import convert  # noqa: E402
from sfx_jogo import ler_arquivos, ler_bloco  # noqa: E402
import gerar_pintura as gp  # noqa: E402

TAM = 512                                  # RIDER.bed: Rider_Template.tga 512x512
CAMADAS = ("base", "primary", "secondary", "detail", "wrinkle")
# parte do COMPOSITOR -> (escolha do perfil, pasta/nome da parte nos arquivos)
PARTES = [
    ("CLOTHING", "roupa", "clothing"),
    ("ARMS", "roupa", "arms"),
    ("LEGS", "roupa", "legs"),
    ("GOGGLES", "oculos", "goggles"),
    ("BOOTS", "bota", "boots"),
    ("GLOVES", "luva", "gloves"),
    ("HELMET", "capacete", "helmet"),
]
# categorias do CLOTHING.xml -> escolha do perfil (ordem do perfil na RAM)
CATEGORIAS = {"Gear": "roupa", "Helmet": "capacete", "Goggles": "oculos", "Gloves": "luva", "Boots": "bota"}
NOME_PADRAO = "PLAYER"                     # perfil novo (string ao lado do "00", 0x56b0a0)
NUMERO_PADRAO = "00"


class Fonte:
    """arquivos pelo caminho do archive (data/arquivos.tsv)"""

    def __init__(self, unpacked, tmp):
        self.unpacked = unpacked
        self.arqs = ler_arquivos()
        self.tmp = tmp
        self.cache = {}

    def bloco(self, cam):
        return ler_bloco(self.unpacked, self.arqs, cam)

    def textura(self, cam):
        if cam not in self.cache:
            p = os.path.join(self.tmp, "_tex.bog")
            with open(p, "wb") as f:
                f.write(self.bloco(cam))
            im, info = convert(p)
            self.cache[cam] = im.convert("RGBA") if im else None
        return self.cache[cam]

    def acha(self, fim):
        fim = fim.lower()
        return next((c for c in self.arqs if c.endswith(fim)), None)


def caixas(f):
    bed = gp.ler_bed(f.bloco("Setup/CharacterComposite/Textures/RIDER.bed"))
    out = {}
    for k, (x0, y0, x1, y1) in bed.items():
        out[k] = [round(x0 * TAM), round(y0 * TAM), round(x1 * TAM) - round(x0 * TAM), round(y1 * TAM) - round(y0 * TAM)]
    return out


def clothing(f):
    """modelos por categoria (mName, mTextureNum) e as DefaultColours (1 por roupa)"""
    r = ET.fromstring(f.bloco("Setup/CLOTHING.xml").decode("latin-1"))
    modelos = {}
    for cat in r:
        if cat.tag in CATEGORIAS:
            modelos[CATEGORIAS[cat.tag]] = [{"nome": c.get("mName"), "tex": int(c.get("mTextureNum"))} for c in cat]
    cores = []
    for c in r.find("DefaultColours"):
        cores.append({k.lower(): [round(float(c.find(k).get(ch).strip()) * 255) for ch in "RGB"]
                      for k in ("BASE", "PRIMARY", "SECONDARY", "TEXT")})
    return modelos, cores


# ------------------------------------------------------------ a conta (inteira)
def _div255(a):
    t = a + 128
    return ((t >> 8) + t) >> 8


def tinta(px, cor):
    """RGB x cor (PIL point v*m//255)"""
    return [tuple(v * m // 255 for v, m in zip(p[:3], cor)) for p in px]


def juntar_parte(camadas, cores):
    """as 5 camadas (listas de pixels RGBA, mesmo tamanho) -> pixels RGB"""
    base = tinta(camadas["base"], cores["base"])
    out = base
    for k in ("primary", "secondary"):
        t = tinta(camadas[k], cores[k])
        out = [tuple(_div255(o * (255 - p[3]) + c * p[3]) for o, c in zip(op, cp))
               for op, cp, p in zip(out, t, camadas[k])]
    out = [tuple(_div255(o * (255 - p[3]) + c * p[3]) for o, c in zip(op, p[:3]))
           for op, p in zip(out, camadas["detail"])]
    out = [tuple(o * w // 255 for o, w in zip(op, p[:3])) for op, p in zip(out, camadas["wrinkle"])]
    return out


def alpha_sobre(dst, src, cor=None):
    """alpha_composite do PIL (fundo RGBA) de uma peça (cor: tinge o RGB)"""
    out = []
    for d, s in zip(dst, src):
        sr, sg, sb, sa = s
        if cor:
            sr, sg, sb = sr * cor[0] // 255, sg * cor[1] // 255, sb * cor[2] // 255
        if sa == 0:
            out.append(d)
            continue
        da = d[3]
        outa255 = sa * 255 + da * (255 - sa)
        c1 = sa * 255 * 255 * 128 // outa255
        c2 = 255 * 128 - c1
        rgb = []
        for sc, dc in ((sr, d[0]), (sg, d[1]), (sb, d[2])):
            t = sc * c1 + dc * c2 + (0x80 << 7)
            rgb.append((((t >> 8) + t) >> 8) >> 7)
        ta = outa255 + 0x80
        out.append((rgb[0], rgb[1], rgb[2], ((ta >> 8) + ta) >> 8))
    return out


# ------------------------------------------------------------ exportar
def exportar(unpacked, out, log=print):
    pasta = os.path.join(out, "camadas")
    os.makedirs(pasta, exist_ok=True)
    open(os.path.join(pasta, ".gdignore"), "w").close()     # o Godot lê cru, sem importar
    f = Fonte(unpacked, pasta)
    cx = caixas(f)
    modelos, cores_padrao = clothing(f)
    # camadas de cada conjunto já no tamanho da caixa
    for box, _esc, parte in PARTES:
        x, y, w, h = cx[box]
        for n in range(1, 13):
            for cam in CAMADAS:
                c = f.acha("/rider_%02d_%s_%s.bog" % (n, cam, parte))
                im = f.textura(c) if c else None
                if im is None:
                    # o jogo não tem (RIDER_02 sem DETAIL nas pernas): camada
                    # neutra (base e dobras brancas, o resto transparente)
                    neutra = (255, 255, 255, 255) if cam in ("base", "wrinkle") else (0, 0, 0, 0)
                    Image.new("RGBA", (w, h), neutra).save(os.path.join(pasta, "%s_%02d_%s.png" % (parte, n, cam)))
                    continue
                im.resize((w, h), Image.BILINEAR).save(os.path.join(pasta, "%s_%02d_%s.png" % (parte, n, cam)))
    # rostos (masculino e feminino) e cabelos, no tamanho da caixa
    rostos = {"m": [], "f": []}
    for sexo, pref in (("m", "characters/textures/face_male/"), ("f", "characters/textures/face_female/")):
        cams = sorted(c for c in f.arqs if c.startswith(pref))
        for k, c in enumerate(cams):
            nome = "face_%s_%d.png" % (sexo, k + 1)
            f.textura(c).resize(tuple(cx["FACE"][2:]), Image.BILINEAR).save(os.path.join(pasta, nome))
            rostos[sexo].append(os.path.basename(c))
    cabelos = []
    for k, c in enumerate(sorted(c for c in f.arqs if c.startswith("characters/textures/hair/"))):
        f.textura(c).resize(tuple(cx["HAIR"][2:]), Image.BILINEAR).save(os.path.join(pasta, "hair_%d.png" % (k + 1)))
        cabelos.append(os.path.basename(c).split(".")[0].split("_", 1)[-1])
    # nome e número em branco (o Godot tinge com a cor TEXT)
    textos = {}
    arq = gp.Arquivos(unpacked)
    comp = ET.fromstring(f.bloco("Setup/CharacterComposite/Textures/COMPOSITOR.xml").decode("latin-1"))
    for lay in comp.findall("LAYER"):
        t = lay.find("LAYER[@Type='Text']")
        if t is None:
            continue
        b = gp.ler_bed(f.bloco("Setup/CharacterComposite/Textures/RIDER.bed"))[lay.get("Box")]
        texto = NOME_PADRAO if lay.get("Box") == "PLAYER_NAME" else NUMERO_PADRAO
        r = gp.texto_peca(arq, b, t, texto, (TAM, TAM))
        if r:
            nome = lay.get("Box").lower() + ".png"
            r[0].save(os.path.join(pasta, nome))
            textos[lay.get("Box")] = {"png": nome, "x": r[1][0], "y": r[1][1], "texto": texto}
    # perfil padrão: o 2º piloto da RAM nos 2 saves (perfil novo, provável):
    # tudo no modelo 1 e as DefaultColours do 1; rosto 2, cabelo 5, sexo 1?
    padrao = {"roupa": 1, "capacete": 1, "oculos": 1, "luva": 1, "bota": 1,
              "rosto": 1, "cabelo": 1, "sexo": "m", "cores": cores_padrao[0]}
    info = {"tamanho": TAM, "caixas": cx, "partes": [[b, e, p] for b, e, p in PARTES], "modelos": modelos,
            "cores_padrao": cores_padrao, "rostos": rostos, "cabelos": cabelos, "textos": textos, "padrao": padrao}
    with open(os.path.join(pasta, "piloto.json"), "w", encoding="utf-8") as fp:
        json.dump(info, fp)
    img = montar(pasta, info, padrao)
    img.save(os.path.join(out, "piloto.png"))
    # referência do teste (tests/teste_piloto_pintura.gd): o piloto dos saves
    # do Matheus (roupa 11, capacete 9, óculos 12, luva 3, bota 10, cores do
    # Paint Shop: base 233,35,0, primária 255,100,0, secundária 255,200,69)
    teste = {"roupa": 11, "capacete": 9, "oculos": 12, "luva": 3, "bota": 10, "rosto": 6, "cabelo": 4,
             "sexo": "m", "cores": {"base": [233, 35, 0], "primary": [255, 100, 0],
                                    "secondary": [255, 200, 69], "text": [255, 255, 255]}}
    info["teste"] = teste
    with open(os.path.join(pasta, "piloto.json"), "w", encoding="utf-8") as fp:
        json.dump(info, fp)
    montar(pasta, info, teste).save(os.path.join(pasta, "teste_ref.png"))
    log(f"[+] piloto: {len(PARTES)} partes x 12 modelos, {len(rostos['m'])}+{len(rostos['f'])} rostos, "
        f"{len(cabelos)} cabelos -> {pasta}; piloto.png do perfil padrão")
    return img


def montar(pasta, info, esc):
    """textura do piloto (Image RGB) com estas escolhas; a conta do Godot"""
    tam = info["tamanho"]
    fundo = [(0, 0, 0, 255)] * (tam * tam)
    cores = {k: tuple(v) for k, v in esc["cores"].items()}
    ler = lambda n: list(Image.open(os.path.join(pasta, n)).convert("RGBA").get_flattened_data())

    def colar(px, x, y, w, h):
        for j in range(h):
            fundo[(y + j) * tam + x:(y + j) * tam + x + w] = [p + (255,) for p in px[j * w:(j + 1) * w]]

    for box, qual, parte in info["partes"]:
        x, y, w, h = info["caixas"][box]
        n = esc[qual]
        cam = {k: ler("%s_%02d_%s.png" % (parte, n, k)) for k in CAMADAS}
        colar(juntar_parte(cam, cores), x, y, w, h)
    for box, nome in (("FACE", "face_%s_%d.png" % (esc["sexo"], esc["rosto"])), ("HAIR", "hair_%d.png" % esc["cabelo"])):
        x, y, w, h = info["caixas"][box]
        colar([p[:3] for p in ler(nome)], x, y, w, h)
    for box in ("PLAYER_NAME", "PLAYER_NUMBER"):
        t = info["textos"].get(box)
        if not t:
            continue
        im = Image.open(os.path.join(pasta, t["png"])).convert("RGBA")
        w, h = im.size
        src = list(im.get_flattened_data())
        for j in range(h):
            yy = t["y"] + j
            if not 0 <= yy < tam:
                continue
            for i in range(w):
                xx = t["x"] + i
                if 0 <= xx < tam:
                    k = yy * tam + xx
                    fundo[k] = alpha_sobre([fundo[k]], [src[j * w + i]], cores["text"])[0]
    out = Image.new("RGB", (tam, tam))
    out.putdata([p[:3] for p in fundo])
    return out


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("unpacked")
    ap.add_argument("--out", default="assets/piloto")
    a = ap.parse_args()
    exportar(a.unpacked, a.out)


if __name__ == "__main__":
    main()
