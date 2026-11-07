"""
pingu2obj.py
==============
Converte modelos .pingu do ATV Offroad Fury 4 em .obj (abre no
Blender, no visualizador 3D do Windows, etc).

Formato descoberto: a malha vem em pacotes VIF (o formato que o PS2
usa pra mandar geometria pra unidade vetorial VU1). Cada pacote é uma
tira de triângulos (triangle strip):

    xx xx 01 60   UNPACK S-32   nº de vértices (+ flags)
    xx xx NN 6C   UNPACK V4-32  posição x, y, z + flag ADC no 4º campo
    xx xx NN 6A   UNPACK V3-8   normal (3 bytes com sinal)
    xx xx NN 6C   UNPACK V4-32  UV (s, t) + 2º conjunto de UV (s2, t2)
      ou NN 64    UNPACK V2-32  UV (s, t)
    xx xx NN 6E   UNPACK V4-8   cor RGBA
    00 00 00 17   MSCNT         manda a VU1 desenhar

    O 4º campo da posição tem o bit ADC (0x8000): quando ligado, aquele
    vértice NÃO fecha triângulo (é assim que a tira "recomeça").

Camada: o lote de material pode ter uma 2ª textura (registro +0x18, com
+0x08 = 2) desenhada por cima pelo 2º UV. A pintura das carrocerias tem a
"dirt" (a sujeira: o jogo troca pela textura da pista) e as rodas a
UNI_TyreOverlay (lama do pneu). Essas tiras saem também num <nome>_camada.obj
com o 2º UV (car.gd / sujeira.gd).

Cor do vértice: 0x80 = 1.0 e passa disso (até 255 = 2.0; alfa sempre 0x80).
O PS2 multiplica a textura por ela: é a sombra "assada" no modelo e a cor
das lanternas (vidro claro na textura x vértice vermelho 167, 24, 24). O .obj
só guarda de 0 a 1, então sai codificada: sRGB de (linear(c/128) / COR_K),
com COR_K = linear(255/128). O car.gd desfaz (o Godot passa a cor de sRGB pra
linear e o material multiplica por COR_K).

Uso:
    python pingu2obj.py unpacked\\other\\19998_bloco.bin
    python pingu2obj.py unpacked\\other --out modelos
    python pingu2obj.py unpacked\\other --out modelos --min-tris 50
    python pingu2obj.py unpacked\\other\\21711_bloco.bin --out renegade --copy-tex
"""

import argparse
import hashlib
import os
import struct


def _lin(c):
    """sRGB -> linear (a conta do Godot, sem cortar acima de 1)"""
    return c / 12.92 if c < 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _srgb(x):
    return x * 12.92 if x < 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055


COR_K = _lin(255 / 128.0)     # o vértice mais claro possível (2.0)
COR_VERSAO = 2                # pecas.json "cor_vertice" (sem = cortada em 1.0)


def cor_obj(c):
    """cor do jogo (c/128, até 2.0) -> 0..1 do .obj"""
    return _srgb(_lin(c) / COR_K)


def sub_strip(st, a, b):
    """pedaço [a, b) de uma tira; os 2 primeiros vértices viram recomeço"""
    verts, normals, uvs, colors, adc, off = st
    if b - a < 3:
        return None
    adc2 = list(adc[a:b])
    adc2[0] = adc2[1] = True
    # a paridade da ordem dos triângulos depende da posição na tira original
    if a % 2:
        # mantém o sentido de giro trocando os dois primeiros vértices
        v = list(verts[a:b]); n = list(normals[a:b]); u = list(uvs[a:b]); c = list(colors[a:b])
        v.insert(0, v[0]); n.insert(0, n[0]); u.insert(0, u[0]); c.insert(0, c[0]); adc2.insert(0, True)
        return (v, n, u, c, adc2, off)
    return (verts[a:b], normals[a:b], uvs[a:b], colors[a:b], adc2, off)


def cmd_at(d, p):
    """(num, cmd) do VIFcode em p"""
    return d[p + 2], d[p + 3]


