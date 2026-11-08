extends RefCounted
## Volantes gerados (melhoria nossa, car.gd VOLANTE_NOSSO). O do jogo é parte
## da carroceria: aro de 6 a 12 lados e, em 8 carros, o mesmo X furado girado
## uns 20°. Aqui cada carro ganha um volante redondo e centralizado:
##   - os que eram únicos no jogo (Renegade, Bulldog, Inferno, Storm e 7 dos
##     trucks) e o X furado ganham uma versão melhorada do próprio desenho;
##   - os outros seguem as fotos de volantes que o Matheus mandou (buggy,
##     Sparco de camurça preto e azul, Mountney, kart, aro de espuma, couro e
##     o do Fusca Itamar no Mosquito).
## Tamanho e inclinação são os do volante do jogo (pecas.json: raio e eixo do
## aro, tools/volante.py): o aro fica no mesmo raio, então a IK das mãos do
## piloto não muda. B no jogo troca o estilo.
##
## Montado em volta da origem, no frame do jogo: eixo = normal do aro (pro
## piloto), "cima" = o y do modelo no plano do aro. Ângulo dos raios em graus a
## partir do topo; todos os desenhos são simétricos, então o espelho do carro
## não muda nada.

const SEG := 72                 # segmentos em volta do aro
const LADOS := 14               # lados da seção do aro

# estilo = PADRAO + o que muda. Cores em RGB 0..1; "metal"/"rugo" do material.
const PADRAO := {
	"aro_cor": Color(0.035, 0.035, 0.04), "aro_metal": 0.0, "aro_rugo": 0.9,
	"aro_a": 0.016,              # meia largura da seção do aro (radial), m
	"aro_b": 0.018,              # meia espessura (no eixo)
	"luva": 0.30,                # o aro engrossa 30% onde os raios encostam
	"luva_ang": 0.20,            # largura da luva (rad)
	"luva_cor": null,            # capa de outra cor onde o raio encosta
	"frisos": null,              # 2 frisos (dentro e fora) na frente do aro, cor
	"marca_cor": null,           # marca do topo
	"marca_ang": 0.06,
	"raios": [90, 270, 180],     # 9h, 3h e 6h
	"raio_larg": [0.046, 0.034], # perto do cubo e perto do aro
	"raio_esp": 0.005,
	"raio_forma": "chapa",       # chapa ou tubo (raio_larg = diâmetro)
	"raio_cor": Color(0.85, 0.86, 0.88), "raio_metal": 0.7, "raio_rugo": 0.35,
	"escovado": true,
	"rasgos": [],                # [v, u0, u1, meia largura em m] (u ao longo do raio)
	"furos": [],                 # [u, v, raio em m]
	"furo_borda": null,          # anel em volta do furo (chanfro)
	"rebites": false,
	"dish": 0.035,               # centro recuado pro painel
	"placa": 0.05,               # disco do centro, do material dos raios (0 = sem)
	"cubo": "tampa",             # tampa, parafusos, buzina, losango, fusca, t ou ""
	"cubo_r": 0.045,
	"cubo_cor": Color(0.05, 0.05, 0.055), "cubo_metal": 0.5, "cubo_rugo": 0.35,
	"n_parafusos": 6,
	"parafuso_cor": Color(0.75, 0.76, 0.78),
	"centro": "emblema",         # emblema ou porca (no cubo de parafusos)
	"emblema_cor": null, "emblema_borda": null,
	"botoes": false,             # placa de botões em asa em cima do cubo
	"t_cor": Color(0.82, 0.83, 0.85),   # placa em T do cubo "t"
}

