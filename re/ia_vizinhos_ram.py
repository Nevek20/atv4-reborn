"""
ia_vizinhos_ram.py
==================
Lê a percepção dos rivais num save state de corrida (RX01): pra cada rival,
o comportamento ativo do cérebro (#7 linha, #5 ultrapassar), a tabela de
vizinhos (veículos) com a vaga (+0x24: 0/1 à frente, 2/3 atrás), as
distâncias longitudinal (+0x28) e lateral (+0x2c), as taxas (+0x30/+0x34) e
o tempo até colidir (+0xb0, -1 = não), comparadas com a posição real.

Uso:
    python re/ia_vizinhos_ram.py arquivo.p2s     (ou o eeMemory.bin)
"""
import struct, sys, math, os
if len(sys.argv) < 2:
    print(__doc__); sys.exit()
if sys.argv[1].endswith('.p2s'):
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
    from ler_savestate import ler_ram
    m = ler_ram(sys.argv[1])
else:
    m = open(sys.argv[1], 'rb').read()
f = lambda a: struct.unpack_from('<f', m, a & 0x1ffffff)[0]
u = lambda a: struct.unpack_from('<I', m, a & 0x1ffffff)[0]
i32 = lambda a: struct.unpack_from('<i', m, a & 0x1ffffff)[0]
ok = lambda p: 0x100000 <= p < 0x2000000
V = lambda a: [f(a + 4 * j) for j in range(3)]
mgr = u(0x7f5750); n = u(mgr + 4); lista = u(mgr + 8)
# veículo de cada corredor do jogo
corr2veh = {}
for k in range(8):
    veh = 0xc7eb00 + k * 0xba0
    corr2veh[veh] = k
def pos(veh):
    c = u(veh + 0x9d4); return V(c + 0x70), V(c + 0xd0), V(c + 0xb0)
for k in range(n):
    w = u(lista + 4 * k); pil = u(w + 0x14)
    if not ok(pil) or u(pil + 8) != 0x5ae0d0: continue
    veh = u(w + 0xc); kk = corr2veh.get(veh, -1)
    cer = u(pil + 0x14); atual = u(cer + 4)
    comp = {0x5af4e8: '#7', 0x5af228: '#5'}.get(u(atual + 0x14), '?')
    viz = u(cer + 0x10) + 4
    cnt = u(viz + 8); arr = u(viz + 0xc)
    p0, fz, fx = pos(veh)
    slots = [(u(viz + 0x44 + 8 * j), u(viz + 0x48 + 8 * j)) for j in range(4)]
    print('rival %d (%s) vizinhos %d | vagas: %s' % (kk, comp, cnt, ' '.join('%d:%s' % (j, (corr2veh.get(r, "-"))) for j, (r, inf) in enumerate(slots))))
    for j in range(cnt):
        r = u(arr + 8 * j); inf = u(arr + 8 * j + 4)
        if not ok(r) or not ok(inf): continue
        ov = r; ko = corr2veh.get(ov, -1)
        q, _, _ = pos(ov)
        d = [q[i] - p0[i] for i in range(3)]
        frente = sum(d[i] * fz[i] for i in range(3)); lado = sum(d[i] * fx[i] for i in range(3))
        print('   viz %d: válida %d vaga %d lat %.2f lon %.2f +30 %.2f +34 %.2f +38 %d +3c %d folga %.2f | real: frente %.1f lado %.1f' % (
            ko, i32(inf + 0x18), i32(inf + 0x24), f(inf + 0x28), f(inf + 0x2c), f(inf + 0x30), f(inf + 0x34), i32(inf + 0x38), i32(inf + 0x3c), f(inf + 0xb0), frente, lado))
