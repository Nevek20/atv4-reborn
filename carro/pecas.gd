extends RefCounted
## Peças compradas (oficina, aba Upgrade; no jogo: Garage > Vehicle >
## Upgrade). As opções e os efeitos são os do upgrades.xml (14889), por
## classe (Buggy, Truck); as de fábrica são a DefaultConfig do vehicles.xml
## (14887). A troca entra no lugar da DefaultConfig na mesma conta de
## fábrica (vehicle_data.factory_tuning: efeitos somam por tipo, presos em
## 0..1). Shocks, GearRatios, BrakeBalanceController e GearboxType ficam pro
## Tune & Setup. NOSSO: a tela e salvar em user://oficina.json (chave
## "pecas" -> carro -> {slot: peça}); só o carro do jogador.

const UPGRADES := "res://data/upgrades.xml"
const VEICULOS := "res://data/vehicles.xml"
const SALVAS := "user://oficina.json"
const SLOTS := ["EngineInternals", "EngineManagement", "EngineHeader", "Exhaust", "IntakeKit",
	"GearboxLevel", "Clutch", "Brake", "Suspension", "BodyMass"]
const NOMES := {"EngineInternals": "Motor (interno)", "EngineManagement": "Injeção",
	"EngineHeader": "Coletor", "Exhaust": "Escape", "IntakeKit": "Admissão",
	"GearboxLevel": "Câmbio", "Clutch": "Embreagem", "Brake": "Freio",
	"Suspension": "Suspensão", "BodyMass": "Peso"}


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
	return out


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


## "EngineInternals_Level3" -> "Nível 3"
static func rotulo(peca: String) -> String:
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