const ESTILOS := {
	# o primeiro (fotos do OMP, do alumínio com rasgos e do buggy de couro)
	"buggy": {
		"marca_cor": Color(0.95, 0.72, 0.05),
		"rasgos": [[0.33, 0.32, 0.80, 0.004], [0.67, 0.32, 0.80, 0.004]],
	},
	# Sparco de camurça: raios pretos com 3 furos, capas cinza, marca cinza, dish fundo
	"sparco_preto": {
		"aro_cor": Color(0.03, 0.03, 0.03), "aro_rugo": 1.0,
		"luva": 0.12, "luva_ang": 0.09, "luva_cor": Color(0.32, 0.32, 0.33),
		"marca_cor": Color(0.45, 0.45, 0.46), "marca_ang": 0.05,
		"raios": [95, 265, 180], "raio_larg": [0.05, 0.036],
		"raio_cor": Color(0.06, 0.06, 0.065), "raio_metal": 0.5, "raio_rugo": 0.3,
		"furos": [[0.40, 0.5, 0.0055], [0.55, 0.5, 0.0055], [0.70, 0.5, 0.0055]],
		"furo_borda": Color(0.8, 0.8, 0.82),
		"dish": 0.06, "placa": 0.055,
		"cubo": "parafusos", "cubo_r": 0.05, "cubo_cor": Color(0.05, 0.05, 0.055),
		"parafuso_cor": Color(0.08, 0.08, 0.09),
		"emblema_cor": Color(0.05, 0.05, 0.05), "emblema_borda": Color(0.9, 0.9, 0.9),
	},
	# Sparco azul do buggy de rali: camurça cinza, marca amarela, placa de botões
	"sparco_azul": {
		"aro_cor": Color(0.07, 0.07, 0.07), "aro_rugo": 1.0, "luva": 0.35,
		"marca_cor": Color(0.9, 0.75, 0.2), "marca_ang": 0.05,
		"raios": [95, 265, 180], "raio_larg": [0.052, 0.04],
		"raio_cor": Color(0.05, 0.45, 0.85), "raio_metal": 0.6, "raio_rugo": 0.35,
		"dish": 0.04, "placa": 0.055,
		"cubo": "parafusos", "cubo_r": 0.05, "cubo_cor": Color(0.05, 0.45, 0.85),
		"cubo_metal": 0.6, "centro": "porca",
		"botoes": true,
	},
	# Mountney do buggy VW: raios polidos com um rasgo, aro de couro, buzina
	"mountney": {
		"aro_cor": Color(0.04, 0.04, 0.04), "aro_rugo": 0.55,
		"aro_a": 0.014, "aro_b": 0.015, "luva": 0.40, "luva_ang": 0.15,
		"raios": [80, 280, 180], "raio_larg": [0.05, 0.034],
		"raio_cor": Color(0.86, 0.87, 0.89), "raio_metal": 0.9, "raio_rugo": 0.18,
		"rasgos": [[0.5, 0.30, 0.72, 0.0065]],
		"dish": 0.03, "placa": 0.055,
		"cubo": "buzina", "cubo_r": 0.05, "cubo_cor": Color(0.86, 0.87, 0.89), "cubo_metal": 0.9,
		"emblema_cor": Color(0.1, 0.35, 0.8), "emblema_borda": Color(0.9, 0.9, 0.92),
	},
	# kart: placa prateada lisa com um furo por raio, aro grosso nos raios, reto
	"kart": {
		"luva": 0.45, "luva_ang": 0.25,
		"raio_larg": [0.06, 0.045], "raio_esp": 0.004,
		"raio_cor": Color(0.75, 0.76, 0.78), "raio_metal": 0.7, "raio_rugo": 0.4,
		"furos": [[0.55, 0.5, 0.009]],
		"dish": 0.0, "placa": 0.06,
		"cubo": "parafusos", "cubo_r": 0.035, "cubo_cor": Color(0.75, 0.76, 0.78),
		"cubo_metal": 0.7,
		"emblema_cor": Color(0.05, 0.05, 0.05),
	},
	# aro de espuma grosso, raios de alumínio com rasgos, cubo de 3 parafusos
	"espuma": {
		"aro_cor": Color(0.045, 0.045, 0.045), "aro_rugo": 1.0,
		"aro_a": 0.02, "aro_b": 0.02, "luva": 0.0,
		"raio_larg": [0.044, 0.032],
		"rasgos": [[0.33, 0.30, 0.78, 0.0035], [0.67, 0.30, 0.78, 0.0035]],
		"dish": 0.03,
		"cubo": "parafusos", "cubo_r": 0.042, "n_parafusos": 3,
		"cubo_cor": Color(0.85, 0.86, 0.88), "cubo_metal": 0.7,
		"parafuso_cor": Color(0.1, 0.1, 0.1), "emblema_cor": Color(0.05, 0.05, 0.05),
	},
	# buggy de couro: raios pretos com um rasgo e tampa cromada
	"couro": {
		"aro_cor": Color(0.03, 0.03, 0.03), "aro_rugo": 0.55, "luva": 0.35,
		"raio_cor": Color(0.06, 0.06, 0.065), "raio_metal": 0.4, "raio_rugo": 0.4,
		"rasgos": [[0.5, 0.32, 0.75, 0.005]],
	},
	# Fusca Itamar (Mosquito): 2 raios largos de plástico e a buzina retangular
	"fusca": {
		"aro_cor": Color(0.04, 0.04, 0.04), "aro_rugo": 0.6,
		"aro_a": 0.019, "aro_b": 0.021, "luva": 0.35, "luva_ang": 0.22,
		"raios": [100, 260], "raio_larg": [0.075, 0.045], "raio_esp": 0.022,
		"raio_cor": Color(0.04, 0.04, 0.04), "raio_metal": 0.0, "raio_rugo": 0.6,
		"escovado": false,
		"dish": 0.012, "placa": 0.0,
		"cubo": "fusca", "cubo_cor": Color(0.045, 0.045, 0.045), "cubo_metal": 0.0, "cubo_rugo": 0.6,
		"emblema_cor": Color(0.1, 0.1, 0.1), "emblema_borda": Color(0.22, 0.22, 0.23),
	},
	# --- versões melhoradas dos volantes do jogo ---
	# os 8 carros do X furado (aro de 6/8 lados prateado, X girado ~20°). O X
	# fica a 45° do topo: as mãos pegam a 65° (piloto.gd PEGA_GRAUS), longe
	# dos raios
	"furado": {
		"aro_cor": Color(0.78, 0.79, 0.8), "aro_metal": 0.9, "aro_rugo": 0.25,
		"aro_a": 0.015, "aro_b": 0.015, "luva": 0.0,
		"raios": [45, 135, 225, 315], "raio_larg": [0.036, 0.036],
		"raio_cor": Color(0.8, 0.81, 0.83),
		"furos": [[0.35, 0.5, 0.0065], [0.55, 0.5, 0.0065], [0.75, 0.5, 0.0065]],
		"dish": 0.02, "placa": 0.0,
	},
	# Renegade: aro preto, barra reta escura e cubo em losango com 4 parafusos
	"renegade": {
		"aro_a": 0.015, "aro_b": 0.016, "luva": 0.15,
		"raios": [90, 270], "raio_larg": [0.028, 0.028], "raio_esp": 0.008,
		"raio_cor": Color(0.12, 0.12, 0.13), "raio_metal": 0.7, "raio_rugo": 0.35,
		"dish": 0.0, "placa": 0.0,
		"cubo": "losango", "cubo_r": 0.05, "cubo_cor": Color(0.72, 0.73, 0.75), "cubo_metal": 0.6,
		"parafuso_cor": Color(0.15, 0.15, 0.16), "emblema_cor": Color(0.6, 0.61, 0.63),
	},
	# Bulldog: tubo prateado e barra larga atravessada
	"bulldog": {
		"aro_cor": Color(0.8, 0.81, 0.82), "aro_metal": 0.9, "aro_rugo": 0.2,
		"aro_a": 0.013, "aro_b": 0.013, "luva": 0.0,
		"raios": [90, 270], "raio_larg": [0.06, 0.06], "raio_esp": 0.006,
		"raio_cor": Color(0.62, 0.63, 0.65), "raio_metal": 0.8, "raio_rugo": 0.3,
		"dish": 0.0, "placa": 0.0,
	},
	# Inferno: aro preto e X de chapa de aço escura com rebites
	"inferno": {
		"luva": 0.0,
		"raios": [45, 135, 225, 315], "raio_larg": [0.042, 0.042], "raio_esp": 0.006,
		"raio_cor": Color(0.2, 0.21, 0.22), "raio_metal": 0.6, "raio_rugo": 0.45,
		"rebites": true, "dish": 0.015, "placa": 0.0,
		"cubo": "parafusos", "cubo_r": 0.032, "n_parafusos": 4,
		"cubo_cor": Color(0.2, 0.21, 0.22), "cubo_metal": 0.6,
		"parafuso_cor": Color(0.55, 0.56, 0.58), "emblema_cor": Color(0.12, 0.12, 0.13),
	},
	# Storm: o mesmo X de aço com o aro de tubo prateado
	"storm": {
		"aro_cor": Color(0.78, 0.79, 0.8), "aro_metal": 0.9, "aro_rugo": 0.25,
		"aro_a": 0.014, "aro_b": 0.014, "luva": 0.0,
		"raios": [45, 135, 225, 315], "raio_larg": [0.042, 0.042], "raio_esp": 0.006,
		"raio_cor": Color(0.2, 0.21, 0.22), "raio_metal": 0.6, "raio_rugo": 0.45,
		"rebites": true, "dish": 0.015, "placa": 0.0,
		"cubo": "parafusos", "cubo_r": 0.032, "n_parafusos": 4,
		"cubo_cor": Color(0.2, 0.21, 0.22), "cubo_metal": 0.6,
		"parafuso_cor": Color(0.55, 0.56, 0.58), "emblema_cor": Color(0.12, 0.12, 0.13),
	},
	# --- trucks: versões melhoradas dos únicos (o desenho do jogo de frente:
	# tools/volante.py + prints_tmp/vol_plano.py, out/2026). Shinto e Panther
	# usam o X furado e TT e Hammerhead o X liso do Storm, iguais aos buggies
	# Buccaneer: aro preto e 3 varões escuros (12h, 4h e 8h), cubo pequeno
	"buccaneer": {
		"aro_a": 0.015, "aro_b": 0.016, "luva": 0.2, "luva_ang": 0.12,
		"raios": [0, 120, 240], "raio_forma": "tubo", "raio_larg": [0.017, 0.012],
		"raio_cor": Color(0.13, 0.13, 0.14), "raio_metal": 0.6, "raio_rugo": 0.4,
		"dish": 0.03, "placa": 0.0,
		"cubo": "parafusos", "cubo_r": 0.03, "n_parafusos": 3,
		"cubo_cor": Color(0.08, 0.08, 0.085), "cubo_metal": 0.4,
		"parafuso_cor": Color(0.5, 0.5, 0.52), "emblema_cor": Color(0.1, 0.1, 0.11),
	},
	# Jericho: aro escuro de 2 frisos, X de lâminas afinando pro aro e chapa
	# quadrada com 4 parafusos
	"jericho": {
		"aro_cor": Color(0.06, 0.06, 0.065), "aro_rugo": 0.7, "aro_a": 0.017, "aro_b": 0.015,
		"luva": 0.0, "frisos": Color(0.5, 0.48, 0.45),
		"raios": [45, 135, 225, 315], "raio_larg": [0.05, 0.013], "raio_esp": 0.005,
		"raio_cor": Color(0.46, 0.44, 0.41), "raio_metal": 0.6, "raio_rugo": 0.4,
		"dish": 0.02, "placa": 0.0,
		"cubo": "losango", "cubo_r": 0.034, "cubo_cor": Color(0.72, 0.73, 0.75), "cubo_metal": 0.6,
		"parafuso_cor": Color(0.15, 0.15, 0.16), "emblema_cor": Color(0.6, 0.61, 0.63),
	},
	# Lazarus (a carroceria original do Jericho): o mesmo desenho com o aro
	# cromado e as lâminas pretas
	"lazarus": {
		"aro_cor": Color(0.78, 0.79, 0.8), "aro_metal": 0.9, "aro_rugo": 0.25,
		"aro_a": 0.016, "aro_b": 0.014, "luva": 0.0, "frisos": Color(0.25, 0.25, 0.27),
		"raios": [45, 135, 225, 315], "raio_larg": [0.042, 0.012], "raio_esp": 0.005,
		"raio_cor": Color(0.09, 0.09, 0.1), "raio_metal": 0.5, "raio_rugo": 0.4,
		"dish": 0.02, "placa": 0.0,
		"cubo": "losango", "cubo_r": 0.03, "cubo_cor": Color(0.1, 0.1, 0.11), "cubo_metal": 0.5,
		"parafuso_cor": Color(0.7, 0.71, 0.73), "emblema_cor": Color(0.75, 0.76, 0.78),
	},
	# Herbst Truggy: o X liso de aço com o aro prateado e a placa em T por cima
	"truggy": {
		"aro_cor": Color(0.78, 0.79, 0.8), "aro_metal": 0.9, "aro_rugo": 0.25,
		"aro_a": 0.014, "aro_b": 0.014, "luva": 0.0,
		"raios": [45, 135, 225, 315], "raio_larg": [0.04, 0.04], "raio_esp": 0.006,
		"raio_cor": Color(0.2, 0.21, 0.22), "raio_metal": 0.6, "raio_rugo": 0.45,
		"rebites": true, "dish": 0.012, "placa": 0.0,
		"cubo": "t", "cubo_r": 0.045, "t_cor": Color(0.82, 0.83, 0.85),
		"parafuso_cor": Color(0.06, 0.06, 0.065),
		"emblema_cor": Color(0.12, 0.12, 0.13), "emblema_borda": Color(0.6, 0.61, 0.63),
	},
	# Fireball (picape antiga): aro grosso preto e 4 tubos cromados, os de
	# cima abertos (no jogo a ~65°; aqui 75° pra não cair na mão, 65°)
	"fireball": {
		"aro_cor": Color(0.04, 0.035, 0.03), "aro_rugo": 0.55, "aro_a": 0.019, "aro_b": 0.019,
		"luva": 0.0,
		"raios": [75, 285, 155, 205], "raio_forma": "tubo", "raio_larg": [0.016, 0.014],
		"raio_cor": Color(0.86, 0.86, 0.88), "raio_metal": 1.0, "raio_rugo": 0.12,
		"dish": 0.045, "placa": 0.0,
		"cubo": "tampa",
	},
	# Goliath: aro preto de 2 frisos e X largo de alumínio com 2 furos
	"goliath": {
		"aro_cor": Color(0.035, 0.035, 0.04), "aro_a": 0.017, "aro_b": 0.015,
		"luva": 0.0, "frisos": Color(0.42, 0.42, 0.44),
		"raios": [45, 135, 225, 315], "raio_larg": [0.056, 0.042], "raio_esp": 0.005,
		"raio_cor": Color(0.78, 0.79, 0.8),
		"furos": [[0.45, 0.5, 0.0085], [0.72, 0.5, 0.0075]],
		"dish": 0.015, "placa": 0.0,
		"cubo": "parafusos", "cubo_r": 0.032, "n_parafusos": 4,
		"cubo_cor": Color(0.78, 0.79, 0.8), "cubo_metal": 0.7,
		"parafuso_cor": Color(0.1, 0.1, 0.11), "emblema_cor": Color(0.08, 0.08, 0.09),
	},
	# Chimera (rali): aro grosso de camurça, X de alumínio com 3 furos e cubo
	# redondo com anel de parafusos
	"chimera": {
		"aro_cor": Color(0.07, 0.07, 0.075), "aro_rugo": 1.0, "aro_a": 0.02, "aro_b": 0.021,
		"luva": 0.0,
		"raios": [45, 135, 225, 315], "raio_larg": [0.042, 0.036], "raio_esp": 0.005,
		"raio_cor": Color(0.8, 0.81, 0.83),
		"furos": [[0.38, 0.5, 0.0062], [0.56, 0.5, 0.0062], [0.74, 0.5, 0.0062]],
		"dish": 0.03, "placa": 0.0,
		"cubo": "parafusos", "cubo_r": 0.04, "n_parafusos": 6,
		"cubo_cor": Color(0.75, 0.76, 0.78), "cubo_metal": 0.8,
		"parafuso_cor": Color(0.12, 0.12, 0.13),
		"emblema_cor": Color(0.06, 0.06, 0.065), "emblema_borda": Color(0.8, 0.81, 0.83),
	},
}

