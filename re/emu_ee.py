"""Emulador mínimo do EE (R5900 + VU0 macro) pra rodar um trecho do exe com
números nossos e ver o que ele grava (contas de vetor que o Ghidra embaralha).
Lê o assembly do re/ghidra_scripts/DumpAsm.java (linhas "ENDEREÇO  instrução";
"_" na frente = delay slot). Só as instruções que já precisamos; o resto
levanta erro com o endereço.

Uso (exemplo em re/rabo_colisores.py):
    e = Emu(open("asm.txt").read(), exe_bytes)
    e.gpr["a0"] = ...; e.escrever_f(endereco, [x, y, z, w])
    e.rodar(0x1a9db0, parar_em={0x1ab394})
"""
import math
import re
import struct

REGS = ["zero", "at", "v0", "v1", "a0", "a1", "a2", "a3", "t0", "t1", "t2", "t3", "t4", "t5", "t6", "t7",
        "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "t8", "t9", "k0", "k1", "gp", "sp", "fp", "ra"]
M32 = 0xffffffff


def f2u(f):
    return struct.unpack("<I", struct.pack("<f", f))[0]


def u2f(u):
    return struct.unpack("<f", struct.pack("<I", u & M32))[0]


class Emu:
    def __init__(self, asm, exe=None):
        self.ins = {}
        self.ordem = []
        for ln in asm.splitlines():
            m = re.match(r"([0-9a-f]{8})\s+(\S+)\s*(.*)", ln)
            if m:
                a = int(m.group(1), 16)
                self.ins[a] = (m.group(2).lstrip("_"), [o.strip() for o in m.group(3).split(",")] if m.group(3) else [])
                self.ordem.append(a)
        self.exe = exe
        self.mem = {}
        self.gpr = {r: [0, 0, 0, 0] for r in REGS}
        self.fpr = [0.0] * 32
        self.vf = [[0.0, 0.0, 0.0, 0.0] for _ in range(32)]
        self.acc = [0.0] * 4
        self.I = 0.0
        self.Q = 0.0
        self.chamadas = {}       # endereço -> função python (self) chamada no jal
        self.cc = False
        self.gpr["sp"] = [0x01f00000, 0, 0, 0]

    # ---------------------------------------------------------------- memória
    def ler32(self, a):
        a &= M32
        if a in self.mem:
            return self.mem[a]
        if self.exe and 0x100000 <= a < 0x100000 + len(self.exe) - 0x80:
            return struct.unpack_from("<I", self.exe, a - 0x100000 + 0x80)[0]
        return 0

    def gravar32(self, a, v):
        self.mem[a & M32] = v & M32

    def escrever_f(self, a, fs):
        for i, f in enumerate(fs):
            self.gravar32(a + 4 * i, f2u(f))

    def ler_f(self, a, n=4):
        return [u2f(self.ler32(a + 4 * i)) for i in range(n)]

    # ---------------------------------------------------------------- ajuda
    def r(self, n):
        return 0 if n == "zero" else self.gpr[n][0]

    def setr(self, n, v):
        if n != "zero":
            v &= M32
            self.gpr[n] = [v, M32 if v & 0x80000000 else 0, self.gpr[n][2], self.gpr[n][3]]

    @staticmethod
    def imm(s):
        return int(s, 0)

    def end(self, s):
        m = re.match(r"(-?0x[0-9a-f]+|-?\d+)\((\w+)\)", s)
        return (int(m.group(1), 0) + self.r(m.group(2))) & M32

    @staticmethod
    def vreg(s):
        return int(s[2:].rstrip("xyzw"), 10) if s.startswith("vf") else None

    @staticmethod
    def campos(mn):
        return ["xyzw".index(c) for c in mn.split(".")[1]] if "." in mn else [0, 1, 2, 3]

    def vget(self, n):
        return [0.0, 0.0, 0.0, 1.0] if n == 0 else self.vf[n]

    # ---------------------------------------------------------------- execução
    def rodar(self, inicio, parar_em=(), max_passos=200000):
        pc = inicio
        for _ in range(max_passos):
            if pc in parar_em:
                return pc
            mn, ops = self.ins[pc]
            prox = self.passo(pc, mn, ops)
            if prox == "fim":
                return pc
            pc = prox
        raise RuntimeError("passos demais")

    def passo(self, pc, mn, ops):
        if mn in ("bne", "beq", "bnel", "beql", "b", "bc1t", "bc1f", "bc1tl", "bc1fl", "blez", "bgtz", "bltz", "bgez"):
            alvo = int(ops[-1], 16)
            if mn == "b":
                ok = True
            elif mn.startswith("bc1"):
                ok = self.cc if mn[3] == "t" else not self.cc
            elif mn in ("blez", "bgtz", "bltz", "bgez"):
                v = self.r(ops[0])
                v = v - (1 << 32) if v & 0x80000000 else v
                ok = {"blez": v <= 0, "bgtz": v > 0, "bltz": v < 0, "bgez": v >= 0}[mn]
            else:
                igual = self.r(ops[0]) == self.r(ops[1])
                ok = igual if mn.startswith("beq") else not igual
            provavel = mn.endswith("l") and mn not in ("bc1fl", "bc1tl") or mn in ("bc1fl", "bc1tl")
            if ok or not provavel:
                ds = self.ordem[self.ordem.index(pc) + 1]
                self.passo(ds, *self.ins[ds])
            return alvo if ok else self.ordem[self.ordem.index(pc) + 2]
        if mn in ("jal", "jalr"):
            ds = self.ordem[self.ordem.index(pc) + 1]
            self.passo(ds, *self.ins[ds])
            alvo = int(ops[0], 16) if mn == "jal" else self.r(ops[0])
            f = self.chamadas.get(alvo)
            if f is not None:
                f(self)
            elif alvo in self.ins:           # função que está no dump: roda ela
                self.rodar(alvo)
            else:
                raise RuntimeError("jal sem stub %x em %x" % (alvo, pc))
            return self.ordem[self.ordem.index(pc) + 2]
        if mn == "jr":
            ds = self.ordem[self.ordem.index(pc) + 1]
            self.passo(ds, *self.ins[ds])
            return "fim"
        self.exec(pc, mn, ops)
        return self.ordem[self.ordem.index(pc) + 1]

    def exec(self, pc, mn, ops):
        base = mn.split(".")[0]
        if mn in ("nop", "vnop", "vwaitq"):
            return
        if mn in ("addiu", "daddiu"):
            self.setr(ops[0], self.r(ops[1]) + self.imm(ops[2]))
        elif mn == "li":
            self.setr(ops[0], self.imm(ops[1]))
        elif mn == "lui":
            self.setr(ops[0], self.imm(ops[1]) << 16)
        elif mn == "ori":
            self.setr(ops[0], self.r(ops[1]) | self.imm(ops[2]))
        elif mn == "xori":
            self.setr(ops[0], self.r(ops[1]) ^ self.imm(ops[2]))
        elif mn in ("move",):
            self.gpr[ops[0]] = list(self.gpr[ops[1]]) if ops[1] != "zero" else [0, 0, 0, 0]
        elif mn in ("addu", "daddu"):
            self.setr(ops[0], self.r(ops[1]) + self.r(ops[2]))
        elif mn == "subu":
            self.setr(ops[0], self.r(ops[1]) - self.r(ops[2]))
        elif mn == "sll":
            self.setr(ops[0], self.r(ops[1]) << self.imm(ops[2]))
        elif mn == "slt" or mn == "slti":
            a = self.r(ops[1])
            b = self.r(ops[2]) if mn == "slt" else self.imm(ops[2]) & M32
            a = a - (1 << 32) if a & 0x80000000 else a
            b = b - (1 << 32) if b & 0x80000000 else b
            self.setr(ops[0], 1 if a < b else 0)
        elif mn == "mult":
            self.setr(ops[0], self.r(ops[1]) * self.r(ops[2]))
        elif mn == "lw":
            self.setr(ops[0], self.ler32(self.end(ops[1])))
        elif mn == "lh":
            a = self.end(ops[1])
            v = (self.ler32(a & ~3) >> (8 * (a & 3))) & 0xffff
            self.setr(ops[0], v - 0x10000 if v & 0x8000 else v)
        elif mn == "sw":
            self.gravar32(self.end(ops[1]), self.r(ops[0]))
        elif mn in ("sd",):
            a = self.end(ops[1])
            g = self.gpr[ops[0]]
            self.gravar32(a, g[0]); self.gravar32(a + 4, g[1])
        elif mn in ("ld",):
            a = self.end(ops[1])
            self.gpr[ops[0]] = [self.ler32(a), self.ler32(a + 4), 0, 0]
        elif mn == "lq":
            a = self.end(ops[1]) & ~15
            self.gpr[ops[0]] = [self.ler32(a + 4 * i) for i in range(4)]
        elif mn == "sq":
            a = self.end(ops[1]) & ~15
            g = self.gpr[ops[0]] if ops[0] != "zero" else [0, 0, 0, 0]
            for i in range(4):
                self.gravar32(a + 4 * i, g[i])
        elif mn == "lwc1":
            self.fpr[int(ops[0][1:])] = u2f(self.ler32(self.end(ops[1])))
        elif mn == "swc1":
            self.gravar32(self.end(ops[1]), f2u(self.fpr[int(ops[0][1:])]))
        elif mn == "mtc1":
            self.fpr[int(ops[1][1:])] = u2f(self.r(ops[0]))
        elif mn == "mfc1":
            self.setr(ops[0], f2u(self.fpr[int(ops[1][1:])]))
        elif mn == "clear":
            self.fpr[int(ops[0][1:])] = 0.0
        elif base in ("mov", "add", "sub", "mul", "div", "neg", "abs", "sqrt") and mn.endswith(".S"):
            d = int(ops[0][1:])
            a = self.fpr[int(ops[1][1:])]
            b = self.fpr[int(ops[2][1:])] if len(ops) > 2 else 0.0
            self.fpr[d] = {"mov": a, "add": a + b, "sub": a - b, "mul": a * b, "div": a / b if b else 0.0,
                           "neg": -a, "abs": abs(a), "sqrt": math.sqrt(max(b if len(ops) > 2 else a, 0.0))}[base]
        elif base in ("c",) and mn.endswith(".S"):
            a, b = self.fpr[int(ops[0][1:])], self.fpr[int(ops[1][1:])]
            self.cc = {"c.lt": a < b, "c.le": a <= b, "c.eq": a == b}[mn[:-2]]
        elif mn == "pextlw":
            rs, rt = self.gpr[ops[1]], self.gpr[ops[2]]
            self.gpr[ops[0]] = [rt[0], rs[0], rt[1], rs[1]]
        elif mn == "pcpyld":
            rs, rt = self.gpr[ops[1]], self.gpr[ops[2]]
            self.gpr[ops[0]] = [rt[0], rt[1], rs[0], rs[1]]
        elif mn == "lqc2":
            a = self.end(ops[1]) & ~15
            self.vf[self.vreg(ops[0])] = [u2f(self.ler32(a + 4 * i)) for i in range(4)]
        elif mn == "sqc2":
            a = self.end(ops[1]) & ~15
            v = self.vget(self.vreg(ops[0]))
            for i in range(4):
                self.gravar32(a + 4 * i, f2u(v[i]))
        elif mn == "qmtc2":
            self.vf[self.vreg(ops[1])] = [u2f(w) for w in self.gpr[ops[0]]]
        elif mn == "qmfc2":
            self.gpr[ops[0]] = [f2u(x) for x in self.vget(self.vreg(ops[1]))]
        elif mn == "ctc2":
            if ops[1] == "vc5":
                self.I = u2f(self.r(ops[0]))
            else:
                raise RuntimeError("ctc2 %s em %x" % (ops[1], pc))
        elif base in ("vsqrt",):
            n = self.vreg(ops[1]); c = "xyzw".index(ops[1][-1])
            self.Q = math.sqrt(max(self.vget(n)[c], 0.0))
        elif base == "vdiv":
            a = self.vget(self.vreg(ops[1]))["xyzw".index(ops[1][-1])]
            b = self.vget(self.vreg(ops[2]))["xyzw".index(ops[2][-1])]
            self.Q = a / b if b else 0.0
        elif base == "vmove":
            d = self.vreg(ops[0]); s = self.vget(self.vreg(ops[1]))
            for c in self.campos(mn):
                self.vf[d][c] = s[c]
        else:
            self.vu(pc, mn, ops)

    def vu(self, pc, mn, ops):
        m = re.match(r"v(add|sub|mul|madd|msub)(a?)([xyzwiq]?)\.([xyzw]+)$", mn)
        if not m:
            raise RuntimeError("instrução %s em %x" % (mn, pc))
        op, acc, bc, dest = m.groups()
        cs = ["xyzw".index(c) for c in dest]
        s = self.vget(self.vreg(ops[1]))
        if bc == "i":
            t = [self.I] * 4
        elif bc == "q":
            t = [self.Q] * 4
        else:
            tv = self.vget(self.vreg(ops[2]))
            t = [tv["xyzw".index(bc)]] * 4 if bc else tv
        r = [0.0] * 4
        for c in cs:
            if op == "add":
                r[c] = s[c] + t[c]
            elif op == "sub":
                r[c] = s[c] - t[c]
            elif op == "mul":
                r[c] = s[c] * t[c]
            elif op == "madd":
                r[c] = self.acc[c] + s[c] * t[c]
            elif op == "msub":
                r[c] = self.acc[c] - s[c] * t[c]
        if acc:
            for c in cs:
                self.acc[c] = r[c]
        else:
            d = self.vreg(ops[0])
            if d:
                for c in cs:
                    self.vf[d][c] = r[c]
