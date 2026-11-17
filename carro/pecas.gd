extends RefCounted
## Peças compradas (oficina, aba Upgrade; no jogo: Garage > Vehicle >
## Upgrade). As opções e os efeitos são os do upgrades.xml (14889), por
## classe (Buggy, Truck); as de fábrica são a DefaultConfig do vehicles.xml
## (14887). A troca entra no lugar da DefaultConfig na mesma conta de
## fábrica (vehicle_data.factory_tuning: efeitos somam por tipo, presos em
## 0..1). Pneu (Tire): os do catálogo (componentes.xml); muda o atrito
## (Override do material do chão) e a roda (TYRE_<pneu>_<tamanho>, car.gd).
## Aro (Alloy): a textura ALLOY da roda (IG_WHEEL_HEAVYCLASS_0N, carro_montagem).
## Shocks, GearRatios, BrakeBalanceController e GearboxType ficam pro Tune &
## Setup. NOSSO: a tela e salvar em user://oficina.json (chave
## "pecas" -> carro -> {slot: peça}); só o carro do jogador.

const UPGRADES := "res://data/upgrades.xml"
const VEICULOS := "res://data/vehicles.xml"
const SALVAS := "user://oficina.json"
const COMPONENTES := "res://data/componentes.xml"   # catálogo de peças do jogo (xml 14882)
const MATERIAIS := "res://data/materials_rx01.xml"
const SLOTS := ["EngineInternals", "EngineManagement", "EngineHeader", "Exhaust", "IntakeKit",
	"GearboxLevel", "Clutch", "Brake", "Suspension", "BodyMass", "Tire", "Alloy"]
const NOMES := {"EngineInternals": "Motor (interno)", "EngineManagement": "Injeção",
	"EngineHeader": "Coletor", "Exhaust": "Escape", "IntakeKit": "Admissão",
	"GearboxLevel": "Câmbio", "Clutch": "Embreagem", "Brake": "Freio",
	"Suspension": "Suspensão", "BodyMass": "Peso", "Tire": "Pneu", "Alloy": "Aro"}


## {slot: [peça, ...]} da classe, na ordem do XML; e {peça: {efeito: valor}}
static func opcoes(classe: String) -> Dictionary:
	var out := {"slots": {}, "efeitos": {}}
	var x := XMLParser.new()
	if x.open(UPGRADES) != OK:
		return out
	var dentro := false
	var slot := ""
	var comp := ""
	while x.read() == OK:
		var t := x.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var n := x.get_node_name()
			if n == classe:
				dentro = true
			elif dentro and n == "Effect" and comp != "":
				out.efeitos[comp][x.get_named_attribute_value_safe("Type")] = x.get_named_attribute_value_safe("Value")
			elif dentro and n.begins_with(slot + "_") and slot != "":
				comp = n
				out.slots[slot].append(n)
				out.efeitos[n] = {}
			elif dentro and not x.is_empty():
				slot = n
				comp = ""
				out.slots[slot] = []
		elif t == XMLParser.NODE_ELEMENT_END and x.get_node_name() == classe:
			break
	_pneus(classe, out)
	return out


