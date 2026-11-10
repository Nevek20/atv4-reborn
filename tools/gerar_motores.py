"""Gera os 12 scripts .mr do Engine Simulator (ATG), um por buggy.

    python tools/gerar_motores.py            -> som/engine_sim/*.mr

Cada .mr é independente (cola no assets/ do engine-sim e carrega com o
main.mr). O script confere a geometria antes de escrever: o PMS de cada
cilindro sai do virabrequim e do ângulo da bancada do mesmo jeito que o
engine-sim calcula (crankshaft.cpp / cylinder_bank.cpp):

    PMS no ciclo = tdc + pino - bancada - 90   (mod 360)

e a ordem de ignição tem que bater com esses PMS. Se não bater, para.
Os comandos (lobos) saem do mesmo ângulo de ignição, igual aos exemplos
do engine-sim: admissão = ign + 360 + centro, escape = ign + 360 - centro.
"""
import itertools
import math
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAIDA = os.path.join(RAIZ, "som", "engine_sim")

# forma das curvas de fluxo do cabeçote (fração do pico, 0..600 thou de 50 em 50),
# tirada do cabeçote EJ25 do engine-sim
FORMA_ADM = [0, .206, .367, .555, .762, .886, .954, .996, .996, 1, 1, 1, 1]
FORMA_ESC = [0, .150, .293, .459, .650, .797, .902, .955, .996, 1, 1, 1, 1]


# ---------------------------------------------------------------- geometria

def pms(tdc, pino, bancada):
    return (tdc + pino - bancada - 90) % 360


def ignicoes(m):
    """Ângulo de ignição de cada cilindro (0..720) seguindo a ordem de ignição."""
    ang = {}
    ant = None
    for n in m["ordem"]:
        c = m["cil"][n]
        base = pms(m["tdc"], m["pinos"][c["pino"]], m["bancadas"][c["b"]][0])
        if ant is None:
            # o 1º da ordem dispara em 0: o tdc tem que deixar ele em 0
            if abs(base) > 1e-6 and abs(base - 360) > 1e-6:
                return None
            v = 0.0
        else:
            v = base
            while v <= ant + 1e-6:
                v += 360
        ang[n] = v
        ant = v
    if ant >= 720 - 1e-6:
        return None
    return ang


def intervalos(m, ang):
    seq = [ang[n] for n in m["ordem"]] + [720.0]
    return [round(b - a, 3) for a, b in zip(seq, seq[1:])]


def procurar_pinos(m, passo, quer):
    """Acha os ângulos dos pinos (permutação de k*passo, 1º pino em 0) que dão
    os intervalos de ignição pedidos (lista ou conjunto aceito)."""
    npinos = len(m["pinos"])
    opcoes = [i * passo for i in range(npinos)]
    lados = [m["bancadas"]]
    if m.get("tdc_auto"):
        # o lado de cada bancada depende da marca: tenta as duas
        lados.append([(-b, f) for b, f in m["bancadas"]])
    for m["bancadas"], perm in itertools.product(lados, itertools.permutations(opcoes[1:])):
        m["pinos"] = [0] + list(perm)
        if m.get("tdc_auto"):
            # tdc que põe o 1º da ordem no PMS de ignição em 0
            c = m["cil"][m["ordem"][0]]
            m["tdc"] = (m["bancadas"][c["b"]][0] + 90 - m["pinos"][c["pino"]]) % 360
        ang = ignicoes(m)
        if ang is None:
            continue
        iv = intervalos(m, ang)
        if all(round(x) in quer for x in iv):
            return
    sys.exit("%s: nenhum virabrequim bate com a ordem de ignição" % m["arq"])


def pinos_da_ignicao(m, intervalo):
    """Virabrequim de pino próprio por cilindro (V6 90° com pino defasado):
    o pino sai do ângulo de ignição que a gente quer."""
    m["pinos"] = []
    for k, n in enumerate(m["ordem"]):
        c = m["cil"][n]
        alvo = k * intervalo
        b = m["bancadas"][c["b"]][0]
        m["pinos"].append((alvo - m["tdc"] + b + 90) % 360)
        c["pino"] = k


# ---------------------------------------------------------------- motores
# ordem dos campos: pinos = ângulo de cada moente; cil = n -> bancada, pino,
# admissão, escape, primário (pol). Medidas em mm, pol (in), thou, cc.

def cil(b, pino, esc=0, prim=0.0, adm=0):
    return {"b": b, "pino": pino, "esc": esc, "prim": prim, "adm": adm}


BUGGY = dict(massa=1100, area_frente=(70, 60), cx=0.45, pneu=15.0, atrito=300)
# trucks: massa de fábrica do jogo (truck_NN.xml + peças) e pneu maior
TRUCK = dict(BUGGY, area_frente=(80, 72), cx=0.5, pneu=17.0, atrito=400)
# marchas na proporção do Renegade no save state (18.2/11.9/8.9/7.1/5.9)
MARCHAS = [18.2 / 5.9, 11.9 / 5.9, 8.9 / 5.9, 7.1 / 5.9, 1.0]


def boxer4(pinos):
    """Boxer 4 (VW ou Subaru). Bancada 0 = +90, bancada 1 = -90, tdc 180.
    Cilindros opostos chegam juntos no PMS."""
    return dict(tdc=180, bancadas=[(90, True), (-90, False)], pinos=pinos)


MOTORES = []

# 1. Mosquito (Manx): VW Tipo 4 2.0 a ar, dois carburadores, 900-5500
MOTORES.append(dict(
    arq="01_mosquito_vw_tipo4_2000", no="vw_type4_2000", nome="VW Tipo 4 2.0 [Boxer 4, ar]",
    buggy="Mosquito (Manx)", cv=144, lenta=900, corte=5500,
    **boxer4([0, 180, 180, 0]),
    # VW: 1-2 na bancada direita, 3-4 na esquerda, ordem 1-4-3-2
    cil={1: cil(0, 0, 0, 6), 2: cil(0, 1, 0, 14), 3: cil(1, 2, 0, 6, 1), 4: cil(1, 3, 0, 14, 1)},
    ordem=[1, 4, 3, 2],
    diam=94.0, curso=71.0, biela=128.0, alt_comp=1.0, cr=8.8,
    massa_biela=520, massa_pistao=480, massa_vira=8.0, massa_volante=6.0, raio_volante=5.5,
    atrito_vira=3.0,
    fluxo=(150, 112), dutos=(1.25, 1.1), lift_scale=1.0,
    adm=dict(dur=214, gamma=1.6, lift=420), esc=dict(dur=214, gamma=1.6, lift=420),
    centros=(110, 110), raio_base=0.55,
    admissoes=[dict(fluxo=300, runner=110, runner_len=6.0, lenta=0.9978, plenum=0.6, decay=0.5)] * 2,
    escapes=[dict(saida=1000, prim_len=14, prim_fluxo=400, compr=60, vol=6.0, ir="mild_exhaust_0")],
    avanco=[(0, 10), (1000, 10), (2000, 22), (3000, 30), (4000, 32), (6000, 32)],
    combustivel=dict(mte=2.0, mbe=0.8), jitter=0.6, freq=20000, limitador=0.12,
    partida=(60, 300), embreagem=180,
))

# 2. Inferno: small-block Chevy 305 carburado, 750-6000 (som de 454 menor)
MOTORES.append(dict(
    arq="02_inferno_sbc_305", no="sbc_305", nome="Chevrolet 305 [V8, carb]",
    buggy="Inferno", cv=198, lenta=750, corte=6000,
    tdc=45, bancadas=[(-45, False), (45, True)],
    pinos=[0, 270, 90, 180],  # mesmo virabrequim do 454/LS do engine-sim
    cil={1: cil(0, 0, 0, 16), 3: cil(0, 1, 0, 12), 5: cil(0, 2, 0, 8), 7: cil(0, 3, 0, 4),
         2: cil(1, 0, 1, 16), 4: cil(1, 1, 1, 12), 6: cil(1, 2, 1, 8), 8: cil(1, 3, 1, 4)},
    ordem=[1, 8, 4, 3, 6, 5, 7, 2],
    diam=3.736 * 25.4, curso=3.48 * 25.4, biela=5.7 * 25.4, alt_comp=1.56, cr=9.0,
    massa_biela=600, massa_pistao=560, massa_vira=22.0, massa_volante=13.0, raio_volante=7.0,
    atrito_vira=8.0,
    fluxo=(185, 140), dutos=(1.75, 1.5), lift_scale=1.0,
    adm=dict(dur=200, gamma=0.8, lift=420), esc=dict(dur=208, gamma=0.8, lift=440),
    centros=(110, 114), raio_base=0.6,
    admissoes=[dict(fluxo=600, runner=160, runner_len=8.0, lenta=0.9925, plenum=1.5, decay=0.5)],
    escapes=[dict(saida=550, prim_len=12, prim_fluxo=120, compr=180, vol=5.0, ir="default_0"),
             dict(saida=550, prim_len=12, prim_fluxo=120, compr=230, vol=5.0, ir="default_0")],
    avanco=[(0, 12), (1000, 12), (2000, 20), (3000, 30), (4000, 36), (6000, 36)],
    combustivel=dict(mte=3.0, mbe=0.85), jitter=0.5, freq=10000, limitador=0.15,
    partida=(200, 200), embreagem=330,
))

