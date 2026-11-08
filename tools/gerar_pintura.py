"""
gerar_pintura.py
=================
Monta a pintura (livery) de um veículo do jeito que o jogo faz em tempo
real e salva como pintura.png na pasta do modelo.

No modelo, a carroceria usa uma textura chamada "white" que não existe no
disco: o jogo gera ela juntando camadas descritas num XML (ex.: 15100 pro
Buggy_10):

    Buggy_10_Base       cor BASE preenchendo tudo (o alfa dela é o brilho)
    Buggy_10_Primary    máscara pintada com a cor PRIMARY
    Buggy_10_Secondary  máscara pintada com a cor SECONDARY
    Buggy_10_Detail     detalhes já coloridos (rebites, grelhas, logos)

Depois vêm as camadas de cima, na ordem do XML (desenho no exe: 0x2fedf8
Sprite, 0x2fffd8 Text, 0x2ffc40 Box):

    Box + Text          número do piloto (fonte HUD_Numbers) nos quadros
                        brancos; Fit="Vertical" = altura do texto = altura da
                        caixa x Scale, centrado, girado em volta do centro
    Decal               logo da BuggyLogos numa ou mais caixas; o logo de cada
                        um vem do DefaultDecals do vehicles.xml: a k-ésima
                        camada com DecalArea="Hood" é a HOOD<k>. KeepAspect
                        encaixa o logo dentro da caixa ANTES de girar

As caixas vêm do .bed (Chassis_Buggy_NN.bed): cada item é um polígono com
coordenadas inteiras = fração da textura x 100000 (o máximo é 100000 exato e
o dígito de 29 px da HUD_Digital dá 22656 = 29/128; conferido nos quadros do
número, nos logos e nos dígitos). O número padrão é o do perfil novo do
jogo, "00" (string ao lado do nome "PLAYER" no exe, 0x56b0a0; o print do
save state mostra 2 dígitos pretos). Rotação positiva = anti-horária na
imagem.

Uso:
    python gerar_pintura.py unpacked BUGGY_10 renegade
    python gerar_pintura.py unpacked BUGGY_04 sphinx
    python gerar_pintura.py unpacked BUGGY_04 sphinx --nome pintura_speedrun.png --base 225,225,230 --primary 215,85,20 --secondary 45,35,175

As cores padrão são as do XML (as de fábrica). --base/--primary/--secondary
trocam a cor, como na oficina de pintura do jogo. --numero troca o número,
--sem-decalques tira logos e número.
"""

import os
import re
import struct
import sys
import xml.etree.ElementTree as ET

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gob_tex2png import convert  # noqa: E402
from sfx_jogo import PROJ, ler_arquivos, ler_bloco  # noqa: E402

BED_ESCALA = 100000.0             # .bed: fração da textura x 100000
NUMERO = "00"                     # perfil novo do jogo


def chassis(veh):
    """DefaultConfig Chassis do veículo no data/vehicles.xml ("" se não achar)"""
    s = open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data",
                          "vehicles.xml"), encoding="latin-1").read()
    m = re.search(r'<Vehicle Name="%s".*?Chassis="([^"]+)"' % re.escape(veh.upper()), s, re.S)
    return m.group(1) if m else ""


def achar_xml(xml_dir, prefixo):
    alvo = f'Path="{prefixo}_Base"'
    for f in sorted(os.listdir(xml_dir)):
        if f.endswith(".xml"):
            s = open(os.path.join(xml_dir, f), encoding="latin-1").read()
            if alvo in s:
                return f, s
    return None, None


def cor(s, nome):
    m = re.search(r'Name="%s"\s*>\s*<Diffuse R="(\d+)" G="(\d+)" B="(\d+)"' % nome, s)
    return tuple(int(x) for x in m.groups()) if m else None


def achar_gob(gob_dir, nome):
    # o nome no disco nem sempre bate a caixa com o XML (Buggy_03_base)
    for f in sorted(os.listdir(gob_dir)):
        if f.lower().endswith(f"_{nome}.gob".lower()):
            return os.path.join(gob_dir, f)
    return None


