"""
sfx_jogo.py
===========
Extrai os sons do jogo que o carro usa (pneu, suspensão, pouso) pra
assets/sons (fora do git): um .wav por "tom" e o sons.json com o programa de
cada som. Quem toca é o som_jogo.gd, quem decide quando é o sfx_carro.gd.

Bancos (Audio/*.bnk, achados pelo data/arquivos.tsv; os únicos que o jogo
carrega numa corrida no RX01, conferido na RAM do SPU de 17 save states):
    Surface  = Audio/SURFACE.bnk   (rodas: Dirt, Tarmac, Screech, Gravel...)
    Coll_Big = Audio/Collide.bnk   (BigSuspension, SmallSuspension, LandingImpact...)
Nome e índice de cada som = Audio/SampleBanks.xml (posição da entrada = índice
do som no banco 989snd).

Formato do banco (989snd "SBlk" v3, little endian):
    0x08 u32 início do SBlk, 0x10/0x14 início/tamanho das amostras (PS-ADPCM)
    SBlk +0x16 u16 nº de sons, +0x1c tabela de sons (12 B: u8 vol, ..., u16 nº de
    grãos, u16 flags, s32 offset do 1º grão), +0x20 tabela de grãos (8 B: u32
    tipo << 24 | dado, u32 espera), +0x34 base dos dados dos grãos.
    Tom (0x18 B): u8 prio, s8 vol, u8 CN, u8 CF, s16 pan, s8 mapa baixo/alto,
    s8 PBLow/PBHigh (semitons do pitch bend, +8/+9), u16 ADSR1
    (+0xa), u16 ADSR2 (+0xc), u16 flags, u32 offset e u32 tamanho das
    amostras. ADSR = registradores do envelope do SPU (o som_jogo.gd roda o
    ataque e o release: parar um som é key-off, a voz desce pelo release).
    Taxa com tom 1.0 = 48000 * 2^((CN + CF/128 - 196) / 12) (registrador de
    pitch das vozes do SPU nos save states: 11025, 16000 e 22050 Hz).
Grãos (989snd, u32 = tipo << 24 | args, s32 espera), em sequência; a espera
vale ANTES do grão, em ticks de 240 Hz (BlockSoundHandler do 989snd, igual ao
reimplementado no jak-project; quem roda é o som_jogo.gd):
    1 toca um tom, 5 toca um som filho (dado -> +0 vol, +0xc índice),
    21/22 começo/fim de repetição, 25 RAND_PLAY (arg0 opções, arg1 grãos por
    opção), 26 RAND_DELAY (0..dado ticks a mais), 27 RAND_PB (arg0 = % da
    faixa de pitch bend), 31 SET_REGISTER_RAND (arg0 registrador, arg1..arg2
    faixa; tom com volume < 0 lê o registrador).

Uso:
    python tools/sfx_jogo.py <unpacked> [saida=assets/sons]
"""

import json
import os
import re
import struct
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BANCOS = {"Surface": "Audio/SURFACE.bnk", "Coll_Big": "Audio/Collide.bnk"}
COEF = [(0, 0), (60, 0), (115, -52), (98, -55), (122, -60)]


def u8(d, o): return d[o]
def u16(d, o): return struct.unpack_from("<H", d, o)[0]
def u32(d, o): return struct.unpack_from("<I", d, o)[0]
def s32(d, o): return struct.unpack_from("<i", d, o)[0]
def s8(b): return b - 256 if b > 127 else b


def ler_arquivos():
    """caminho em minúsculas -> fonte no unpacked (ex. raw/00005r_bloco.bin+0)"""
    out = {}
    for ln in open(os.path.join(PROJ, "data", "arquivos.tsv"), encoding="utf-8"):
        if ln.startswith("#"):
            continue
        cam, _, tam, _, fonte = ln.rstrip("\n").split("\t")
        out[cam.lower()] = (fonte, int(tam))
    return out


def ler_bloco(unpacked, arqs, caminho):
    fonte, tam = arqs[caminho.lower()]
    arq, _, off = fonte.partition("+")
    with open(os.path.join(unpacked, arq), "rb") as f:
        f.seek(int(off or 0))
        return f.read(tam if off else -1)


def adpcm(data):
    """PS-ADPCM -> (amostras, início do loop, fim, repete)"""
    out = []
    h1 = h2 = 0
    ini = fim = None
    repete = False
    for f in range(0, len(data) - 15, 16):
        hdr, flags = data[f], data[f + 1]
        shift, pred = hdr & 0x0F, min((hdr >> 4) & 0x0F, 4)
        if shift > 12:
            shift = 9
        c1, c2 = COEF[pred]
        if flags & 0x04 and ini is None:
            ini = len(out)
        for b in data[f + 2:f + 16]:
            for nib in (b & 0x0F, b >> 4):
                s = nib - 16 if nib >= 8 else nib
                v = ((s << 12) >> shift) + ((h1 * c1 + h2 * c2 + 32) >> 6)
                v = max(-32768, min(32767, v))
                out.append(v)
                h2, h1 = h1, v
        if flags & 0x01:
            fim = len(out)
            repete = bool(flags & 0x02)
            break
    return out, ini or 0, fim or len(out), repete