# 3. Trident (Snake): GM Ecotec 2.4 DOHC 16v, 900-7000 (som de Honda VTEC)
MOTORES.append(dict(
    arq="03_trident_ecotec_24", no="ecotec_24", nome="GM Ecotec 2.4 [I4, DOHC]",
    buggy="Trident (Snake)", cv=196, lenta=900, corte=7000,
    tdc=90, bancadas=[(0, False)], pinos=[0, 180, 180, 0],
    # coletor 4-1 de corrida, primários iguais e quase sem silencioso
    # (minimal_muffling_02), escolhido pelo Matheus de ouvido. Com 4-2-1 e o
    # silencioso mild o som saía 80-100% numa frequência só (apito); com
    # primários de tamanhos diferentes virava o batidão de Fusca
    cil={1: cil(0, 0, 0, 14), 2: cil(0, 1, 0, 14), 3: cil(0, 2, 0, 14), 4: cil(0, 3, 0, 14)},
    ordem=[1, 3, 4, 2],
    diam=88.0, curso=98.0, biela=145.5, alt_comp=1.1, cr=10.4,
    massa_biela=560, massa_pistao=420, massa_vira=14.0, massa_volante=7.0, raio_volante=5.5,
    atrito_vira=2.0,
    fluxo=(235, 175), dutos=(1.4, 1.25), lift_scale=1.0,
    adm=dict(dur=226, gamma=1.0, lift=420), esc=dict(dur=222, gamma=1.0, lift=400),
    centros=(112, 114), raio_base=0.65,
    admissoes=[dict(fluxo=750, runner=240, runner_len=9.0, lenta=0.9984, plenum=1.3, decay=0.5)],
    escapes=[dict(saida=1000, prim_len=14, prim_fluxo=220, compr=50, vol=6.0, ir="minimal_muffling_02")],
    avanco=[(0, 15), (1000, 15), (2000, 25), (3000, 34), (4000, 38), (7000, 38)],
    combustivel=dict(mte=2.5, mbe=0.8), jitter=0.3, freq=20000, limitador=0.06,
    partida=(70, 400), embreagem=230,
))

# 4. Sphinx (Pre Runner): VW Tipo 1 2180 cc preparado, dois Weber, escape desigual
MOTORES.append(dict(
    arq="04_sphinx_vw_tipo1_2180", no="vw_type1_2180", nome="VW Tipo 1 2180 [Boxer 4, ar, preparado]",
    buggy="Sphinx (Pre Runner)", cv=180, lenta=900, corte=6500,
    **boxer4([0, 180, 180, 0]),
    # primários bem diferentes num escape só = o ronco desigual do EJ25 UH
    cil={1: cil(0, 0, 0, 2.0), 2: cil(0, 1, 0, 3.0), 3: cil(1, 2, 0, 19.7, 1), 4: cil(1, 3, 0, 21.7, 1)},
    ordem=[1, 4, 3, 2],
    diam=92.0, curso=82.0, biela=136.0, alt_comp=1.0, cr=9.0,  # 137,16 explode no engine-sim
    massa_biela=560, massa_pistao=500, massa_vira=9.0, massa_volante=5.0, raio_volante=5.5,
    atrito_vira=2.5,
    fluxo=(175, 130), dutos=(1.5, 1.3), lift_scale=1.0,
    adm=dict(dur=240, gamma=1.4, lift=480), esc=dict(dur=244, gamma=1.4, lift=480),
    centros=(108, 112), raio_base=0.55,
    admissoes=[dict(fluxo=420, runner=150, runner_len=7.0, lenta=0.9975, plenum=0.5, decay=0.5)] * 2,
    escapes=[dict(saida=1000, prim_len=24, prim_fluxo=400, compr=500 / 25.4, vol=0.01,
                  ir="minimal_muffling_02")],
    avanco=[(0, 12), (1000, 12), (2000, 24), (3000, 32), (4000, 34), (6500, 34)],
    combustivel=dict(mte=2.5, mbe=0.85), jitter=0.5, freq=20000, limitador=0.12,
    partida=(70, 400), embreagem=220,
))

# 5. Bulldog (Carlos): GM 4.3 LV3 V6 90° (família LS, pino defasado, ignição a cada 120°)
MOTORES.append(dict(
    arq="05_bulldog_gm_lv3_43_v6", no="gm_lv3_v6", nome="GM 4.3 LV3 [V6 90, familia LS]",
    buggy="Bulldog (Carlos)", cv=280, lenta=800, corte=6500,
    tdc=45, bancadas=[(-45, False), (45, True)], pinos=None, intervalo=120,
    cil={1: cil(0, 0, 0, 10), 3: cil(0, 0, 0, 6), 5: cil(0, 0, 0, 2),
         2: cil(1, 0, 1, 10), 4: cil(1, 0, 1, 6), 6: cil(1, 0, 1, 2)},
    ordem=[1, 6, 5, 4, 3, 2],
    diam=99.6, curso=92.0, biela=6.098 * 25.4, alt_comp=1.3, cr=11.0,
    massa_biela=550, massa_pistao=400, massa_vira=20.0, massa_volante=12.0, raio_volante=7.0,
    atrito_vira=6.0,
    fluxo=(255, 190), dutos=(2.0, 1.6), lift_scale=1.0,
    adm=dict(dur=208, gamma=1.1, lift=500), esc=dict(dur=212, gamma=1.1, lift=500),
    centros=(116, 116), raio_base=1.0,
    admissoes=[dict(fluxo=650, runner=180, runner_len=12.0, lenta=0.9955, plenum=1.2, decay=0.5)],
    escapes=[dict(saida=1000, prim_len=26, prim_fluxo=450, compr=100, vol=4.0, ir="default_0"),
             dict(saida=1000, prim_len=26, prim_fluxo=450, compr=150, vol=4.0, ir="default_0")],
    avanco=[(0, 12), (1000, 12), (2000, 20), (3000, 30), (4000, 38), (6500, 38)],
    combustivel=dict(mte=2.0, mbe=1.0, chama=True), jitter=0.5, freq=15000, limitador=0.15,
    partida=(150, 250), embreagem=350,
))

# 6. Phantom (Baja Challenge): Subaru EJ25, coletor igual (EJ25 EH do engine-sim)
MOTORES.append(dict(
    arq="06_phantom_subaru_ej25", no="subaru_ej25", nome="Subaru EJ25 [Boxer 4]",
    buggy="Phantom (Baja Challenge)", cv=297, lenta=800, corte=6500,
    **boxer4([0, 180, 0, 180]),  # igual ao exemplo EJ25 do engine-sim
    cil={1: cil(0, 0, 0, 0), 3: cil(0, 3, 0, 0), 2: cil(1, 1, 1, 0, 0), 4: cil(1, 2, 1, 0, 0)},
    ordem=[1, 3, 2, 4],
    diam=99.5, curso=79.0, biela=5.142 * 25.4, alt_comp=1.0, cr=11.0,
    massa_biela=535, massa_pistao=566, massa_vira=9.39, massa_volante=6.8, raio_volante=6.0,
    atrito_vira=1.0,
    fluxo=(295, 255), dutos=(1.45, 1.3), lift_scale=1.0,
    adm=dict(dur=256, gamma=1.4, lift=460), esc=dict(dur=256, gamma=1.4, lift=450),
    centros=(108, 110), raio_base=34.0 / 2 / 25.4,
    admissoes=[dict(fluxo=900, runner=270, runner_len=12.0, lenta=0.9985, plenum=1.325, decay=0.5)],
    escapes=[dict(saida=1000, prim_len=10, prim_fluxo=500, compr=None, vol=0.5 * 8, ir="mild_exhaust_0",
                  volume_l=100),
             dict(saida=1000, prim_len=10, prim_fluxo=500, compr=None, vol=1.0 * 8, ir="mild_exhaust_0",
                  volume_l=100)],
    avanco=[(0, 15), (1000, 15), (2000, 23.3), (3000, 31.7), (4000, 40), (5000, 40), (6000, 40), (7000, 40)],
    # o EJ25 de 297 cv é o turbo (STI): turbo de mentira, ver "energia" no montar
    combustivel=dict(mte=2.5, mbe=0.8, energia=48.1), jitter=0.5, freq=20000, limitador=0.08,
    partida=(70, 500), embreagem=300,
))

# 7. Kraken V8 (Unlimited V8): Chevy 454 big-block com comando forte, 700-5500
MOTORES.append(dict(
    arq="07_kraken_chevy_454", no="chevy_454", nome="Chevrolet 454 [V8 big-block]",
    buggy="Kraken V8 (Unlimited V8)", cv=363, lenta=700, corte=5500,
    tdc=45, bancadas=[(-45, False), (45, True)], pinos=[0, 270, 90, 180],
    cil={1: cil(0, 0, 0, 16), 3: cil(0, 1, 0, 12), 5: cil(0, 2, 0, 8), 7: cil(0, 3, 0, 4),
         2: cil(1, 0, 1, 16), 4: cil(1, 1, 1, 12), 6: cil(1, 2, 1, 8), 8: cil(1, 3, 1, 4)},
    ordem=[1, 8, 4, 3, 6, 5, 7, 2],
    diam=4.25 * 25.4, curso=4.0 * 25.4, biela=6.135 * 25.4, alt_comp=1.64, cr=9.5,
    massa_biela=850, massa_pistao=750, massa_vira=27.0, massa_volante=14.0, raio_volante=7.0,
    atrito_vira=10.0,
    fluxo=(270, 195), dutos=(2.1, 1.75), lift_scale=1.0,
    adm=dict(dur=224, gamma=0.8, lift=500), esc=dict(dur=230, gamma=0.8, lift=510),
    centros=(110, 114), raio_base=0.6,
    admissoes=[dict(fluxo=850, runner=220, runner_len=8.0, lenta=0.9915, plenum=2.0, decay=0.5)],
    escapes=[dict(saida=1200, prim_len=30, prim_fluxo=400, compr=180 + 72, vol=5.5, ir="default_0"),
             dict(saida=1200, prim_len=30, prim_fluxo=400, compr=180, vol=5.5, ir="default_0")],
    avanco=[(0, 12), (1000, 12), (2000, 20), (3000, 30), (4000, 36), (6000, 36)],
    combustivel=dict(mte=3.0, mbe=0.85), jitter=0.5, freq=10000, limitador=0.2,
    partida=(200, 200), embreagem=550,
))