# carro (id do vehicles.xml) -> estilo
const POR_CARRO := {
	"BUGGY_01": "fusca",         # Mosquito
	"BUGGY_02": "inferno",
	"BUGGY_03": "espuma",        # Trident
	"BUGGY_04": "furado",        # Sphinx
	"BUGGY_05": "bulldog",
	"BUGGY_06": "buggy",         # Phantom
	"BUGGY_07": "sparco_preto",  # Kraken V8
	"BUGGY_08": "mountney",      # McKenzies
	"BUGGY_09": "sparco_azul",   # Viper
	"BUGGY_10": "renegade",
	"BUGGY_11": "kart",          # Hurricane
	"BUGGY_12": "storm",
	# trucks (out/2026): o próprio desenho melhorado; Shockwave e Punisher não
	# têm volante no modelo (escolha nossa, o Matheus troca com B)
	"TRUCK_01": "buccaneer",
	"TRUCK_02": "bulldog",       # Shockwave (sem volante no jogo)
	"TRUCK_03": "furado",        # Shinto (o X furado dos buggies)
	"TRUCK_04": "jericho",
	"TRUCK_05": "sparco_preto",  # Punisher (sem volante no jogo)
	"TRUCK_06": "furado",        # Panther
	"TRUCK_07": "truggy",        # Herbst Truggy
	"TRUCK_08": "storm",         # Herbst TT (o X liso de aro prateado do Storm)
	"TRUCK_09": "storm",         # Hammerhead
	"TRUCK_10": "fireball",
	"TRUCK_11": "goliath",
	"TRUCK_12": "chimera",
	"LAZARUS": "lazarus",
}


