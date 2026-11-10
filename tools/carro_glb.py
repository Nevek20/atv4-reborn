"""
carro_glb.py
============
Carro extra NOSSO a partir de um modelo .glb no padrão do Assetto Corsa (o
que o Sketchfab mais tem: nós WHEEL_LF/RF/LR/RR com a origem no centro da
roda, STEER_HR = volante, SUSP_xx = cubo da roda, COCKPIT_HR = interior).
O jogo não tem nada disso: tudo aqui é escolha nossa, medida no modelo.

Gera, no frame do modelo do jogo (x = -x do glTF: o glTF com +z pra frente
tem +x na ESQUERDA; o jogo é mão esquerda, +x na direita):
  assets/carros/<nome>/<nome>.glb    cópia do modelo (o Godot importa com os
                              materiais PBR; o car.gd junta as malhas)
  assets/carros/<nome>/pecas.json    nós que saem da carroceria (rodas, volante,
                              cubos), roda de cada canto, volante
                              (centro, eixo, raio) e a licença do modelo
  data/vehicles/<nome>_points.json  pontos como os do jogo: WHEEL_*, ARSE,
                              EXHAUST*, BRAKE_LIGHT*, HEAD_LIGHT*
  data/vehicles/<nome>_casco.json   esferas de colisão (como o
                              VehicleWorld.hsc do jogo): fileiras em volta da
                              carroceria e da cabine
  data/vehicles/<nome>.xml    física: a do carro --base (padrão o Storm,
                              o rally do jogo) com raio/largura das rodas,
                              curso, massa, CoM e dimensões trocados

Uso: python tools/carro_glb.py <modelo.glb> <nome> [--base buggy_12]
     [--massa 0.9] [--curso 0.25] [--estatico 0.12]
"""

import argparse
import json
import os
import re
import shutil
import struct

import numpy as np

AQUI = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(AQUI)

RODAS = {"FL": "WHEEL_LF", "FR": "WHEEL_RF", "RL": "WHEEL_LR", "RR": "WHEEL_RR"}
PONTO_RODA = {"FL": "WHEEL_FRONT_LEFT", "FR": "WHEEL_FRONT_RIGHT", "RL": "WHEEL_REAR_LEFT", "RR": "WHEEL_REAR_RIGHT"}
CUBOS = {"FL": ["SUSP_LF", "steerL"], "FR": ["SUSP_RF", "steerR"], "RL": ["SUSP_LR"], "RR": ["SUSP_RR"]}
ESPELHO = np.array([-1.0, 1.0, 1.0])
# o jogo desenha os carros ~25% maiores que os de verdade (entre-eixos: Storm
# = Delta S4 x 1.24, Lazarus = Silverado x 1.27): o extra entra na mesma escala
ESCALA_JOGO = 1.25
ESC = 1.0

TIPOS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}