# 8. McKenzies: GM LS6 5.7 (405 cv de fábrica no Z06), 800-6600
MOTORES.append(dict(
    arq="08_mckenzies_gm_ls6", no="gm_ls6", nome="GM LS6 5.7 [V8]",
    buggy="McKenzies", cv=405, lenta=800, corte=6600,
    tdc=45, bancadas=[(-45, False), (45, True)], pinos=[0, 270, 90, 180],
    cil={1: cil(0, 0, 0, 3 * 2 + 0.8), 3: cil(0, 1, 0, 2 * 2 + 0.4), 5: cil(0, 2, 0, 2 + 1.2), 7: cil(0, 3, 0, 2.0),
         2: cil(1, 0, 1, 3 * 2 + 0.4), 4: cil(1, 1, 1, 2 * 2 + 2.0), 6: cil(1, 2, 1, 2 + 2.8), 8: cil(1, 3, 1, 0)},
    ordem=[1, 8, 7, 2, 6, 5, 4, 3],
    diam=99.0, curso=92.0, biela=6.098 * 25.4, alt_comp=1.3, cr=10.5,
    massa_biela=600, massa_pistao=450, massa_vira=22.0, massa_volante=13.0, raio_volante=8.0,
    atrito_vira=15.0,
    fluxo=(285, 205), dutos=(2.2, 1.75), lift_scale=1.0,
    adm=dict(dur=204, gamma=1.1, lift=551), esc=dict(dur=211, gamma=1.1, lift=547),
    centros=(116.5, 116.5), raio_base=1.0,
    admissoes=[dict(fluxo=800, runner=150, runner_len=12.0, lenta=0.996, plenum=1.325, decay=0.5)],
    escapes=[dict(saida=1000, prim_len=29, prim_fluxo=500, compr=100, vol=4.0, ir="default_0"),
             dict(saida=1000, prim_len=29, prim_fluxo=500, compr=172, vol=4.0, ir="default_0")],
    avanco=[(0, 12), (1000, 12), (2000, 20), (3000, 30), (4000, 40), (8000, 40)],
    combustivel=dict(mte=2.0, mbe=1.0, chama=True), jitter=0.6, freq=10000, limitador=0.2,
    partida=(200, 200), embreagem=500,
))

# 9. Viper (Higman): V10 tipo Dodge Viper 8.0, 90°, pino comum = ignição desigual 90/54
MOTORES.append(dict(
    arq="09_viper_v10_80", no="viper_v10", nome="Viper 8.0 [V10 90, ignicao desigual]",
    buggy="Viper (Higman)", cv=334, lenta=700, corte=6000,
    tdc=45, bancadas=[(-45, False), (45, True)], pinos=[0, 0, 0, 0, 0], passo_pino=72,
    intervalos_ok={54, 90},
    cil={1: cil(0, 0, 0, 5), 3: cil(0, 1, 0, 4), 5: cil(0, 2, 0, 3), 7: cil(0, 3, 0, 2), 9: cil(0, 4, 0, 1),
         2: cil(1, 0, 1, 5), 4: cil(1, 1, 1, 4), 6: cil(1, 2, 1, 3), 8: cil(1, 3, 1, 2), 10: cil(1, 4, 1, 1)},
    ordem=[1, 10, 9, 4, 3, 6, 5, 8, 7, 2],
    diam=4.00 * 25.4, curso=3.88 * 25.4, biela=6.124 * 25.4, alt_comp=1.3, cr=9.6,
    massa_biela=650, massa_pistao=520, massa_vira=30.0, massa_volante=14.0, raio_volante=7.5,
    atrito_vira=14.0,
    fluxo=(255, 190), dutos=(2.0, 1.75), lift_scale=1.0,
    adm=dict(dur=212, gamma=1.0, lift=490), esc=dict(dur=218, gamma=1.0, lift=490),
    centros=(114, 114), raio_base=0.9,
    admissoes=[dict(fluxo=1000, runner=200, runner_len=10.0, lenta=0.9955, plenum=2.0, decay=0.5)],
    # filtro real_engine_2, escolhido pelo Matheus de ouvido. O mild_exhaust tem
    # 75% da energia entre 100 e 250 Hz (pico de +11.5 dB em 133 Hz): de 4000 a
    # 4500 rpm o som virava um zumbido grave, 90% num tom só e o dobro do volume
    escapes=[dict(saida=1500, prim_len=30, prim_fluxo=600, compr=100, vol=2.0, ir="real_engine_2"),
             dict(saida=1500, prim_len=30, prim_fluxo=600, compr=100.5, vol=2.0, ir="real_engine_2")],
    avanco=[(0, 12), (1000, 12), (2000, 22), (3000, 30), (4000, 36), (6000, 36)],
    combustivel=dict(mte=3.0, mbe=0.9), jitter=0.3, freq=8000, limitador=0.12,
    partida=(200, 200), embreagem=650,
))

# 10. Renegade (Caddy): Cadillac Northstar 4.6 DOHC 32v, 700-7000 (som de LS)
MOTORES.append(dict(
    arq="10_renegade_northstar_46", no="northstar_46", nome="Cadillac Northstar 4.6 [V8, DOHC]",
    buggy="Renegade (Caddy)", cv=441, lenta=700, corte=7000,
    # bancada ímpar do outro lado (senão o 2 não dispara 90° depois do 1)
    tdc=135, bancadas=[(45, False), (-45, True)], pinos=[0, 0, 0, 0], passo_pino=90,
    intervalos_ok={90},
    cil={1: cil(0, 0, 0, 6.8), 3: cil(0, 1, 0, 4.4), 5: cil(0, 2, 0, 3.2), 7: cil(0, 3, 0, 2.0),
         2: cil(1, 0, 1, 6.4), 4: cil(1, 1, 1, 6.0), 6: cil(1, 2, 1, 4.8), 8: cil(1, 3, 1, 0)},
    ordem=[1, 2, 7, 3, 4, 5, 6, 8],
    diam=93.0, curso=84.0, biela=155.0, alt_comp=1.2, cr=10.5,
    massa_biela=520, massa_pistao=380, massa_vira=20.0, massa_volante=11.0, raio_volante=7.5,
    atrito_vira=10.0,
    fluxo=(290, 220), dutos=(2.0, 1.7), lift_scale=1.0,
    adm=dict(dur=236, gamma=1.0, lift=420), esc=dict(dur=232, gamma=1.0, lift=410),
    centros=(110, 112), raio_base=0.65,
    admissoes=[dict(fluxo=1000, runner=220, runner_len=10.0, lenta=0.9965, plenum=1.5, decay=0.5)],
    escapes=[dict(saida=1200, prim_len=29, prim_fluxo=500, compr=100, vol=4.0, ir="default_0"),
             dict(saida=1200, prim_len=29, prim_fluxo=500, compr=172, vol=4.0, ir="default_0")],
    avanco=[(0, 12), (1000, 12), (2000, 22), (3000, 32), (4000, 40), (8000, 40)],
    combustivel=dict(mte=2.0, mbe=1.0, chama=True), jitter=0.4, freq=10000, limitador=0.1,
    partida=(150, 250), embreagem=450,
))

# 11. Hurricane (Bruck): LS7 7.0 bravo (comando grande, cabeçote trabalhado), 800-7000
MOTORES.append(dict(
    arq="11_hurricane_gm_ls7", no="gm_ls7_bravo", nome="GM LS7 7.0 [V8, bravo]",
    buggy="Hurricane (Bruck)", cv=604, lenta=800, corte=7000,
    tdc=45, bancadas=[(-45, False), (45, True)], pinos=[0, 270, 90, 180],
    cil={1: cil(0, 0, 0, 6.8), 3: cil(0, 1, 0, 4.4), 5: cil(0, 2, 0, 3.2), 7: cil(0, 3, 0, 2.0),
         2: cil(1, 0, 1, 6.4), 4: cil(1, 1, 1, 6.0), 6: cil(1, 2, 1, 4.8), 8: cil(1, 3, 1, 0)},
    ordem=[1, 8, 7, 2, 6, 5, 4, 3],
    diam=104.8, curso=101.6, biela=6.067 * 25.4, alt_comp=1.175, cr=11.5,
    massa_biela=480, massa_pistao=450, massa_vira=23.0, massa_volante=11.0, raio_volante=8.0,
    atrito_vira=18.0,
    fluxo=(375, 270), dutos=(2.4, 1.9), lift_scale=1.0,
    adm=dict(dur=242, gamma=1.0, lift=640), esc=dict(dur=250, gamma=1.0, lift=640),
    centros=(110, 114), raio_base=1.0,
    admissoes=[dict(fluxo=1300, runner=260, runner_len=11.0, lenta=0.9945, plenum=1.8, decay=0.5)],
    escapes=[dict(saida=1600, prim_len=30, prim_fluxo=650, compr=90, vol=4.5, ir="default_0"),
             dict(saida=1600, prim_len=30, prim_fluxo=650, compr=150, vol=4.5, ir="default_0")],
    avanco=[(0, 14), (1000, 14), (2000, 22), (3000, 30), (4000, 34), (8000, 34)],
    combustivel=dict(mte=2.0, mbe=1.0, chama=True), jitter=0.7, freq=10000, limitador=0.15,
    partida=(200, 200), embreagem=750,
))