def gravar_wav(caminho, pcm, taxa, loop=None):
    corpo = struct.pack("<%dh" % len(pcm), *pcm)
    fmt = struct.pack("<HHIIHH", 1, 1, taxa, taxa * 2, 2, 16)
    blocos = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / taxa), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, loop[0], loop[1] - 1, 0, 0)
        blocos += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    blocos += b"data" + struct.pack("<I", len(corpo)) + corpo
    with open(caminho, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(blocos)) + b"WAVE" + blocos)


def nomes_banco(sample_banks, banco):
    m = re.search(r'<SampleBank bankName="%s"[^>]*>(.*?)</SampleBank>' % banco, sample_banks, re.S)
    return re.findall(r'<entry name="([^"]+)"', m.group(1)) if m else []


def extrair(d, nomes, pasta, rel):
    sb = u32(d, 0x08)
    doff, dsz = u32(d, 0x10), u32(d, 0x14)
    assert d[sb:sb + 4] == b"SBlk" and u32(d, sb + 4) == 3, "não é SBlk v3"
    amostras = d[doff:doff + dsz]
    ns = u16(d, sb + 0x16)
    t_sons, t_graos = sb + u32(d, sb + 0x1c), sb + u32(d, sb + 0x20)
    base = sb + u32(d, sb + 0x34)
    # nomes do próprio banco (flags & 0x100): servem pros sons filhos, que
    # não estão no SampleBanks.xml (ex. GRAVELEMENT1 do cascalho)
    internos = {}
    if u32(d, sb + 8) & 0x100:
        p = sb + u32(d, sb + 0x38)
        while p + 0x14 <= doff:
            nm = d[p + 1:p + 16].split(b"\0")[0]
            if len(nm) >= 3 and d[p + 1] >= 65 and all(48 <= c < 91 or c == 95 for c in nm) and u32(d, p + 16) < ns:
                internos[u32(d, p + 16)] = nm.decode()
                p += 0x14
            else:
                p += 1
    sons = {}
    for i in range(ns):
        nome = nomes[i] if i < len(nomes) else internos.get(i, "som%02d" % i)
        e = t_sons + i * 12
        vol, n, goff = u8(d, e), u16(d, e + 4), s32(d, e + 8)
        prog, tons = [], []
        for g in range(n):
            go = t_graos + goff + g * 8
            w, espera = u32(d, go), u32(d, go + 4)
            tipo, dado = w >> 24, w & 0xFFFFFF
            if tipo == 1:
                t = base + dado
                cn, cf, tvol = d[t + 2], d[t + 3], d[t + 1]
                adsr = [u16(d, t + 0xa), u16(d, t + 0xc)]
                pb = [s8(d[t + 8]), s8(d[t + 9])]
                off, tam = u32(d, t + 0x10), u32(d, t + 0x14)
                taxa = int(round(48000 * 2 ** ((cn + cf / 128.0 - 196) / 12.0)))
                pcm, ini, fim, repete = adpcm(amostras[off:off + tam])
                arq = "%02d_%s_%d.wav" % (i, nome, len(tons))
                gravar_wav(os.path.join(pasta, arq), pcm, taxa, (ini, fim) if repete else None)
                prog.append(["tom", len(tons), espera])
                tons.append({"arq": rel + "/" + arq, "vol": tvol, "taxa": taxa, "loop": repete,
                             "ini": ini, "fim": fim, "seg": round(len(pcm) / taxa, 3), "adsr": adsr, "pb": pb})
            elif tipo == 5:
                c = base + dado
                prog.append(["filho", u32(d, c + 0xc), d[c], espera])
            elif tipo == 21:
                prog.append(["repete", espera])
            elif tipo == 22:
                prog.append(["volta", espera])
            elif tipo == 25:
                prog.append(["sorteia", dado & 0xFF, espera, (dado >> 8) & 0xFF])
            elif tipo == 26:
                prog.append(["espera_sorteada", dado, espera])
            elif tipo == 27:
                prog.append(["desvio_tom", dado, espera])
            elif tipo == 31:
                prog.append(["registrador_sorteado", s8(dado & 0xFF), espera,
                             s8((dado >> 8) & 0xFF), s8((dado >> 16) & 0xFF)])
            else:
                prog.append(["ignora", tipo, espera])
        sons[nome] = {"indice": i, "vol": vol, "prog": prog, "tons": tons}
    # filhos pelo nome
    por_indice = {s["indice"]: k for k, s in sons.items()}
    for s in sons.values():
        for g in s["prog"]:
            if g[0] == "filho":
                g[1] = por_indice.get(g[1], "")
    return sons


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    unpacked = sys.argv[1]
    saida = sys.argv[2] if len(sys.argv) > 2 else os.path.join(PROJ, "assets", "sons")
    arqs = ler_arquivos()
    sample_banks = ler_bloco(unpacked, arqs, "Audio/SampleBanks.xml").decode("latin-1")
    tudo = {"versao": 2, "tick_hz": 240, "bancos": {}}
    for banco, caminho in BANCOS.items():
        pasta = os.path.join(saida, banco)
        os.makedirs(pasta, exist_ok=True)
        sons = extrair(ler_bloco(unpacked, arqs, caminho), nomes_banco(sample_banks, banco), pasta, banco)
        tudo["bancos"][banco] = sons
        print("%-9s %3d sons, %3d tons" % (banco, len(sons), sum(len(s["tons"]) for s in sons.values())))
    with open(os.path.join(saida, "sons.json"), "w", encoding="utf-8") as f:
        json.dump(tudo, f, indent=1)
    print("ok ->", saida)


if __name__ == "__main__":
    main()