def v3_8_size(n):
    return ((3 * n + 3) // 4) * 4


def parse(d):
    """acha todas as tiras. Devolve lista de (verts, normals, uvs, colors, adc)"""
    strips = []
    p = 0
    n = len(d)
    while True:
        p = d.find(b"\x6c", p)
        if p == -1:
            break
        s = p - 3
        p += 1
        if s < 0 or s % 4:
            continue
        num = d[s + 2]
        if not 1 <= num <= 255:
            continue
        pos_end = s + 4 + 16 * num
        if pos_end + 4 > n:
            continue
        nnum, ncmd = cmd_at(d, pos_end)
        if ncmd != 0x6A or nnum != num:
            continue

        verts, adc = [], []
        for i in range(num):
            x, y, z = struct.unpack_from("<3f", d, s + 4 + 16 * i)
            flag = struct.unpack_from("<I", d, s + 4 + 16 * i + 12)[0]
            verts.append((x, y, z))
            adc.append(bool(flag & 0x8000))

        q = pos_end + 4
        normals = []
        for i in range(num):
            nx, ny, nz = struct.unpack_from("<3b", d, q + 3 * i)
            normals.append((nx / 127.0, ny / 127.0, nz / 127.0))
        q += v3_8_size(num)

        uvs = [(0.0, 0.0)] * num
        colors = [(1.0, 1.0, 1.0)] * num
        # os comandos seguintes (UV / cor), se existirem
        for _ in range(3):
            if q + 4 > n:
                break
            cnum, ccmd = cmd_at(d, q)
            if cnum != num:
                break
            if ccmd == 0x6C:        # V4-32: s, t, s2, t2
                uvs = [struct.unpack_from("<4f", d, q + 4 + 16 * i) for i in range(num)]
                q += 4 + 16 * num
            elif ccmd == 0x64:      # V2-32: s, t
                uvs = [struct.unpack_from("<2f", d, q + 4 + 8 * i) for i in range(num)]
                q += 4 + 8 * num
            elif ccmd == 0x6E:      # V4-8: RGBA (0x80 = 1.0, até 2.0)
                colors = [tuple(c / 128.0 for c in d[q + 4 + 4 * i:q + 7 + 4 * i])
                          for i in range(num)]
                q += 4 + 4 * num
            else:
                break

        strips.append((verts, normals, uvs, colors, adc, s))
        p = q
    return strips


def read_batches(d):
    """lotes de material do cabeçalho do pingu: registros de 0x50 bytes
    a partir de 0xd0. Campo +0x14 = slot de textura (-1 = sem textura),
    +0x28 = onde o lote começa, +0x48 = quantas tiras ele tem, +0x08 = quantas
    texturas e +0x18 = slot da 2ª (camada, pelo 2º UV)."""
    if d[0x10:0x18] != b"gniPi2SP":
        return []
    # 0xBC conta só parte dos lotes; o total fica em 0xAC (no Sphinx, 21531:
    # 0xBC = 13 e 0xAC = 15; os 2 últimos são os bancos e o motor). Vale o maior
    count = max(struct.unpack_from("<I", d, 0xBC)[0], struct.unpack_from("<I", d, 0xAC)[0])
    if not 0 < count < 256:
        return []
    out = []
    for i in range(count):
        o = 0xD0 + i * 0x50
        if o + 0x50 > len(d):
            break
        w = struct.unpack_from("<20I", d, o)
        slot = w[5] if w[5] != 0xFFFFFFFF else -1
        camada = w[6] if w[2] >= 2 and w[6] != 0xFFFFFFFF else -1
        out.append({"slot": slot, "camada": camada, "start": w[10], "strips": w[18]})
    out.sort(key=lambda b: b["start"])
    return out


def assign_batches(strips, batches, campo="slot"):
    """as tiras aparecem no arquivo na mesma ordem dos lotes, então é só
    distribuir na sequência usando a contagem de cada lote.

    Quando a contagem não bate (tira longa que o jogo manda em mais de um
    pacote VIF vira 2+ tiras aqui; acontece no Sphinx, 21531), cada tira vai
    pro lote cujo início (+0x28) é o último antes dela no arquivo. No
    Renegade os dois jeitos dão o mesmo resultado (2 de 558 tiras mudam)."""
    if not batches:
        return [None] * len(strips)
    if sum(b["strips"] for b in batches) == len(strips):
        out = []
        for b in batches:
            out += [b[campo]] * b["strips"]
        return out
    starts = [b["start"] for b in batches]
    out = []
    for st in strips:
        off = st[5]
        i = 0
        while i + 1 < len(starts) and starts[i + 1] <= off:
            i += 1
        out.append(batches[i][campo])
    return out


def texture_names(model_path):
    """lista de texturas do modelo: o arquivo 'raw' logo antes dele
    (índice - 1) é uma lista de nomes separados por quebra de linha"""
    base = os.path.basename(model_path)
    try:
        idx = int(base.split("_", 1)[0])
    except ValueError:
        return idx_none()
    raw_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(model_path))), "raw")
    if not os.path.isdir(raw_dir):
        return idx, []
    # peças pequenas (amortecedores) às vezes não têm lista própria e usam a
    # da peça anterior: procura até 10 blocos pra trás
    files = os.listdir(raw_dir)
    for back in range(1, 11):
        prefix = f"{idx - back:05d}r"
        for f in files:
            if f.startswith(prefix):
                data = open(os.path.join(raw_dir, f), "rb").read()
                names = [n.strip().decode("latin-1") for n in data.split(b"\n")]
                names = [n for n in names if n and all(32 <= ord(c) < 127 for c in n)]
                if names:
                    return idx, names
    return idx, []