# 12. Storm (Lancia): Lancia Delta S4 1.8 16v, 1000-8400 (som de Honda VTEC, bravo de rali)
MOTORES.append(dict(
    arq="12_storm_lancia_delta_s4", no="lancia_s4", nome="Lancia Delta S4 1.8 [I4, rali]",
    buggy="Storm (Lancia)", cv=417, lenta=1000, corte=8400,
    tdc=90, bancadas=[(0, False)], pinos=[0, 180, 180, 0],
    cil={1: cil(0, 0, 0, 3), 2: cil(0, 1, 1, 3), 3: cil(0, 2, 1, 3), 4: cil(0, 3, 0, 3)},
    ordem=[1, 3, 4, 2],
    diam=88.5, curso=71.5, biela=133.0, alt_comp=1.0, cr=11.0,
    massa_biela=450, massa_pistao=330, massa_vira=11.0, massa_volante=4.0, raio_volante=5.0,
    atrito_vira=1.5,
    fluxo=(270, 205), dutos=(1.55, 1.35), lift_scale=1.0,
    adm=dict(dur=248, gamma=1.0, lift=440), esc=dict(dur=244, gamma=1.0, lift=420),
    centros=(108, 110), raio_base=0.65,
    admissoes=[dict(fluxo=750, runner=240, runner_len=9.0, lenta=0.998, plenum=1.3, decay=0.5)],
    escapes=[dict(saida=1200, prim_len=14, prim_fluxo=400, compr=60, vol=6.0, ir="mild_exhaust_0"),
             dict(saida=1200, prim_len=14, prim_fluxo=400, compr=61, vol=8.0, ir="mild_exhaust_0")],
    # avanço demais em alta (40°) derruba a potência no engine-sim; 34° no máximo
    avanco=[(0, 12), (1000, 12), (2000, 19.3), (3000, 26.7), (4000, 34), (5000, 34), (6000, 34),
            (7000, 34), (8000, 34), (9000, 34)],
    # o S4 de verdade era turbo + compressor: turbo de mentira, ver "energia" no montar
    combustivel=dict(mte=2.5, mbe=0.85, energia=48.1), jitter=0.2, freq=20000, limitador=0.05,
    partida=(70, 500), embreagem=260,
))


# ---------------------------------------------------------------- trucks
# Um motor por truck (docs/som_motor.md, Trucks): o do carro real quando a
# base foi reconhecida no modelo 3D, escolha nossa (variando a família) nos
# trophy trucks sem marca. cv = HP de fábrica do jogo (Drive_torque x 250 com
# as peças de fábrica, truck_NN.xml); massa = a de fábrica do jogo.

def ford_v8(prim):
    """Ford: 1-4 na bancada direita, 5-8 na esquerda; pinos (1,5) (2,6) (3,7)
    (4,8). O virabrequim (cruzado, 90°) sai da ordem de ignição."""
    return dict(bancadas=[(-45, False), (45, True)], pinos=[0, 0, 0, 0], passo_pino=90,
                intervalos_ok={90}, tdc_auto=True,
                cil={1: cil(0, 0, 0, prim[0]), 2: cil(0, 1, 0, prim[1]), 3: cil(0, 2, 0, prim[2]),
                     4: cil(0, 3, 0, prim[3]), 5: cil(1, 0, 1, prim[0]), 6: cil(1, 1, 1, prim[1]),
                     7: cil(1, 2, 1, prim[2]), 8: cil(1, 3, 1, prim[3])})


def gm_v8(prim, um_escape=False):
    """Chevy/Mopar: ímpares numa bancada, pares na outra, pinos (1,2) (3,4)
    (5,6) (7,8): o mesmo virabrequim do 454/LS do engine-sim."""
    e = 0 if um_escape else 1
    return dict(tdc=45, bancadas=[(-45, False), (45, True)], pinos=[0, 270, 90, 180],
                cil={1: cil(0, 0, 0, prim[0]), 3: cil(0, 1, 0, prim[1]), 5: cil(0, 2, 0, prim[2]),
                     7: cil(0, 3, 0, prim[3]), 2: cil(1, 0, e, prim[0]), 4: cil(1, 1, e, prim[1]),
                     6: cil(1, 2, e, prim[2]), 8: cil(1, 3, e, prim[3])})


def i6(prim, escapes=(0, 0, 0, 0, 0, 0)):
    """6 em linha, ordem 1-5-3-6-2-4: pinos (1,6) 0°, (2,5) 120°, (3,4) 240°."""
    return dict(tdc=90, bancadas=[(0, False)], pinos=[0, 120, 240, 240, 120, 0],
                cil={n: cil(0, n - 1, escapes[n - 1], prim[n - 1]) for n in range(1, 7)},
                ordem=[1, 5, 3, 6, 2, 4])


def v6_60(lado_a, lado_b, prim):
    """V6 60° de ignição a cada 120° (pino próprio por cilindro, como os
    virabrequins de 6 moentes)."""
    c = {}
    for n in lado_a:
        c[n] = cil(0, 0, 0, prim)
    for n in lado_b:
        c[n] = cil(1, 0, 1, prim)
    return dict(tdc=90, bancadas=[(-30, False), (30, True)], pinos=None, intervalo=120, cil=c)


def caminhao(kg):
    return dict(TRUCK, massa=kg)


# t01 Buccaneer (Jeep Wrangler YJ): AMC 4.6 stroker (o 4.0 com o virabrequim do 4.2)
MOTORES.append(dict(
    arq="t01_buccaneer_amc_46_i6", no="amc_46_stroker", nome="AMC 4.6 stroker [I6]",
    buggy="Buccaneer (Jeep Wrangler YJ)", cv=272, lenta=700, corte=5500,
    **i6([20, 18, 16, 16, 18, 20]),
    diam=98.4, curso=99.0, biela=149.2, alt_comp=1.4, cr=9.6,
    massa_biela=640, massa_pistao=520, massa_vira=27.0, massa_volante=12.0, raio_volante=6.5,
    atrito_vira=8.0,
    fluxo=(230, 175), dutos=(1.6, 1.4), lift_scale=1.0,
    adm=dict(dur=212, gamma=1.1, lift=470), esc=dict(dur=218, gamma=1.1, lift=470),
    centros=(112, 114), raio_base=0.75,
    admissoes=[dict(fluxo=650, runner=200, runner_len=14.0, lenta=0.996, plenum=1.5, decay=0.5)],
    escapes=[dict(saida=900, prim_len=20, prim_fluxo=350, compr=110, vol=4.0, ir="real_engine_0")],
    avanco=[(0, 10), (1000, 10), (2000, 20), (3000, 28), (4000, 32), (6000, 32)],
    combustivel=dict(mte=2.5, mbe=0.85), jitter=0.4, freq=14000, limitador=0.12,
    partida=(150, 250), embreagem=350, veiculo=caminhao(1700),
))

# t02 Shockwave (Bronco II / S-10 Blazer): Ford 4.0 SOHC Cologne V6 60°
MOTORES.append(dict(
    arq="t02_shockwave_ford_40_v6", no="ford_40_sohc", nome="Ford 4.0 SOHC [V6 60]",
    buggy="Shockwave (Bronco II)", cv=270, lenta=750, corte=6200,
    ordem=[1, 4, 2, 5, 3, 6], **v6_60([1, 2, 3], [4, 5, 6], 18),
    diam=100.4, curso=84.4, biela=143.0, alt_comp=1.2, cr=9.7,
    massa_biela=560, massa_pistao=450, massa_vira=18.0, massa_volante=10.0, raio_volante=6.0,
    atrito_vira=5.0,
    fluxo=(235, 180), dutos=(1.6, 1.4), lift_scale=1.0,
    adm=dict(dur=220, gamma=1.0, lift=440), esc=dict(dur=224, gamma=1.0, lift=440),
    centros=(112, 112), raio_base=0.7,
    admissoes=[dict(fluxo=700, runner=220, runner_len=12.0, lenta=0.996, plenum=1.2, decay=0.5)],
    escapes=[dict(saida=1000, prim_len=18, prim_fluxo=350, compr=90, vol=0.4, ir="minimal_muffling_01"),
             dict(saida=1000, prim_len=18, prim_fluxo=350, compr=110, vol=0.4, ir="minimal_muffling_01")],
    avanco=[(0, 12), (1000, 12), (2000, 22), (3000, 30), (4000, 34), (7000, 34)],
    combustivel=dict(mte=2.5, mbe=0.85), jitter=0.4, freq=16000, limitador=0.1,
    partida=(120, 300), embreagem=330, veiculo=caminhao(1800),
))