class Glb:
    def __init__(self, caminho):
        d = open(caminho, "rb").read()
        if d[:4] != b"glTF":
            raise ValueError("não é .glb")
        n = struct.unpack_from("<I", d, 12)[0]
        self.j = json.loads(d[20:20 + n])
        o = 20 + n
        n2 = struct.unpack_from("<I", d, o)[0]
        self.bin = d[o + 8:o + 8 + n2]
        self.mundo = {}
        for s in self.j["scenes"]:
            for r in s["nodes"]:
                self._andar(r, np.eye(4))

    def acessor(self, i):
        a = self.j["accessors"][i]
        bv = self.j["bufferViews"][a["bufferView"]]
        k = TIPOS[a["type"]]
        tp = np.dtype(COMP[a["componentType"]])
        ini = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        passo = bv.get("byteStride", 0) or k * tp.itemsize
        cru = np.frombuffer(self.bin, dtype=np.uint8, count=passo * (a["count"] - 1) + k * tp.itemsize, offset=ini)
        if passo == k * tp.itemsize:
            return np.frombuffer(cru.tobytes(), dtype=tp).reshape(a["count"], k)
        out = np.empty((a["count"], k), dtype=tp)
        for c in range(a["count"]):
            out[c] = np.frombuffer(cru[c * passo:c * passo + k * tp.itemsize].tobytes(), dtype=tp)
        return out

    @staticmethod
    def _matriz(nd):
        if "matrix" in nd:
            return np.array(nd["matrix"], dtype=float).reshape(4, 4).T
        m = np.eye(4)
        if "scale" in nd:
            m = np.diag(list(nd["scale"]) + [1.0]) @ m
        if "rotation" in nd:
            x, y, z, w = nd["rotation"]
            r = np.eye(4)
            r[:3, :3] = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
            m = r @ m
        if "translation" in nd:
            t = np.eye(4)
            t[:3, 3] = nd["translation"]
            m = t @ m
        return m

    def _andar(self, n, pai):
        w = pai @ self._matriz(self.j["nodes"][n])
        self.mundo[n] = w
        for c in self.j["nodes"][n].get("children", []):
            self._andar(c, w)

    def no(self, prefixo):
        """nó pelo começo do nome (o Sketchfab põe _NNN no fim)"""
        for i, nd in enumerate(self.j["nodes"]):
            nome = nd.get("name", "")
            if nome == prefixo or re.fullmatch(re.escape(prefixo) + r"_\d+", nome):
                return i
        return None

    def descendentes(self, n):
        out = [n]
        for c in self.j["nodes"][n].get("children", []):
            out += self.descendentes(c)
        return out

    def vertices(self, nos, material=None):
        """vértices (mundo do glTF) das malhas dos nós; material = parte do nome"""
        pts = []
        for n in nos:
            nd = self.j["nodes"][n]
            if "mesh" not in nd:
                continue
            for p in self.j["meshes"][nd["mesh"]]["primitives"]:
                if material is not None:
                    mi = p.get("material")
                    nome = self.j["materials"][mi].get("name", "") if mi is not None else ""
                    if material.lower() not in nome.lower():
                        continue
                v = self.acessor(p["attributes"]["POSITION"]).astype(float)
                v = (self.mundo[n] @ np.c_[v, np.ones(len(v))].T).T[:, :3]
                pts.append(v)
        return np.concatenate(pts) if pts else np.zeros((0, 3))


def jogo(v):
    """ponto do glTF -> frame do jogo (x virado e na escala do jogo)"""
    return np.asarray(v) * ESPELHO * ESC


def direcao(v):
    d = np.asarray(v) * ESPELHO
    return d / np.linalg.norm(d)


def r5(v):
    return [round(float(x), 5) for x in v]


def grupos_x(v, raio=0.15):
    """separa por lado (x) em até 2 grupos: [(centro, vértices), ...]"""
    if len(v) == 0:
        return []
    esq, dir_ = v[v[:, 0] < 0], v[v[:, 0] >= 0]
    return [g for g in (esq, dir_) if len(g) > 0]


def volante(g, n):
    """centro, eixo (pro piloto) e raio do aro, pelos vértices do volante"""
    v = g.vertices(g.descendentes(n))
    c = (v.min(0) + v.max(0)) / 2.0
    q = v - v.mean(0)
    _, _, vt = np.linalg.svd(q, full_matrices=False)
    eixo = vt[2]
    if eixo[2] > 0:                  # o piloto fica atrás (z menor)
        eixo = -eixo
    d = q - np.outer(q @ eixo, eixo)
    raio = float(np.percentile(np.linalg.norm(d, axis=1), 97))
    return c, eixo, raio