def idx_none():
    return None, []


_TEX_INDEX = {}


def find_png(tex_dir, name, model_idx):
    """PNG com esse nome, do bloco mais próximo ANTES do modelo (o jogo
    carrega o pacote de texturas logo antes do modelo que usa)"""
    if tex_dir not in _TEX_INDEX:
        idx = {}
        if os.path.isdir(tex_dir):
            for f in os.listdir(tex_dir):
                if f.endswith(".png") and "_" in f:
                    head, rest = f.split("_", 1)
                    num = int(head.rstrip("r")) if head.rstrip("r").isdigit() else -1
                    idx.setdefault(rest[:-4].lower(), []).append((num, f))
        _TEX_INDEX[tex_dir] = idx
    idx = _TEX_INDEX[tex_dir]
    cands = idx.get(safe_name(name).lower(), [])
    if not cands:
        # o extrator corta o nome no primeiro caractere fora de [A-Za-z0-9_]
        # (ex: "Dakar_C-Lock_index" virou "Dakar_C"), então tenta o prefixo
        import re
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", name)
        if m:
            cands = idx.get(m.group().lower(), [])
    before = [c for c in cands if model_idx is None or c[0] < model_idx]
    pick = max(before) if before else (min(cands) if cands else None)
    return os.path.join(tex_dir, pick[1]) if pick else None


def safe_name(name):
    import re
    return re.sub(r"[^A-Za-z0-9_.\-]", "_", name)[:60]


def triangulos(verts, normals, adc):
    """triângulos da tira (índices locais a, b, c; o .obj escreve "a c b").
    Cada vértice sem o 0x8000 fecha um com os 2 de antes; o giro é conferido
    com as normais do próprio jogo e desvirado se precisar. Assim dá pra
    ligar o descarte de face de trás (painéis de duas faces no mesmo lugar,
    tipo a tampa do motor do Sphinx, não ficam piscando)"""
    out = []
    for i in range(2, len(verts)):
        if adc[i]:
            continue
        a, b, c = i - 2, i - 1, i
        if i % 2:
            a, b = b, a
        pa, pb, pc = verts[a], verts[b], verts[c]
        e1 = [pc[k] - pa[k] for k in range(3)]
        e2 = [pb[k] - pa[k] for k in range(3)]
        fn = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
        vn = [normals[a][k] + normals[b][k] + normals[c][k] for k in range(3)]
        if fn[0] * vn[0] + fn[1] * vn[1] + fn[2] * vn[2] < 0:
            b, c = c, b
        out.append((a, b, c))
    return out


def alfas(d, st):
    """alfa do V4-8 de cor de cada vértice da tira (0x80 = 1.0; o parse só
    guarda o RGB). None se a tira não tem cor"""
    verts, _, _, _, _, s = st
    num = len(verts)
    q = s + 4 + 16 * num + 4 + v3_8_size(num)
    for _ in range(3):
        if q + 4 > len(d):
            break
        cnum, ccmd = cmd_at(d, q)
        if cnum != num:
            break
        if ccmd == 0x6C:
            q += 4 + 16 * num
        elif ccmd == 0x64:
            q += 4 + 8 * num
        elif ccmd == 0x6E:
            return [d[q + 4 + 4 * i + 3] for i in range(num)]
        else:
            break
    return None


def camada_tris(d, strips):
    """camada (2ª textura do lote) como lista plana pro Godot montar a malha
    (o import de .obj do Godot joga fora o alfa do vértice, e é ele que diz
    onde a camada aparece: no arco de largada o artista pintou 40..128).
    Por vértice de cada triângulo, já na ordem do Godot (o importador de
    .obj inverte a face "a c b" = a, b, c): x y z, nx ny nz, r g b do .obj
    (cor_obj), alfa (vértice/128, até 1), s t do 2º UV"""
    out = []
    for st in strips:
        verts, normals, uvs, colors, adc, _ = st
        al = alfas(d, st) or [128] * len(verts)
        for tri in triangulos(verts, normals, adc):
            for k in tri:
                uv = uvs[k]
                s, t = uv[2:4] if len(uv) == 4 else uv[:2]
                out += [round(v, 5) for v in verts[k]] + [round(v, 4) for v in normals[k]]
                out += [round(cor_obj(c), 4) for c in colors[k]] + [round(min(al[k] / 128.0, 1.0), 4)]
                out += [round(s, 5), round(t, 5)]
    return out


