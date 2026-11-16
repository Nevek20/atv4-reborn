"""
piloto.py
==========
Extrai o piloto do jogo (malha com ossos, esqueleto e a animação da direção)
pra assets/piloto/piloto.json, que o piloto.gd monta no Godot.

Formatos (decifrados em out/2026, docs/engenharia_reversa.md "Piloto"):

  .skl  "cstfd" (Characters/Skeletons/InGame_Mid.skl, other/00519)
        0x0c nº de ossos (47); tabelas por offset em 0x10..0x2c:
        0x40 pai (int16), 0xa0 osso espelho (int16, direito <-> esquerdo),
        0x100 matriz inversa de repouso, 0xcc0 matriz de repouso (4x4,
        translação na 4ª linha), 0x1e60 posição local (x trocado!),
        nomes em 0x2204 (com zeros entre eles).

  .srd  "SKRDPS2 " (Characters/Models/InGame_MidSkel/MALE_HIGH.srd, 00514)
        0x10 nº de ossos, 0x14 offset das matrizes inversas de repouso,
        0x4c nome do material ("WHITE" = textura montada do piloto),
        0x48 offset da geometria: 1ª palavra = tamanho em qwords, depois
        pacotes VIF de 51 vértices:
          UNPACK V3-32  posição
          UNPACK V4-5   normal (x, y, z em 5 bits: (v - 15.5) / 15.5) e o
                        bit 15 = ADC (o vértice não fecha triângulo)
          UNPACK V2-16  UV (/ 4096)
          UNPACK V4-8   4 ossos (índice x 4, 255 = nenhum)
          UNPACK V4-8   4 pesos (/ 255)
          MSCNT
        O PS2 desenha os dois lados: o triângulo é virado pela normal do jogo.

  .bac  "BAC 2.07" (Characters/Animations/InGame_MidSkel/HighDetail/Truck/
        Controls/#23f42d6c = STEER_LEFT, other/00312; o do Buggy é igual)
        0x0c nº de ossos, 0x40 duração (1/6 s), 0x44 tipo (1), 0x48 bloco D.
        Tipo 1 (0x2340f8, amostrador 0x234750): D+0x04 posições (vec4),
        D+0x08 índice da posição por quadro e osso, D+0x10 rotações
        (quaternion x, y, z, w), D+0x14 índice da rotação, D+0x24 nº de
        quadros, D+0x28 tempos, D+0x2c/0x2d largura dos índices (8 = byte).
        osso b no quadro k = tabela[índice[k * nº_ossos + b]].

O jogo (0x190e50) toca o STEER_LEFT no tempo |s| x duração, com s a direção
suavizada do piloto (0x187060), e espelha quando s > 0 (direita).

Uso:
    python tools/piloto.py <unpacked> [--out assets/piloto]
    (a textura sai direto do gob do unpacked, pelo gob_tex2png)
"""

import argparse
import json
import os
import struct
import sys

SKL = "other/00519_bloco.bin"          # Characters/Skeletons/InGame_Mid.skl
SRD = "other/00514_bloco.bin"          # MALE_HIGH.srd
# piloto feminino (nov/2026): o mesmo esqueleto de 47 ossos; o rabo de cavalo
# é outro modelo (7 ossos próprios) no mesmo espaço do corpo, atrás do osso
# "head", que a PONY_TAIL_POSE (2 quadros iguais) dobra pra baixo
SRD_F = "other/00510_bloco.bin"        # FEMALE_HIGH.srd
SKL_RABO = "other/00520_bloco.bin"     # Characters/Skeletons/PonyTail.skl
SRD_RABO = "other/00517_bloco.bin"     # Characters/Models/PonyTail/PONYTAIL.srd
BAC_RABO = ("raw/00507r_bloco.bin", 0, 514)   # PonyTail/HighDetail/Generic/PONY_TAIL_POSE.bac
BAC = "other/00312_bloco.bin"          # Truck/Controls STEER_LEFT.bac
TEXTURA = "gob/00970_rider_fury.gob"   # Characters/Textures/Template/rider_fury.bog


