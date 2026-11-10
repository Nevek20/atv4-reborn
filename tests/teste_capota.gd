extends SceneTree
## Capotagem na curva (0x211b58, altura da força lateral pela inclinação): cada
## carro acelera reto em chão plano até VEL km/h (padrão 80), vira tudo com o
## acelerador no fundo por DUR s (padrão 3) e mede a maior inclinação de lado
## e se capotou. Roda 2 cópias de cada carro: "jogo" (Lateral_scale cai de 0.09
## a 0 entre 3° e 8° de inclinação, como o exe) e "antes" (sempre 0.09, o
## remake até out/2026). MU = atrito do chão (padrão 0.8, pista), VEHS =
## índices da frota (padrão Renegade, Buccaneer, Truggy, Fireball, Goliath).
## Uso: VEL=80 godot --headless --path . -s res://tests/teste_capota.gd

const Car := preload("res://carro/car.gd")
const Main := preload("res://main.gd")

var carros := []        # [car, nome, modo, estado]
var t := 0.0
var dur := 3.0
var alvo := 80.0


class Estado:
	var t_vira := -1.0
	var inc_max := 0.0
	var capotou := -1.0


func _initialize() -> void:
	alvo = float(OS.get_environment("VEL")) if OS.has_environment("VEL") else 80.0
	dur = float(OS.get_environment("DUR")) if OS.has_environment("DUR") else 3.0
	var mu := float(OS.get_environment("MU")) if OS.has_environment("MU") else 0.8
	var vehs := (OS.get_environment("VEHS") if OS.has_environment("VEHS") else "0,13,19,22,23").split(",")
	var chao := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8000, 2, 8000)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	chao.add_child(cs)
	root.add_child(chao)
	var k := 0
	for vi in vehs:
		var v: Dictionary = Main.frota()[int(vi)]
		for modo in ["jogo", "antes"]:
			var c = Car.new()
			c.asset_dir = v.dir
			c.data_files = Main.dados(v)
			c.points_file = v.points
			c.vehicle_id = v.id
			c.tune_override = v.get("tune", {})
			c.suspension = false
			c.melhorias = false
			c.SURFACE_MU = mu
			c.SURFACE_AMORT = 0.0
			root.add_child(c)
			c.reset_to(Vector3(k * 60.0, 1.5, -3500), 0.0)
			c.test_input = {"thr": 0.0, "brk": 0.0, "steer": 0.0}
			carros.append([c, v.name, modo, Estado.new()])
			k += 1


func _physics_process(dt: float) -> bool:
	t += dt
	if t < 0.05:
		return false
	var fim := true
	for e in carros:
		var c = e[0]
		var s: Estado = e[3]
		if e[2] == "antes" and c.P.has("h_lat_s0"):
			c.P.h_lat_s0 = 98.0       # nunca passa do limiar: sempre o std
			c.P.h_lat_s1 = 99.0
		c.test_input.thr = 1.0 if t > 1.0 else 0.0
		var kmh: float = c.linear_velocity.length() * 3.6
		if s.t_vira < 0.0 and kmh >= alvo:
			s.t_vira = t
		if s.t_vira < 0.0:
			if t < 60.0:
				fim = false
			continue
		c.test_input.steer = 1.0
		var tv := t - s.t_vira
		if tv < dur:
			fim = false
		else:
			continue
		var up: Vector3 = c.global_transform.basis.y
		s.inc_max = maxf(s.inc_max, rad_to_deg(acos(clampf(up.y, -1.0, 1.0))))
		if up.y < 0.0 and s.capotou < 0.0:
			s.capotou = tv
	if fim:
		print("VEL %d km/h, vira tudo %.1f s, atrito %.2f" % [alvo, dur, carros[0][0].SURFACE_MU])
		for e in carros:
			var s: Estado = e[3]
			var txt := "capotou em %.2f s" % s.capotou if s.capotou >= 0.0 else "não capotou"
			if s.t_vira < 0.0:
				txt = "não chegou na velocidade"
			print("  %-14s %-6s inclinação máx %5.1f°  %s" % [e[1], e[2], s.inc_max, txt])
		return true
	return false