def to_obj(strips, name, slots=None, mtl_name=None, mat_names=None, uv2=False):
    lines = [f"# {name} - convertido de .pingu (ATV Offroad Fury 4)"]
    if mtl_name:
        lines.append(f"mtllib {mtl_name}")
    lines.append(f"o {name}")
    faces = []          # (material, a, b, c)
    base = 0
    slots = slots or [None] * len(strips)
    for (verts, normals, uvs, colors, adc, _off), slot in zip(strips, slots):
        mat = (mat_names or {}).get(slot, "sem_textura")
        for (x, y, z), c in zip(verts, colors):
            r, g, b = (cor_obj(k) for k in c)
            lines.append(f"v {x:.6f} {y:.6f} {z:.6f} {r:.4f} {g:.4f} {b:.4f}")
        for uv in uvs:
            s, t = uv[2:4] if uv2 and len(uv) == 4 else uv[:2]
            lines.append(f"vt {s:.6f} {1.0 - t:.6f}")
        for nx, ny, nz in normals:
            lines.append(f"vn {nx:.4f} {ny:.4f} {nz:.4f}")
        for la, lb, lc in triangulos(verts, normals, adc):
            faces.append((mat, base + la + 1, base + lb + 1, base + lc + 1))
        base += len(verts)
    current = None
    for mat, a, b, c in faces:
        if mtl_name and mat != current:
            lines.append(f"usemtl {mat}")
            current = mat
        lines.append(f"f {a}/{a}/{a} {c}/{c}/{c} {b}/{b}/{b}")
    return "\n".join(lines) + "\n", base, len(faces)


