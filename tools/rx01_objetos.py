"""
rx01_objetos.py
===============
Objetos da pista RX01 (casas, celeiros, arquibancadas, arco de largada,
cones, placas, barreiras, cercas, fardos, pedras, cactos, árvores) a partir
dos arquivos do jogo. O RX01 não tem modelo no stream (o log do
Pingus/pingustream.header diz "Models Total = 0 bytes"): tudo vem do evento.

Arquivos (data/arquivos.tsv):
  Levels/RX_01/Event/Rallycross/Default/#def5772a   (other/12290)  instâncias
  Levels/RX_01/Event/Rallycross/RALLYCROSS.bin      (other/12289)  entidades
  Levels/RX_01/Models/Pingus/*.pingu  (+ .pfn = lista de texturas, o "raw"
                                       antes do bloco)
  Levels/RX_01/Models/Bantams/*.bantam (+ #hash logo DEPOIS = texturas)
  Levels/RX_01/Models/HsC/*.hsc        colisão (planos + esferas, "CSH")
  Levels/RX_01/Models/Textures/*.bog   texturas (gob 12324..12402)

Formato de chunks (os 2 arquivos do evento): 0x00030000, depois chunks
  F00DABCD, u32 tamanho (do fim do campo até o DEADDCBA, incluso), u32 tipo
  (hash), campos e chunks filhos, DEADDCBA. Campo = u32 chave (hash) + u32
  valor, ou chave + u32 n + n bytes de texto (preenchido até 4). Vetor =
  chunk filho com 3 campos x/y/z (chaves 484dc9b4, 3f4af922, a643a898).

Instâncias (#def5772a): raiz 4939a99a
  1c85cac0: pingus. Um chunk e9aba222 por modelo (01ee2ec7 = nome,
    7db6ffbc = quantas instâncias) e UM grupo 1b05a8d9 (7db6ffbc = total,
    07297d35 = registros de 160 bytes, na ordem dos modelos):
      +0x00 matriz 4x4 (linhas = eixos x, y, z do modelo no mundo, 4ª = posição)
      +0x40 centro (vec4), +0x68 1.0, +0x6c flags, +0x70 cor RGBA (luz)
  e0baf2b2: bantams. Um e9aba222 por modelo (21fdb9c8 = n grupos) com os
    grupos 1b05a8d9: 7db6ffbc = n, c32f9493 = 40 bytes de cabeçalho (do
    jogo em execução) + n registros de 96 bytes:
      +0x00 matriz 3x4 (linhas = eixos com escala, 4ª = posição + 1.0)
      +0x40 cor RGBA (luz), +0x50 flags
  24530fce: quadtree (índice espacial das mesmas instâncias, ignorado).
  Totais: 57 pingus e 651 bantams (o cabeçalho 1c85cac0 diz 651).

Mundo do jogo -> remake: (X, Y, Z) = (z - 1024, y, x) (terrain.gd, mão).

Uso:
    python tools/rx01_objetos.py <unpacked> [<texturas>] [--out assets/rx01]
        [--so-json]   só o data/rx01_objetos.json (posições), sem modelos
Sai:
    data/rx01_objetos.json   instâncias (modelo, matriz do jogo, cor) e entidades
    data/environment_rx01.xml  o Environment.xml da pista (luz, céu, névoa)
    assets/rx01/<modelo>.obj/.mtl + texturas (fora do git, como os carros)
    assets/rx01/ceu/<cúpula>.obj  as cúpulas do céu (SkyDome do Environment.xml)
"""

import argparse
import json
import os
import struct
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(AQUI)

MAG = 0xCDAB0DF0
FIM = 0xBADCADDE
K_NOME = 0x01EE2EC7
K_N = 0x7DB6FFBC
K_CLASSE = 0x489C80F9
CHAVES_TEXTO = {K_NOME, K_CLASSE, 0xDD734945, 0x9BE64DE6}
VX, VY, VZ = 0x484DC9B4, 0x3F4AF922, 0xA643A898
T_PINGUS, T_BANTAMS, T_MODELO, T_GRUPO = 0x1C85CAC0, 0xE0BAF2B2, 0xE9ABA222, 0x1B05A8D9

# blocos do archive (data/arquivos.tsv)
ARQ_INSTANCIAS = "Levels/RX_01/Event/Rallycross/Default/#def5772a"
ARQ_ENTIDADES = "Levels/RX_01/Event/Rallycross/RALLYCROSS.bin"


def ler_indice():
    out = {}
    for linha in open(os.path.join(PROJ, "data", "arquivos.tsv"), encoding="utf-8"):
        if linha.startswith("#"):
            continue
        c = linha.rstrip("\n").split("\t")
        if len(c) >= 5:
            out[c[0]] = (int(c[1]), int(c[2]), c[3], c[4])
    return out


def bloco(unpacked, ind, caminho):
    """bytes do arquivo do archive: 'other/NNNNN_bloco.bin' ou
    'raw/NNNNNr_x.bin+offset' (tamanho do índice)"""
    _, tam, _, onde = ind[caminho]
    if "+" in onde:
        arq, off = onde.rsplit("+", 1)
        return open(os.path.join(unpacked, arq), "rb").read()[int(off):int(off) + tam]
    return open(os.path.join(unpacked, onde), "rb").read()


# ------------------------------------------------------------------ chunks
def u32(d, o):
    return struct.unpack_from("<I", d, o)[0]


def filhos(d, o):
    """chunks filhos diretos do chunk em o"""
    fim = o + 8 + u32(d, o + 4)
    p = o + 12
    out = []
    while p < fim - 4:
        if u32(d, p) == MAG:
            out.append(p)
            p += 8 + u32(d, p + 4)
        else:
            p += 4
    return out


