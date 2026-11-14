"""
ia_dados.py
===========
Dados da IA do jogo -> data/ia.json (pista/ia.gd).

Fontes (data/arquivos.tsv):
  Setup/AIPlayers.xml (xml/14833): os 80 pilotos da IA. Cada um tem Skill
    (0.20..1.0), Rivalry (POTENTIAL = carreira normal; o resto é só do modo
    história), Number e as classes que pilota (ATV, Bike, Buggy, Truck).
  Setup/CatchupDatabase.xml (xml/14838): perfis de catchup STD/STDH/STDL_01..10
    (StartDelay, DefaultScale, AIinfront/behind Threshold, Interval, MaxScale).
    Lidos no exe por 0x34cb50 / 0x34d9f0 (as mesmas 8 chaves, nessa ordem).
  Setup/Ai/ctchup_RALLYCROSS.xml (raw/14901+1424): NORMAL = STDH_04,
    EXPERT = STDH_09 (os outros eventos têm o seu ctchup_<EVENTO>.xml).

Uso:
    python tools/ia_dados.py <unpacked>
"""
import json
import os
import re
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def tsv() -> dict:
    out = {}
    for l in open(os.path.join(PROJ, "data", "arquivos.tsv"), encoding="utf-8"):
        if l.startswith("#"):
            continue
        p = l.rstrip("\n").split("\t")
        if len(p) >= 5:
            out[p[0]] = p[4]
    return out


def ler(unp: str, fonte: str) -> str:
    arq, _, off = fonte.partition("+")
    d = open(os.path.join(unp, arq), "rb").read()
    if off:
        d = d[int(off):]
        d = d[:d.find(b"</Root>") + 7]
    return d.decode("latin1")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    unp = sys.argv[1]
    t = tsv()
    pilotos = []
    s = ler(unp, t["Setup/AIPlayers.xml"])
    for m in re.finditer(r'<(\w+) Skill="([\d.]+)" Rivalry="(\w+)" Number="(\d+)"[^>]*>(.*?)</\1>', s, re.S):
        cl = re.findall(r"<(ATV|Bike|Buggy|Truck)/>", m.group(5).split("</Classes>")[0])
        pilotos.append({"nome": m.group(1), "skill": float(m.group(2)), "rivalry": m.group(3),
                        "numero": int(m.group(4)), "classes": cl})
    catchup = {}
    s = ler(unp, t["Setup/CatchupDatabase.xml"])
    for m in re.finditer(r"<(STD\w*_\d+) ([^/>]*)/>", s):
        catchup[m.group(1)] = {k: float(v) for k, v in re.findall(r'(\w+)="([-\d.]+)"', m.group(2))}
    eventos = {}
    for nome, fonte in t.items():
        mm = re.match(r"Setup/Ai/ctchup_(\w+)\.xml$", nome)
        if mm:
            s = ler(unp, fonte)
            eventos[mm.group(1)] = dict(re.findall(r'<(NORMAL|EXPERT) Dataname="(\w+)"', s))
    out = {"fonte": "AIPlayers.xml, CatchupDatabase.xml, Setup/Ai/ctchup_*.xml (tools/ia_dados.py)",
           "pilotos": pilotos, "catchup": catchup, "eventos": eventos}
    dst = os.path.join(PROJ, "data", "ia.json")
    json.dump(out, open(dst, "w", encoding="utf-8", newline="\n"), indent=1, ensure_ascii=False)
    print(f"{len(pilotos)} pilotos, {len(catchup)} perfis de catchup, {len(eventos)} eventos -> {dst}")


if __name__ == "__main__":
    main()
