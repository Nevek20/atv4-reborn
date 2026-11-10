"""
extrair_material.py
===================
Lê o stream da pista (STREAMT/RX/RX01.000) e gera o mapa de MATERIAL do chão
(índice 0..15 do Materials.xml da pista) na mesma grade do
assets/pista/terreno/rx01_height.bin: 1025 x 1025 pontos, 1 m, linha = z, coluna = x,
pixel (gx, gz) = ponto do mundo do jogo (x = gx, z = 1024 + gz).

Uso (na pasta do projeto):
    python tools/extrair_material.py <RX01.000> assets/pista/terreno
        --materiais <unpacked>/xml/12280   Materials.xml do RX_01 (nomes e
                                           WheelJitter no JSON; pode ser só o
                                           prefixo, o unpacked põe sufixo)
        [--png previa.png]                 mapa em cinza (valor = material)
        [--ram [nome=]arquivo.ram ...]     confere com a RAM de save states
                                           parados (tools/ler_savestate.py --dump)
        [--ref tests/ref_ram_chao.json]    grava o contato e o material das
                                           rodas dessas RAMs (mundo do jogo)

Sai na pasta:
    rx01_material.bin  u8 1025x1025 (linha = z), índice do material
    rx01_material.json contagem por material e a regra de alinhamento
    rx01_height.bin    float32 1025x1025 (linha = z), altura do jogo
    rx01_height.json   tamanho e min/max
Os .bin ficam no layout do jogo (linha = z, coluna = x). terrain.gd lê com
FileAccess e transpõe pro remake (X = z - 1024, Z = x), por causa da mão
(o jogo é mão esquerda).

Alturas: a grade de 1 m com a diagonal do jogo, (i+1, j)-(i, j+1) (a mesma do
HeightMapShape3D do Godot), reproduz FUN_00299a60 exato, menos na última
célula de 1 m de um bloco de 8 m vizinho de patch de outro passo (até ~2 cm).
Bilinear erra até 10 cm.

Formato do RX01.000 (conferido no exe e na RAM dos 6 save states da largada;
alturas batem com o contato das rodas a 0.1 mm):
  - 128 tiles alinhados em 0x800: 64 "tilehi" (128 m, malha até 1 m) e 64
    "tilelo". A ordem e os tamanhos estão no stream.header (other/12286) e no
    OPT.xml (xml/12285), mas o script acha os tiles pelo cabeçalho mesmo.
  - Cabeçalho do tile (u32): tx, tz, 0x40 (malha), ?, C, 0x600, D (textura
    GOB 256x256), tamanho D, E, tamanho E.
  - Tile (tx, tz) ocupa x em [128 tx, 128 tx + 128), z em
    [1024 + 128 tz, ...) (struct em *0x7f48dc: x 0..1024, z 1024..2048).
  - Malha: [0x80, n_vert, base_dos_patches/16, 0], vértices de 16 bytes
    (escala, offset, escala_delta, u16 patch, u16 nó), nós de 12 bytes,
    patches de 0x70 bytes (9x9 alturas: 25 u16 nos pontos pares + 56 s8 de
    delta, tabela de índices em 0x550c00). FUN_0029bcb0 decodifica.
  - C: 16 x 16 blocos de 8 m -> (x8, z8, passo, ?, u16 vértice) = patch mais
    fino que cobre o bloco (FUN_001e9af0). Altura = FUN_00299a60: célula do
    patch, triângulo pela diagonal (i+1, j)-(i, j+1), y = offset + h*escala.
  - E: cabeçalho (65, 65, 2 m) + 65x65 entradas de 5 bytes, uma a cada 2 m
    (no tilelo: 33, 33, 4 m).
    Material = byte0 & 0xF da entrada (int(lx/2), int(lz/2))
    (FUN_001f0170 / FUN_001e9e48; "MAT: %d" do debug em FUN_00107d78 e
    FUN_001839b0 indexa a tabela de materiais de passo 0x60 com ele).
"""

import argparse
import glob
import json
import os
import re
import struct
import sys
import zlib

TAM = 1025
TILE = 128
Z0 = 1024.0          # z do mundo na linha 0 da grade

# índice (j*9 + i) -> u16 (pontos pares) ou s8 (+0x30) dentro do patch de 0x70
# bytes (tabela do exe em 0x550c00)
T_IDX = [0, 0, 1, 1, 2, 2, 3, 3, 4,
         4, 5, 6, 7, 8, 9, 10, 11, 52,
         5, 12, 6, 13, 7, 14, 8, 15, 9,
         16, 17, 18, 19, 20, 21, 22, 23, 53,
         10, 24, 11, 25, 12, 26, 13, 27, 14,
         28, 29, 30, 31, 32, 33, 34, 35, 54,
         15, 36, 16, 37, 17, 38, 18, 39, 19,
         40, 41, 42, 43, 44, 45, 46, 47, 55,
         20, 48, 21, 49, 22, 50, 23, 51, 52]