def campos(d, o):
    """campos simples de um chunk (sem descer nos filhos): chave -> valor
    (int, float pelo contexto de quem lê, ou texto)"""
    fim = o + 8 + u32(d, o + 4)
    p = o + 12
    out = {}
    vetores = {}
    while p < fim - 4:
        w = u32(d, p)
        if w == MAG:
            t = u32(d, p + 8)
            cs = campos(d, p)
            if set(cs) >= {VX, VY, VZ}:
                vetores.setdefault(t, []).append(tuple(struct.unpack("<f", struct.pack("<I", cs[k]))[0]
                                                       for k in (VX, VY, VZ)))
            p += 8 + u32(d, p + 4)
            continue
        if w == FIM:
            p += 4
            continue
        n = u32(d, p + 4)
        txt = d[p + 8:p + 8 + n] if 3 <= n < 200 else b""
        pad = d[p + 8 + n:p + 8 + ((n + 3) & ~3)]
        # texto: chave conhecida (o preenchimento até 4 às vezes tem lixo) ou
        # imprimível e preenchido com zeros (um contador seguido da próxima
        # chave não passa nisso)
        if txt and all(32 <= c < 127 for c in txt) and (w in CHAVES_TEXTO or (not any(pad) and (n % 4 or n >= 8))):
            out[w] = txt.decode()
            p += 8 + ((n + 3) & ~3)
        else:
            out[w] = n
            p += 8
    out["_vet"] = vetores
    return out


def f32(w):
    return struct.unpack("<f", struct.pack("<I", w))[0]


# ------------------------------------------------------------- instâncias
def instancias(d):
    raiz = d.find(struct.pack("<I", MAG))
    out = []
    for c in filhos(d, raiz):
        tipo = u32(d, c + 8)
        if tipo == T_PINGUS:
            modelos = []
            for e in filhos(d, c):
                if u32(d, e + 8) == T_MODELO:
                    cs = campos(d, e)
                    modelos.append((cs[K_NOME], cs[K_N]))
                elif u32(d, e + 8) == T_GRUPO:
                    total = u32(d, e + 16)
                    p = e + 24
                    regs = [struct.unpack_from("<40f", d, p + 160 * k) for k in range(total)]
            assert sum(n for _, n in modelos) == len(regs), "pingus: contagem"
            k = 0
            for nome, n in modelos:
                for _ in range(n):
                    r = regs[k]
                    k += 1
                    flags = struct.unpack("<I", struct.pack("<f", r[27]))[0]
                    out.append({"modelo": nome, "tipo": "pingu",
                                "linhas": [list(r[0:3]), list(r[4:7]), list(r[8:11])],
                                "pos": list(r[12:15]), "cor": list(r[28:32]),
                                "centro": list(r[16:19]), "flags": flags})
        elif tipo == T_BANTAMS:
            for e in filhos(d, c):
                if u32(d, e + 8) != T_MODELO:
                    continue
                nome = campos(d, e)[K_NOME]
                for g in filhos(d, e):
                    if u32(d, g + 8) != T_GRUPO:
                        continue
                    n = u32(d, g + 16)
                    p = g + 24 + 40
                    for k in range(n):
                        r = struct.unpack_from("<24f", d, p + 96 * k)
                        flags = struct.unpack_from("<I", d, p + 96 * k + 0x50)[0]
                        out.append({"modelo": nome, "tipo": "bantam",
                                    "linhas": [list(r[0:3]), list(r[4:7]), list(r[8:11])],
                                    "pos": list(r[12:15]), "cor": list(r[16:20]), "flags": flags})
    return out


def entidades(d):
    raiz = d.find(struct.pack("<I", MAG))
    out = []
    for c in filhos(d, raiz):
        cs = campos(d, c)
        cls = cs.get(K_CLASSE)
        if not isinstance(cls, str):
            continue
        ent = {"classe": cls, "tipo": "%08x" % u32(d, c + 8)}
        vet = cs["_vet"]
        if 0x3EF310BC in vet:
            ent["pos"] = list(vet[0x3EF310BC][0])
        if 0x74F784C3 in vet:
            ent["dir"] = list(vet[0x74F784C3][0])
        if 0x44C2FA64 in vet:
            ent["tamanho"] = list(vet[0x44C2FA64][0])
        extra = {}
        for k, v in cs.items():
            if k in ("_vet", K_CLASSE):
                continue
            extra["%08x" % k] = v
        ent["campos"] = extra
        out.append(ent)
    return out