def build_materials(path, d, strips, out_dir, tex_dir, copy_tex=False):
    """devolve (slots por tira, {slot: nome_material}, texto do .mtl, relatório)"""
    batches = read_batches(d)
    slots = assign_batches(strips, batches)
    if not batches or slots[0] is None and len(set(slots)) == 1:
        return None, None, None, []
    model_idx, names = texture_names(path)
    mats, mtl, report = {}, ["# materiais gerados pelo pingu2obj.py"], []
    for slot in sorted(set(s for s in slots if s is not None)):
        if slot < 0:
            mats[slot] = "sem_textura"
            mtl += ["newmtl sem_textura", "Kd 1 1 1", ""]
            continue
        tname = names[slot] if slot < len(names) else f"slot_{slot}"
        mname = f"s{slot}_{safe_name(tname)}"
        mats[slot] = mname
        png = find_png(tex_dir, tname, model_idx) if slot < len(names) else None
        mtl += [f"newmtl {mname}", "Kd 1 1 1"]
        if png:
            if copy_tex:
                # copia o PNG pra pasta do modelo: fica tudo junto pra
                # arrastar no visualizador ou abrir no Blender
                import shutil
                dst = os.path.join(out_dir, os.path.basename(png))
                if not os.path.exists(dst):
                    shutil.copyfile(png, dst)
                rel = os.path.basename(png)
            else:
                rel = os.path.relpath(os.path.abspath(png), os.path.abspath(out_dir)).replace("\\", "/")
            mtl.append(f"map_Kd {rel}")
        mtl.append("")
        report.append((slot, tname, os.path.basename(png) if png else "-"))
    if -1 in slots and -1 not in mats:
        mats[-1] = "sem_textura"
        mtl += ["newmtl sem_textura", "Kd 1 1 1", ""]
    return slots, mats, "\n".join(mtl), report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", help="um arquivo ou uma pasta")
    ap.add_argument("--out", default="modelos")
    ap.add_argument("--min-tris", type=int, default=1)
    ap.add_argument("--tex", default="texturas",
                    help="pasta com os PNGs gerados pelo gob_tex2png.py")
    ap.add_argument("--no-mtl", action="store_true", help="não gera materiais")
    ap.add_argument("--copy-tex", action="store_true",
                    help="copia os PNGs usados pra pasta de saída (bom pra um modelo só)")
    ap.add_argument("--split", action="append", default=[], metavar="NOME:TIRAS",
                    help="separa tiras num .obj próprio (peça móvel). "
                         "Ex: --split volante:44,53,54,234-242")
    args = ap.parse_args()

    if os.path.isdir(args.src):
        files = sorted(os.path.join(args.src, f) for f in os.listdir(args.src))
    else:
        files = [args.src]
    os.makedirs(args.out, exist_ok=True)

    ok = with_tex = 0
    for f in files:
        d = open(f, "rb").read()
        strips = parse(d)
        if not strips:
            continue
        name = os.path.splitext(os.path.basename(f))[0]
        slots = mats = mtl = None
        report = []
        if not args.no_mtl:
            slots, mats, mtl, report = build_materials(f, d, strips, args.out, args.tex, args.copy_tex)
        # o Godot só reimporta o .obj quando ELE muda (o .mtl não conta): a
        # assinatura do .mtl vai num comentário, senão um .mtl novo (com
        # textura) fica com o material velho importado (sem textura, branco)
        assin = "# mtl %s\n" % hashlib.md5(mtl.encode()).hexdigest()[:12] if mtl else ""
        # peças separadas (ex: volante), cada uma no seu .obj.
        # Sintaxe das tiras: "44,53,234-242" pega tiras inteiras;
        # "233[12-26]" pega só os vértices 12 a 26 da tira 233 (às vezes uma
        # tira do PS2 junta duas peças, separadas por um recomeço ADC).
        batches = read_batches(d)
        cams = assign_batches(strips, batches, "camada") if batches else [-1] * len(strips)
        body = [(st, sl, cm) for st, sl, cm in zip(strips, slots or [None] * len(strips), cams)]
        body = [[b] for b in body]          # cada tira pode virar vários pedaços
        for spec in args.split:
            part, _, ranges = spec.partition(":")
            chosen = []
            for tok in ranges.split(","):
                tok = tok.strip()
                if "[" in tok:
                    i = int(tok[:tok.index("[")])
                    a, _, b = tok[tok.index("[") + 1:-1].partition("-")
                    a, b = int(a), int(b or a)
                    if i >= len(strips):
                        continue
                    st, sl, cm = strips[i], (slots[i] if slots else None), cams[i]
                    chosen.append((sub_strip(st, a, b + 1), sl, cm))
                    rest = [x for x in (sub_strip(st, 0, a), sub_strip(st, b + 1, len(st[0]))) if x]
                    body[i] = [(x, sl, cm) for x in rest]
                else:
                    a, _, b = tok.partition("-")
                    for i in range(int(a), int(b or a) + 1):
                        if i < len(strips):
                            chosen += body[i]
                            body[i] = []
            chosen = [c for c in chosen if c[0]]
            pobj, pnv, pnt = to_obj([c[0] for c in chosen], f"{name}_{part}",
                                    [c[1] for c in chosen] if slots else None,
                                    name + ".mtl" if mtl else None, mats)
            with open(os.path.join(args.out, f"{name}_{part}.obj"), "w") as fo:
                fo.write(assin + pobj)
            print(f"  peça '{part}': {len(chosen)} tiras, {pnt} triângulos -> {name}_{part}.obj")
        flat = [p for pieces in body for p in pieces]
        obj, nv, nt = to_obj([p[0] for p in flat], name,
                             [p[1] for p in flat] if slots else None,
                             name + ".mtl" if mtl else None, mats)
        if nt < args.min_tris:
            continue
        with open(os.path.join(args.out, name + ".obj"), "w") as fo:
            fo.write(assin + obj)
        # camada (2ª textura pelo 2º UV): só as tiras que têm, já sem as peças separadas
        cam = [p for p in flat if p[2] is not None and p[2] >= 0]
        if cam:
            nomes = texture_names(f)[1]
            tex_cam = sorted({nomes[p[2]] if p[2] < len(nomes) else "slot_%d" % p[2] for p in cam})
            cobj, _, cnt = to_obj([p[0] for p in cam], f"{name}_camada " + " ".join(tex_cam), uv2=True)
            with open(os.path.join(args.out, name + "_camada.obj"), "w") as fo:
                fo.write(cobj)
            if len(files) == 1:
                print(f"  camada {', '.join(tex_cam)}: {len(cam)} tiras, {cnt} triângulos -> {name}_camada.obj")
        if mtl:
            with open(os.path.join(args.out, name + ".mtl"), "w") as fo:
                fo.write(mtl)
            if any(r[2] != "-" for r in report):
                with_tex += 1
        ok += 1
        if len(files) == 1:
            print(f"  {name}: {len(strips)} tiras, {nv} vértices, {nt} triângulos")
            for slot, tname, png in report:
                print(f"    slot {slot:2d}  {tname:32s} -> {png}")
        elif ok % 200 == 0:
            print(f"  ... {ok} modelos")
    print(f"\n[+] {ok} modelos salvos em {args.out} ({with_tex} com textura encontrada)")


if __name__ == "__main__":
    main()
