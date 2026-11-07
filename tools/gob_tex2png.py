"""
gob_tex2png.py
================
Converte os GOBs de TEXTURA do ATV Offroad Fury 4 em PNG.

Formato descoberto (GOB de textura):
    0x044  nome (ex: IG_TYRE_PROTOTYPE)
    0x0d8  largura, altura (uint32)
    0x0e8  bits por pixel (4 ou 8)
    0x0f8  PSM do GS (0x14 = 4bpp indexado, 0x13 = 8bpp indexado)
    ...    pacotes GIF com os registradores de upload (BITBLTBUF,
           TRXPOS, TRXREG, TRXDIR). O primeiro sobe a PALETA, que vem
           logo depois do GIFtag. O outro sobe a IMAGEM, que fica nos
           últimos bytes do arquivo.

    A imagem é enviada pra VRAM "disfarçada" de outro formato (4bpp vai
    como PSMCT16, 8bpp vai como PSMCT32) e o GS lê de volta como
    indexada. Por isso os pixels ficam embaralhados no arquivo, e o
    gs_swizzle.py refaz esse caminho.

Uso:
    python gob_tex2png.py unpacked\\gob\\19574_IG_TYRE_PROTOTYPE.gob
    python gob_tex2png.py unpacked\\gob --out texturas
    python gob_tex2png.py unpacked\\gob --out texturas --filter TYRE
"""

import argparse
import os
import struct
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gs_swizzle import GSMem  # noqa: E402

BPP_OF_PSM = {0x00: 32, 0x02: 16, 0x13: 8, 0x14: 4}


def u32(d, o):
    return struct.unpack_from("<I", d, o)[0]


def find_uploads(d):
    """acha os conjuntos BITBLTBUF/TRXPOS/TRXREG/TRXDIR (A+D, 16 bytes
    cada, registrador no byte 8) e o GIFtag IMAGE que vem depois"""
    ups = []
    for o in range(0, len(d) - 64, 16):
        if (d[o + 8] == 0x50 and d[o + 24] == 0x51 and d[o + 40] == 0x52
                and d[o + 56] == 0x53):
            bb = struct.unpack_from("<Q", d, o)[0]
            reg = struct.unpack_from("<Q", d, o + 32)[0]
            up = {
                "at": o,
                "dbp": (bb >> 32) & 0x3FFF,
                "dbw": (bb >> 48) & 0x3F,
                "dpsm": (bb >> 56) & 0x3F,
                "w": reg & 0xFFF,
                "h": (reg >> 32) & 0xFFF,
                "data": None,
            }
            # GIFtag IMAGE (FLG=2) logo depois do TRXDIR
            for t in range(o + 64, min(len(d) - 16, o + 64 + 0x60), 16):
                hi = d[t + 7]
                if (hi >> 2) & 3 == 2:
                    nloop = struct.unpack_from("<H", d, t)[0] & 0x7FFF
                    up["tag"] = t
                    up["nloop"] = nloop
                    break
            ups.append(up)
    return ups


def unswizzle_clut256(pal):
    out = list(pal)
    for i in range(256):
        if (i & 0x18) == 0x08:
            out[i], out[i + 8] = pal[i + 8], pal[i]
    return out


def rgba32(b):
    return (b[0], b[1], b[2], min(255, b[3] * 2))


