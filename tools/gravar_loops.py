"""Grava loops de som dos motores do Engine Simulator.

    python tools/gravar_loops.py                  -> som/loops/<motor>/*.wav (os 12)
    python tools/gravar_loops.py 08 11 --passo 500

Precisa do tools/engine_sim_dyno compilado (bash tools/engine_sim_dyno/preparar.sh,
Linux). Pra cada motor: lenta.wav e, a cada 500 rpm de 1000 até o corte,
on_RRRR.wav (acelerando, borboleta toda aberta) e off_RRRR.wav (soltando,
borboleta fechada com o motor arrastado no mesmo rpm). O dinamômetro segura o
rpm, então cada gravação é um rpm só.

Corte do loop: ~2 s com um número inteiro de ciclos do motor (720°, que é o
período do ronco), começando e terminando num zero subindo (amostra anterior
< 0 <= amostra). Entre os pares de zeros possíveis fica o que tem a forma de
onda mais parecida dos dois lados da emenda. O .wav leva um bloco smpl com o
loop (o Godot lê com Loop Mode = Detect From WAV).

Volume: o app do engine-sim passa o som por um nivelador (alvo 30000 de pico,
ganho máximo 1,9). Aqui o mesmo ganho é aplicado, mas constante no loop todo
(no app ele bombeia). info.csv tem o nível cru em dB de cada loop pra quem
quiser recuperar a diferença real entre on e off.
"""
import argparse
import csv
import glob
import os
import struct
import subprocess
import sys
import tempfile
from multiprocessing import Pool

import numpy as np

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRAVAR = os.path.join(RAIZ, "tools", "engine_sim_dyno", "build", "gravar")
FS = 44100
ALVO_PICO, GANHO_MAX = 30000.0, 1.9  # nivelador do engine-sim (synthesizer.h)


def zeros_subindo(x, a, b):
    a, b = max(1, a), min(len(x), b)
    i = np.nonzero((x[a - 1:b - 1] < 0) & (x[a:b] >= 0))[0] + a
    return i


def cortar(x, rpm, dur=2.0):
    """Devolve (inicio, fim, ciclos, nota da emenda). Loop = x[inicio:fim]."""
    T = 120.0 / rpm * FS                       # um ciclo de 720° em amostras
    n = max(1, int(round(dur * FS / T)))
    L = n * T
    w = 96                                     # ~2 ms de cada lado da emenda
    ini0 = int(0.2 * FS)
    melhor = None
    for s in zeros_subindo(x, ini0, ini0 + int(T) + 1):
        alvo = s + L
        tol = max(T / 8, 40)
        for e in zeros_subindo(x, int(alvo - tol), int(alvo + tol) + 1):
            if e + w >= len(x):
                continue
            # emenda: o que vem antes do fim tem que parecer o que vem antes do
            # começo, e o que vem depois do começo, o que viria depois do fim
            a = np.concatenate([x[e - w:e], x[s:s + w]])
            b = np.concatenate([x[s - w:s], x[e:e + w]]) if s >= w else None
            if b is None:
                continue
            nota = float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9))
            if melhor is None or nota > melhor[3]:
                melhor = (int(s), int(e), n, nota)
    return melhor


def wav16(nome, a):
    dados = a.astype("<i2").tobytes()
    n = len(a)
    # smpl: 1 loop para frente de 0 até a última amostra
    smpl = struct.pack("<9I", 0, 0, int(1e9 / FS), 60, 0, 0, 0, 1, 0)
    smpl += struct.pack("<6I", 0, 0, 0, n - 1, 0, 0)
    fmt = struct.pack("<HHIIHH", 1, 1, FS, FS * 2, 2, 16)
    corpo = (b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt
             + b"data" + struct.pack("<I", len(dados)) + dados
             + b"smpl" + struct.pack("<I", len(smpl)) + smpl)
    with open(nome, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(corpo)) + corpo)