static func do_carro(id: String) -> String:
	return POR_CARRO.get(id, "buggy")


static func nomes() -> Array:
	return ESTILOS.keys()


## quanto o miolo (atrás da chapa do centro) fica atrás do plano do aro (m)
static func fundo(nome: String) -> float:
	var e: Dictionary = PADRAO.duplicate()
	e.merge(ESTILOS.get(nome, {}), true)
	return float(e.dish) + float(e.raio_esp) * 0.5


static func montar(raio: float, eixo: Vector3, nome := "buggy") -> ArrayMesh:
	var e: Dictionary = PADRAO.duplicate()
	e.merge(ESTILOS.get(nome, {}), true)
	var n := eixo.normalized()
	var cima := Vector3.UP - n * n.dot(Vector3.UP)
	cima = cima.normalized()
	var lado := n.cross(cima)
	var dirs: Array = []
	for g in e.raios:
		var a := deg_to_rad(float(g))
		dirs.append(cima * cos(a) + lado * sin(a))
	var mesh := ArrayMesh.new()
	_aro(mesh, e, raio, n, cima, lado, dirs)
	var centro := -n * float(e.dish)
	_raios(mesh, e, raio, n, centro, dirs)
	_cubo(mesh, e, n, cima, lado, centro + n * float(e.raio_esp) * 0.5)
	return mesh