# t03 Shinto (Chevrolet C10 1981-87): Chevy 350 carburado, escape único de picape
MOTORES.append(dict(
    arq="t03_shinto_chevy_350", no="chevy_350_c10", nome="Chevrolet 350 [V8, carb, C10]",
    buggy="Shinto (Chevrolet C10)", cv=255, lenta=650, corte=5500,
    ordem=[1, 8, 4, 3, 6, 5, 7, 2], **gm_v8([16, 12, 8, 4], um_escape=True),
    diam=4.00 * 25.4, curso=3.48 * 25.4, biela=5.7 * 25.4, alt_comp=1.56, cr=8.5,
    massa_biela=600, massa_pistao=580, massa_vira=23.0, massa_volante=14.0, raio_volante=7.0,
    atrito_vira=9.0,
    fluxo=(190, 140), dutos=(1.75, 1.5), lift_scale=1.0,
    adm=dict(dur=196, gamma=0.8, lift=410), esc=dict(dur=204, gamma=0.8, lift=420),
    centros=(112, 116), raio_base=0.6,
    admissoes=[dict(fluxo=600, runner=160, runner_len=7.0, lenta=0.992, plenum=1.5, decay=0.5)],
    # as duas bancadas num cano só (Y): batida irregular de picape de série
    escapes=[dict(saida=500, prim_len=14, prim_fluxo=110, compr=150, vol=5.0, ir="default_0")],
    avanco=[(0, 8), (1000, 8), (2000, 18), (3000, 28), (4000, 34), (6000, 34)],
    combustivel=dict(mte=3.0, mbe=0.85), jitter=0.5, freq=10000, limitador=0.2,
    partida=(200, 200), embreagem=380, veiculo=caminhao(1500),
))

# t04 Jericho (Ford F-150 1997-2003): Ford 5.4 Triton SOHC 2 válvulas (modular)
MOTORES.append(dict(
    arq="t04_jericho_ford_54", no="ford_54_triton", nome="Ford 5.4 Triton [V8, SOHC]",
    buggy="Jericho (Ford F-150)", cv=288, lenta=650, corte=5500,
    ordem=[1, 3, 7, 2, 6, 5, 4, 8], **ford_v8([12, 9, 6, 3]),
    diam=90.2, curso=105.8, biela=169.1, alt_comp=1.1, cr=9.0,
    massa_biela=620, massa_pistao=520, massa_vira=26.0, massa_volante=13.0, raio_volante=7.0,
    atrito_vira=10.0,
    fluxo=(200, 150), dutos=(1.7, 1.5), lift_scale=1.0,
    adm=dict(dur=200, gamma=1.1, lift=400), esc=dict(dur=206, gamma=1.1, lift=400),
    centros=(116, 116), raio_base=0.65,
    admissoes=[dict(fluxo=650, runner=170, runner_len=16.0, lenta=0.994, plenum=2.0, decay=0.5)],
    escapes=[dict(saida=800, prim_len=24, prim_fluxo=300, compr=120, vol=4.0, ir="real_engine_1"),
             dict(saida=800, prim_len=24, prim_fluxo=300, compr=150, vol=4.0, ir="real_engine_1")],
    avanco=[(0, 10), (1000, 10), (2000, 20), (3000, 30), (4000, 36), (6000, 36)],
    combustivel=dict(mte=2.5, mbe=0.9), jitter=0.4, freq=10000, limitador=0.15,
    partida=(200, 200), embreagem=420, veiculo=caminhao(1600),
))

# t05 Punisher (trophy truck): Ford 351 Windsor de carburador, headers abertos
MOTORES.append(dict(
    arq="t05_punisher_ford_351w", no="ford_351w", nome="Ford 351 Windsor [V8, carb]",
    buggy="Punisher (trophy truck)", cv=504, lenta=800, corte=6500,
    ordem=[1, 3, 7, 2, 6, 5, 4, 8], **ford_v8([30, 28, 26, 24]),
    diam=4.00 * 25.4, curso=3.50 * 25.4, biela=5.956 * 25.4, alt_comp=1.6, cr=10.5,
    massa_biela=650, massa_pistao=560, massa_vira=24.0, massa_volante=11.0, raio_volante=7.0,
    atrito_vira=12.0,
    fluxo=(270, 200), dutos=(2.0, 1.75), lift_scale=1.0,
    adm=dict(dur=236, gamma=0.9, lift=560), esc=dict(dur=244, gamma=0.9, lift=570),
    centros=(108, 112), raio_base=0.7,
    admissoes=[dict(fluxo=900, runner=240, runner_len=8.0, lenta=0.994, plenum=1.6, decay=0.5)],
    escapes=[dict(saida=1400, prim_len=32, prim_fluxo=550, compr=60, vol=0.4, ir="minimal_muffling_03"),
             dict(saida=1400, prim_len=32, prim_fluxo=550, compr=62, vol=0.4, ir="minimal_muffling_03")],
    avanco=[(0, 14), (1000, 14), (2000, 24), (3000, 32), (4000, 34), (7000, 34)],
    combustivel=dict(mte=3.0, mbe=0.9), jitter=0.6, freq=10000, limitador=0.15,
    partida=(200, 200), embreagem=650, veiculo=caminhao(1800),
))

# t06 Panther (truggy): .mr feito à mão (som/engine_sim/t06_panther_gm_ls_custom.mr,
# GM LS com coletor custom que o Matheus achou e escolheu de ouvido, nov/2026).
# Fica fora do gerador: o arquivo usa coisas que o montar() não faz (peso de
# som por cilindro, noise, hf_gain). O 2JZ que estava aqui foi reprovado.

# t07 Herbst Truggy (Landshark da Terrible Herbst): Ford 460 big-block
MOTORES.append(dict(
    arq="t07_herbst_truggy_ford_460", no="ford_460", nome="Ford 460 [V8 big-block]",
    buggy="Herbst Truggy (Landshark)", cv=540, lenta=700, corte=6000,
    ordem=[1, 5, 4, 2, 6, 3, 7, 8], **ford_v8([30, 28, 26, 24]),
    diam=4.36 * 25.4, curso=3.85 * 25.4, biela=6.605 * 25.4, alt_comp=1.7, cr=10.0,
    massa_biela=850, massa_pistao=760, massa_vira=32.0, massa_volante=14.0, raio_volante=7.5,
    atrito_vira=14.0,
    fluxo=(280, 205), dutos=(2.2, 1.85), lift_scale=1.0,
    adm=dict(dur=230, gamma=0.9, lift=560), esc=dict(dur=238, gamma=0.9, lift=570),
    centros=(110, 114), raio_base=0.7,
    admissoes=[dict(fluxo=1000, runner=260, runner_len=9.0, lenta=0.993, plenum=2.2, decay=0.5)],
    escapes=[dict(saida=1300, prim_len=34, prim_fluxo=500, compr=110, vol=4.0, ir="default_0"),
             dict(saida=1300, prim_len=34, prim_fluxo=500, compr=150, vol=4.0, ir="default_0")],
    avanco=[(0, 12), (1000, 12), (2000, 22), (3000, 30), (4000, 34), (7000, 34)],
    combustivel=dict(mte=3.0, mbe=0.9), jitter=0.5, freq=9000, limitador=0.18,
    partida=(250, 200), embreagem=750, veiculo=caminhao(2000),
))

# t08 Herbst TT (Ford F-150 Trophy Truck da Herbst): Ford 427 Windsor (Roush)
MOTORES.append(dict(
    arq="t08_herbst_tt_ford_427w", no="ford_427w", nome="Ford 427 Windsor [V8, Roush]",
    buggy="Herbst TT (Ford F-150 Trophy Truck)", cv=638, lenta=850, corte=7000,
    ordem=[1, 3, 7, 2, 6, 5, 4, 8], **ford_v8([32, 30, 28, 26]),
    diam=4.125 * 25.4, curso=4.00 * 25.4, biela=6.2 * 25.4, alt_comp=1.18, cr=11.0,
    massa_biela=600, massa_pistao=500, massa_vira=25.0, massa_volante=10.0, raio_volante=7.0,
    atrito_vira=14.0,
    fluxo=(330, 240), dutos=(2.3, 1.9), lift_scale=1.0,
    adm=dict(dur=246, gamma=0.9, lift=620), esc=dict(dur=252, gamma=0.9, lift=620),
    centros=(108, 112), raio_base=0.75,
    admissoes=[dict(fluxo=1200, runner=280, runner_len=8.0, lenta=0.994, plenum=1.8, decay=0.5)],
    escapes=[dict(saida=1600, prim_len=34, prim_fluxo=650, compr=70, vol=0.4, ir="minimal_muffling_01"),
             dict(saida=1600, prim_len=34, prim_fluxo=650, compr=72, vol=0.4, ir="minimal_muffling_01")],
    avanco=[(0, 14), (1000, 14), (2000, 24), (3000, 32), (4000, 34), (8000, 34)],
    combustivel=dict(mte=3.0, mbe=0.95), jitter=0.6, freq=10000, limitador=0.15,
    partida=(250, 200), embreagem=850, veiculo=caminhao(2200),
))

# t09 Hammerhead (trophy truck, escolha nossa): Dodge 360 Magnum (Mopar)
MOTORES.append(dict(
    arq="t09_hammerhead_dodge_360", no="dodge_360_magnum", nome="Dodge 360 Magnum [V8]",
    buggy="Hammerhead (trophy truck)", cv=504, lenta=750, corte=6200,
    ordem=[1, 8, 4, 3, 6, 5, 7, 2], **gm_v8([28, 26, 24, 22]),
    diam=4.00 * 25.4, curso=3.58 * 25.4, biela=6.123 * 25.4, alt_comp=1.68, cr=10.5,
    massa_biela=700, massa_pistao=600, massa_vira=26.0, massa_volante=12.0, raio_volante=7.0,
    atrito_vira=12.0,
    fluxo=(270, 200), dutos=(2.0, 1.75), lift_scale=1.0,
    adm=dict(dur=232, gamma=0.9, lift=540), esc=dict(dur=240, gamma=0.9, lift=550),
    centros=(110, 114), raio_base=0.7,
    admissoes=[dict(fluxo=950, runner=240, runner_len=10.0, lenta=0.994, plenum=1.8, decay=0.5)],
    escapes=[dict(saida=1300, prim_len=30, prim_fluxo=500, compr=90, vol=4.0, ir="real_engine_2"),
             dict(saida=1300, prim_len=30, prim_fluxo=500, compr=140, vol=4.0, ir="real_engine_2")],
    avanco=[(0, 12), (1000, 12), (2000, 22), (3000, 30), (4000, 34), (7000, 34)],
    combustivel=dict(mte=3.0, mbe=0.9), jitter=0.5, freq=10000, limitador=0.15,
    partida=(200, 200), embreagem=650, veiculo=caminhao(1800),
))

