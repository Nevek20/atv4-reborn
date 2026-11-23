"""
hud_ram.py
==========
Lê o HUD do jogo na RAM de um save state (PCSX2): os quadros pelos dados
do XML (alinhamento, offset, escala, modo: 8 palavras em quadro+8, matriz
em quadro+0x30, pai em +0x70, escala de pixel em +0x74..0x7c) e os
elementos que apontam pra cada matriz (elemento+0x28). Mostra o ponteiro do
conta-giros (+0x98 ângulo), os números (texto +0xa0 -> +0x90 valor) e o
estado do carro (rpm, marcha, velocidade) pra comparar com menu/hud_jogo.gd.

Uso: python re/hud_ram.py arquivo.p2s [mais.p2s...]
"""
import os
import struct
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(AQUI), "tools"))
from ler_savestate import ler_ram, Ram, estado, dist  # noqa: E402

QUADROS = {   # nome: (alignX, alignY, offX, offY, offAbs, scaleX, scaleY, modo) do hud_circuit.xml
    "SPEEDO": (1, 0, 0.06, 0.015, 0, 0.33, 0.3, 0),
    "SPEED": (1, 0, 0.145, 0.067, 1, 0.0399, 0.0399, 0),
    "GEAR": (1, 0, 0.064, 0.067, 1, 0.055, 0.04, 0),
    "ACCEL_BAR": (1, 0, 0.100, 0.127, 0, 1.0, 1.0, 2),
    "BRAKE_BAR": (1, 0, 0.085, 0.127, 0, 1.0, 1.0, 2),
    "PLAYER_POS": (1, 1, 0.073, 0.004, 1, 0.69, 0.69, 1),
    "CURRENT_LAP": (0, 1, -0.014, 0.002, 1, 0.6999, 0.6999, 1),
}


def veiculo(r):
    best = None
    for c in [x - 0x68 for x in r.achar(0x5B3F30)]:
        t = r.u(c)
        if not 0x100000 <= t < 0x2000000:
            continue
        try:
            veh = r.u(r.u(t + 0x2B0) + 0xF0)
            alvo = r.v(veh + 0xAA0)
        except struct.error:
            continue
        k = (round(r.f(c + 0x100), 2), -dist(r.v(c + 0x10), alvo))
        if best is None or k > best[0]:
            best = (k, veh)
    return best[1] if best else None


def main():
    for p2s in sys.argv[1:]:
        m = ler_ram(p2s)
        r = Ram(m)
        print("==", os.path.basename(p2s))
        veh = veiculo(r)
        if veh:
            e = estado(r, veh)
            v = e["vel"]
            fr = e["frente"]
            print("  carro: rpm %.0f  marcha %d  limitador %.3f  vel %.1f km/h (pra frente %.1f)  acel %.2f/%.2f freio %.2f/%.2f" % (
                e["rpm"], e["marcha"], e["limitador"], (sum(x * x for x in v) ** 0.5) * 3.6,
                sum(v[i] * fr[i] for i in range(3)) * 3.6, *e["acelerador"], *e["freio"]))
        for nome, d in QUADROS.items():
            i = m.find(struct.pack("<IIffIffI", *d))
            if i < 0:
                print("  %s: quadro não achado" % nome)
                continue
            q = i - 8
            mt = struct.unpack_from("<16f", m, q + 0x30)
            el = None
            alvo = struct.pack("<I", q + 0x30)
            j = m.find(alvo)
            while j >= 0 and j % 4:
                j = m.find(alvo, j + 1)
            if j >= 0:
                el = j - 0x28
            s = "  %-11s matriz sx %.4f sy %.4f tx %.4f ty %.4f" % (nome, mt[0], mt[5], mt[12], mt[13])
            if el:
                tipo = r.u(el + 0xC)
                s += "  tipo %d" % tipo
                if nome == "SPEEDO":
                    s += "  ponteiro %.4f rad (alvo %.4f; min %.3f max %.3f)" % (
                        r.f(el + 0x98), r.f(el + 0x9C), r.f(el + 0x90), r.f(el + 0x94))
                elif tipo == 3:
                    t = r.u(el + 0xA0)
                    if 0x100000 <= t < 0x2000000:
                        s += "  valor %d" % r.u(t + 0x90)
                elif tipo == 9:
                    s += "  blocos acesos %d de %d" % (r.u(el + 0xC8), r.u(el + 0x84))
            print(s)


if __name__ == "__main__":
    main()