def casco(v, rodas_y_chao):
    """esferas em volta da carroceria: fileira de baixo (esquerda e direita) a
    cada ~0.55 m e a da cabine onde o teto é alto. Frame do jogo."""
    zmin, zmax = v[:, 2].min(), v[:, 2].max()
    esf = []
    r = 0.36 * ESC
    zs = np.linspace(zmin + r, zmax - r, max(2, int(round((zmax - zmin - 2 * r) / 0.55)) + 1))
    for z in zs:
        fatia = v[np.abs(v[:, 2] - z) < 0.2]
        if len(fatia) < 10:
            continue
        meia = min(-fatia[:, 0].min(), fatia[:, 0].max())
        baixo = np.percentile(fatia[:, 1], 2)
        y = max(baixo, rodas_y_chao + 0.06 * ESC) + r
        for x in (-(meia - r), meia - r):
            esf.append([x, y, z, r])
    # cabine: só onde o teto passa de 0.5 m acima da fileira de baixo
    rc = 0.42 * ESC
    alto = v[v[:, 1] > np.percentile(v[:, 1], 90)]
    zc = np.linspace(alto[:, 2].min() + rc * 0.6, alto[:, 2].max() - rc * 0.6, 3)
    teto = alto[:, 1].max()
    for z in zc:
        fatia = v[np.abs(v[:, 2] - z) < 0.25]
        meia = min(-fatia[:, 0].min(), fatia[:, 0].max())
        for x in (-(meia - rc - 0.1), meia - rc - 0.1):
            esf.append([x, teto - rc, z, rc])
    return [r5(e) for e in esf]


def fisica(base, saida, rodas, massa, curso, com, dims):
    """XML de física do carro base com rodas, curso, massa, CoM e caixa trocados"""
    x = open(base, encoding="utf-8").read()

    def troca(attr, val, s):
        return re.sub(r'(%s=")[^"]*(")' % attr, r"\g<1>%.7f\g<2>" % val, s)

    # relação final pelo raio da roda: mesma velocidade por rpm (e mesma força
    # no chão) que o carro base com as rodas dele
    r0 = float(re.search(r'<FrontLeft Radius="([^"]*)"', x).group(1))
    k = rodas["FL"]["raio"] / r0
    for attr in ("Final_drive_non_tuned", "Final_drive_fully_tuned"):
        f0 = float(re.search(r'%s="([^"]*)"' % attr, x).group(1))
        x = troca(attr, f0 * k, x)
    x = troca("Mass_non_tuned", massa, x)
    x = troca("Mass_fully_tuned", massa * 0.96, x)
    x = troca("Inertia_dimensions_width", dims[0], x)
    x = troca("Inertia_dimensions_height", dims[1], x)
    x = troca("Inertia_dimensions_length", dims[2], x)
    x = re.sub(r'(<Centre_of_mass )X="[^"]*" Y="[^"]*" Z="[^"]*"',
               r'\1X="%.7f" Y="%.7f" Z="%.7f"' % tuple(com), x)
    for canto, tag in (("FL", "FrontLeft"), ("FR", "FrontRight"), ("RL", "RearLeft"), ("RR", "RearRight")):
        m = re.search(r"<%s [^>]*/>" % tag, x)
        el = m.group(0)
        el = troca("Radius", rodas[canto]["raio"], el)
        el = troca("Width", rodas[canto]["largura"], el)
        el = troca("Maximum_position_non_tuned", curso, el)
        el = troca("Maximum_position_fully_tuned", curso, el)
        x = x.replace(m.group(0), el)
    open(saida, "w", encoding="utf-8", newline="\n").write(x)