def patch_alturas(pt, dscale, morph=1.0):
    """9x9 alturas cruas (unidade do u16) de um patch, como FUN_0029bcb0.
    morph = 1 na consulta de altura da física (0x7f6d24 = 1.0 na RAM)."""
    u = struct.unpack_from("<53H", pt, 0)
    c = struct.unpack_from("<56b", pt, 0x30)
    H = [[0.0] * 9 for _ in range(9)]
    for j in range(9):
        for i in range(9):
            t = T_IDX[j * 9 + i]
            if j % 2 == 0:
                if i % 2 == 0:
                    v = u[t]
                else:
                    v = (u[T_IDX[j * 9 + i - 1]] + u[T_IDX[j * 9 + i + 1]]) * 0.5 + c[t] * dscale * morph
            else:
                if i % 2 == 0:
                    v = (u[T_IDX[(j - 1) * 9 + i]] + u[T_IDX[(j + 1) * 9 + i]]) * 0.5 + c[t] * dscale * morph
                else:
                    v = (u[T_IDX[(j - 1) * 9 + i + 1]] + u[T_IDX[(j + 1) * 9 + i - 1]]) * 0.5 + c[t] * dscale * morph
            H[j][i] = v
    return H


class Tile:
    def __init__(self, buf, off):
        h = struct.unpack_from("<10I", buf, off)
        self.h = h
        self.tx, self.tz = h[0], h[1]
        fim = off + h[8] + h[9]
        self.t = buf[off:fim]
        m = h[2]
        self.size, self.nv, po, _ = struct.unpack_from("<4I", self.t, m)
        self.verts = [struct.unpack_from("<3f2H", self.t, m + 16 + 16 * k) for k in range(self.nv)]
        self.pbase = m + po * 16
        self.C = [struct.unpack_from("<4BH", self.t, h[4] + 6 * k) for k in range(256)]
        self.ew, self.eh, self.epasso = struct.unpack_from("<3I", self.t, h[8])
        self.edados = h[8] + 12
        self._cache = {}

    def _patch(self, v):
        if v not in self._cache:
            esc, off, ds, pi, _ = self.verts[v]
            a = self.pbase + pi * 0x70
            self._cache[v] = (esc, off, patch_alturas(self.t[a:a + 0x70], ds))
        return self._cache[v]

    def altura(self, lx, lz):
        """altura no ponto local (0..128), FUN_001e9af0 + FUN_00299a60"""
        bx = min(int(lx * 0.125), 15)
        bz = min(int(lz * 0.125), 15)
        x8, z8, passo, _, v = self.C[bz * 16 + bx]
        esc, off, H = self._patch(v)
        ux = (lx - x8 * 8.0) / passo
        uz = (lz - z8 * 8.0) / passo
        i = min(max(int(ux), 0), 7)
        j = min(max(int(uz), 0), 7)
        fx, fz = ux - i, uz - j
        if fx + fz < 1.0:
            hh = H[j][i] + (H[j][i + 1] - H[j][i]) * fx + (H[j + 1][i] - H[j][i]) * fz
        else:
            hh = (H[j + 1][i + 1] + (H[j + 1][i] - H[j + 1][i + 1]) * (1 - fx)
                  + (H[j][i + 1] - H[j + 1][i + 1]) * (1 - fz))
        return off + hh * esc

    def entrada_e(self, lx, lz):
        """entrada de 5 bytes do mapa E (FUN_001f0170: int(l / passo), sem
        clamp; passo = 2 m no hi)"""
        i, j = int(lx / self.epasso), int(lz / self.epasso)
        a = self.edados + (j * self.ew + i) * 5
        return self.t[a:a + 5]


def achar_tiles(buf):
    """varre o stream em passos de 0x800 atrás de cabeçalhos de tile"""
    hi, lo = {}, {}
    for off in range(0, len(buf) - 0x40, 0x800):
        h = struct.unpack_from("<10I", buf, off)
        if h[2] != 0x40 or h[5] != 0x600 or h[0] > 63 or h[1] > 63:
            continue
        if not (0x40 < h[3] < h[4] and h[4] + h[5] == h[6] and h[6] + h[7] <= h[8]):
            continue
        if off + h[8] + h[9] > len(buf):
            continue
        w, hh, passo = struct.unpack_from("<3I", buf, off + h[8])
        # E: (65, 65, 2 m) no hi, (33, 33, 4 m) no lo
        if passo not in (2, 4) or w != hh or (w - 1) * passo != TILE or h[9] != 12 + w * hh * 5:
            continue
        if struct.unpack_from("<I", buf, off + 0x40)[0] != 0x80:
            continue
        (hi if w == 65 else lo)[(h[0], h[1])] = off
    return hi, lo