# ------------------------------------------------------------------ bantam
def bantam(d):
    """tiras do .bantam ("TNAB" em 0x44): [(verts, uvs, cores, adc, slot)].
    Cabeçalho: +0x48 ?, raio, caixa mín (vec4), caixa máx (vec4); +0x70 n
    materiais e onde (registros de 0x40), +0x78 n desenhos e onde (16 bytes:
    slot da textura, ?, ?, início do pacote). Pacote = tag de DMA (qwc nos
    16 bits de baixo) + VIF: UNPACK V4-32 no endereço 1 com 2 qwords por
    vértice: (x, y, z, flag; 0x8000 = ADC, não fecha triângulo) e (u | R,
    v | G, B, A): o UV é o float sem o byte de baixo, a cor fica nele (0x80 =
    1.0). Sem normal: a luz vem assada na cor."""
    assert d[0x44:0x48] == b"TNAB", "não é bantam"
    n_des, off_des = u32(d, 0x78), u32(d, 0x7C)
    out = []
    for k in range(n_des):
        slot, _, _, vif = struct.unpack_from("<4I", d, off_des + 16 * k)
        qwc = u32(d, vif) & 0xFFFF
        fim = min(vif + 16 + 16 * qwc, len(d))
        p = vif + 8
        while p + 4 <= fim:
            w = u32(d, p)
            cmd, num, addr = (w >> 24) & 0x7F, (w >> 16) & 0xFF, w & 0x3FF
            p += 4
            if (cmd & 0x60) == 0x60:
                vn, vl = (cmd >> 2) & 3, cmd & 3
                bits = (32, 16, 8, 5)[vl]
                n = num or 256
                tam = ((vn + 1) * bits * n + 31) // 32 * 4
                if (cmd & 0x0F) == 0x0C and addr == 1:
                    verts, uvs, cores, adc = [], [], [], []
                    for i in range(n // 2):
                        x, y, z = struct.unpack_from("<3f", d, p + 32 * i)
                        fl = u32(d, p + 32 * i + 12)
                        a0, a1, a2, a3 = struct.unpack_from("<4I", d, p + 32 * i + 16)
                        verts.append((x, y, z))
                        adc.append(bool(fl & 0x8000))
                        uvs.append((f32(a0 & 0xFFFFFF00), f32(a1 & 0xFFFFFF00)))
                        cores.append(((a0 & 0xFF) / 128.0, (a1 & 0xFF) / 128.0, (a2 & 0xFF) / 128.0))
                    out.append((verts, uvs, cores, adc, slot))
                p += tam
            elif cmd in (0x30, 0x31):       # STROW / STCOL
                p += 16
            elif cmd == 0x20:               # STMASK
                p += 4
            elif cmd in (0x50, 0x51):       # DIRECT / DIRECTHL
                p += 16 * (w & 0xFFFF or 65536)
    return out


def materiais_bantam(d):
    """flag +0x38 de cada material do bantam (registros de 0x40 em +0x74, n em
    +0x70; o índice é o slot da textura). Vale 5 só nas folhagens (Alder,
    pinheiro, moita), que usam placa TRIANGULAR com UV de ~-0.3 a 1.4 em volta
    do quadrado da textura (borda transparente): textura PRESA na borda, senão
    os cantos do triângulo mostram pedaços repetidos (as "placas soltas" no
    céu). 0 no resto (fardo, guard-rail, pedras, placas repetem de verdade).
    Qual bit é o "prende" não foi conferido no exe (inferido pelo uso)."""
    n, o = u32(d, 0x70), u32(d, 0x74)
    return [u32(d, o + 0x40 * k + 0x38) for k in range(n)]


def texturas_bantam(d):
    """lista de texturas (#hash depois do bantam): u32 n + n nomes de 128 bytes"""
    n = u32(d, 0)
    return [d[4 + 128 * i:4 + 128 * (i + 1)].split(b"\0")[0].decode("latin-1") for i in range(n)]


def obj_bantam(tiras, nome, mats):
    """.obj das tiras do bantam: normal por face (sem normal no jogo), giro
    pela paridade da tira (o desenho é dos 2 lados)"""
    from pingu2obj import cor_obj
    ls = ["# %s - convertido de .bantam (ATV Offroad Fury 4, tools/rx01_objetos.py)" % nome,
          "mtllib %s.mtl" % nome, "o %s" % nome]
    faces = []
    base = 0
    nn = 0
    for verts, uvs, cores, adc, slot in tiras:
        for (x, y, z), c in zip(verts, cores):
            r, g, b = (cor_obj(k) for k in c)
            ls.append("v %.6f %.6f %.6f %.4f %.4f %.4f" % (x, y, z, r, g, b))
        for s, t in uvs:
            ls.append("vt %.6f %.6f" % (s, 1.0 - t))
        for i in range(2, len(verts)):
            if adc[i]:
                continue
            a, b, c = i - 2, i - 1, i
            if i % 2:
                a, b = b, a
            pa, pb, pc = verts[a], verts[b], verts[c]
            e1 = [pb[j] - pa[j] for j in range(3)]
            e2 = [pc[j] - pa[j] for j in range(3)]
            fn = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
            ln = (fn[0] ** 2 + fn[1] ** 2 + fn[2] ** 2) ** 0.5
            if ln < 1e-9:
                continue                    # triângulo degenerado (emenda da tira)
            ls.append("vn %.4f %.4f %.4f" % (fn[0] / ln, fn[1] / ln, fn[2] / ln))
            nn += 1
            faces.append((mats.get(slot, "sem_textura"), base + a + 1, base + b + 1, base + c + 1, nn))
        base += len(verts)
    atual = None
    for m, a, b, c, n in faces:
        if m != atual:
            ls.append("usemtl %s" % m)
            atual = m
        ls.append("f %d/%d/%d %d/%d/%d %d/%d/%d" % (a, a, n, c, c, n, b, b, n))
    return "\n".join(ls) + "\n", len(faces)


# ------------------------------------------------------------------ colisão
def kdt(d):
    """.kdt: u32 n, 12 bytes, n registros de 0x70 (triângulo = plano da face +
    3 planos das arestas, normal e d com n.p + d = 0, + caixa mín/máx com 3 cm
    de folga + flags), depois a árvore (não usada aqui). Vértices = encontro
    da face com cada par de arestas."""
    import numpy as np
    n = u32(d, 0)
    tris = []
    for k in range(n):
        o = 16 + 0x70 * k
        pl = np.array(struct.unpack_from("<16f", d, o)).reshape(4, 4)
        flag = u32(d, o + 0x60)
        vs = []
        for a, b in ((1, 2), (2, 3), (3, 1)):
            m = pl[[0, a, b], :3]
            if abs(np.linalg.det(m)) < 1e-9:
                break
            vs.append(np.linalg.solve(m, -pl[[0, a, b], 3]))
        if len(vs) == 3:
            tris.append([round(float(x), 4) for v in vs for x in v] + [flag])
    return tris


def hsc(d):
    """.hsc ("CSH\\0", o formato do casco dos carros, tools/casco.py)"""
    assert d[:4] == b"CSH\0"
    npl = u32(d, 12)
    p = 16
    planos = [list(struct.unpack_from("<4f", d, p + 16 * i)) for i in range(npl)]
    p += 16 * npl
    nesf = u32(d, p)
    p += 16
    esferas = [list(struct.unpack_from("<4f", d, p + 16 * i)) for i in range(nesf)]
    # cantos da caixa dos planos (n.p + d <= 0 dentro, como o casco.py): a
    # forma convexa dos objetos interativos no remake
    import itertools
    import numpy as np
    P = np.array(planos, dtype=float)
    vs = []
    for i, j, k in itertools.combinations(range(len(P)), 3):
        A = P[[i, j, k], :3]
        if abs(np.linalg.det(A)) < 1e-6:
            continue
        x = np.linalg.solve(A, -P[[i, j, k], 3])
        if np.all(P[:, :3] @ x + P[:, 3] <= 1e-4) and not any(np.linalg.norm(x - y) < 1e-4 for y in vs):
            vs.append(x)
    return {"planos": planos, "esferas": esferas, "vertices": [[float(c) for c in v] for v in vs]}


# ------------------------------------------------------------------ texturas
def textura(unpacked, ind, nome, pasta, feitas, pasta_jogo="Levels/RX_01/Models/Textures", mistura=False):
    """<pasta_jogo>/<nome>.bog -> pasta/<nome>.png (com alfa se o jogo tem
    furo: > 1% dos pixels com alfa < 20, como o alfa_texturas). mistura = a
    textura de um lote transparente (+0x00 = 1 no .pingu): sai sempre com o
    alfa do PS2 (0x80 = 1.0) levado pro PNG (x 2, cortado em 255)"""
    if mistura:
        nome_m = nome + "#mistura"
        if nome_m in feitas:
            return feitas[nome_m]
        feitas[nome_m] = None
        cam = "%s/%s.bog" % (pasta_jogo, nome)
        if cam not in ind or not ind[cam][3].startswith("gob/"):
            return None
        from gob_tex2png import convert
        import numpy as np
        from PIL import Image
        im, _ = convert(os.path.join(unpacked, ind[cam][3]))
        a = np.asarray(im.convert("RGBA")).copy()
        a[..., 3] = np.minimum(a[..., 3].astype(np.int32) * 2, 255).astype(np.uint8)
        arq = "%s.png" % nome.replace(" ", "_")
        Image.fromarray(a, "RGBA").save(os.path.join(pasta, arq))
        feitas[nome_m] = (arq, True)
        return feitas[nome_m]
    if nome in feitas:
        return feitas[nome]
    feitas[nome] = None
    cam = "%s/%s.bog" % (pasta_jogo, nome)
    if cam not in ind:
        return None
    onde = ind[cam][3]
    if not onde.startswith("gob/"):
        return None
    from gob_tex2png import convert
    import numpy as np
    try:
        im, _ = convert(os.path.join(unpacked, onde))
    except Exception as e:
        print("  textura %s: %s" % (nome, e))
        return None
    im = im.convert("RGBA")
    al = np.asarray(im)[..., 3]
    furo = float((al < 20).mean() * 100)
    arq = "%s.png" % nome.replace(" ", "_")
    (im if furo > 1.0 else im.convert("RGB")).save(os.path.join(pasta, arq))
    feitas[nome] = (arq, furo > 1.0)
    return feitas[nome]


def _extraido(ind, cam):
    return cam in ind and ind[cam][3] != ""


# listas que o unpacked não tem em nenhuma pista (arquivos de 132 e 13 bytes
# não extraídos): por eliminação são as 3 texturas do RX01 que sobram sem
# modelo (e o .pfn de 13 bytes = "water_puddle\n")
LISTAS_FALTANDO = {"GEN_HayBale.bantam": ["GEN_HayBale"], "GEN_Rock_Group.bantam": ["GEN_Rock"],
                   "WATER_puddle01.pingu": ["water_puddle"]}


def lista_bantam(unpacked, ind, nome):
    """texturas do bantam: o #hash logo DEPOIS dele no archive. O unpacked não
    tem alguns desses (GEN_HayBale e GEN_Rock_Group no RX01): aí vale o do
    mesmo bantam em outra pista (o arquivo é o mesmo, 680/2425 bytes)"""
    for cam in ["Levels/RX_01/Models/Bantams/" + nome] + sorted(
            k for k in ind if k.endswith("/Models/Bantams/" + nome) and not k.startswith("Levels/RX_01/")):
        pasta = cam.rsplit("/", 1)[0] + "/#"
        off = ind[cam][0]
        depois = sorted((v[0], k) for k, v in ind.items() if k.startswith(pasta) and v[0] > off)
        if depois and _extraido(ind, depois[0][1]):
            return texturas_bantam(bloco(unpacked, ind, depois[0][1]))
    return LISTAS_FALTANDO.get(nome, [])


def lista_pingu(unpacked, ind, base):
    """texturas do pingu: o .pfn (nomes por linha); se não foi extraído, o do
    mesmo modelo em outra pista"""
    for cam in ["Levels/RX_01/Models/Pingus/%s.pfn" % base] + sorted(
            k for k in ind if k.endswith("/Models/Pingus/%s.pfn" % base)):
        if _extraido(ind, cam):
            return [n.strip() for n in bloco(unpacked, ind, cam).decode("latin-1").split("\n") if n.strip()]
    return LISTAS_FALTANDO.get(base + ".pingu", [])


def mtl(mats, texs):
    """mats: {slot: nome do material}; texs: {nome do material: (png, furo)}"""
    ls = ["# materiais (tools/rx01_objetos.py)"]
    for slot, m in sorted(mats.items()):
        ls += ["newmtl %s" % m, "Kd 1 1 1"]
        t = texs.get(m)
        if t:
            ls.append("map_Kd tex/%s" % t[0])
        ls.append("")
    return "\n".join(ls)


def modelos(unpacked, ind, out, nomes):
    """converte cada modelo usado (pingu e bantam) e devolve o relatório"""
    sys.path.insert(0, AQUI)
    import hashlib
    import pingu2obj
    os.makedirs(os.path.join(out, "tex"), exist_ok=True)
    feitas = {}
    info = {}
    for nome in sorted(nomes):
        base, ext = nome.rsplit(".", 1)
        if ext == "pingu":
            cam = "Levels/RX_01/Models/Pingus/%s" % nome
            d = bloco(unpacked, ind, cam)
            strips = pingu2obj.parse(d)
            lotes = pingu2obj.read_batches(d)
            slots = pingu2obj.assign_batches(strips, lotes) if lotes else [-1] * len(strips)
            tnomes = lista_pingu(unpacked, ind, base)
            # lotes marcados transparentes (+0x00 = 1; na pista só a poça)
            transp = set()
            n_l = max(struct.unpack_from("<I", d, 0xBC)[0], struct.unpack_from("<I", d, 0xAC)[0])
            for i in range(n_l if 0 < n_l < 256 else 0):
                o = 0xD0 + i * 0x50
                if o + 0x50 <= len(d) and struct.unpack_from("<I", d, o)[0] == 1:
                    transp.add(struct.unpack_from("<i", d, o + 0x14)[0])
            mats, texs = {}, {}
            for s in sorted(set(slots)):
                if s is None or s < 0 or s >= len(tnomes):
                    mats[s] = "sem_textura"
                    continue
                mats[s] = "s%d_%s" % (s, pingu2obj.safe_name(tnomes[s]))
                t = textura(unpacked, ind, tnomes[s].strip(), os.path.join(out, "tex"), feitas,
                            mistura=s in transp)
                if t:
                    texs[mats[s]] = t
            txt_mtl = mtl(mats, texs)
            txt, nv, nf = pingu2obj.to_obj(strips, base, slots, base + ".mtl", mats)
            txt = "# mtl %s\n" % hashlib.md5(txt_mtl.encode()).hexdigest()[:12] + txt
            info[nome] = {"tipo": "pingu", "faces": nf, "texturas": [t[0] for t in texs.values()],
                          "alfa": any(t[1] for t in texs.values()),
                          "misturada": [m for s_, m in mats.items() if s_ in transp]}
            # camada (2ª textura do lote pelo 2º UV, +0x18 do registro): na
            # pista, as camisetas coloridas da US_Bleacher_Wood_02
            # (Crowd_ColourChange por cima da Crowd_02) -> <modelo>_camada.obj
            cams = pingu2obj.assign_batches(strips, lotes, "camada") if lotes else [-1] * len(strips)
            por_cam = {}
            for st_, c in zip(strips, cams):
                if c is not None and 0 <= c < len(tnomes):
                    por_cam.setdefault(c, []).append(st_)
            for c0, sts in sorted(por_cam.items()):
                t = textura(unpacked, ind, tnomes[c0].strip(), os.path.join(out, "tex"), feitas, mistura=True)
                if t:
                    ctxt, _, cnt = pingu2obj.to_obj(sts, "%s_camada%d" % (base, c0), uv2=True)
                    open(os.path.join(out, "%s_camada%d.obj" % (base, c0)), "w").write(
                        "# camada %s\n" % t[0] + ctxt)
                    # "tris": a mesma malha com o alfa do vértice (o .obj
                    # perde; o objetos_rx01.gd monta por ela)
                    info[nome].setdefault("camadas", []).append(
                        {"obj": "%s_camada%d.obj" % (base, c0), "textura": t[0],
                         "tris": pingu2obj.camada_tris(d, sts)})
        elif ext == "bantam":
            cam = "Levels/RX_01/Models/Bantams/%s" % nome
            d = bloco(unpacked, ind, cam)
            tiras = bantam(d)
            tnomes = lista_bantam(unpacked, ind, nome)
            mats, texs = {}, {}
            for s in sorted(set(t[4] for t in tiras)):
                if s >= len(tnomes):
                    mats[s] = "sem_textura"
                    continue
                mats[s] = "s%d_%s" % (s, pingu2obj.safe_name(tnomes[s]))
                t = textura(unpacked, ind, tnomes[s], os.path.join(out, "tex"), feitas)
                if t:
                    texs[mats[s]] = t
            txt_mtl = mtl(mats, texs)
            txt, nf = obj_bantam(tiras, base, mats)
            txt = "# mtl %s\n" % hashlib.md5(txt_mtl.encode()).hexdigest()[:12] + txt
            flags = materiais_bantam(d)
            info[nome] = {"tipo": "bantam", "faces": nf, "texturas": [t[0] for t in texs.values()],
                          "alfa": any(t[1] for t in texs.values()),
                          "textura_presa": [m for s_, m in mats.items() if 0 <= s_ < len(flags) and flags[s_]]}
        else:
            continue
        open(os.path.join(out, base + ".obj"), "w").write(txt)
        open(os.path.join(out, base + ".mtl"), "w").write(txt_mtl)
        print("  %-38s %5d faces  %s" % (nome, info[nome]["faces"], ", ".join(info[nome]["texturas"]) or "SEM TEXTURA"))
    return info


# KDt sem nome conhecido (o dicionário do archive, com as strings do exe, da
# RAM e dos XMLs, não acha): casados pela caixa dos triângulos x caixa do
# modelo (nov/2026). Erro somado das 6 faces da caixa: chalé 01 e 03 0.0,
# cerca de chevron 0.4, barreira da torcida 0.4, placa 03 0.3 (as 3 placas
# 03 têm o mesmo modelo de madeira), US_Barn_1 0.7; placa 02 com x e topo
# iguais (as pernas descem no chão); GEN_AM_Bleacher x/z iguais (a bandeira e
# as placas de cima não colidem); US_Bleacher 02 e 03 = cópias do KDt da
# US_Bleacher_Wood (que tem nome); chalé 02 = o único prédio que sobra (10
# triângulos, caixa simplificada); alto-falante = só o poste (topo e base
# iguais aos do modelo).
KDT_POR_CAIXA = {
    "93cb5b22": ["US_Building_Cabin01.pingu"], "e90b0842": ["US_Building_Cabin03.pingu"],
    "773b20ac": ["US_Barn_1.pingu"], "05ff4828": ["GEN_AM_Chevron_Fence.pingu"],
    "93a500ca": ["SAM_Crowd_BarrierTG.bantam"],
    "e52cf330": ["GEN_AD_Board_03_AXO_01.bantam", "GEN_AD_Board_03_Moose_01.bantam",
                 "GEN_AD_Board_03_Yoshimura.bantam"],
    "d84cda80": ["GEN_AD_Board_02_DUB_01.bantam"], "81456214": ["GEN_AM_Bleacher_Wood.pingu"],
    "d1878b1e": ["US_Bleacher_Wood_02.pingu"], "ece7a2ae": ["US_Bleacher_Wood_03.pingu"],
    "d46b21f2": ["US_Building_Cabin02.pingu"], "b93bc618": ["GEN_Loudspeaker.pingu"],
}


ARQ_AMBIENTE = "Levels/RX_01/Env/Default/Environment.xml"


def ceu(unpacked, ind, out):
    """céu do RX01 (Environment.xml, SkyDome): cada Outer/Inner é um .pingu de
    Levels/SkyDomes (o XML diz .clm; o loader 0x1d62b8 troca pela extensão
    do modelo) com a textura do .pfn ao lado. Sai assets/rx01/ceu/<nome>.obj
    e copia o Environment.xml pra data/environment_rx01.xml"""
    import re
    import hashlib
    import pingu2obj
    xml = bloco(unpacked, ind, ARQ_AMBIENTE)
    open(os.path.join(PROJ, "data", "environment_rx01.xml"), "wb").write(xml)
    pasta = os.path.join(out, "ceu")
    os.makedirs(os.path.join(pasta, "tex"), exist_ok=True)
    feitas = {}
    feitos = []
    for nome in re.findall(rb'Filename="Levels\\SkyDomes\\([^".]+)\.clm"', xml):
        nome = nome.decode()
        cam = "Levels/SkyDomes/%s.pingu" % nome
        if cam not in ind:
            print("  céu: %s não está no archive" % nome)
            continue
        d = bloco(unpacked, ind, cam)
        strips = pingu2obj.parse(d)
        lotes = pingu2obj.read_batches(d)
        slots = pingu2obj.assign_batches(strips, lotes) if lotes else [-1] * len(strips)
        pfn = "Levels/SkyDomes/%s.pfn" % nome
        tnomes = [n.strip() for n in bloco(unpacked, ind, pfn).decode("latin-1").split("\n") if n.strip()] \
            if _extraido(ind, pfn) else []
        mats, texs = {}, {}
        for s_ in sorted(set(slots)):
            if s_ is None or s_ < 0 or s_ >= len(tnomes):
                mats[s_] = "sem_textura"
                continue
            mats[s_] = "s%d_%s" % (s_, pingu2obj.safe_name(tnomes[s_]))
            t = textura(unpacked, ind, tnomes[s_], os.path.join(pasta, "tex"), feitas, "Levels/SkyDomes")
            if t:
                texs[mats[s_]] = t
        txt_mtl = mtl(mats, texs)
        txt, nv, nf = pingu2obj.to_obj(strips, nome, slots, nome + ".mtl", mats)
        txt = "# mtl %s\n" % hashlib.md5(txt_mtl.encode()).hexdigest()[:12] + txt
        open(os.path.join(pasta, nome + ".obj"), "w").write(txt)
        open(os.path.join(pasta, nome + ".mtl"), "w").write(txt_mtl)
        feitos.append(nome)
        print("  céu %-28s %4d faces  %s" % (nome, nf, ", ".join(t[0] for t in texs.values()) or "SEM TEXTURA"))
    return feitos


def colisao(unpacked, ind, nomes):
    """KDt (triângulos) e HsC (esferas) de cada modelo. O nome do KDt é
    #crc32(minúsculo('<modelo>.kdt')) ^ 0xFFFFFFFF (como o archive faz com
    pasta sem nome conhecido)"""
    import zlib
    out = {}
    kdts = {k.rsplit("#", 1)[1]: k for k in ind if k.startswith("Levels/RX_01/Models/KDt/#")}
    usados = set()
    for nome in sorted(nomes):
        base = nome.rsplit(".", 1)[0]
        h = "%08x" % (zlib.crc32(("%s.kdt" % base).lower().encode("latin-1")) ^ 0xFFFFFFFF)
        c = {}
        if h not in kdts:
            h = next((k for k, ms in KDT_POR_CAIXA.items() if nome in ms), h)
            if h in kdts:
                c["kdt_por_caixa"] = True
        if h in kdts:
            c["triangulos"] = kdt(bloco(unpacked, ind, kdts[h]))
            c["kdt"] = h
            usados.add(h)
        cam = "Levels/RX_01/Models/HsC/%s.hsc" % base
        if cam in ind:
            c.update(hsc(bloco(unpacked, ind, cam)))
        if c:
            out[nome] = c
    sobra = sorted(set(kdts) - usados)
    return out, sobra


def particula_pts(unpacked, ind, nome):
    """pontos de partícula do modelo (Levels/RX_01/Models/PtS/Bantams/<m>.pts:
    "POINT 1.00", u32 n em +16, n x [nome 32 bytes "particle <Efeito>",
    posição (3 floats), matriz 3x3 (x 0.01)]) + o efeito (Setup/Particles.xml
    -> data/particles.xml) e o sistema (Effects/WorldFX.xml ->
    data/world_fx.xml)"""
    import xml.etree.ElementTree as ET
    cam = "Levels/RX_01/Models/PtS/Bantams/%s.pts" % nome.rsplit(".", 1)[0]
    if cam not in ind:
        return {}
    d = bloco(unpacked, ind, cam)
    if not d.startswith(b"POINT"):
        return {}
    n = u32(d, 16)
    pontos = []
    efeito = ""
    for k in range(n):
        o = 20 + k * 80
        nm = d[o:o + 32].split(b"\0")[0].decode("latin1")
        if not nm.lower().startswith("particle "):
            continue
        efeito = nm[9:]
        pontos.append(list(struct.unpack_from("<3f", d, o + 32)))
    out = {"pontos": pontos, "efeito": efeito}
    pe = None
    for e in ET.parse(os.path.join(PROJ, "data", "particles.xml")).getroot():
        if e.get("Name") == efeito:
            pe = e
    if pe is None:
        return out
    di = pe.find("Direction")
    out["taxa"] = float(pe.get("ParticlesPerSec", 0))
    out["vel"] = [float(pe.get("VelocityVariationMin", 0)), float(pe.get("VelocityVariationMax", 0))]
    out["spray"] = float(pe.get("Spray", 0))
    out["dir"] = [float(di.get(k, 0)) for k in "XYZ"] if di is not None else [0, 1, 0]
    sis = pe.get("System")
    for ps in ET.parse(os.path.join(PROJ, "data", "world_fx.xml")).getroot():
        if ps.get("Name") != sis:
            continue
        s = {"max": int(ps.get("MaxParticles", 0))}
        for b in ps.findall("Behaviour"):
            g = b.find("Gravity")
            if g is not None:
                s["gravidade"] = [float(g.get(k, 0)) for k in "XYZ"]
        r = ps.find("Renderer/ParticleInfo")
        if r is not None:
            s["textura"] = r.get("Texture")
            s["caixa"] = r.get("Box")
        for i in ps.findall("Initialiser"):
            v = i.get("ValueName")
            if i.get("MinValue") is not None:
                s[v] = [float(i.get("MinValue")), float(i.get("MaxValue"))]
            elif v == "Colour":
                c = i.find("Value")
                s[v] = [float(c.get(k, 1)) for k in "RGBA"]
            elif i.get("Value") is not None:
                try:
                    s[v] = float(i.get("Value"))
                except ValueError:
                    s[v] = i.get("Value")
        out["sistema"] = s
    return out


def quebraveis(ind, nomes, unpacked=None):
    """objetos interativos da pista pelo Setup/InstanceDatabase.xml
    (data/instance_database.xml; ModelName sem diferenciar maiúscula):
    classe (cObjectFlimsyFence = cerca que quebra, cObjectTrackBlock = bloco
    solto), massa (t), atrito, dureza, ActiveResetTimeout, AngResistance,
    ShatterImpulse e as peças (Fragment: modelo + casco)"""
    import xml.etree.ElementTree as ET
    arq = os.path.join(PROJ, "data", "instance_database.xml")
    if not os.path.exists(arq):
        return {}
    raiz = ET.parse(arq).getroot()
    por_nome = {}
    for e in raiz:
        mn = e.get("ModelName")
        it = e.find("Interactive")
        if mn is None or it is None:
            continue
        por_nome[mn.lower()] = (e, it)
    bantams = {k.rsplit("/", 1)[1].rsplit(".", 1)[0].lower(): k.rsplit("/", 1)[1]
               for k in ind if k.startswith("Levels/RX_01/Models/Bantams/")}
    out = {}
    for nome in sorted(nomes):
        base = nome.rsplit(".", 1)[0].lower()
        if base not in por_nome:
            continue
        e, it = por_nome[base]
        f = lambda k, p=0.0: float(it.get(k, p))
        ang = it.find("AngResistance")
        if ang is None:
            ang = e.find("AngResistance")
        q = {"classe": it.get("ClassName") or it.get("Classname") or "cObjectInteractive",
             "massa": f("Mass"), "atrito": f("Friction"), "dureza": f("Hardness"),
             "reset": f("ActiveResetTimeout"), "som": e.get("CollisionSample", ""),
             "ang": [float(ang.get(k, 0)) for k in "XYZ"] if ang is not None else [0, 0, 0]}
        de = it.find("Destructible")
        if de is not None:
            q["quebra"] = float(de.get("ShatterImpulse", 0))
            q["pecas"] = []
            for fr in de.findall("Fragment"):
                m = bantams.get(fr.get("Model", "").lower())
                if m:
                    q["pecas"].append({"modelo": m, "casco": fr.get("CollSkin", "").rsplit(".", 1)[0]})
        pt = it.find("ParticleTrigger")
        if pt is not None:
            q["particula"] = {"tipo": pt.get("Type"), "impulso": float(pt.get("Impulse", 0)),
                              "espera": float(pt.get("Timeout", 0))}
            if unpacked:
                q["particula"].update(particula_pts(unpacked, ind, nome))
        out[nome] = q
    return out


ARQ_MULTIDAO = "Levels/RX_01/Models/Wahoos/RX01_Crowds.wahoo"
ARQ_MULTIDAO_NOMES = "Levels/RX_01/Models/Wahoos/#5d1b7d96"    # o .wfn (nomes)


def anims_uv():
    """Setup/UVRGBAAnim.xml (data/uv_anim.xml): AnimUV1 name -> [[duração,
    u, v], ...] + ping_pong"""
    import xml.etree.ElementTree as ET
    out = {}
    for a in ET.parse(os.path.join(PROJ, "data", "uv_anim.xml")).getroot():
        if a.tag != "AnimUV1":
            continue
        ks = []
        for k in a.iter("Key_Frame"):
            uv = k.find("Set_UV")
            if uv is None:
                continue
            ks.append([float(k.get("time", 0)), float(uv.get("u", 0)), float(uv.get("v", 0))])
        out[a.get("name")] = {"chaves": ks, "ping_pong": a.find("Ping_Pong") is not None}
    return out


def multidao(unpacked, ind):
    """RX01_Crowds.wahoo ("OHAW" 1.3; carregador 0x2821c8 / 0x2825b8):
    cabeçalho +0x84 n texturas (nomes no .wfn, 0x80 cada), +0x9c n objetos
    de 0x60 em +0xa0, +0x104 -> {ptr, n} materiais de 0x40 (+0 índice, +4 =
    textura do .wfn). Objeto: +0x00 esfera, +0x30 material, +0x48 animação
    {+0 ?, +4 índice no 2º nome do .wfn (AnimUV1 do UVRGBAAnim.xml), +8/+0xc
    -1}, +0x50 dados VIF. Dados: UNPACK V4-32 posição (mundo do jogo; w com
    0x8000 = vértice sem triângulo, tira de 4 por pessoa), V3-8 normal,
    V2-32 UV, V4-8 cor (0x80 = 1.0)"""
    if ARQ_MULTIDAO not in ind or ARQ_MULTIDAO_NOMES not in ind:
        return None
    d = bloco(unpacked, ind, ARQ_MULTIDAO)
    w = bloco(unpacked, ind, ARQ_MULTIDAO_NOMES)
    nt, _, na = struct.unpack_from("<3I", w, 0)
    texs = [w[12 + i * 0x80:12 + i * 0x80 + 0x80].split(b"\0")[0].decode() for i in range(nt)]
    o = 12 + nt * 0x80
    nomes_anim = [w[o + i * 0x20:o + i * 0x20 + 0x20].split(b"\0")[0].decode() for i in range(na)]
    nobj, pobj = struct.unpack_from("<2I", d, 0x9c)
    pmat = struct.unpack_from("<I", d, 0x104)[0]
    mp, mn = struct.unpack_from("<2I", d, pmat)
    mat_tex = [struct.unpack_from("<i", d, mp + k * 0x40 + 4)[0] for k in range(mn)]
    objs = []
    for k in range(nobj):
        b = pobj + k * 0x60
        mat, = struct.unpack_from("<I", d, b + 0x30)
        pa, pdados, pfim = struct.unpack_from("<3I", d, b + 0x48)[0], struct.unpack_from("<I", d, b + 0x50)[0], \
            struct.unpack_from("<I", d, b + 0x54)[0]
        anim = None
        if pa:
            ia = struct.unpack_from("<i", d, pa + 4)[0]
            if 0 <= ia < len(nomes_anim):
                anim = nomes_anim[ia]
        lotes = []
        p = pdados
        atual = None
        while p < pfim:
            c = struct.unpack_from("<I", d, p)[0]
            cmd = c >> 24
            if cmd & 0x60 != 0x60:
                p += 4
                continue
            num = (c >> 16) & 0xff
            vn, vl = (cmd >> 2) & 3, cmd & 3
            tam = ((32 >> vl) * (vn + 1) * num + 31) // 32 * 4
            q = p + 4
            if cmd == 0x6c and num > 1:
                atual = {"pos": [], "sem": [], "uv": [], "cor": []}
                lotes.append(atual)
                for i in range(num):
                    x, y, z, ww = struct.unpack_from("<3fI", d, q + i * 16)
                    atual["pos"].append([x, y, z])
                    atual["sem"].append(1 if ww & 0x8000 else 0)
            elif cmd == 0x64 and atual is not None:
                for i in range(num):
                    atual["uv"].append(list(struct.unpack_from("<2f", d, q + i * 8)))
            elif cmd == 0x6e and atual is not None:
                for i in range(num):
                    atual["cor"].append(list(struct.unpack_from("<4B", d, q + i * 4)))
            p = q + tam
        objs.append({"textura": texs[mat_tex[mat]] if 0 <= mat < len(mat_tex) else "", "anim": anim,
                     "lotes": [l for l in lotes if len(l["uv"]) == len(l["pos"])]})
    return {"fonte": ARQ_MULTIDAO, "texturas": texs, "objetos": objs, "anims": anims_uv()}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("unpacked")
    ap.add_argument("--out", default=os.path.join(PROJ, "assets", "rx01"))
    ap.add_argument("--so-json", action="store_true")
    a = ap.parse_args()
    ind = ler_indice()
    d = bloco(a.unpacked, ind, ARQ_INSTANCIAS)
    inst = instancias(d)
    ents = entidades(bloco(a.unpacked, ind, ARQ_ENTIDADES))
    print("instâncias: %d (pingus %d, bantams %d), entidades %d" % (
        len(inst), sum(i["tipo"] == "pingu" for i in inst), sum(i["tipo"] == "bantam" for i in inst), len(ents)))
    nomes = set(i["modelo"] for i in inst)
    qb = quebraveis(ind, nomes, a.unpacked)
    pecas = set(p["modelo"] for q in qb.values() for p in q.get("pecas", []))
    print("interativos: %s; peças: %s" % (", ".join("%s (%s)" % (k, v["classe"]) for k, v in qb.items()),
                                         ", ".join(sorted(pecas))))
    col, sobra = colisao(a.unpacked, ind, nomes | pecas)
    # casco das peças pelo nome do CollSkin (a 2ª peça da cerca SAM usa o da 1ª)
    for q in qb.values():
        for p in q.get("pecas", []):
            c = colisao(a.unpacked, ind, {p["casco"] + ".bantam"})[0]
            if c:
                col[p["casco"] + ".casco"] = list(c.values())[0]
    print("colisão: %d modelos com KDt, %d com HsC; KDt sem modelo: %d" % (
        sum("triangulos" in c for c in col.values()), sum("esferas" in c for c in col.values()), len(sobra)))
    md = multidao(a.unpacked, ind)
    if md:
        print("multidão: %d objetos, %d com animação, %d placas" % (len(md["objetos"]),
              sum(o["anim"] is not None for o in md["objetos"]),
              sum(sum(len(l["pos"]) for l in o["lotes"]) for o in md["objetos"]) // 4))
    json.dump({"fonte": [ARQ_INSTANCIAS, ARQ_ENTIDADES], "instancias": inst, "entidades": ents,
               "colisao": col, "interativos": qb, "multidao": md},
              open(os.path.join(PROJ, "data", "rx01_objetos.json"), "w"), separators=(",", ":"))
    if a.so_json:
        return
    os.makedirs(a.out, exist_ok=True)
    info = modelos(a.unpacked, ind, a.out, nomes | pecas)
    if md:
        # texturas da multidão: alfa do PS2 levado pro PNG (recorte das pessoas)
        feitas = {}
        for t in md["texturas"]:
            textura(a.unpacked, ind, t, os.path.join(a.out, "tex"), feitas, mistura=True)
    json.dump(info, open(os.path.join(a.out, "modelos.json"), "w"), indent=1)
    print("modelos em %s: %d" % (a.out, len(info)))
    print("céu: %s" % ", ".join(ceu(a.unpacked, ind, a.out)))
    print("detalhe do chão: %s" % detalhe_chao(a.unpacked, ind))


ARQ_DETALHE = "Levels/RX_01/Env/Default/Default/DETAIL.bog"


def detalhe_chao(unpacked, ind):
    """textura de detalhe do relevo (o renderer do chão 0x1eb758 carrega o
    "detail" da pasta Env da pista): 128 x 128, cor cinza fixa (131) e o
    desenho no ALFA (do PS2, 0x80 = 1.0; 12..190 no RX01). Sai o alfa cru
    num PNG cinza (valor = alfa do PS2 0..255) em assets/terrain/rx01_detalhe.png"""
    if ARQ_DETALHE not in ind or not ind[ARQ_DETALHE][3].startswith("gob/"):
        return "não achado"
    from gob_tex2png import convert
    im, _ = convert(os.path.join(unpacked, ind[ARQ_DETALHE][3]))
    alfa = im.convert("RGBA").getchannel("A")
    destino = os.path.join(PROJ, "assets", "terrain", "rx01_detalhe.png")
    alfa.save(destino)
    return "%s (%dx%d)" % (os.path.relpath(destino, PROJ), alfa.size[0], alfa.size[1])


if __name__ == "__main__":
    main()
