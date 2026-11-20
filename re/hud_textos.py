"""
hud_textos.py
=============
Referência dos TEXTOS do HUD tirada da RAM de um save state (PAL): a
posição de cada letra que o jogo montou (vértices do GS de cada objeto de
texto) e a tabela da fonte já carregada (largura e caixa de cada caractere).
Grava tests/ref_hud_textos.json pro tests/teste_hud.gd.

Conta do GS (PAL, framebuffer 512 x 512 mostrado em 640 x 480): vértice em
1/16 de pixel, centro em 2048 -> x da tela 640 = (X/16 - 1792) x 1.25,
y da tela 480 = (Y/16 - 1792) x 480 / 512. Objeto de texto (0x2689c0): fonte
em +8, string em +0xc, flags +0x20, posição (NDC) +0x30, escala +0x40/+0x44,
vértices em +0x6c (0x40 bytes por letra, espaço não tem). Classes:
número (vtable 0x5e13d0, 0x494a78: valor +0x90, células +0x70) e tempo
(vtable 0x5e1398, 0x494fb0: valor +0x80, sem valor +0x90, sinal +0x8c).
O string desses dois é o MODELO ("0000", "--:--:--"): o jogo só troca a
textura de cada célula, então as posições valem pro valor mostrado.

O nome do perfil do jogador (a linha dele na lista) fica de fora.

Uso: python re/hud_textos.py andando_em_linha_reta.p2s
"""
import json
import os
import struct
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(AQUI)
sys.path.insert(0, os.path.join(PROJ, "tools"))
from ler_savestate import ler_ram  # noqa: E402

LINHA = {"FONT_SMALL": 22.0, "FONT_MEDIUM": 30.0}
VT_NUMERO = 0x5E13D0
VT_TEMPO = 0x5E1398