def ler_bed(d):
    """.bed -> {nome: (x0, y0, x1, y1)} em fração da textura. Cabeçalho: u8 1,
    u8 1, nome.tga, u16 largura, altura, quantos; cada item: u16 pontos,
    pontos (s32 x, s32 y), nome, u16 0xffff. O jogo usa os cantos 0 e 2."""
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
            continue        # o Chassis_Truck_10.bed diz 25 itens e o 25º vem vazio
        (x0, y0), (x1, y1) = pts[0], pts[2]
        out[nome] = (x0 / BED_ESCALA, y0 / BED_ESCALA, x1 / BED_ESCALA, y1 / BED_ESCALA)
    return out


class Arquivos:
    """bed e textura pelo nome do arquivo no archive (data/arquivos.tsv)"""

    def __init__(self, src):
        self.src = src
        self.arqs = ler_arquivos()
        self.cache = {}

    def _caminho(self, nome):
        nome = nome.lower()
        for cam in self.arqs:
            if cam.rsplit("/", 1)[-1] == nome:
                return cam
        return None

    def bed(self, nome):
        if nome not in self.cache:
            cam = self._caminho(nome + ".bed")
            self.cache[nome] = ler_bed(ler_bloco(self.src, self.arqs, cam)) if cam else None
        return self.cache[nome]

    def textura(self, nome):
        k = nome + ".bog"
        if k not in self.cache:
            cam = self._caminho(k)
            im = None
            if cam:
                im, _ = convert(os.path.join(self.src, self.arqs[cam][0]))
            self.cache[k] = im.convert("RGBA") if im else None
        return self.cache[k]


def decalques_padrao(veh):
    """DefaultDecals do vehicles.xml: {"HOOD1": "ITP", ...}"""
    raiz = ET.parse(os.path.join(PROJ, "data", "vehicles.xml")).getroot()
    for v in raiz.iter("Vehicle"):
        if v.get("Name") == veh:
            d = v.find("DefaultDecals")
            return dict(d.attrib) if d is not None else {}
    return {}


def recorte(atlas, r):
    w, h = atlas.size
    return atlas.crop((round(r[0] * w), round(r[1] * h), round(r[2] * w), round(r[3] * h)))


def colar(img, peca, w, h, graus, centro):
    """peça redimensionada pra w x h px, girada (anti-horário) e colada com o
    centro em centro (px). Alfa pré-multiplicado pra borda não escurecer."""
    if w < 1 or h < 1:
        return
    pm = peca.convert("RGBa").resize((max(1, round(w)), max(1, round(h))), Image.LANCZOS)
    g = round(graus) % 360
    if g in (90, 180, 270):
        pm = pm.transpose({90: Image.ROTATE_90, 180: Image.ROTATE_180, 270: Image.ROTATE_270}[g])
    elif g:
        pm = pm.rotate(graus, Image.BICUBIC, expand=True)
    pm = pm.convert("RGBA")
    img.alpha_composite(pm, (round(centro[0] - pm.width / 2), round(centro[1] - pm.height / 2)))


def caixa_px(caixa, size):
    x0, y0, x1, y1 = caixa
    w, h = size
    return ((x0 + x1) / 2 * w, (y0 + y1) / 2 * h), abs(x1 - x0) * w, abs(y1 - y0) * h


