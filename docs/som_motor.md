# Som do motor (melhoria nossa)

O jogo tem só 3 bancos de som de motor (02/03/04, XMLs 00002/00004/00005)
repetidos nos 12 buggies: o Mosquito soa igual ao Kraken V8. O plano é o
Matheus montar cada motor no Engine Simulator (ange-yaghi/engine-sim),
gravar loops e o remake tocar com crossfade + pitch pelo rpm.

## Física x motor de verdade

No jogo os 12 buggies giram igual: marcha lenta 1000, limitador 8000
(buggy_base.xml, Engine). A curva de torque é a mesma em todos (pico
~5000 rpm); só a escala muda (HP da ficha = Drive_torque x 250, 0x1f5e90).
Opção (b), combinada: o 1000-8000 do jogo é esticado pra faixa real de
cada motor (marcha lenta -> limitador).

## Motor por buggy (proposta)

Base = o que o Matheus achou; nome interno = LongName do data/vehicles.xml
(dado do jogo, pesa mais). HP e massa de fábrica saem do remake (car.gd).
"Escolha nossa" = sem fonte, pra variar o som.

| Carro | Nome interno | Base (Matheus) | HP / kg | Motor proposto | Fonte | Partir de (engine-sim) | Faixa real |
|---|---|---|---|---|---|---|---|
| Mosquito (01) | Manx | Chenowth Desert Buggy | 144 / 900 | VW boxer 4 a ar, 2.0 L | Meyers Manx = VW 1600 a ar [5]; DPV da Chenowth = VW 2.0 a ar [1] | atg-video-1/06_subaru_ej25 (boxer 4), menor | 900-5500 |
| Inferno (02) | Inferno | Sand Rail V8 | 198 / 1100 | V8 small-block carburado (~350) | sand rail V8 [7] | chevrolet/chev_truck_454, menor | 750-6000 |
| Trident (03) | Snake | Jimco Buggy | 196 / 1150 | GM Ecotec 2.4 4 em linha | Jimco Class 10 = Ecotec 4 cil [3] | atg-video-2/05_honda_vtec | 900-7000 |
| Sphinx (04) | Pre Runner | Chenowth Racing Buggy | 180 / 1200 | VW Type 1 preparado 2180 cc | Chenowth Magnum com VW Type I 2180 cc [2]; faixa de um 2276: 1800-6500 [9] | 06_subaru_ej25 com escape desigual | 900-6500 |
| Bulldog (05) | Carlos | Funco Sand Rail | 280 / 1000 | GM LS V8 (alternativa: V6, escolha nossa) | Funco = V8 LS [4] | atg-video-2/07_gm_ls (ou 04_60_degree_v6) | 800-6500 |
| Phantom (06) | Baja Challenge | Jimco Unlimited Buggy | 297 / 1100 | Subaru EJ25 boxer (turbo) | carros Baja Challenge = Subaru EJ25 [6]; limitador 6500 [10] | atg-video-2/02_subaru_ej25_uh (pronto) | 800-6500 |
| Kraken V8 (07) | Unlimited V8 | V8 Sand Rail | 363 / 1250 | Chevy 454 big-block | nome interno; sand rail V8 [7] | chevrolet/chev_truck_454 (pronto) | 700-5500 |
| McKenzies (08) | McKenzies | McKenzie's Racing Buggy | 405 / 1350 | GM LS V8 | sand car moderno = LS [7] | 07_gm_ls (pronto) | 800-6600 |
| Viper (09) | Higman | (sem base) | 334 / 1150 | V10 tipo Dodge Viper (escolha nossa, pelo nome) | nada achado sobre Higman | atg-video-2/10_lfa_v10, maior e mais lento | 700-6000 |
| Renegade (10) | Caddy | Unlimited personalizado | 441 / 1200 | Cadillac Northstar 4.6 V8 DOHC | "Caddy"; Northstar era o preferido dos sand cars caros antes do LS [8] | 07_gm_ls (cruzado) com 4 válvulas e giro alto | 700-7000 |
| Hurricane (11) | Bruck | Unlimited personalizado | 604 / 1600 | LS7 7.0 V8 bravo (escolha nossa: o mais forte e pesado) | Funco GTQ: LS7 440 com compressor [4] | 07_gm_ls, maior | 800-7000 |
| Storm (12) | Lancia | Unlimited personalizado | 417 / 1050 | Lancia Delta S4 1.8 4 em linha (turbo + compressor) | Delta S4 [11] | 05_honda_vtec, 1.76 L | 1000-8400 |

