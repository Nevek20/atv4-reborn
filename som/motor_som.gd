extends Node
## Som do motor (melhoria nossa, car.gd SOM_MOTOR). O jogo tem só 3 bancos de
## motor pros 12 buggies; aqui cada buggy toca o motor dele, gravado no Engine
## Simulator (som/loops, docs/som_motor.md, som/engine_sim/LEIA-ME.md).
##
## Opção (b): o rpm do jogo (lenta 1000, corte 8000, igual nos 12) vira o rpm
## real do motor, esticado da lenta gravada até o último on_RRRR. Em cada
## camada (acelerando = on_RRRR, soltando = off_RRRR + lenta) tocam os 2 loops
## vizinhos do rpm real, com o tom corrigido (pitch = rpm / rpm gravado) e
## crossfade de potência constante. A mistura acelerando/soltando é a carga do
## motor (car.gd som_carga = acelerador x limitador x troca de marcha): no
## corte o som pipoca junto com o motor.
##
## Volume: cada wav foi normalizado na gravação (coluna ganho do info.csv) e o
## nivel_cru_db diz o volume de verdade. Ele entra comprimido: K_RPM da
## diferença de volume entre giros e K_OFF da diferença soltando/acelerando
## (no cru o soltando fica 17 dB abaixo, em média; aqui uns 8).
##
## O rpm que vai pro som passa por um filtro de RPM_SUAVE: com a roda
## patinando na 1ª a física (portada do jogo) faz o rpm ir e voltar ~800 rpm
## umas 6 vezes por segundo, e o tom tremendo junto soava como ruído
## (Mosquito acima de 6500). Loops com ruído alto (coluna ruido_pct do
## info.csv, parte que não repete a cada ciclo do motor) ficam de fora: o
## off_4000 do Phantom tem 53% (o motor fica irregular ali, toda vez).

const JOGO_LENTA := 1000.0
const JOGO_CORTE := 8000.0
const K_RPM := 0.5
const K_OFF := 0.5
const PISO_DB := -12.0        # nenhum loop abaixo disso (lenta ainda se ouve)
const VOLUME_DB := -4.0        # volume geral
const SUAVE := 0.03            # s, constante de tempo da carga (sem estalo)
const RPM_SUAVE := 0.08        # s, constante de tempo do rpm do som
const RUIDO_MAX := 20.0        # % de ruído acima disso o loop fica de fora
const PITCH_MIN := 0.5
const PITCH_MAX := 1.25
const PASTA := "res://som/loops"

var _on: Array = []            # {rpm, db, p} por rpm crescente
var _off: Array = []
var lenta_real := 800.0
var corte_real := 6000.0
var pasta := ""
var _carga := 0.0
var _rpm := -1.0               # rpm do jogo filtrado
var r_real := 0.0              # conferência: rpm real tocando agora


## pasta dos loops do carro pelo id do vehicles.xml: som/loops/NN_* nos
## buggies, som/loops/tNN_* nos trucks (o bônus passa a pasta dele, car.som_pasta)
static func pasta_do_carro(id: String) -> String:
	var prefixo := ""
	if id.begins_with("BUGGY_"):
		prefixo = "%02d_" % id.trim_prefix("BUGGY_").to_int()
	elif id.begins_with("TRUCK_"):
		prefixo = "t%02d_" % id.trim_prefix("TRUCK_").to_int()
	if prefixo == "" or prefixo.begins_with("00") or prefixo.begins_with("t00"):
		return ""
	for d in DirAccess.get_directories_at(PASTA):
		if d.begins_with(prefixo):
			return PASTA.path_join(d)
	return ""