# t10 Fireball (Ford F-100 1953-56): Ford 292 Y-block com compressor (a Ford
# vendia o Y-block com compressor Paxton de fábrica em 1957). Ordem de ignição
# própria do Y-block, 1-5-4-8-6-3-7-2
MOTORES.append(dict(
    arq="t10_fireball_ford_292_yblock", no="ford_292_yblock", nome="Ford 292 Y-block [V8, compressor]",
    buggy="Fireball (Ford F-100)", cv=551, lenta=650, corte=5800,
    ordem=[1, 5, 4, 8, 6, 3, 7, 2], **ford_v8([20, 18, 16, 14]),
    diam=3.75 * 25.4, curso=3.30 * 25.4, biela=6.24 * 25.4, alt_comp=1.75, cr=8.5,
    massa_biela=650, massa_pistao=600, massa_vira=25.0, massa_volante=15.0, raio_volante=7.5,
    atrito_vira=10.0,
    fluxo=(230, 170), dutos=(1.8, 1.55), lift_scale=1.0,
    adm=dict(dur=220, gamma=0.8, lift=480), esc=dict(dur=226, gamma=0.8, lift=480),
    centros=(112, 114), raio_base=0.6,
    admissoes=[dict(fluxo=800, runner=220, runner_len=8.0, lenta=0.993, plenum=1.5, decay=0.5)],
    escapes=[dict(saida=1000, prim_len=20, prim_fluxo=300, compr=150, vol=4.0, ir="real_engine_0"),
             dict(saida=1000, prim_len=20, prim_fluxo=300, compr=190, vol=4.0, ir="real_engine_0")],
    avanco=[(0, 8), (1000, 8), (2000, 18), (3000, 26), (4000, 30), (6000, 30)],
    combustivel=dict(mte=3.0, mbe=0.85, energia=48.1), jitter=0.6, freq=9000, limitador=0.2,
    partida=(200, 180), embreagem=700, veiculo=caminhao(1500),
))

# t11 Goliath (trophy truck, escolha nossa): Chevy 572 big-block, o mais forte
MOTORES.append(dict(
    arq="t11_goliath_chevy_572", no="chevy_572", nome="Chevrolet 572 [V8 big-block]",
    buggy="Goliath (trophy truck)", cv=698, lenta=750, corte=6500,
    ordem=[1, 8, 4, 3, 6, 5, 7, 2], **gm_v8([34, 32, 30, 28]),
    diam=4.56 * 25.4, curso=4.375 * 25.4, biela=6.535 * 25.4, alt_comp=1.27, cr=10.5,
    massa_biela=900, massa_pistao=700, massa_vira=36.0, massa_volante=14.0, raio_volante=7.5,
    atrito_vira=18.0,
    fluxo=(340, 250), dutos=(2.4, 2.0), lift_scale=1.0,
    adm=dict(dur=244, gamma=0.9, lift=640), esc=dict(dur=252, gamma=0.9, lift=640),
    centros=(108, 112), raio_base=0.75,
    admissoes=[dict(fluxo=1300, runner=300, runner_len=8.0, lenta=0.992, plenum=2.4, decay=0.5)],
    escapes=[dict(saida=1700, prim_len=36, prim_fluxo=700, compr=60, vol=0.4, ir="minimal_muffling_02"),
             dict(saida=1700, prim_len=36, prim_fluxo=700, compr=62, vol=0.4, ir="minimal_muffling_02")],
    avanco=[(0, 14), (1000, 14), (2000, 24), (3000, 32), (4000, 34), (7000, 34)],
    combustivel=dict(mte=3.0, mbe=0.95), jitter=0.6, freq=9000, limitador=0.18,
    partida=(300, 200), embreagem=950, veiculo=caminhao(1900),
))

# t12 Chimera (Mitsubishi Pajero Evolution, Dakar): 3.5 V6 6G74, turbo de mentira
MOTORES.append(dict(
    arq="t12_chimera_mitsubishi_6g74", no="mitsubishi_6g74", nome="Mitsubishi 6G74 3.5 [V6 60, Dakar]",
    buggy="Chimera (Pajero Evolution)", cv=695, lenta=850, corte=7000,
    ordem=[1, 2, 3, 4, 5, 6], **v6_60([1, 3, 5], [2, 4, 6], 14),
    diam=93.0, curso=85.8, biela=152.0, alt_comp=1.1, cr=10.0,
    massa_biela=520, massa_pistao=400, massa_vira=17.0, massa_volante=7.0, raio_volante=5.5,
    atrito_vira=4.0,
    fluxo=(250, 190), dutos=(1.5, 1.35), lift_scale=1.0,
    adm=dict(dur=240, gamma=1.0, lift=420), esc=dict(dur=236, gamma=1.0, lift=410),
    centros=(110, 112), raio_base=0.6,
    admissoes=[dict(fluxo=1000, runner=280, runner_len=8.0, lenta=0.998, plenum=1.6, decay=0.5)],
    escapes=[dict(saida=1300, prim_len=16, prim_fluxo=450, compr=80, vol=4.0, ir="real_engine_1"),
             dict(saida=1300, prim_len=16, prim_fluxo=450, compr=82, vol=4.0, ir="real_engine_1")],
    avanco=[(0, 12), (1000, 12), (2000, 20), (3000, 28), (4000, 32), (8000, 32)],
    combustivel=dict(mte=2.5, mbe=0.85, energia=48.1), jitter=0.3, freq=16000, limitador=0.06,
    partida=(100, 300), embreagem=650, veiculo=caminhao(1750),
))

# t13 Silverado (bônus resgatado, Chevrolet Silverado 2003-06): 5.3 Vortec LM7
MOTORES.append(dict(
    arq="t13_silverado_chevy_53_vortec", no="chevy_53_vortec", nome="Chevrolet 5.3 Vortec LM7 [V8]",
    buggy="Silverado (bonus, Chevrolet Silverado)", cv=288, lenta=650, corte=6000,
    ordem=[1, 8, 7, 2, 6, 5, 4, 3], **gm_v8([20, 16, 12, 8]),
    diam=96.0, curso=92.0, biela=6.098 * 25.4, alt_comp=1.3, cr=9.5,
    massa_biela=650, massa_pistao=480, massa_vira=24.0, massa_volante=13.0, raio_volante=7.5,
    atrito_vira=12.0,
    fluxo=(220, 165), dutos=(2.0, 1.6), lift_scale=1.0,
    adm=dict(dur=190, gamma=1.1, lift=466), esc=dict(dur=191, gamma=1.1, lift=457),
    centros=(116, 116), raio_base=1.0,
    admissoes=[dict(fluxo=700, runner=160, runner_len=14.0, lenta=0.996, plenum=1.6, decay=0.5)],
    escapes=[dict(saida=900, prim_len=26, prim_fluxo=350, compr=130, vol=4.0, ir="default_0"),
             dict(saida=900, prim_len=26, prim_fluxo=350, compr=170, vol=4.0, ir="default_0")],
    avanco=[(0, 12), (1000, 12), (2000, 20), (3000, 30), (4000, 38), (8000, 38)],
    combustivel=dict(mte=2.0, mbe=1.0, chama=True), jitter=0.5, freq=10000, limitador=0.15,
    partida=(200, 200), embreagem=420, veiculo=caminhao(1600),
))

# Ajuste no dinamômetro sem tela (tools/engine_sim_dyno, engine-sim 85f7c3b):
# k_fluxo escala cabeçote + admissão até a potência alvo, a placa da lenta
# acerta a marcha lenta e "energia" é o turbo de mentira (kJ/g, normal 48.1).
# Resultado medido no LEIA-ME de som/engine_sim.
AJUSTE = {
    "01": dict(k_fluxo=2.2872, placa=0.999131),
    "02": dict(k_fluxo=0.8091, placa=0.99433),
    "03": dict(k_fluxo=1.0, placa=0.9984),  # o B que o Matheus escolheu de ouvido (escape 4-1)
    "04": dict(k_fluxo=1.4981, placa=0.99925),
    "05": dict(k_fluxo=0.5751, placa=0.9948),
    "06": dict(k_fluxo=1.5, placa=0.998897, energia=55.32),  # turbo de mentira ~1.15x
    "07": dict(k_fluxo=0.9, placa=0.995972),
    "08": dict(k_fluxo=0.6445, placa=0.99433),
    "09": dict(k_fluxo=0.6366, placa=0.99433),
    "10": dict(k_fluxo=0.6293, placa=0.9966),  # com 0.99688 já apaga
    "11": dict(k_fluxo=0.6302, placa=0.9955),  # comando grande: com 0.99586 já apaga
    "12": dict(k_fluxo=1.5, placa=0.9992, energia=87.21),  # com 0.99937 já apaga;  # turbo de mentira ~1.8x
    # trucks (placa com margem: fechando 0.0001 a mais ainda não apaga)
    "t01": dict(k_fluxo=1.0, placa=0.996908),
    "t02": dict(k_fluxo=1.1063, placa=0.997844),
    "t03": dict(k_fluxo=1.4764, placa=0.996674),
    "t04": dict(k_fluxo=0.807, placa=0.99527),
    "t05": dict(k_fluxo=1.272, placa=0.9964),  # comando grande: lenta ~1180 (com 0.99667 apagava gravando)
    "t07": dict(k_fluxo=1.2495, placa=0.997844),
    "t08": dict(k_fluxo=1.0, placa=0.9956),  # comando grande: lenta ~1300 (com 0.9962 apagava gravando; 0.9958 = 1258)
    "t09": dict(k_fluxo=1.444, placa=0.997376),  # lenta ~1040
    "t10": dict(k_fluxo=1.3, placa=0.99878, energia=78.97),  # compressor de mentira ~1.64x
    "t11": dict(k_fluxo=1.0359, placa=0.997276),
    "t12": dict(k_fluxo=1.3, placa=0.999031, energia=69.55),  # turbo de mentira ~1.45x
    "t13": dict(k_fluxo=0.6217, placa=0.994802),
}