## pneus da classe (catálogo, slot Tire, na ordem do jogo) e o atrito de cada
## um na terra comum do RX01 (materials_rx01.xml, COMMON_1: Override FRICTION
## TYRE <pneu> <valor>; é o que a física usa, terrain.atrito)
static func _pneus(classe: String, out: Dictionary) -> void:
	var x := XMLParser.new()
	if x.open(COMPONENTES) != OK:
		return
	var atrito := {}
	var m := XMLParser.new()
	if m.open(MATERIAIS) == OK:
		while m.read() == OK:
			if m.get_node_type() == XMLParser.NODE_ELEMENT and m.get_node_name() == "Overrides":
				for i in m.get_attribute_count():
					var v := m.get_attribute_value(i).split(" ")
					if v.size() == 4 and v[0] == "FRICTION":
						atrito[v[2]] = v[3]
				break                       # o 1º material é a terra comum (COMMON_1)
	var dentro := false
	var no_tire := false
	var slot := ""
	var lista: Array = []
	while x.read() == OK:
		var t := x.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var n := x.get_node_name()
			if n == classe:
				dentro = true
			elif dentro and (n == "Tire" or n == "Alloy"):
				no_tire = n == "Tire"
				slot = n
				lista = []
				out.slots[n] = lista
			elif slot != "" and n == "Component":
				var c := x.get_named_attribute_value_safe("mComponentName")
				lista.append(c)
				out.efeitos[c] = {"atrito na terra": atrito.get(c, "?")} if no_tire else {}
		elif t == XMLParser.NODE_ELEMENT_END:
			var n := x.get_node_name()
			if n == "Tire" or n == "Alloy":
				slot = ""
			elif n == classe and dentro:
				break
	# NOSSO: o aro 8 (IG_WHEEL_HEAVYCLASS_08) está pronto no archive e o
	# catálogo não lista: entra como extra no fim (gerar_buggies copia)
	if out.slots.has("Alloy") and not out.slots.Alloy.has("WHEEL_08"):
		out.slots.Alloy.append("WHEEL_08")
		out.efeitos["WHEEL_08"] = {}


## DefaultConfig do veículo (Name do vehicles.xml) e a classe dele
static func fabrica(veh: String) -> Dictionary:
	var x := XMLParser.new()
	var out := {"classe": "Buggy", "config": {}}
	if x.open(VEICULOS) != OK:
		return out
	var dentro := false
	while x.read() == OK:
		if x.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var n := x.get_node_name()
		if n == "Vehicle":
			if dentro:
				break
			dentro = x.get_named_attribute_value_safe("Name") == veh
			if dentro:
				out.classe = x.get_named_attribute_value_safe("Class")
		elif dentro and n == "DefaultConfig":
			for i in x.get_attribute_count():
				out.config[x.get_attribute_name(i)] = x.get_attribute_value(i)
	return out


## "EngineInternals_Level3" -> "Nível 3"; pneu "MUD_PREMIUM" -> "Lama Premium";
## aro "WHEEL_03" -> "Aro 3"
static func rotulo(peca: String) -> String:
	if peca.begins_with("WHEEL_"):
		return "Aro %d%s" % [peca.substr(6).to_int(), " (extra)" if peca == "WHEEL_08" else ""]
	if not peca.contains("_Level") and not peca.contains("_Prototype") and peca.to_upper() == peca:
		var tipo := {"DIRT": "Terra", "MUD": "Lama", "SAND": "Areia", "SNOW": "Neve", "GENERAL": "Uso geral"}
		var p := peca.split("_")
		return "%s %s" % [tipo.get(p[0], p[0]), {"BUDGET": "Budget", "PREMIUM": "Premium", "PROTOTYPE": "Protótipo"}.get(p[-1], p[-1])]
	var s := peca.get_slice("_", 1)
	if s.begins_with("Level"):
		return "Nível " + s.substr(5)
	return {"Prototype": "Protótipo"}.get(s, s)


static func salvas(chave: String) -> Dictionary:
	var j = JSON.parse_string(FileAccess.get_file_as_string(SALVAS)) if FileAccess.file_exists(SALVAS) else null
	if typeof(j) == TYPE_DICTIONARY and typeof(j.get("pecas")) == TYPE_DICTIONARY \
			and typeof(j.pecas.get(chave)) == TYPE_DICTIONARY:
		return j.pecas[chave]
	return {}


static func salvar(chave: String, esc: Dictionary) -> void:
	var j = JSON.parse_string(FileAccess.get_file_as_string(SALVAS)) if FileAccess.file_exists(SALVAS) else null
	if typeof(j) != TYPE_DICTIONARY:
		j = {}
	if typeof(j.get("pecas")) != TYPE_DICTIONARY:
		j["pecas"] = {}
	if esc.is_empty():
		j.pecas.erase(chave)
	else:
		j.pecas[chave] = esc
	var f := FileAccess.open(SALVAS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(j, "\t"))