# ------------------------------------------------------------ aro
## tubo de seção elíptica, mais grosso nas luvas dos raios; marca do topo e
## capas das luvas saem em materiais separados
static func _aro(mesh: ArrayMesh, e: Dictionary, raio: float, n: Vector3, cima: Vector3,
		lado: Vector3, dirs: Array) -> void:
	var st_aro := _st()
	var st_marca := _st()
	var st_luva := _st()
	var luva: float = e.luva
	var luva_ang: float = e.luva_ang
	var pts: Array = []
	var nrs: Array = []
	for i in SEG + 1:
		var th := TAU * i / SEG
		var radial := cima * cos(th) + lado * sin(th)
		var k := 1.0
		for r in dirs:
			var d := absf(radial.signed_angle_to(r, n))
			k += luva * exp(-pow(d / luva_ang, 2.0))
		var a: float = e.aro_a * k
		var b: float = e.aro_b * k
		var anel: Array = []
		var anel_n: Array = []
		for j in LADOS:
			var ph := TAU * j / LADOS
			anel.append(radial * (raio + a * cos(ph)) + n * (b * sin(ph)))
			anel_n.append((radial * (b * cos(ph)) + n * (a * sin(ph))).normalized())
		pts.append(anel)
		nrs.append(anel_n)
	for i in SEG:
		var th := TAU * (i + 0.5) / SEG
		var radial := cima * cos(th) + lado * sin(th)
		var st := st_aro
		if e.marca_cor != null and absf(wrapf(th, -PI, PI)) < float(e.marca_ang):
			st = st_marca
		elif e.luva_cor != null:
			for r in dirs:
				if absf(radial.signed_angle_to(r, n)) < luva_ang:
					st = st_luva
		for j in LADOS:
			var j2 := (j + 1) % LADOS
			_quad(st, pts[i][j], pts[i + 1][j], pts[i + 1][j2], pts[i][j2],
				nrs[i][j], nrs[i + 1][j], nrs[i + 1][j2], nrs[i][j2])
	_fechar(mesh, st_aro, _material(e.aro_cor, e.aro_metal, e.aro_rugo))
	if e.frisos != null:
		# aro de 2 frisos do jogo (Jericho, Goliath, Lazarus): filete fino na
		# borda de dentro e na de fora, do lado do piloto
		var st_f := _st()
		for s: float in [-0.8, 0.8]:
			_anel(st_f, raio + float(e.aro_a) * s, n * float(e.aro_b) * 0.55, 0.0024, n, cima, lado)
		_fechar(mesh, st_f, _material(e.frisos, 0.8, 0.3))
	if e.marca_cor != null:
		_fechar(mesh, st_marca, _material(e.marca_cor, 0.0, 0.8))
	if e.luva_cor != null:
		_fechar(mesh, st_luva, _material(e.luva_cor, 0.0, 0.6))


# ------------------------------------------------------------ raios
## cada raio é uma chapa (caixa fina) do centro recuado até o meio do tubo do
## aro; furos e rasgos são o alfa da textura (u ao longo do raio)
static func _raios(mesh: ArrayMesh, e: Dictionary, raio: float, n: Vector3, centro: Vector3,
		dirs: Array) -> void:
	var placa: float = e.placa
	var r0 := placa * 0.6
	var w0: float = e.raio_larg[0]
	var w1: float = e.raio_larg[1]
	var esp: float = e.raio_esp
	var st := _st()
	if e.raio_forma == "tubo":
		# varão/tubo redondo do centro recuado até o meio do aro (Buccaneer, Fireball)
		for r in dirs:
			_tubo(st, centro + r * r0, r * raio, w0 * 0.5, w1 * 0.5, n)
		_fechar(mesh, st, _material(e.raio_cor, e.raio_metal, e.raio_rugo))
		return
	for r in dirs:
		var perp: Vector3 = n.cross(r)
		var ini: Vector3 = centro + r * r0
		var fim: Vector3 = r * raio
		var nr: Vector3 = (fim - ini).cross(perp).normalized()
		if nr.dot(n) < 0.0:
			nr = -nr
		var passos := 8
		for s in passos:
			var t0 := float(s) / passos
			var t1 := float(s + 1) / passos
			var c0 := ini.lerp(fim, t0)
			var c1 := ini.lerp(fim, t1)
			var h0 := lerpf(w0, w1, t0) * 0.5
			var h1 := lerpf(w0, w1, t1) * 0.5
			for lado_f in [1.0, -1.0]:
				var o: Vector3 = nr * (esp * 0.5 * lado_f)
				_quad_uv(st, c0 - perp * h0 + o, c1 - perp * h1 + o, c1 + perp * h1 + o, c0 + perp * h0 + o,
					nr * lado_f, Vector2(t0, 0.0), Vector2(t1, 0.0), Vector2(t1, 1.0), Vector2(t0, 1.0))
			for lado_p in [1.0, -1.0]:
				var a0: Vector3 = c0 + perp * h0 * lado_p
				var a1: Vector3 = c1 + perp * h1 * lado_p
				var o := nr * esp * 0.5
				var pn: Vector3 = perp * lado_p
				_quad(st, a0 - o, a1 - o, a1 + o, a0 + o, pn, pn, pn, pn)
	if placa > 0.0:
		_prisma(st, _circulo(placa, 32), centro - n * esp * 0.5, n, n * esp)
	var L := raio - r0
	_fechar(mesh, st, _material_raio(e, (w0 + w1) * 0.5, L))