def convert(path):
    d = open(path, "rb").read()
    if not d.startswith(b" GOB 2SP"):
        return None, "não é GOB"
    w, h = u32(d, 0xD8), u32(d, 0xDC)
    psm = u32(d, 0xF8)
    if psm not in BPP_OF_PSM or not (0 < w <= 2048 and 0 < h <= 2048):
        return None, "não parece textura"
    bpp = BPP_OF_PSM[psm]
    img_size = w * h * bpp // 8

    ups = find_uploads(d)
    if not ups:
        return None, "sem pacotes de upload"

    # paleta: upload pequeno em CT32 com dados logo depois do GIFtag
    pal = None
    if bpp in (4, 8):
        ncol = 16 if bpp == 4 else 256
        for up in ups:
            if up["dpsm"] == 0 and up["w"] * up["h"] == ncol and "tag" in up:
                s = up["tag"] + 16
                raw = d[s:s + ncol * 4]
                pal = [rgba32(raw[i * 4:i * 4 + 4]) for i in range(ncol)]
                if ncol == 256:
                    pal = unswizzle_clut256(pal)
                break
        if pal is None:
            return None, "paleta não encontrada"

    # imagem: upload cujo tamanho bate com a textura; dados no fim do arquivo
    bytes_pp = {0: 4, 1: 4, 2: 2, 0x13: 1, 0x14: 0.5}
    img_up = None
    for up in ups:
        if up["w"] * up["h"] * bytes_pp.get(up["dpsm"], 0) == img_size:
            img_up = up
            break
    if img_up is None:
        return None, "upload da imagem não encontrado"
    # o cabeçalho diz onde estão os pixels (0x158 = tamanho, 0x15c =
    # offset). Alguns GOBs crus têm outra coisa colada depois da imagem
    # (ex: banco de som), então não dá pra confiar no fim do arquivo.
    sz, off = u32(d, 0x158), u32(d, 0x15C)
    if sz == img_size and off + sz <= len(d):
        pix = d[off:off + sz]
    elif sz > img_size and off + img_size <= len(d) and off + sz <= len(d):
        # com mipmaps (ex: DETAIL.bog das pistas, 10880 = 128x128 + 64 + 32 +
        # 16 em 4 bits): o nível 0 vem primeiro. Antes caía no "fim do
        # arquivo" e misturava os níveis menores (saía ruído embaralhado)
        pix = d[off:off + img_size]
    else:
        pix = d[len(d) - img_size:]

    g = GSMem()
    g.write(img_up["dpsm"], 0, max(1, img_up["dbw"]), img_up["w"], img_up["h"], pix)
    tbw = max(1, w // 64)
    if bpp in (4, 8):
        idx = g.read_indices(psm, 0, tbw, w, h)
        data = [pal[i] for i in idx]
    else:
        raw = g.read32(0, tbw, w, h)
        data = [rgba32(raw[i:i + 4]) for i in range(0, len(raw), 4)]

    im = Image.new("RGBA", (w, h))
    im.putdata(data)
    name = d[0x44:0x44 + 64].split(b"\x00")[0].decode("latin-1")
    return im, f"{name} {w}x{h} {bpp}bpp"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", help="um .gob ou uma pasta de .gob")
    ap.add_argument("--out", default="texturas")
    ap.add_argument("--filter", default=None, help="só arquivos com esse texto no nome")
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--alpha", action="store_true",
                    help="mantém o canal alfa (no PS2 ele muitas vezes é "
                         "brilho/reflexo, não transparência, e deixa a "
                         "imagem com cara de apagada)")
    args = ap.parse_args()

    if os.path.isdir(args.src):
        files = sorted(os.path.join(args.src, f) for f in os.listdir(args.src)
                       if f.endswith(".gob"))
    else:
        files = [args.src]
    if args.filter:
        files = [f for f in files if args.filter.lower() in os.path.basename(f).lower()]
    if args.limit:
        files = files[:args.limit]

    os.makedirs(args.out, exist_ok=True)
    ok = skip = 0
    reasons = {}
    for n, f in enumerate(files):
        try:
            im, info = convert(f)
        except Exception as e:  # formato inesperado: conta e segue
            im, info = None, f"erro: {e}"
        if im is None:
            skip += 1
            reasons[info] = reasons.get(info, 0) + 1
            if len(files) == 1:
                print(f"[!] {f}: {info}")
            continue
        out = os.path.join(args.out, os.path.splitext(os.path.basename(f))[0] + ".png")
        (im if args.alpha else im.convert("RGB")).save(out)
        ok += 1
        if len(files) == 1 or n % 500 == 0:
            print(f"  [{n}/{len(files)}] {info} -> {out}")
    print(f"\n[+] {ok} texturas convertidas, {skip} arquivos pulados")
    for r, c in sorted(reasons.items(), key=lambda kv: -kv[1]):
        print(f"    {c:6d}  {r}")


if __name__ == "__main__":
    main()