func carregar(dir: String) -> bool:
	var csv := dir.path_join("info.csv")
	if not FileAccess.file_exists(csv):
		return false
	pasta = dir
	var info := {}
	var f := FileAccess.open(csv, FileAccess.READ)
	var cab := f.get_csv_line()
	while not f.eof_reached():
		var l := f.get_csv_line()
		if l.size() < cab.size():
			continue
		var r := {}
		for i in cab.size():
			r[cab[i]] = l[i]
		info[r.arquivo] = r
	var on := {}
	var off := {}
	for arq in info:
		if info[arq].has("ruido_pct") and float(info[arq].ruido_pct) > RUIDO_MAX:
			continue
		if arq.begins_with("on_"):
			on[arq.trim_prefix("on_").trim_suffix(".wav").to_int()] = info[arq]
		elif arq.begins_with("off_"):
			off[arq.trim_prefix("off_").trim_suffix(".wav").to_int()] = info[arq]
	if on.is_empty() or not info.has("lenta.wav"):
		return false
	var rpms: Array = on.keys()
	rpms.sort()
	var le: Dictionary = info["lenta.wav"]
	lenta_real = float(le.rpm_medido)
	corte_real = float(on[rpms[-1]].rpm_medido)
	# nível de cada arquivo: o cru (comprimido) menos o que o ganho já deu
	var ref := -INF
	for r in rpms:
		ref = maxf(ref, float(on[r].nivel_cru_db))
	var arq_ref := ref + _db(on[rpms.reduce(func(a, b): return a if float(on[a].nivel_cru_db) >= float(on[b].nivel_cru_db) else b)].ganho)
	for r in rpms:
		var o: Dictionary = on[r]
		var alvo := maxf(K_RPM * (float(o.nivel_cru_db) - ref), PISO_DB)
		_on.append(_tocador("on_%d.wav" % r, o, alvo, arq_ref))
		if off.has(r):
			var x: Dictionary = off[r]
			var alvo_off := maxf(alvo + K_OFF * (float(x.nivel_cru_db) - float(o.nivel_cru_db)), PISO_DB)
			_off.append(_tocador("off_%d.wav" % r, x, alvo_off, arq_ref))
	# lenta = soltando na marcha lenta, comparada com o on mais baixo
	var o0: Dictionary = on[rpms[0]]
	var alvo_le := maxf(K_RPM * (float(o0.nivel_cru_db) - ref) + K_OFF * (float(le.nivel_cru_db) - float(o0.nivel_cru_db)), PISO_DB)
	_off.append(_tocador("lenta.wav", le, alvo_le, arq_ref))
	_off.sort_custom(func(a, b): return a.rpm < b.rpm)
	return true


## um AudioStreamPlayer parado por loop; volume final = alvo - (nível do
## arquivo - nível do arquivo de referência)
func _tocador(arq: String, i: Dictionary, alvo: float, arq_ref: float) -> Dictionary:
	var p := AudioStreamPlayer.new()
	p.stream = _carregar_wav(pasta.path_join(arq))
	p.name = arq.get_basename()
	add_child(p)
	var nivel := float(i.nivel_cru_db) + _db(i.ganho) - arq_ref
	return {"rpm": float(i.rpm_medido), "db": minf(alvo - nivel, 6.0), "p": p, "arq": arq}


static func _db(ganho) -> float:
	return 20.0 * log(maxf(float(ganho), 1e-6)) / log(10.0)


## o wav já é o loop inteiro (ciclos completos do motor, bloco smpl). Sem a
## importação do editor ele é lido direto e o loop vira o arquivo todo
static func _carregar_wav(caminho: String) -> AudioStream:
	var st: AudioStream = null
	if ResourceLoader.exists(caminho):
		st = load(caminho)
	if st == null:
		st = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(caminho))
	if st is AudioStreamWAV and st.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		var bpa := (2 if st.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if st.stereo else 1)
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = st.data.size() / bpa
	return st


## rpm do jogo e carga (0..1) do motor a cada quadro
func atualizar(rpm_jogo: float, carga: float, dt: float) -> void:
	_carga += (clampf(carga, 0.0, 1.0) - _carga) * (1.0 - exp(-dt / SUAVE))
	if _rpm < 0.0:
		_rpm = rpm_jogo
	_rpm += (rpm_jogo - _rpm) * (1.0 - exp(-dt / RPM_SUAVE))
	r_real = lenta_real + (_rpm - JOGO_LENTA) / (JOGO_CORTE - JOGO_LENTA) * (corte_real - lenta_real)
	_camada(_on, r_real, sin(_carga * PI * 0.5))
	_camada(_off, r_real, cos(_carga * PI * 0.5))


func _camada(lista: Array, r: float, ganho: float) -> void:
	var pesos := {}
	if r <= lista[0].rpm:
		pesos[0] = 1.0
	elif r >= lista[-1].rpm:
		pesos[lista.size() - 1] = 1.0
	else:
		for i in lista.size() - 1:
			if r < lista[i + 1].rpm:
				var t: float = (r - lista[i].rpm) / (lista[i + 1].rpm - lista[i].rpm)
				pesos[i] = cos(t * PI * 0.5)
				pesos[i + 1] = sin(t * PI * 0.5)
				break
	for k in lista.size():
		var s: Dictionary = lista[k]
		var p: AudioStreamPlayer = s.p
		var w: float = pesos.get(k, 0.0) * ganho
		if w < 0.003:
			if p.playing:
				p.stop()
			continue
		p.pitch_scale = clampf(r / s.rpm, PITCH_MIN, PITCH_MAX)
		p.volume_db = VOLUME_DB + s.db + linear_to_db(w)
		if not p.playing:
			p.play()


## conferência (tests/teste_som.gd): [arquivo, peso linear, pitch] dos loops tocando
func tocando() -> Array:
	var out: Array = []
	for s in _on + _off:
		var p: AudioStreamPlayer = s.p
		if p.playing:
			out.append([s.arq, db_to_linear(p.volume_db - VOLUME_DB - s.db), p.pitch_scale])
	return out