Motores que já vêm no engine-sim (assets/engines): Honda TRX520,
Kohler CH750, Harley Shovelhead, Hayabusa, Honda VTEC, Subaru EJ25 (normal,
escape igual e desigual), Audi 5 cil, radiais, 2JZ, V6 60°, V6 ímpar e par,
GM LS, Ferrari F136 V8, LFA V10, Merlin V12, Ferrari 412 T2, BMW M52B28,
Chevy 454 de caminhão. Não tem VW a ar: sai do EJ25 (também boxer 4).
Não achei se o engine-sim simula turbo ou compressor.

## Motor por truck (out/2026)

Carro real reconhecido no modelo 3D do jogo (carroceria renderizada de 4
lados + texturas; o jogo não tem descrição nem logo, fora a Silverado
resgatada). Onde a base é um trophy truck sem marca, o motor é escolha nossa,
variando a família pra não soarem iguais. HP = o de fábrica do jogo
(Drive_torque x 250 com as peças de fábrica do vehicles.xml). Os de "turbo de
mentira" passam do que um aspirado daquele tamanho dá (o engine-sim não tem
sobrealimentação: energia do combustível maior faz o papel).

| Truck | Carro real (base) | Certeza | HP / kg | Motor | Por quê |
|---|---|---|---|---|---|
| Buccaneer (01) | Jeep Wrangler YJ (faróis quadrados) | alta | 272 / 1700 | AMC 4.6 stroker 6 em linha | o 4.0 do Jeep com o virabrequim do 4.2, preparação clássica |
| Shockwave (02) | SUV 2 portas anos 80 (Bronco II / S-10 Blazer) | média-baixa | 270 / 1800 | Ford 4.0 SOHC V6 60° | troca comum no Bronco II; V6 60° (o Bulldog é 90°) |
| Shinto (03) | Chevrolet C10/K10 "quadradona" 1981-87 | alta | 255 / 1500 | Chevy 350 carburado, escape único | o da C10 |
| Jericho (04) | Ford F-150 SuperCab 1997-2003 (ou Tundra) | média | 288 / 1600 | Ford 5.4 Triton SOHC V8 | o da F-150 |
| Punisher (05) | trophy truck sem marca | - | 504 / 1800 | Ford 351 Windsor, carburador | escolha nossa |
| Panther (06) | truggy de tubo | - | 510 / 1700 | GM LS V8 com coletor custom (.mr feito à mão) | escolhido pelo Matheus de ouvido (nov/2026); o som do jogo dele (TRUCK1_06) é V8 cruzado |
| Herbst Truggy (07) | "Landshark" da Terrible Herbst (Smithbuilt, 1995) | alta | 540 / 2000 | Ford 460 big-block | o real era Ford V8 (cilindrada não achada) |
| Herbst TT (08) | Ford F-150 Trophy Truck da Terrible Herbst | alta | 638 / 2200 | Ford 427 Windsor (Roush) | Ford V8 de trophy truck |
| Hammerhead (09) | trophy truck (frente lembra Silverado 99-02) | baixa | 504 / 1800 | Dodge 360 Magnum | escolha nossa (Mopar) |
| Fireball (10) | Ford F-100 1953-56 | alta | 551 / 1500 | Ford 292 Y-block com compressor (turbo de mentira) | o Y-block saía com compressor Paxton de fábrica em 1957; ordem 1-5-4-8-6-3-7-2 |
| Goliath (11) | trophy truck sem marca | - | 698 / 1900 | Chevy 572 big-block | escolha nossa, o mais forte |
| Chimera (12) | Mitsubishi Pajero Evolution (Dakar) | média-alta | 695 / 1750 | Mitsubishi 6G74 3.5 V6 60° (turbo de mentira) | o do Pajero |
| Silverado (bônus) | Chevrolet Silverado 2003-06 (logo na textura) | certa | 288 / 1600 | Chevy 5.3 Vortec LM7 | o de fábrica dá 285 cv |