def gravar_png(caminho, w, h, linhas):
    """PNG 8 bits cinza sem depender do Pillow"""
    cru = b"".join(b"\0" + bytes(l) for l in linhas)

    def chunk(tipo, dados):
        c = struct.pack(">I", len(dados)) + tipo + dados
        return c + struct.pack(">I", zlib.crc32(tipo + dados) & 0xFFFFFFFF)

    with open(caminho, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(cru, 9)))
        f.write(chunk(b"IEND", b""))


def ler_materiais(caminho):
    if not os.path.exists(caminho):
        # o unpacked põe sufixo no nome (xml/12280_COMMON_1_DIRT_COMMON__.xml)
        achados = sorted(glob.glob(glob.escape(caminho) + "_*"))
        if not achados:
            sys.exit(f"não achei {caminho}")
        caminho = achados[0]
    xml = open(caminho, encoding="latin-1").read()
    mats = {}
    for m in re.finditer(r"<Material_(\d+) ([^>]*)>", xml):
        attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(2)))
        mats[int(m.group(1)) - 1] = attrs
    return mats


def conferir_ram(caminho, tiles):
    """rodas do jogador num save state parado: contato no mundo (W+0x130)
    -> célula da grade -> material e altura do stream x RAM. Devolve as rodas
    (mundo do jogo) pro --ref."""
    r = open(caminho, "rb").read()
    rodas = []

    def rd(a, f="<I"):
        return struct.unpack_from(f, r, a & 0x1FFFFFF)[0]

    veh = 0xC7EB00
    corpo = rd(veh + 0x9D4)
    print(f"{os.path.basename(caminho)}:")
    for i, nome in enumerate(("FL", "RL", "FR", "RR")):
        W = rd(corpo + 0x254 + 4 * i)
        x, y, z = struct.unpack_from("<3f", r, W + 0x130)
        gx, gz = int(x), int(z - Z0)
        tx, tz = min(gx // TILE, 7), min(gz // TILE, 7)
        t = tiles[(tx, tz)]
        lx, lz = x - tx * TILE, z - Z0 - tz * TILE
        mat = t.entrada_e(lx, lz)[0] & 0xF
        h = t.altura(lx, lz)
        print(f"  {nome}: mundo ({x:.2f}, {y:.3f}, {z:.2f}) grade ({gx}, {gz}) "
              f"material stream {mat} / RAM W+0x140 {rd(W + 0x140)} veh+0xa88 {rd(veh + 0xA88 + 4 * i)} "
              f"| altura stream {h:.4f} (dif {h - y:+.4f})")
        rodas.append({"roda": nome, "x": round(x, 5), "y": round(y, 5), "z": round(z, 5),
                      "mat": rd(W + 0x140),
                      "atrito": round(struct.unpack_from("<f", r, (corpo + 0x750 + 12 * i) & 0x1FFFFFF)[0], 5),
                      "amort": round(struct.unpack_from("<f", r, (corpo + 0x758 + 12 * i) & 0x1FFFFFF)[0], 5)})
    return rodas


def tabela_ram(caminho):
    """tabela de materiais do carro (veículo+0xd0, registros de 0x60, um por
    Material_N da pista): atrito do pneu (+0x00) e Damping (+0x08)"""
    r = open(caminho, "rb").read()
    veh = 0xC7EB00
    out = []
    for i in range(24):                 # o loader (0x3a9608) aloca 0x900 = 24 registros
        a, _, d = struct.unpack_from("<3f", r, (veh + 0xD0 + i * 0x60) & 0x1FFFFFF)
        out.append({"atrito": round(a, 5), "amort": round(d, 5)})
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("stream")
    ap.add_argument("pasta")
    ap.add_argument("--materiais")
    ap.add_argument("--png")
    ap.add_argument("--ram", nargs="*", default=[])
    ap.add_argument("--ref")
    a = ap.parse_args()

    buf = open(a.stream, "rb").read()
    hi, lo = achar_tiles(buf)
    if len(hi) != 64 or set(hi) != {(x, z) for x in range(8) for z in range(8)}:
        sys.exit(f"esperava 64 tiles hi 8x8, achei {len(hi)}")
    tiles = {k: Tile(buf, off) for k, off in hi.items()}
    print(f"{len(hi)} tiles hi, {len(lo)} tiles lo")
    os.makedirs(a.pasta, exist_ok=True)

    # material: pixel (gx, gz) = entrada E da célula de 2 m que contém o ponto
    mat = [[0] * TAM for _ in range(TAM)]
    for gz in range(TAM):
        tz = min(gz // TILE, 7)
        lz = gz - tz * TILE
        for gx in range(TAM):
            tx = min(gx // TILE, 7)
            mat[gz][gx] = tiles[(tx, tz)].entrada_e(gx - tx * TILE, lz)[0] & 0xF
    sai = os.path.join(a.pasta, "rx01_material.bin")
    with open(sai, "wb") as f:
        f.write(b"".join(bytes(l) for l in mat))
    print(f"gravei {sai} (u8 {TAM}x{TAM}, linha = z)")
    if a.png:
        gravar_png(a.png, TAM, TAM, mat)

    cont = {}
    for linha in mat:
        for v in linha:
            cont[v] = cont.get(v, 0) + 1
    # contagem por célula de 2 m de verdade (512 x 512 no mundo de 1024 m)
    cel = {}
    for gz in range(0, 1024, 2):
        for gx in range(0, 1024, 2):
            v = mat[gz][gx]
            cel[v] = cel.get(v, 0) + 1
    nomes = ler_materiais(a.materiais) if a.materiais else {}
    info = {
        "arquivo": "rx01_material.bin",
        "tamanho": TAM,
        "espacamento_m": 1.0,
        "origem_mundo_xz": [0.0, Z0],
        "orientacao": "byte (coluna gx, linha gz) = mundo do jogo (x = gx, z = 1024 + gz), igual ao "
                      "rx01_height.bin; no remake (espelho, terrain.gd) X = gz, Z = gx",
        "regra": "material no ponto (x, z) do jogo = byte (floor(x), floor(z - 1024)); "
                 "células de 2 m (byte0 & 0xF da entrada E int(lx/2), int(lz/2) do tile); "
                 "índice i = Material_(i+1) do Materials.xml da pista",
        "materiais": {},
    }
    total_cel = 512 * 512
    for k in sorted(set(cont) | set(cel)):
        e = {"pixels": cont.get(k, 0), "celulas_2m": cel.get(k, 0),
             "porcento": round(100.0 * cel.get(k, 0) / total_cel, 3)}
        if k in nomes:
            e["nome"] = nomes[k].get("Name")
            e["WheelJitter"] = float(nomes[k].get("WheelJitter", "nan"))
            e["SFX"] = nomes[k].get("SFX")
        info["materiais"][str(k)] = e
    js = os.path.join(a.pasta, "rx01_material.json")
    with open(js, "w", encoding="utf-8") as f:
        json.dump(info, f, indent=1, ensure_ascii=False)
    print(f"gravei {js}")
    for k, e in info["materiais"].items():
        print(f"  {k:>2} {e.get('nome', ''):<28} {e['porcento']:7.3f}%  ({e['celulas_2m']} células)")

    import array
    alt = array.array("f")
    for gz in range(TAM):
        tz = min(gz // TILE, 7)
        for gx in range(TAM):
            tx = min(gx // TILE, 7)
            alt.append(tiles[(tx, tz)].altura(gx - tx * TILE, gz - tz * TILE))
    if sys.byteorder != "little":
        alt.byteswap()
    sai = os.path.join(a.pasta, "rx01_height.bin")
    with open(sai, "wb") as f:
        alt.tofile(f)
    with open(os.path.join(a.pasta, "rx01_height.json"), "w") as f:
        json.dump({"size": TAM, "spacing": 1.0, "min": min(alt), "max": max(alt)}, f)
    print(f"gravei {sai} (min {min(alt):.3f}, max {max(alt):.3f})")

    ref = {}
    tabela = None
    for r in a.ram:
        nome, _, arq = r.rpartition("=")
        ref[nome or os.path.basename(arq)] = conferir_ram(arq, tiles)
        t = tabela_ram(arq)
        if tabela is not None and t != tabela:
            sys.exit(f"tabela de materiais diferente em {arq}")
        tabela = t
    if a.ref:
        with open(a.ref, "w", encoding="utf-8") as f:
            json.dump({"fonte": "contato das rodas (W+0x130), material (W+0x140), atrito e Damping "
                                "(corpo+0x750/0x758+12i) nos save states parados na largada, mundo do "
                                "jogo; tabela = materiais do carro (veículo+0xd0+i*0x60: atrito do "
                                "pneu e Damping), igual nos save states (tools/extrair_material.py --ref)",
                       "carros": ref, "tabela": tabela}, f, indent=1, ensure_ascii=False)
        print(f"gravei {a.ref}")


if __name__ == "__main__":
    main()