def texto(img, arq, caixa, lay, numero):
    """camada Text (0x2fffd8): cada letra = o glifo do .bed da fonte (nome =
    código ASCII), proporção natural; Fit 1 "Vertical" = altura da caixa,
    2 "Horizontal" = largura, 3 "Both" = o menor; vezes Scale"""
    fonte = lay.get("Font", "HUD_Numbers")
    bed, atlas = arq.bed(fonte), arq.textura(fonte)
    if not bed or atlas is None:
        print(f"[!] fonte {fonte} não achada")
        return
    glifos = [recorte(atlas, bed[str(ord(c))]) for c in numero if str(ord(c)) in bed]
    if not glifos:
        return
    linha = Image.new("RGBA", (sum(g.width for g in glifos), max(g.height for g in glifos)))
    x = 0
    for g in glifos:
        linha.paste(g, (x, 0))
        x += g.width
    d = lay.find("Diffuse")
    cor = tuple(int(d.get(k, 255)) for k in ("R", "G", "B", "A")) if d is not None else (255,) * 4
    r, g, b, a = linha.split()
    tinta = [c.point(lambda v, m=m: v * m // 255) for c, m in zip((r, g, b, a), cor)]
    linha = Image.merge("RGBA", tinta)
    centro, cw, ch = caixa_px(caixa, img.size)
    fit = lay.get("Fit", "No")
    e = 1.0
    if fit == "Vertical":
        e = ch / linha.height
    elif fit == "Horizontal":
        e = cw / linha.width
    elif fit == "Both":
        e = min(ch / linha.height, cw / linha.width)
    e *= float(lay.get("Scale", 1.0))
    colar(img, linha, linha.width * e, linha.height * e, float(lay.get("Rotation", 0)), centro)


def sprite(img, logo, caixa, lay):
    """Sprite (0x2fedf8) com o logo: KeepAspect encaixa dentro da caixa sem
    girar (largura/altura da caixa x do logo), depois gira no centro"""
    centro, w, h = caixa_px(caixa, img.size)
    if lay.get("KeepAspect", "0") not in ("0", ""):
        a_caixa = (w / h) / float(lay.get("Aspect", 1.0))
        a_logo = logo.width / logo.height
        if a_caixa < a_logo:
            h *= a_caixa / a_logo
        else:
            w *= a_logo / a_caixa
    colar(img, logo, w, h, float(lay.get("Rotation", 0)), centro)


def decalques(img, s, src, veh, numero, log=print):
    """camadas Box/Text e Decal do XML, na ordem"""
    arq = Arquivos(src)
    padrao = {k.upper(): v for k, v in decalques_padrao(veh).items()}
    conta = {}
    for lay in ET.fromstring(s).findall("LAYER"):
        tipo = lay.get("Type")
        if tipo == "Box":
            t = lay.find("LAYER[@Type='Text']")
            bed = arq.bed(lay.get("BedFile"))
            if t is None or not bed or lay.get("Box") not in bed:
                continue
            texto(img, arq, bed[lay.get("Box")], t, numero)
        elif tipo == "Decal":
            area = lay.get("DecalArea", "")
            conta[area] = conta.get(area, 0) + 1
            chave = area.replace(" ", "").upper() + str(conta[area])
            nome = padrao.get(chave)
            if not nome:
                log(f"    {chave:12s} (vazio)")
                continue
            tex = lay.find("LAYER[@Type='Texture']")
            path = tex.get("Path") if tex is not None else "BuggyLogos"
            logos, atlas = arq.bed(path), arq.textura(path)
            # sem diferenciar maiúscula nem espaço: o vehicles.xml pede "HERBST 1" e
            # o .bed tem "Herbst  1" (2 espaços); "JB Marketing " tem espaço no fim
            igual = lambda a: " ".join(a.split()).upper()
            r = next((v for k, v in (logos or {}).items() if igual(k) == igual(nome)), None)
            if r is None or atlas is None:
                log(f"[!] {chave}: logo {nome!r} não está na {path}")
                continue
            logo = recorte(atlas, r)
            caixas = []
            for b in lay.findall("LAYER[@Type='Box']"):
                bed = arq.bed(b.get("BedFile"))
                sp = b.find("LAYER[@Type='Sprite']")
                if bed and b.get("Box") in bed and sp is not None:
                    sprite(img, logo, bed[b.get("Box")], sp)
                    caixas.append(b.get("Box"))
            log(f"    {chave:12s} {nome:24s} {' '.join(caixas)}")


# cores da última pintura montada (main grava em <nome>.json: as lasquinhas
# da batida usam a BASE, 0x3bbd60; RAM: Renegade 220,231,235, Storm 190,26,16)
ULTIMAS_CORES = {}


def montar(src, veh, trocar=None, numero=NUMERO, com_decalques=True, log=print, chassis_=None):
    """pintura do veículo (Image RGB) ou None; trocar = {"BASE": (r, g, b)...}"""
    prefixo = re.sub(r"^BUGGY", "Buggy", veh, flags=re.I)
    if prefixo == "Buggy_12":
        prefixo = "Lancia"          # o Storm usa as texturas Lancia_*
    elif veh.upper().startswith("TRUCK"):
        # a pintura é do chassis (TRUCK_04 usa o CHASSIS_Truck_11, TRUCK_12 o Dakar)
        # (o bônus do gerar_buggies passa a carroceria dele, CHASSIS_Truck_04)
        prefixo = (chassis_ or chassis(veh)).replace("CHASSIS_", "") or re.sub(r"^TRUCK", "Truck", veh, flags=re.I)
    xml_nome, s = achar_xml(os.path.join(src, "xml"), prefixo)
    if not s:
        log(f"[!] não achei o XML da pintura de {prefixo}")
        return None
    cores = {k: cor(s, k) for k in ("BASE", "PRIMARY", "SECONDARY")}
    cores.update(trocar or {})
    ULTIMAS_CORES.clear()
    ULTIMAS_CORES.update(cores)
    log(f"[+] {xml_nome}: base {cores['BASE']} primária {cores['PRIMARY']} secundária {cores['SECONDARY']}")

    camadas = {}
    for k in ("Base", "Primary", "Secondary", "Detail"):
        g = achar_gob(os.path.join(src, "gob"), f"{prefixo}_{k}")
        if not g:
            log(f"[!] faltou a textura {prefixo}_{k}")
            continue
        im, info = convert(g)
        if im is None:
            log(f"[!] {g}: {info}")
            continue
        camadas[k] = im.convert("RGBA")

    if "Base" not in camadas:
        return None
    w, h = camadas["Base"].size
    base = cores["BASE"] or (255, 255, 255)
    img = Image.new("RGB", (w, h), base)
    for k, c in (("Primary", cores["PRIMARY"]), ("Secondary", cores["SECONDARY"])):
        if k in camadas and c:
            cam = camadas[k].resize((w, h))
            img = Image.composite(Image.new("RGB", (w, h), c), img, cam.getchannel("A"))
    if "Detail" in camadas:
        cam = camadas["Detail"].resize((w, h))
        img = Image.composite(cam.convert("RGB"), img, cam.getchannel("A"))
    if com_decalques:
        img = img.convert("RGBA")
        decalques(img, s, src, veh, numero, log)
        img = img.convert("RGB")
    return img


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("veh")
    ap.add_argument("out")
    ap.add_argument("--nome", default="pintura.png")
    ap.add_argument("--base")
    ap.add_argument("--primary")
    ap.add_argument("--secondary")
    ap.add_argument("--numero", default=NUMERO)
    ap.add_argument("--sem-decalques", action="store_true")
    ap.add_argument("--chassis", help="carroceria (trucks), se não for a do vehicles.xml")
    a = ap.parse_args()
    trocar = {k.upper(): tuple(int(x) for x in getattr(a, k).split(","))
              for k in ("base", "primary", "secondary") if getattr(a, k)}
    img = montar(a.src, a.veh, trocar, a.numero, not a.sem_decalques, chassis_=a.chassis)
    if img is None:
        return
    os.makedirs(a.out, exist_ok=True)
    dst = os.path.join(a.out, a.nome)
    img.save(dst)
    print(f"[+] salvo {dst} ({img.width}x{img.height})")
    import json
    cj = os.path.splitext(dst)[0] + ".json"
    with open(cj, "w", encoding="utf-8") as f:
        json.dump({k.lower(): list(v) if v else None for k, v in ULTIMAS_CORES.items()}, f)
    print(f"[+] cores em {cj}")


if __name__ == "__main__":
    main()