def processar(mr, saida, passo):
    nome = os.path.splitext(os.path.basename(mr))[0]
    tmp = tempfile.mkdtemp(prefix="loops_")  # f32 crus, apagados no fim
    r = subprocess.run([GRAVAR, mr, tmp, str(passo), "1000"], capture_output=True, text=True)
    if r.returncode != 0:
        return nome, "ERRO: " + r.stdout[-500:]
    medido = {}
    for linha in r.stdout.split("\n"):
        p = linha.split()
        if len(p) == 4 and p[0] in ("lenta", "on", "off"):
            medido["lenta" if p[0] == "lenta" else "%s_%04d" % (p[0], int(p[1]))] = float(p[2])
    pasta = os.path.join(saida, nome)
    os.makedirs(pasta, exist_ok=True)
    linhas = []
    for f in sorted(glob.glob(os.path.join(tmp, "*.f32"))):
        chave = os.path.splitext(os.path.basename(f))[0]
        x = np.fromfile(f, np.float32).astype(np.float64)
        rpm = medido[chave]
        if rpm < 300:  # apagou
            linhas.append(dict(arquivo=chave + ".wav (APAGOU)", rpm_medido=round(rpm), segundos=0, ciclos=0,
                               ganho=0, nivel_cru_db=0, emenda_corr=0, emenda_salto=0, ruido_pct=0))
            os.remove(f)
            continue
        s, e, ciclos, nota = cortar(x, rpm)
        loop = x[s:e]
        pico = np.abs(loop).max()
        ganho = min(GANHO_MAX, ALVO_PICO / pico)
        y = np.clip(np.round(loop * ganho), -32768, 32767)
        wav16(os.path.join(pasta, chave + ".wav"), y)
        # salto na emenda comparado com o passo típico entre amostras
        salto = abs(y[0] - y[-1]) / (np.median(np.abs(np.diff(y))) + 1e-9)
        # ruído = energia fora dos múltiplos da frequência do ciclo (720°): o
        # que não se repete de um ciclo pro outro (motor irregular). Na lenta
        # o rpm não fica preso e varia, então lá a conta não vale (~90%)
        # (±1 faixa da FFT: num som muito "tonal", como o V8 com coletor 180°,
        # o pico cai entre duas faixas e sem a folga dava ~100% num loop limpo)
        X = np.abs(np.fft.rfft(loop)) ** 2
        perto = np.zeros(len(X), bool)
        for d in (-1, 0, 1):
            j = np.arange(0, len(X), ciclos) + d
            perto[j[(j >= 0) & (j < len(X))]] = True
        ruido = 100 * (1 - X[perto].sum() / X.sum())
        linhas.append(dict(arquivo=chave + ".wav", rpm_medido=round(rpm), segundos=round(len(y) / FS, 3),
                           ciclos=ciclos, ganho=round(ganho, 6), nivel_cru_db=round(20 * np.log10(pico), 1),
                           emenda_corr=round(nota, 3), emenda_salto=round(salto, 2),
                           ruido_pct=round(ruido, 1)))
        os.remove(f)
    os.rmdir(tmp)
    with open(os.path.join(pasta, "info.csv"), "w", newline="") as fo:
        w = csv.DictWriter(fo, fieldnames=list(linhas[0]))
        w.writeheader()
        w.writerows(linhas)
    bons = [l for l in linhas if l["ciclos"]]
    piores = min(l["emenda_corr"] for l in bons)
    msg = "%d loops, pior emenda corr %.3f" % (len(bons), piores)
    if len(bons) < len(linhas):
        msg += ", APAGOU: " + " ".join(l["arquivo"] for l in linhas if not l["ciclos"])
    return nome, msg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("motores", nargs="*", help="prefixo do arquivo (ex. 08); vazio = todos")
    ap.add_argument("--passo", type=int, default=500)
    ap.add_argument("--saida", default=os.path.join(RAIZ, "som", "loops"))
    ap.add_argument("-j", type=int, default=4)
    a = ap.parse_args()
    mrs = sorted(glob.glob(os.path.join(RAIZ, "som", "engine_sim", "*.mr")))
    if a.motores:
        mrs = [m for m in mrs if any(os.path.basename(m).startswith(p) for p in a.motores)]
    if not os.path.exists(GRAVAR):
        sys.exit("falta compilar: bash tools/engine_sim_dyno/preparar.sh")
    with Pool(a.j) as pool:
        for nome, msg in pool.starmap(processar, [(m, a.saida, a.passo) for m in mrs]):
            print(nome, msg, flush=True)


if __name__ == "__main__":
    main()