# ------------------------------------------------------------ cubo
static func _cubo(mesh: ArrayMesh, e: Dictionary, n: Vector3, cima: Vector3, lado: Vector3,
		base: Vector3) -> void:
	var tipo: String = e.cubo
	var cubo_r: float = e.cubo_r
	var st := _st()
	var st_p := _st()        # parafusos
	var st_em := _st()       # emblema (miolo)
	var st_eb := _st()       # borda do emblema
	var cromo := _st()
	var botoes: Array = []   # [SurfaceTool, cor]
	var topo := base
	match tipo:
		"tampa":
			# tampa cromada (cilindro afinando), virada pro piloto
			_prisma(cromo, _circulo(0.030, 24), base, n, n * 0.022, 0.85)
		"parafusos", "buzina":
			_prisma(st, _circulo(cubo_r, 32), base, n, n * 0.008)
			topo = base + n * 0.008
			var np: int = e.n_parafusos
			for i in np:
				var a := TAU * (i + 0.5) / np
				var p := topo + (cima * cos(a) + lado * sin(a)) * cubo_r * 0.78
				_prisma(st_p, _circulo(0.0042, 6), p, n, n * 0.004)
			if tipo == "buzina":
				# buzina preta abaulada no meio do anel
				var st_b := _st()
				_prisma(st_b, _circulo(cubo_r * 0.72, 32), topo, n, n * 0.016, 0.9)
				_fechar(mesh, st_b, _material(Color(0.03, 0.03, 0.03), 0.0, 0.5))
				topo += n * 0.016
				_emblema(st_em, st_eb, topo, n, 0.016)
			elif e.centro == "porca":
				# miolo vazado com a porca da coluna
				var st_f := _st()
				_prisma(st_f, _circulo(cubo_r * 0.55, 32), topo, n, n * 0.0015)
				_fechar(mesh, st_f, _material(Color(0.03, 0.03, 0.03), 0.0, 0.9))
				_prisma(cromo, _circulo(0.011, 6), topo, n, n * 0.012)
			else:
				_emblema(st_em, st_eb, topo, n, cubo_r * 0.45)
		"losango":
			# Renegade: chapa quadrada em pé no canto, 4 parafusos, botão redondo
			var q := PackedVector2Array([Vector2(0, cubo_r), Vector2(cubo_r, 0), Vector2(0, -cubo_r), Vector2(-cubo_r, 0)])
			_prisma(st, q, base, n, n * 0.01, 1.0, cima, lado)
			topo = base + n * 0.01
			for d in [cima, lado, -cima, -lado]:
				_prisma(st_p, _circulo(0.004, 6), topo + d * cubo_r * 0.68, n, n * 0.004)
			_prisma(st_em, _circulo(0.019, 24), topo, n, n * 0.008, 0.9)
		"t":
			# Truggy: placa em T por cima do X (braços pros lados e pra baixo),
			# com furos de alívio e o emblema no meio
			var st_t := _st()
			_prisma(st_t, _placa_t(cubo_r), base, n, n * 0.008, 1.0, cima, lado)
			topo = base + n * 0.008
			for f: Vector2 in [Vector2(-0.62, 0), Vector2(-0.95, 0), Vector2(0.62, 0), Vector2(0.95, 0), Vector2(0, -0.75)]:
				_prisma(st_p, _circulo(0.0065, 16), topo + (lado * f.x + cima * f.y) * cubo_r * 2.2, n, n * 0.0012)
			_fechar(mesh, st_t, _material(e.t_cor, 0.7, 0.35))
			_emblema(st_em, st_eb, topo, n, 0.022)
		"fusca":
			# buzina retangular arredondada com duas teclas e o emblema redondo
			var o := base - cima * 0.006
			_prisma(st, _ret_arred(0.20, 0.085, 0.028), o, n, n * 0.03, 0.94, cima, lado)
			topo = o + n * 0.03
			var st_t := _st()
			for s: float in [1.0, -1.0]:
				_prisma(st_t, _ret_arred(0.026, 0.052, 0.008), topo + lado * (0.066 * s), n, n * 0.002, 1.0, cima, lado)
			_fechar(mesh, st_t, _material(Color(0.12, 0.12, 0.125), 0.0, 0.5))
			_emblema(st_em, st_eb, topo, n, 0.017)
	if e.botoes:
		# placa de botões em asa, atrás do cubo (2 botões em cada asa)
		var st_a := _st()
		var cores := [Color(0.1, 0.45, 0.6), Color(0.1, 0.55, 0.3), Color(0.75, 0.08, 0.06), Color(0.1, 0.55, 0.3)]
		var k := 0
		for s: float in [1.0, -1.0]:
			var d := (cima * 0.8 + lado * (0.6 * s)).normalized()
			var dp := n.cross(d)
			var c := base - n * 0.004 + d * 0.075
			_prisma(st_a, _ret_arred(0.042, 0.075, 0.012), c, n, n * 0.003, 1.0, d, dp)
			for t in [0.022, -0.018]:
				var sb := _st()
				_prisma(sb, _circulo(0.0085, 16), c + n * 0.003 + d * t, n, n * 0.009, 0.95)
				botoes.append([sb, cores[k]])
				k += 1
		_fechar(mesh, st_a, _material(Color(0.8, 0.81, 0.83), 0.7, 0.4))
	_fechar(mesh, st, _material(e.cubo_cor, e.cubo_metal, e.cubo_rugo))
	_fechar(mesh, st_p, _material(e.parafuso_cor, 0.8, 0.3))
	_fechar(mesh, cromo, _material(Color(0.86, 0.86, 0.88), 1.0, 0.12))
	if e.emblema_cor != null:
		_fechar(mesh, st_em, _material(e.emblema_cor, 0.3, 0.4))
	if e.emblema_borda != null:
		_fechar(mesh, st_eb, _material(e.emblema_borda, 0.5, 0.3))
	for b in botoes:
		_fechar(mesh, b[0], _material(b[1], 0.0, 0.35))