Os .mr saem do tools/gerar_motores.py (t01..t13), os loops vão pra
som/loops/tNN_* e o tocador acha pela id (o bônus pela entrada "som" do
main.gd). O som do motor vale nos trucks mesmo com as outras melhorias
desligadas neles.

## Gravação (Matheus)

- Uma pasta por carro, `som/buggy_NN/`, com `on_<rpm>.ogg` (acelerando,
  com carga) e `off_<rpm>.ogg` (soltando), rpm REAL no nome.
- A cada 500 rpm da marcha lenta ao limitador, loops de 1-2 s cortados no
  zero da onda (sem estalo na volta). O dinamômetro do engine-sim segura o
  rpm.
- `som/buggy_NN/motor.json` com a faixa real: `{"lenta": 900, "limitador": 5500}`.

## Fontes

1. Desert Patrol Vehicle: https://en.wikipedia.org/wiki/Desert_Patrol_Vehicle
2. Chenowth Magnum com VW Type I 2180 cc: https://www.qsl.net/xe2wcg/Pub3/index.html
3. Jimco Class 10 da Hatch Racing (Ecotec 2.4): https://shop.jimcorace.com/pages/hatch-racing-spec-tt-class-10
4. Funco GTQ LS7 com compressor: https://www.offroadxtreme.com/news/video-funco-gtq-is-an-ls7-powered-sand-monster/
5. Meyers Manx 1968 (VW 1600): https://barrett-jackson.com/Archive/Event/Item/1968-MEYERS-MANX-DUNE-BUGGY-244531
6. Baja Challenge = Subaru EJ25: https://subarudrive.com/articles/baja-buggies-under-the-hood-dp-16-3-oe
7. Sand rails com LS: https://www.lsxmag.com/?p=103618
8. Northstar nos sand cars: https://www.drivingline.com/articles/3-hi-performance-tips-for-building-the-cadillac-northstar-v8-gms-32-valve-swap-sandrail-and-kit-car-champ/
9. VW Type 1 2276 (faixa 1800-6500): https://www.speedsterowners.com/topic/newly-built-turnkey-2276-type-1-engine-for-sale
10. Subaru EJ25 (limitador 6500, ordem 1-3-2-4): https://thinktuning.com/subaru-ej25-engine/
11. Lancia Delta S4: https://en.wikipedia.org/wiki/Lancia_Delta_S4
12. engine-sim: https://github.com/ange-yaghi/engine-sim

## Tocador no Godot (motor_som.gd)

- Pasta pelo id: BUGGY_07 -> `som/loops/07_*`. Um AudioStreamPlayer por loop
  (sem posição 3D), só os que têm peso tocam (no máximo 4).
- rpm real = lenta gravada + (rpm do jogo - 1000) / 7000 x (último on - lenta).
- Camada acelerando = on_RRRR; camada soltando = off_RRRR + lenta.wav (no rpm
  medido dela). Em cada uma, os 2 loops vizinhos do rpm real com pitch =
  rpm / rpm gravado e crossfade de potência constante.
- Mistura das camadas pela carga do motor (car.gd som_carga = acelerador x
  limitador x embreagem na troca), suavizada em 30 ms: no limitador o som
  pipoca junto.
- O rpm que vai pro som passa por um filtro de 80 ms (RPM_SUAVE): com a roda
  patinando na 1ª a física do jogo leva o rpm de 6300 a 7900 e de volta umas
  6 vezes por segundo, e o tom tremendo junto soava como ruído (Mosquito).
- Loops com ruido_pct > 20 no info.csv ficam de fora (o off_4000 do Phantom:
  53%, o motor fica irregular ali e o engine-sim repete igual toda vez). Na
  lenta o rpm não fica preso, então o ruido_pct dela (~90%) não vale.
- Volume: nível cru (info.csv) comprimido, K_RPM = 0.5 entre giros e
  K_OFF = 0.5 entre soltando e acelerando, piso de -12 dB.
- Conferência: tests/teste_som.gd (pesos, tom, lenta). Prévia com áudio:
  tests/gravar_som.gd no Movie Maker do Godot.