def ajustado(m):
    a = AJUSTE.get(m["arq"].split("_")[0])
    if not a:
        return m
    m = dict(m, k_fluxo=a["k_fluxo"])
    m["admissoes"] = [dict(x, lenta=a["placa"]) for x in m["admissoes"]]
    if "energia" in a:
        m["combustivel"] = dict(m["combustivel"], energia=a["energia"])
    return m


# ---------------------------------------------------------------- escrita

def g(x, casas=4):
    s = ("%." + str(casas) + "f") % x
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s if s not in ("", "-0") else "0"


def montar(m):
    # k_fluxo: escala do fluxo do cabeçote e da admissão, ajustada no
    # dinamômetro (tools/engine_sim_dyno) pra bater a potência alvo
    k = m.get("k_fluxo", 1.0)
    m["fluxo"] = tuple(f * k for f in m["fluxo"])
    m["admissoes"] = [dict(a, fluxo=a["fluxo"] * k, runner=a["runner"] * k) for a in m["admissoes"]]
    if m.get("pinos") is None:
        pinos_da_ignicao(m, m["intervalo"])
    elif "passo_pino" in m:
        procurar_pinos(m, m["passo_pino"], m["intervalos_ok"])
    ang = ignicoes(m)
    if ang is None:
        sys.exit("%s: ordem de ignição não bate com o virabrequim" % m["arq"])
    iv = intervalos(m, ang)
    if len(set(ang.values())) != len(ang):
        sys.exit("%s: dois cilindros disparando junto" % m["arq"])
    m["_ang"], m["_iv"] = ang, iv

    n_cil = len(m["cil"])
    vd_cc = math.pi / 4 * (m["diam"] / 10) ** 2 * (m["curso"] / 10)
    m["_vd"] = vd_cc * n_cil
    camara = vd_cc / (m["cr"] - 1)

    nb = len(m["bancadas"])
    por_banc = [[n for n in sorted(m["cil"]) if m["cil"][n]["b"] == b] for b in range(nb)]
    no = m["no"]

    L = []
    w = L.append
    w('import "engine_sim.mr"')
    w("")
    w("// %s: %s" % (m["buggy"], m["nome"]))
    w("// %.0f cc, taxa %s:1, marcha lenta ~%d rpm, corte %d rpm, alvo ~%d cv" % (
        m["_vd"], g(m["cr"], 1), m["lenta"], m["corte"], m["cv"]))
    w("// ordem de ignicao %s, intervalos %s graus" % (
        "-".join(str(n) for n in m["ordem"]), "/".join(g(x, 1) for x in iv)))
    w("// gerado por tools/gerar_motores.py (mexer la e gerar de novo)")
    w("")
    w("units units()")
    w("constants constants()")
    w("impulse_response_library ir_lib()")
    w("label cycle(2 * 360 * units.deg)")
    w("")
    w("private node wires {")
    for n in sorted(m["cil"]):
        w("    output wire%d: ignition_wire();" % n)
    w("}")
    w("")

    if m["combustivel"].get("chama"):
        w("private node %s_flame_speed {" % no)
        w("    alias output __out:")
        w("        function(5.0)")
        w("            .add_sample(0.0, 3.0)")
        w("            .add_sample(5.0, 1.5 * 5.0)")
        w("            .add_sample(10.0, 1.75 * 10.0)")
        for k in range(15, 50, 5):
            w("            .add_sample(%d.0, 2.0 * %d.0)%s" % (k, k, ";" if k == 45 else ""))
        w("}")
        w("")

    # cabeçote
    fa, fe = m["fluxo"]
    da, de = m["dutos"]
    w("private node %s_head {" % no)
    w("    input intake_camshaft;")
    w("    input exhaust_camshaft;")
    w("    input chamber_volume: %s * units.cc;" % g(camara, 1))
    w("    input intake_runner_volume: 149.6 * units.cc;")
    w("    input intake_runner_cross_section_area: %s * units.inch * %s * units.inch;" % (g(da), g(da)))
    w("    input exhaust_runner_volume: 50.0 * units.cc;")
    w("    input exhaust_runner_cross_section_area: %s * units.inch * %s * units.inch;" % (g(de), g(de)))
    w("")
    w("    input flow_attenuation: 1.0;")
    w("    input lift_scale: %s;" % g(m["lift_scale"]))
    w("    input flip_display: false;")
    w("    alias output __out: head;")
    for nome_f, pico, forma in (("intake_flow", fa, FORMA_ADM), ("exhaust_flow", fe, FORMA_ESC)):
        w("")
        w("    function %s(50 * units.thou)" % nome_f)
        w("    %s" % nome_f)
        for k, f in enumerate(forma):
            w("        .add_flow_sample(%d * lift_scale, %d * flow_attenuation)" % (k * 50, round(pico * f)))
    w("")
    w("    generic_cylinder_head head(")
    w("        chamber_volume: chamber_volume,")
    w("        intake_runner_volume: intake_runner_volume,")
    w("        intake_runner_cross_section_area: intake_runner_cross_section_area,")
    w("        exhaust_runner_volume: exhaust_runner_volume,")
    w("        exhaust_runner_cross_section_area: exhaust_runner_cross_section_area,")
    w("")
    w("        intake_port_flow: intake_flow,")
    w("        exhaust_port_flow: exhaust_flow,")
    w("        valvetrain: standard_valvetrain(")
    w("            intake_camshaft: intake_camshaft,")
    w("            exhaust_camshaft: exhaust_camshaft")
    w("        ),")
    w("        flip_display: flip_display")
    w("    )")
    w("}")
    w("")

    # comando
    w("private node %s_camshaft {" % no)
    w("    input lobe_profile;")
    w("    input intake_lobe_profile: lobe_profile;")
    w("    input exhaust_lobe_profile: lobe_profile;")
    w("    input lobe_separation: 114 * units.deg;")
    w("    input intake_lobe_center: lobe_separation;")
    w("    input exhaust_lobe_center: lobe_separation;")
    w("    input advance: 0 * units.deg;")
    w("    input base_radius: 1.0 * units.inch;")
    w("")
    for b in range(nb):
        w("    output intake_cam_%d: _intake_cam_%d;" % (b, b))
        w("    output exhaust_cam_%d: _exhaust_cam_%d;" % (b, b))
    w("")
    w("    camshaft_parameters params (")
    w("        advance: advance,")
    w("        base_radius: base_radius")
    w("    )")
    w("")
    for b in range(nb):
        w("    camshaft _intake_cam_%d(params, lobe_profile: intake_lobe_profile)" % b)
        w("    camshaft _exhaust_cam_%d(params, lobe_profile: exhaust_lobe_profile)" % b)
    w("")
    w("    label rot360(360 * units.deg)")
    for b in range(nb):
        w("")
        w("    _exhaust_cam_%d" % b)
        for n in por_banc[b]:
            w("        .add_lobe(rot360 - exhaust_lobe_center + %s * units.deg) // %d" % (g(ang[n]), n))
        w("    _intake_cam_%d" % b)
        for n in por_banc[b]:
            w("        .add_lobe(rot360 + intake_lobe_center + %s * units.deg) // %d" % (g(ang[n]), n))
    w("}")
    w("")

    # motor
    cb = m["combustivel"]
    st, ss = m["partida"]
    w("public node %s {" % no)
    w("    alias output __out: engine;")
    w("")
    w("    engine engine(")
    w('        name: "%s",' % m["nome"])
    w("        starter_torque: %d * units.lb_ft," % st)
    w("        starter_speed: %d * units.rpm," % ss)
    w("        redline: %d * units.rpm," % m["corte"])
    w("        fuel: fuel(")
    if cb.get("energia"):
        # "turbo de mentira": o engine-sim não tem sobrealimentação, então mais
        # energia por grama de mistura faz o papel da pressão do turbo
        w("            energy_density: %s * units.kJ / units.g," % g(cb["energia"], 2))
    w("            max_turbulence_effect: %s," % g(cb["mte"]))
    if cb.get("chama"):
        w("            max_burning_efficiency: %s," % g(cb["mbe"]))
        w("            turbulence_to_flame_speed_ratio: %s_flame_speed()" % no)
    else:
        w("            max_burning_efficiency: %s" % g(cb["mbe"]))
    w("        ),")
    w("        throttle_gamma: 2.0,")
    w("        hf_gain: 0.01,")
    w("        noise: 1.0,")
    w("        jitter: %s," % g(m["jitter"]))
    w("        simulation_frequency: %d" % m["freq"])
    w("    )")
    w("")
    w("    wires wires()")
    w("")
    w("    label stroke(%s * units.mm)" % g(m["curso"], 2))
    w("    label bore(%s * units.mm)" % g(m["diam"], 2))
    w("    label rod_length(%s * units.mm)" % g(m["biela"], 2))
    w("    label rod_mass(%d * units.g)" % m["massa_biela"])
    w("    label compression_height(%s * units.inch)" % g(m["alt_comp"], 3))
    w("    label crank_mass(%s * units.kg)" % g(m["massa_vira"], 2))
    w("    label flywheel_mass(%s * units.kg)" % g(m["massa_volante"], 2))
    w("    label flywheel_radius(%s * units.inch)" % g(m["raio_volante"], 2))
    w("")
    w("    label crank_moment(")
    w("        disk_moment_of_inertia(mass: crank_mass, radius: stroke / 2)")
    w("    )")
    w("    label flywheel_moment(")
    w("        disk_moment_of_inertia(mass: flywheel_mass, radius: flywheel_radius)")
    w("    )")
    w("    label other_moment( // comando, polias etc [estimado]")
    w("        disk_moment_of_inertia(mass: 10 * units.kg, radius: 6.0 * units.cm)")
    w("    )")
    w("")
    w("    crankshaft c0(")
    w("        throw: stroke / 2,")
    w("        flywheel_mass: flywheel_mass,")
    w("        mass: crank_mass,")
    w("        friction_torque: %s * units.lb_ft," % g(m["atrito_vira"]))
    w("        moment_of_inertia:")
    w("            crank_moment + flywheel_moment + other_moment,")
    w("        position_x: 0.0,")
    w("        position_y: 0.0,")
    w("        tdc: %s * units.deg" % g(m["tdc"]))
    w("    )")
    w("")
    for k, a in enumerate(m["pinos"]):
        w("    rod_journal rj%d(angle: %s * units.deg)" % (k, g(a)))
    w("    c0")
    for k in range(len(m["pinos"])):
        w("        .add_rod_journal(rj%d)" % k)
    w("")
    w("    piston_parameters piston_params(")
    w("        mass: %d * units.g," % m["massa_pistao"])
    w("        compression_height: compression_height,")
    w("        wrist_pin_position: 0.0,")
    w("        displacement: 0.0")
    w("    )")
    w("")
    w("    connecting_rod_parameters cr_params(")
    w("        mass: rod_mass,")
    w("        moment_of_inertia: rod_moment_of_inertia(")
    w("            mass: rod_mass,")
    w("            length: rod_length")
    w("        ),")
    w("        center_of_mass: 0.0,")
    w("        length: rod_length")
    w("    )")
    w("")
    for k, a in enumerate(m["admissoes"]):
        w("    intake intake%d(" % k)
        w("        plenum_volume: %s * units.L," % g(a["plenum"]))
        w("        plenum_cross_section_area: 20.0 * units.cm2,")
        w("        intake_flow_rate: k_carb(%s)," % g(a["fluxo"]))
        w("        runner_flow_rate: k_carb(%s)," % g(a["runner"]))
        w("        runner_length: %s * units.inch," % g(a["runner_len"]))
        w("        idle_flow_rate: k_carb(0.0),")
        w("        idle_throttle_plate_position: %s, // maior = marcha lenta mais baixa" % g(a["lenta"], 6))
        w("        velocity_decay: %s" % g(a["decay"]))
        w("    )")
        w("")
    for k, e in enumerate(m["escapes"]):
        w("    exhaust_system_parameters es_params%d(" % k)
        w("        outlet_flow_rate: k_carb(%s)," % g(e["saida"]))
        w("        primary_tube_length: %s * units.inch," % g(e["prim_len"]))
        w("        primary_flow_rate: k_carb(%s)," % g(e["prim_fluxo"]))
        if e.get("volume_l"):
            w("        velocity_decay: 1.0,")
            w("        volume: %s * units.L" % g(e["volume_l"]))
        else:
            w("        velocity_decay: 1.0")
        w("    )")
        w("    exhaust_system exhaust%d(" % k)
        w("        es_params%d," % k)
        w("        audio_volume: %s," % g(e["vol"]))
        if e.get("compr"):
            w("        length: %s * units.inch," % g(e["compr"], 2))
        w("        impulse_response: ir_lib.%s" % e["ir"])
        w("    )")
        w("")
    w("    cylinder_bank_parameters bank_params(")
    w("        bore: bore,")
    w("        deck_height: stroke / 2 + rod_length + compression_height")
    w("    )")
    w("")
    for b, (ab, _) in enumerate(m["bancadas"]):
        w("    cylinder_bank b%d(bank_params, angle: %s * units.deg)" % (b, g(ab)))
    for b, (ab, flip) in enumerate(m["bancadas"]):
        w("    b%d" % b)
        for n in por_banc[b]:
            c = m["cil"][n]
            w("        .add_cylinder(")
            w("            piston: piston(piston_params, blowby: k_28inH2O(0.0)),")
            w("            connecting_rod: connecting_rod(cr_params),")
            w("            rod_journal: rj%d," % c["pino"])
            w("            intake: intake%d," % c["adm"])
            w("            exhaust_system: exhaust%d," % c["esc"])
            w("            ignition_wire: wires.wire%d," % n)
            w("            primary_length: %s * units.inch" % g(c["prim"], 2))
            w("        )")
        w("        .set_cylinder_head(")
        w("            %s_head(" % no)
        w("                intake_camshaft: camshaft.intake_cam_%d," % b)
        w("                exhaust_camshaft: camshaft.exhaust_cam_%d," % b)
        w("                flip_display: %s)" % ("true" if flip else "false"))
        w("        )")
    w("")
    w("    engine")
    for b in range(nb):
        w("        .add_cylinder_bank(b%d)" % b)
    w("")
    w("    engine.add_crankshaft(c0)")
    w("")
    for nome_l, l in (("intake_lobe", m["adm"]), ("exhaust_lobe", m["esc"])):
        w("    harmonic_cam_lobe %s(" % nome_l)
        w("        duration_at_50_thou: %s * units.deg," % g(l["dur"]))
        w("        gamma: %s," % g(l["gamma"]))
        w("        lift: %s * units.thou," % g(l["lift"]))
        w("        steps: 100")
        w("    )")
        w("")
    w("    %s_camshaft camshaft(" % no)
    w('        lobe_profile: "N/A",')
    w("")
    w("        intake_lobe_profile: intake_lobe,")
    w("        exhaust_lobe_profile: exhaust_lobe,")
    w("        intake_lobe_center: %s * units.deg," % g(m["centros"][0]))
    w("        exhaust_lobe_center: %s * units.deg," % g(m["centros"][1]))
    w("        base_radius: %s * units.inch" % g(m["raio_base"], 3))
    w("    )")
    w("")
    w("    function timing_curve(1000 * units.rpm)")
    w("    timing_curve")
    for rpm, deg in m["avanco"]:
        w("        .add_sample(%04d * units.rpm, %s * units.deg)" % (rpm, g(deg)))
    w("")
    w("    ignition_module ignition_module(")
    w("        timing_curve: timing_curve,")
    w("        rev_limit: %d * units.rpm," % (m["corte"] + 200))
    w("        limiter_duration: %s)" % g(m["limitador"]))
    w("    ignition_module")
    for n in m["ordem"]:
        w("            .connect_wire(wires.wire%d, %s * units.deg)" % (n, g(ang[n])))
    w("")
    w("    engine.add_ignition_module(ignition_module)")
    w("}")
    w("")

    # buggy e câmbio: relação final dá ~170 km/h na 5ª no corte
    V = dict(m.get("veiculo", BUGGY))
    r_m = V["pneu"] * 0.0254
    final = (m["corte"] / 60 * 2 * math.pi * r_m) / (170 / 3.6)
    lw, lh = V["area_frente"]
    w("private node %s_buggy {" % no)
    w("    alias output __out:")
    w("        vehicle(")
    w("            mass: %d * units.kg," % V["massa"])
    w("            drag_coefficient: %s," % g(V["cx"]))
    w("            cross_sectional_area: (%d * units.inch) * (%d * units.inch)," % (lw, lh))
    w("            diff_ratio: %s," % g(final, 2))
    w("            tire_radius: %s * units.inch," % g(V["pneu"]))
    w("            rolling_resistance: %d * units.N" % V["atrito"])
    w("        );")
    w("}")
    w("")
    w("private node %s_transmission {" % no)
    w("    alias output __out:")
    w("        transmission(")
    w("            max_clutch_torque: %d * units.lb_ft" % m["embreagem"])
    w("        )")
    for k, r in enumerate(MARCHAS):
        w("        .add_gear(%s)%s" % (g(r, 3), ";" if k == len(MARCHAS) - 1 else ""))
    w("}")
    w("")
    w("public node main {")
    w("    run(")
    w("        engine: %s()," % no)
    w("        transmission: %s_transmission()," % no)
    w("        vehicle: %s_buggy()" % no)
    w("    )")
    w("}")
    w("")
    w("main()")
    return "\n".join(L) + "\n"


def main():
    os.makedirs(SAIDA, exist_ok=True)
    for m in MOTORES:
        m = ajustado(m)
        txt = montar(m)
        with open(os.path.join(SAIDA, m["arq"] + ".mr"), "w", encoding="utf-8", newline="\n") as f:
            f.write(txt)
        print("%-30s %5.0f cc  ordem %-22s intervalos %s  pinos %s" % (
            m["arq"], m["_vd"], "-".join(map(str, m["ordem"])),
            "/".join(g(x, 0) for x in m["_iv"]), [g(p) for p in m["pinos"]]))


if __name__ == "__main__":
    main()