def pintura(g):
    """material da pintura (nome com "paint", o maior textura) e quanto clarear
    pro branco dele virar o branco do jogo: os modelos do Assetto Corsa trazem
    a sombra assada na textura (branco do Escort = 200 de 255; em luz linear
    0.58 contra 1.0 dos carros do jogo, que ficam neutros com a cor do vértice)"""
    import io
    try:
        from PIL import Image
    except ImportError:
        return None, 1.0
    melhor = None
    for i, m in enumerate(g.j.get("materials", [])):
        if "paint" not in m.get("name", "").lower() or "int_" in m.get("name", "").lower():
            continue
        t = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if t is None:
            continue
        im = g.j["images"][g.j["textures"][t["index"]]["source"]]
        bv = g.j["bufferViews"][im["bufferView"]]
        img = Image.open(io.BytesIO(g.bin[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]))
        if melhor is None or img.size[0] * img.size[1] > melhor[2]:
            melhor = (m["name"], img.convert("RGB"), img.size[0] * img.size[1])
    if melhor is None:
        return None, 1.0
    px = np.asarray(melhor[1]).reshape(-1, 3).astype(float)
    claros = px[(px.min(1) > 150) & (px.max(1) - px.min(1) < 25)]    # brancos/cinzas claros
    if len(claros) < 1000:
        return melhor[0], 1.0
    branco = float(np.median(claros.mean(1)))
    return melhor[0], round(min(1.4, 250.0 / branco), 3)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("glb")
    ap.add_argument("nome")
    ap.add_argument("--base", default="buggy_12", help="física de partida (data/vehicles/<base>.xml)")
    ap.add_argument("--massa", type=float, default=0.9, help="toneladas")
    ap.add_argument("--curso", type=float, default=0.25, help="curso máximo da suspensão (m, tamanho real)")
    ap.add_argument("--escala", type=float, default=ESCALA_JOGO,
                    help="tamanho do modelo no jogo (padrão 1.25 = a escala dos carros do jogo; 1 = real)")
    ap.add_argument("--estatico", default="0.114,0.074",
                    help="frente,trás: quanto a suspensão desce parado (m); o ponto WHEEL fica isso abaixo "
                         "da roda do modelo. Rode o tests/teste_extra.gd e passe o curso parado que ele mede")
    a = ap.parse_args()
    global ESC
    ESC = a.escala
    est = [float(x) for x in a.estatico.split(",")]
    est = est if len(est) == 2 else [est[0], est[0]]
    g = Glb(a.glb)
    nome = a.nome.lower()
    pasta = os.path.join(PROJ, "assets", "carros", nome)
    os.makedirs(pasta, exist_ok=True)
    shutil.copyfile(a.glb, os.path.join(pasta, nome + ".glb"))

    pontos = {}
    rodas = {}
    excluir = []
    for canto, prefixo in RODAS.items():
        n = g.no(prefixo)
        if n is None:
            raise SystemExit("sem o nó %s (o modelo não é do padrão Assetto Corsa?)" % prefixo)
        v = g.vertices(g.descendentes(n))
        c = jogo(g.mundo[n][:3, 3])
        rodas[canto] = {"no": g.j["nodes"][n]["name"], "centro": r5(c),
                        "raio": round(float((v[:, 1].max() - v[:, 1].min()) / 2 * ESC), 4),
                        "largura": round(float((v[:, 0].max() - v[:, 0].min()) * ESC), 4), "cubo": []}
        excluir.append(g.j["nodes"][n]["name"])
        for cb in CUBOS[canto]:
            k = g.no(cb)
            if k is not None:
                rodas[canto]["cubo"].append(g.j["nodes"][k]["name"])
                excluir.append(g.j["nodes"][k]["name"])
        p = np.array(c)
        p[1] -= est[0] if canto[0] == "F" else est[1]
        pontos[PONTO_RODA[canto]] = r5(p)

    vol = {}
    n = g.no("STEER_HR")
    if n is not None:
        c, eixo, raio = volante(g, n)
        vol = {"centro": r5(jogo(c)), "eixo": r5(direcao(eixo)), "raio": round(raio * ESC, 4),
               "no": g.j["nodes"][n]["name"]}
        excluir.append(g.j["nodes"][n]["name"])
        # banco: o ponto ARSE dos carros do jogo fica 0.37 abaixo e 0.46 atrás
        # do centro do volante (car.gd VOLANTE_SEM_MODELO, média dos trucks)
        pontos["ARSE"] = r5(jogo(c) + np.array([0.0, -0.37, -0.46]))

    corpo = [i for i in range(len(g.j["nodes"])) if "mesh" in g.j["nodes"][i]]
    tirar = set()
    for nm in excluir:
        tirar.update(g.descendentes(g.no(nm)))
    corpo = [i for i in corpo if i not in tirar]
    vc = jogo(g.vertices(corpo))

    # escape: a boca = a ponta do cano mais perto da borda da carroceria (de
    # lado ou atrás: no Escort ele sai no lado esquerdo, embaixo da porta);
    # a direção vem dos 8-40 cm de cano antes da ponta
    ve = jogo(g.vertices(corpo, "exhaust"))
    blo, bhi = vc.min(0), vc.max(0)
    saidas = {}
    for i, grupo in enumerate(grupos_x(ve)):
        borda = np.minimum(np.minimum(grupo[:, 0] - blo[0], bhi[0] - grupo[:, 0]), grupo[:, 2] - blo[2])
        ponta = grupo[borda < borda.min() + 0.03]
        boca = ponta.mean(0)
        dist = np.linalg.norm(grupo - boca, axis=1)
        antes = grupo[(dist > 0.08) & (dist < 0.40)]
        d = boca - antes.mean(0) if len(antes) else np.array([0.0, 0.0, -1.0])
        d /= np.linalg.norm(d)
        nome_p = "EXHAUST" if i == 0 else "EXHAUST%d" % (i + 1)
        pontos[nome_p] = r5(boca)
        saidas[nome_p] = d
    # lanternas e faróis: centro de cada lado da malha das luzes
    for prefixo, ponto in (("REAR_LIGHTS", "BRAKE_LIGHT"), ("FRONT_LIGHTS", "HEAD_LIGHT")):
        k = g.no(prefixo)
        if k is None:
            continue
        for i, grupo in enumerate(grupos_x(jogo(g.vertices(g.descendentes(k))))):
            pontos["%s%d" % (ponto, i + 1)] = r5((grupo.min(0) + grupo.max(0)) / 2)
    rot = {}                          # linhas da matriz como no _points.bin (a 3ª = saída do escape)
    for k in pontos:
        rot[k] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        if k in saidas:
            z = saidas[k]
            x = np.cross([0.0, 1.0, 0.0], z)
            x /= np.linalg.norm(x)
            rot[k] = [r5(x), r5(np.cross(z, x)), r5(z)]

    chao = min(r["centro"][1] - r["raio"] for r in rodas.values())
    esferas = casco(vc, chao)

    lo, hi = vc.min(0), vc.max(0)
    dims = hi - lo
    fz = rodas["FL"]["centro"][2]
    tz = rodas["RL"]["centro"][2]
    # CoM: motor na frente, 53% na frente; altura de carro de rua baixo
    com = [0.0, chao + 0.48 * ESC, tz + 0.53 * (fz - tz)]

    asset = g.j.get("asset", {}).get("extras", {})
    pint, brilho = pintura(g)
    pecas = {"carro": a.nome, "glb": nome + ".glb", "excluir": excluir, "estatico": est, "escala": ESC,
             "pintura": {"material": pint, "brilho": brilho},
             "rodas_glb": rodas, "volante": vol, "pecas": {"Body": nome + ".glb"}, "cor_vertice": 0,
             "fonte": {k: asset.get(k, "") for k in ("title", "author", "license", "source")}}
    json.dump(pecas, open(os.path.join(pasta, "pecas.json"), "w", encoding="utf-8", newline="\n"),
              ensure_ascii=False, indent=1)
    dv = os.path.join(PROJ, "data", "vehicles")
    json.dump({"pontos": pontos, "rot": rot}, open(os.path.join(dv, nome + "_points.json"), "w", newline="\n"), indent=1)
    json.dump({"fonte": "tools/carro_glb.py (nosso)", "esferas": esferas, "planos": [], "vertices": []},
              open(os.path.join(dv, nome + "_casco.json"), "w", newline="\n"), separators=(",", ":"))
    fisica(os.path.join(dv, a.base + ".xml"), os.path.join(dv, nome + ".xml"), rodas, a.massa, a.curso * ESC, com,
           [float(dims[0]), float(dims[1]), float(dims[2])])

    print("%s: %d nós com malha na carroceria, %.2f x %.2f x %.2f m" % (a.nome, len(corpo), *dims))
    for canto, r in rodas.items():
        print("  roda %s centro %s raio %.3f largura %.3f cubo %s" % (canto, r["centro"], r["raio"], r["largura"], r["cubo"]))
    print("  volante %s" % vol)
    for k, p in pontos.items():
        print("  %-18s %s%s" % (k, p, "  saída %s" % r5(saidas[k]) if k in saidas else ""))
    print("  casco: %d esferas; CoM %s; chão em y %.3f" % (len(esferas), r5(com), chao))
    print("  pintura %s: branco clareado x %.3f" % (pint, brilho))
    print("  licença: %s (%s)" % (pecas["fonte"]["license"], pecas["fonte"]["author"]))


if __name__ == "__main__":
    main()