def main():
    m = ler_ram(sys.argv[1])
    u = lambda a: struct.unpack_from("<I", m, a)[0]
    f = lambda a: struct.unpack_from("<f", m, a)[0]
    # fontes carregadas: kerning (base, passo) em fonte+0xdc
    fontes = {}
    for nome, par in (("FONT_SMALL", (0.006245330907404423, 0.0031226654537022114)),
                      ("FONT_MEDIUM", (0.003124101785942912, 0.003124101785942912))):
        i = m.find(struct.pack("<ff", *par))
        if i >= 0:
            fontes[i - 0xDC] = nome
    out = {"fontes": {}, "textos": []}
    for F, nome in fontes.items():
        tab = {}
        for c in list(range(0x20, 0x7F)):
            w, u0, v0, u1, v1 = struct.unpack_from("<5f", m, F + 0x100 + c * 0x14)
            if w:
                tab[str(c)] = [round(w * 320.0, 3), round(u0, 5), round(v0, 5), round(u1, 5), round(v1, 5)]
        out["fontes"][nome] = {"altura": round(f(F + 0xFC) * 240.0, 3), "glifos": tab}
    for F, fnome in fontes.items():
        p = struct.pack("<I", F)
        j = m.find(p)
        while j >= 0:
            o = j - 8
            j = m.find(p, j + 1)
            fl, sp, vp = u(o + 0x20), u(o + 0xC), u(o + 0x6C)
            if fl >= 0x10000 or not (0x100000 < sp < len(m)) or not (0x100000 < vp < len(m)):
                continue
            s = m[sp:m.find(b"\0", sp)]
            if not 0 < len(s) < 40:
                continue
            n = len(s.replace(b" ", b""))
            xs = []
            for k in range(n):
                v = vp + k * 0x40
                x0, x1 = u(v + 0x10), u(v + 0x30)
                xs.append([round((x0 / 16.0 - 1792.0) * 1.25, 3), round((x1 / 16.0 - 1792.0) * 1.25, 3)])
            y0 = (u(vp + 0x14) / 16.0 - 1792.0) * 480.0 / 512.0
            y1 = (u(vp + 0x34) / 16.0 - 1792.0) * 480.0 / 512.0
            e = {"fonte": fnome, "txt": s.decode("latin-1"), "flags": fl,
                 "pos": [round(f(o + 0x30), 5), round(f(o + 0x34), 5)],
                 "esc": [round(f(o + 0x40), 5), round(f(o + 0x44), 5)],
                 "x": xs, "y": [round(y0, 3), round(y1, 3)]}
            vt = u(o + 0x1C)
            if vt == VT_NUMERO:
                e["classe"] = "numero"
                e["valor"] = struct.unpack_from("<i", m, o + 0x90)[0]
            elif vt == VT_TEMPO:
                e["classe"] = "tempo"
                e["valor"] = None if u(o + 0x90) else round(f(o + 0x80), 4)
            out["textos"].append(e)
    # nomes do layout pelos quadros da RAM (tests/ref_hud_4x3.json): o texto
    # fica no canto (esquerda, topo) do quadro, escala = altura / linha da
    # fonte (o número centrado anda pra esquerda: casa pelo topo e escala)
    import re
    quadros = json.load(open(os.path.join(PROJ, "tests", "ref_hud_4x3.json")))
    xml = open(os.path.join(PROJ, "data", "hud_circuit.xml"), encoding="latin-1").read()
    fonte_de = dict(re.findall(r'<(\w+) mObjectType="OBJECT_(?:TEXT|TIMER|INTEGER)"[^>]*mFont="(\w+)"', xml))
    centro = set(re.findall(r'<(\w+) mObjectType="OBJECT_INTEGER"[^>]*mAlignCentre="1"', xml))
    lista = quadros.get("PLAYERLIST_TEXT")
    pos_jogador = None
    for e in out["textos"]:
        for nome, q in quadros.items():
            if fonte_de.get(nome) != e["fonte"]:
                continue
            s = q[1] * 240.0 / LINHA[e["fonte"]]
            topo = q[3] + q[1]
            if abs(e["pos"][1] - topo) < 2e-3 and abs(e["esc"][1] - s) < 2e-3 and (
                    nome in centro or abs(e["pos"][0] - q[2]) < 2e-3):
                e["nome"] = nome
                if nome == "PLAYER_POS":
                    pos_jogador = e.get("valor")
        if "nome" not in e and lista and e["fonte"] == "FONT_SMALL" and abs(e["esc"][1] - lista[1] * 240.0 / 22.0) < 2e-3:
            k = round((lista[3] + lista[1] - e["pos"][1]) / (lista[1] * 1.172))
            e["nome"] = "PLAYERLIST_TEXT"
            e["linha"] = k
            e["coluna"] = 0 if abs(e["pos"][0] - lista[2]) < 2e-3 else 1
    # privacidade: o nome do perfil (linha do jogador) não vai pro repositório
    if pos_jogador:
        out["textos"] = [e for e in out["textos"] if not (
            e.get("nome") == "PLAYERLIST_TEXT" and e["coluna"] == 1 and e["linha"] == pos_jogador - 1)]
    out["textos"] = [e for e in out["textos"] if "nome" in e]
    out["textos"].sort(key=lambda e: (e["nome"], e.get("linha", 0), e.get("coluna", 0)))
    json.dump(out, open(os.path.join(PROJ, "tests", "ref_hud_textos.json"), "w", encoding="utf-8"), indent=1)
    print("[+] %d textos, fontes %s em tests/ref_hud_textos.json" % (len(out["textos"]), list(out["fontes"])))
    for e in out["textos"]:
        print("   %-26s %-10s %s %s" % (e["nome"] + ("[%d.%d]" % (e["linha"], e["coluna"]) if "linha" in e else ""),
                                     e.get("classe", "texto"), e["txt"] if e["nome"] != "PLAYERLIST_TEXT" or e["coluna"] == 0 else e["txt"],
                                     e.get("valor", "")))


if __name__ == "__main__":
    main()