# ------------------------------------------------------------ esqueleto .skl
def ler_skl(d):
    assert d[:5] == b"cstfd", "não é .skl"
    n = struct.unpack_from("<H", d, 0xc)[0]
    o_pai, o_esp = struct.unpack_from("<2I", d, 0x10)
    pais = list(struct.unpack_from("<%dh" % n, d, o_pai))
    espelho = list(struct.unpack_from("<%dh" % n, d, o_esp))
    o_nomes = struct.unpack_from("<I", d, 0x30)[0]
    nomes, p = [], o_nomes
    while len(nomes) < n:
        e = d.index(b"\0", p)
        nomes.append(d[p:e].decode())
        p = e + 1
        while p < len(d) and d[p] == 0:
            p += 1
    return nomes, pais, espelho


# ------------------------------------------------------------ VIF (PS2)
def _unpack_tam(cmd, num):
    vn, vl = (cmd >> 2) & 3, cmd & 3
    num = num or 256
    bits = 16 if vl == 3 else (vn + 1) * (32 >> vl)
    return ((num * bits + 31) // 32) * 4, num


def _pacotes(d, p, fim):
    """lotes de UNPACK até cada MSCNT: {endereço VU: (offset, nº)}"""
    lotes, cur = [], {}
    while p + 4 <= fim:
        imm, num, cmd = struct.unpack_from("<HBB", d, p)
        c = cmd & 0x7F
        p += 4
        if c >= 0x60:
            tam, n = _unpack_tam(c, num)
            cur[imm & 0x3FF] = (p, n)
            p += tam
        elif c == 0x17:                  # MSCNT: desenha o lote
            if cur:
                lotes.append(cur)
            cur = {}
        elif c == 0x20:
            p += 4
        elif c in (0x30, 0x31):
            p += 16
        elif c not in (0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x10, 0x11, 0x13, 0x14, 0x15):
            raise ValueError("VIFcode %02x em %x" % (c, p - 4))
    return lotes


# ------------------------------------------------------------ malha .srd
def ler_srd(d):
    assert d[:8] == b"SKRDPS2 ", "não é .srd"
    n_ossos, o_inv = struct.unpack_from("<2I", d, 0x10)
    inv = [list(struct.unpack_from("<16f", d, o_inv + 64 * b)) for b in range(n_ossos)]
    geo = struct.unpack_from("<I", d, 0x48)[0]
    tam = struct.unpack_from("<I", d, geo)[0] & 0xFFFFFF
    lotes = _pacotes(d, geo + 4, geo + tam * 16)
    pos, nrm, uv, oss, pes, tris = [], [], [], [], [], []
    for l in lotes:
        q, n = l[0]
        base = len(pos)
        qn, qu, qo, qp = l[1][0], l[2][0], l[3][0], l[4][0]
        adc = []
        for i in range(n):
            pos.append(struct.unpack_from("<3f", d, q + 12 * i))
            h = struct.unpack_from("<H", d, qn + 2 * i)[0]
            nrm.append(tuple(((h >> s) & 31) / 15.5 - 1.0 for s in (0, 5, 10)))
            adc.append(h >> 15)
            u, v = struct.unpack_from("<2h", d, qu + 4 * i)
            uv.append((u / 4096.0, v / 4096.0))
            ob = d[qo + 4 * i:qo + 4 * i + 4]
            pb = d[qp + 4 * i:qp + 4 * i + 4]
            oss.append(tuple(b // 4 if b != 255 else 0 for b in ob))
            pes.append(tuple(p / 255.0 if o != 255 else 0.0 for o, p in zip(ob, pb)))
        for i in range(2, n):
            if adc[i]:
                continue
            a, b, c = base + i - 2, base + i - 1, base + i
            # o PS2 desenha os dois lados: vira o triângulo pela normal do jogo
            P = [pos[k] for k in (a, b, c)]
            e1 = [P[1][k] - P[0][k] for k in range(3)]
            e2 = [P[2][k] - P[0][k] for k in range(3)]
            g = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
            nm = [nrm[a][k] + nrm[b][k] + nrm[c][k] for k in range(3)]
            if sum(g[k] * nm[k] for k in range(3)) < 0:
                a, b = b, a
            tris.append((a, b, c))
    return {"inv": inv, "pos": pos, "normal": nrm, "uv": uv, "ossos": oss, "pesos": pes, "tris": tris}


# ------------------------------------------------------------ animação .bac
def ler_bac(d):
    assert d[:8] == b"BAC 2.07", "não é .bac"
    n = struct.unpack_from("<I", d, 0xc)[0]
    dur, tipo, D = struct.unpack_from("<fII", d, 0x40)
    assert tipo == 1, "só o tipo 1 (0x2340f8) está decifrado"
    o_t, o_ti = struct.unpack_from("<2I", d, D + 4)
    o_r, o_ri = struct.unpack_from("<2I", d, D + 0x10)
    nk, o_tempos = struct.unpack_from("<2I", d, D + 0x24)
    assert d[D + 0x2c] == 8 and d[D + 0x2d] == 8, "índices de 16/32 bits não suportados"
    tempos = list(struct.unpack_from("<%df" % nk, d, D + o_tempos))
    quadros = []
    for k in range(nk):
        q = []
        for b in range(n):
            t = struct.unpack_from("<3f", d, D + o_t + 16 * d[D + o_ti + k * n + b])
            r = struct.unpack_from("<4f", d, D + o_r + 16 * d[D + o_ri + k * n + b])
            q.append([round(x, 6) for x in t + r])
        quadros.append(q)
    return {"dur": dur, "tempos": tempos, "quadros": quadros}


def rabo_de_cavalo(ler):
    """malha do rabo de cavalo na PONY_TAIL_POSE (vértices e normais no espaço
    do corpo, já dobrado), pra ir inteira no osso "head" do corpo. NOSSO: o
    rabo não balança (no jogo ele tem os 7 ossos dele; a pose é parada)"""
    import numpy as np
    nomes, pais, _esp = ler_skl(ler(SKL_RABO))
    m = ler_srd(ler(SRD_RABO))
    arq, ini, tam = BAC_RABO
    pose = ler_bac(ler(arq)[ini:ini + tam])["quadros"][0]

    def qmat(x, y, z, w):
        return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    g = [None] * len(nomes)
    for b in range(len(nomes)):
        lm = np.eye(4)
        lm[:3, :3] = qmat(*pose[b][3:])
        lm[:3, 3] = pose[b][:3]
        g[b] = lm if pais[b] < 0 else g[pais[b]] @ lm
    # pele: pose global x inversa de repouso (a do .srd é em linhas: transpõe)
    pele = [g[b] @ np.array(m["inv"][b], dtype=float).reshape(4, 4).T for b in range(len(nomes))]
    pos, nrm = [], []
    for v, n, ob, pw in zip(m["pos"], m["normal"], m["ossos"], m["pesos"]):
        acc = np.zeros(3)
        accn = np.zeros(3)
        for b, w in zip(ob, pw):
            if w > 0 and b < len(pele):
                acc += w * (pele[b] @ np.append(v, 1.0))[:3]
                accn += w * (pele[b][:3, :3] @ np.array(n))
        pos.append(acc.tolist())
        ln = np.linalg.norm(accn)
        nrm.append((accn / ln if ln > 0 else accn).tolist())
    return {"pos": pos, "normal": nrm, "uv": m["uv"], "tris": m["tris"]}


def modelo_json(nomes, pais, espelho, m, anim, fonte, rabo=None, osso_cabeca=-1):
    r = lambda v: [round(x, 6) for x in v]
    pos, normal, uv = list(m["pos"]), list(m["normal"]), list(m["uv"])
    ossos_v, pesos, tris = list(m["ossos"]), list(m["pesos"]), list(m["tris"])
    if rabo:
        base = len(pos)
        pos += rabo["pos"]
        normal += rabo["normal"]
        uv += rabo["uv"]
        ossos_v += [[osso_cabeca, 0, 0, 0]] * len(rabo["pos"])
        pesos += [[1.0, 0.0, 0.0, 0.0]] * len(rabo["pos"])
        tris += [[a + base, b + base, c + base] for a, b, c in rabo["tris"]]
    return {
        "fonte": fonte,
        "ossos": [{"nome": nomes[b], "pai": pais[b], "espelho": espelho[b], "inv": r(m["inv"][b])}
                  for b in range(len(nomes))],
        "pos": [x for v in pos for x in r(v)],
        "normal": [x for v in normal for x in r(v)],
        "uv": [x for v in uv for x in r(v)],
        "ossos_v": [x for v in ossos_v for x in v],
        "pesos": [x for v in pesos for x in r(v)],
        "tris": [x for t in tris for x in t],
        "steer_left": anim,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("unpacked")
    ap.add_argument("--out", default="assets/piloto")
    a = ap.parse_args()
    ler = lambda p: open(os.path.join(a.unpacked, p), "rb").read()
    nomes, pais, espelho = ler_skl(ler(SKL))
    m = ler_srd(ler(SRD))
    anim = ler_bac(ler(BAC))
    out = modelo_json(nomes, pais, espelho, m, anim,
                      "tools/piloto.py: %s, %s, %s; textura %s" % (SKL, SRD, BAC, TEXTURA))
    # piloto feminino: corpo + rabo de cavalo no osso da cabeça
    try:
        mf = ler_srd(ler(SRD_F))
        rabo = rabo_de_cavalo(ler)
        out_f = modelo_json(nomes, pais, espelho, mf, anim,
                            "tools/piloto.py: %s, %s (+ rabo %s, %s, pose %s), %s" % (SKL, SRD_F, SKL_RABO, SRD_RABO, BAC_RABO[0], BAC),
                            rabo, nomes.index("head"))
    except Exception as e:  # noqa: BLE001
        out_f = None
        print("[!] piloto feminino: %s" % e)
    os.makedirs(a.out, exist_ok=True)
    json.dump(out, open(os.path.join(a.out, "piloto.json"), "w"), separators=(",", ":"))
    if out_f:
        json.dump(out_f, open(os.path.join(a.out, "piloto_f.json"), "w"), separators=(",", ":"))
        print("[+] piloto feminino: %d vértices (%d do rabo de cavalo)" % (len(out_f["pos"]) // 3, len(out_f["pos"]) // 3 - len(mf["pos"])))
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from gob_tex2png import convert
    im, info = convert(os.path.join(a.unpacked, TEXTURA))
    if im is None:
        sys.exit("textura %s: %s" % (TEXTURA, info))
    im.convert("RGB").save(os.path.join(a.out, "piloto.png"))
    # textura montada como o jogo (Gear + Paint Shop do piloto; oficina): por
    # cima da rider_fury pronta, que fica só se faltar alguma camada
    try:
        import piloto_pintura
        piloto_pintura.exportar(a.unpacked, a.out)
    except Exception as e:  # noqa: BLE001
        print("[!] textura do piloto montada: %s (fica a rider_fury pronta)" % e)
    print("[+] %s: %d ossos, %d vértices, %d triângulos, STEER_LEFT %d quadros em %.3f s" % (
        a.out, len(nomes), len(m["pos"]), len(m["tris"]), len(anim["tempos"]), anim["dur"]))


if __name__ == "__main__":
    main()