## emblema redondo: borda e miolo um pouco acima
static func _emblema(st_em: SurfaceTool, st_eb: SurfaceTool, p: Vector3, n: Vector3, r: float) -> void:
	_prisma(st_eb, _circulo(r, 32), p, n, n * 0.002)
	_prisma(st_em, _circulo(r * 0.78, 32), p + n * 0.002, n, n * 0.0012)


# ------------------------------------------------------------ materiais
static func _material(cor: Color, metal: float, rugo: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = cor
	m.metallic = metal
	m.roughness = rugo
	return m


## material dos raios: cor, escovado, furos e rasgos e rebites na textura
## (w = largura média e L = comprimento do raio, pra furo sair redondo)
static func _material_raio(e: Dictionary, w: float, L: float) -> StandardMaterial3D:
	var m := _material(Color.WHITE, e.raio_metal, e.raio_rugo)
	m.albedo_texture = _textura_raio(e, w, L)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## textura do raio: x = através (v), y = ao longo (u, 0 no centro, 1 no aro)
static func _textura_raio(e: Dictionary, w: float, L: float) -> ImageTexture:
	var nx := 48
	var ny := 256
	var img := Image.create(nx, ny, false, Image.FORMAT_RGBA8)
	var base: Color = e.raio_cor
	var borda = e.furo_borda
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var risco := PackedFloat32Array()
	for x in nx:
		risco.append(rng.randf_range(-0.05, 0.05) if e.escovado else 0.0)
	for y in ny:
		var u := (y + 0.5) / ny
		for x in nx:
			var v := (x + 0.5) / nx
			var c := base.lightened(risco[x]) if risco[x] > 0.0 else base.darkened(-risco[x])
			var px := Vector2((v - 0.5) * w, u * L)        # em metros
			var a := 1.0
			for f in e.furos:
				var d := px.distance_to(Vector2((float(f[1]) - 0.5) * w, float(f[0]) * L))
				if d < float(f[2]):
					a = 0.0
				elif borda != null and d < float(f[2]) + 0.0015:
					c = borda
			for r in e.rasgos:
				var x0 := (float(r[0]) - 0.5) * w
				var yy := clampf(px.y, float(r[1]) * L, float(r[2]) * L)
				var d := px.distance_to(Vector2(x0, yy))
				if d < float(r[3]):
					a = 0.0
				elif borda != null and d < float(r[3]) + 0.0015:
					c = borda
			if e.rebites:
				# fileira de rebites nas duas bordas, a cada 3 cm
				for s: float in [-1.0, 1.0]:
					var rx := s * (w * 0.5 - 0.006)
					var ry := (roundf(px.y / 0.03 - 0.5) + 0.5) * 0.03
					var d := px.distance_to(Vector2(rx, ry))
					if d < 0.0022 and ry > 0.03 and ry < L - 0.02:
						c = base.lightened(0.35 - d * 60.0)
					elif d < 0.0032 and ry > 0.03 and ry < L - 0.02:
						c = base.darkened(0.4)
			c.a = a
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------ geometria
static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _fechar(mesh: ArrayMesh, st: SurfaceTool, mat: Material) -> void:
	var arr := st.commit_to_arrays()
	if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null or arr[Mesh.ARRAY_VERTEX].is_empty():
		return
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


static func _circulo(r: float, lados: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in lados:
		var a := TAU * i / lados
		p.append(Vector2(cos(a), sin(a)) * r)
	return p


## contorno da placa em T (x = lado, y = cima), estrela em volta da origem pro
## leque do _prisma: barra de lado a lado, braço pra baixo afinando e um
## bojo redondo em cima do meio. c = raio do bojo; braços até c x 2.6
static func _placa_t(c: float) -> PackedVector2Array:
	var L := c * 2.6
	var h := c * 0.5
	var p := PackedVector2Array()
	p.append(Vector2(-L, h * 0.8))
	for i in 9:
		var a := PI - PI * i / 8.0           # bojo de 180° a 0°
		p.append(Vector2(cos(a) * c, maxf(sin(a) * c, h)))
	p.append(Vector2(L, h * 0.8))
	p.append(Vector2(L + h * 0.3, 0.0))
	p.append(Vector2(L, -h * 0.8))
	p.append(Vector2(h * 1.1, -h))
	p.append(Vector2(h * 0.75, -c * 1.9))
	p.append(Vector2(0.0, -c * 1.9 - h * 0.25))
	p.append(Vector2(-h * 0.75, -c * 1.9))
	p.append(Vector2(-h * 1.1, -h))
	p.append(Vector2(-L, -h * 0.8))
	p.append(Vector2(-L - h * 0.3, 0.0))
	return p


## tubo de a até b, raio ra em a e rb em b (sem tampas: as pontas somem no
## cubo e no aro)
static func _tubo(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, n: Vector3) -> void:
	var d := (b - a).normalized()
	var p1 := n.cross(d).normalized()
	var p2 := d.cross(p1)
	var lados := 12
	for j in lados:
		var a0 := TAU * j / lados
		var a1 := TAU * (j + 1) / lados
		var r0 := p1 * cos(a0) + p2 * sin(a0)
		var r1 := p1 * cos(a1) + p2 * sin(a1)
		_quad(st, a + r0 * ra, b + r0 * rb, b + r1 * rb, a + r1 * ra, r0, r0, r1, r1)


## anel fino (toro) de raio R em volta do eixo, deslocado por o
static func _anel(st: SurfaceTool, R: float, o: Vector3, r: float, n: Vector3, cima: Vector3, lado: Vector3) -> void:
	var lados := 8
	for i in SEG:
		var t0 := TAU * i / SEG
		var t1 := TAU * (i + 1) / SEG
		var q0 := cima * cos(t0) + lado * sin(t0)
		var q1 := cima * cos(t1) + lado * sin(t1)
		for j in lados:
			var f0 := TAU * j / lados
			var f1 := TAU * (j + 1) / lados
			var na := q0 * cos(f0) + n * sin(f0)
			var nb := q1 * cos(f0) + n * sin(f0)
			var nc := q1 * cos(f1) + n * sin(f1)
			var nd := q0 * cos(f1) + n * sin(f1)
			_quad(st, o + q0 * R + na * r, o + q1 * R + nb * r, o + q1 * R + nc * r, o + q0 * R + nd * r,
				na, nb, nc, nd)


## retângulo de cantos arredondados (largura x altura), centrado
static func _ret_arred(larg: float, alt: float, r: float, por_canto := 6) -> PackedVector2Array:
	var p := PackedVector2Array()
	var cx := larg * 0.5 - r
	var cy := alt * 0.5 - r
	for q in 4:
		var c := Vector2(cx if q == 0 or q == 3 else -cx, cy if q < 2 else -cy)
		for i in por_canto + 1:
			var a := PI * 0.5 * q + PI * 0.5 * i / por_canto
			p.append(c + Vector2(cos(a), sin(a)) * r)
	return p


## extruda um polígono convexo (x ao longo de ex, y ao longo de ey) de o até
## o + h, com tampa em cima e embaixo; o topo pode afinar (escala). Lados lisos
## onde o contorno faz curva (menos de 35° entre arestas)
static func _prisma(st: SurfaceTool, pts: PackedVector2Array, o: Vector3, n: Vector3, h: Vector3,
		escala := 1.0, ey := Vector3.ZERO, ex := Vector3.ZERO) -> void:
	if ey == Vector3.ZERO:
		ey = (Vector3.UP - n * n.dot(Vector3.UP)).normalized()
		ex = n.cross(ey)
	var nb := pts.size()
	var b: Array = []
	var t: Array = []
	for p in pts:
		b.append(o + ex * p.x + ey * p.y)
		t.append(o + h + (ex * p.x + ey * p.y) * escala)
	var cb := o
	var ct := o + h
	var hn := h.normalized()
	# normal de cada aresta (pra fora)
	var en: Array = []
	for i in nb:
		var d: Vector3 = b[(i + 1) % nb] - b[i]
		var nn := d.cross(hn).normalized()
		if nn.dot(b[i] - cb) < 0.0:
			nn = -nn
		en.append(nn)
	for i in nb:
		var i2 := (i + 1) % nb
		_tri(st, ct, t[i], t[i2], hn, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		_tri(st, cb, b[i2], b[i], -hn, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		var na := _normal_vertice(en, i, i, nb)
		var nb2 := _normal_vertice(en, i, i2, nb)
		_quad(st, b[i], b[i2], t[i2], t[i], na, nb2, nb2, na)


## normal do vértice v na aresta i: média com a aresta vizinha se a quina for suave
static func _normal_vertice(en: Array, i: int, v: int, nb: int) -> Vector3:
	var outra: int = (v - 1 + nb) % nb if v == i else v
	var a: Vector3 = en[i]
	var c: Vector3 = en[outra]
	if a.angle_to(c) < deg_to_rad(35.0):
		return (a + c).normalized()
	return a


## triângulo com a frente pro lado da normal (o Godot quer horário de frente)
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, nr: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	if (b - a).cross(c - a).dot(nr) > 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
	for p in [[a, ua], [b, ub], [c, uc]]:
		st.set_normal(nr)
		st.set_uv(p[1])
		st.add_vertex(p[0])


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	for t in [[a, b, c, na, nb, nc], [a, c, d, na, nc, nd]]:
		var p0: Vector3 = t[0]
		var p1: Vector3 = t[1]
		var p2: Vector3 = t[2]
		var n0: Vector3 = t[3]
		var n1: Vector3 = t[4]
		var n2: Vector3 = t[5]
		if (p1 - p0).cross(p2 - p0).dot(n0 + n1 + n2) > 0.0:
			var tp := p1
			p1 = p2
			p2 = tp
			var tn := n1
			n1 = n2
			n2 = tn
		for v in [[p0, n0], [p1, n1], [p2, n2]]:
			st.set_normal(v[1])
			st.set_uv(Vector2.ZERO)
			st.add_vertex(v[0])


static func _quad_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nr: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_tri(st, a, b, c, nr, Vector2(ua.y, ua.x), Vector2(ub.y, ub.x), Vector2(uc.y, uc.x))
	_tri(st, a, c, d, nr, Vector2(ua.y, ua.x), Vector2(uc.y, uc.x), Vector2(ud.y, ud.x))
