extends SceneTree
## HUD do jogo (menu/hud_jogo.gd, HUD_CIRCUIT.xml + assets/hud do
## tools/hud_jogo.py), sem tela:
## 1) conta do quadro do exe (0x46f7c0): a 640x480 (4:3, sem o 0.75 do
##    widescreen) o conta-giros (mPixelScaleRatio 1) tem o tamanho da caixa
##    main_speedo em pixels da textura, no canto inferior direito; a 1280x720
##    (16:9) x 0.75 x 2
## 2) rótulos FONT_SMALL na altura de 0.045 da tela (22 px a 480: 1:1 com a
##    fonte) e o kerning (0x2689c0) encurtando "POSITION"
## 3) ponteiro: 0 rpm em mNeedleMinRot, MAXREVS em mNeedleMaxRot
## Uso: godot --headless --path . -s res://tests/teste_hud.gd

var falhas := 0


func _falha(t: String) -> void:
	print("  FALHA: " + t)
	falhas += 1


func _initialize() -> void:
	var h = load("res://menu/hud_jogo.gd").new()
	if not h.montar():
		print("teste_hud: FALHA (sem assets/hud: rode o tools/hud_jogo.py)")
		quit()
		return
	h.set_anchors_preset(Control.PRESET_TOP_LEFT)
	h.maxrevs = 9000
	h.em_corrida = true
	var caixa: Rect2 = h._caixa("hud_tpage_rev9000", "main_speedo")
	for tam in [Vector2(640, 480), Vector2(1280, 720)]:
		h.size = tam
		var r: Dictionary = h.retangulos()
		var sp: Rect2 = r.SPEEDO
		var esp: Vector2 = caixa.size * (tam.x / 640.0) * (0.75 if tam.x / tam.y > 1.5 else 1.0)
		print("  %dx%d: conta-giros %s (esperado %.1f x %.1f), canto %s" % [tam.x, tam.y, sp, esp.x, esp.y, sp.end])
		if sp.size.distance_to(esp) > 0.5:
			_falha("tamanho do conta-giros")
		if sp.end.x > tam.x or sp.end.y > tam.y or sp.position.x < tam.x * 0.6 or sp.position.y < tam.y * 0.5:
			_falha("conta-giros fora do canto inferior direito")
		var lt: Rect2 = r.LeadTxtElem
		print("    célula do LEAD %.1f px (0.045 x %d = %.1f)" % [lt.size.y, tam.y, 0.045 * tam.y])
		if absf(lt.size.y - 0.045 * tam.y) > 0.5:
			_falha("altura do rótulo")
	var k: Dictionary = h.info.texturas.FONT_SMALL.kern
	var bruto := 0.0
	var junto := 0.0
	var s := "POSITION"
	for i in s.length():
		var c := s.unicode_at(i)
		var w: float = h._caixa("FONT_SMALL", str(c)).size.x
		bruto += w
		junto += w - h._kern(k, c, s.unicode_at(i + 1) if i + 1 < s.length() else 0)
	print("  POSITION: %.0f px sem kerning, %.0f com (fonte de 22 px)" % [bruto, junto])
	if not (junto < bruto - 8.0):
		_falha("kerning não encurtou o texto")
	print("teste_hud: %s" % ("ok" if falhas == 0 else "FALHA (%d)" % falhas))
	h.free()
	quit()
