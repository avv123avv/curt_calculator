extends SceneTree
## Скриншоты для инструкции и README: docs/scheme_<lang>.png и docs/cutaway_<lang>.png.
## Запуск (с окном, не headless):  godot --path . -s docs/screenshot.gd -- --lang=ru
## Состояние — конец примера 123 × 456 из инструкции.

const SHOTS := ["scheme", "cutaway"]

var _c: Curta3D
var _frame := 0
var _shot := 0


func _initialize() -> void:
	_c = load("res://curta_3d.tscn").instantiate()
	root.add_child(_c)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_set_state(SHOTS[_shot])
	elif _frame == 30:
		var path := ProjectSettings.globalize_path("res://docs/%s_%s.png" % [SHOTS[_shot], I18n.current()])
		root.get_viewport().get_texture().get_image().save_png(path)
		print("Сохранено: ", path)
		_shot += 1
		_frame = 0
		if _shot >= SHOTS.size():
			quit()
	return false


func _set_state(shot: String) -> void:
	var m := _c.model
	m.set_type(1)
	m.set_sliders_value(123)
	for k in 3:
		m.set_carriage(k)
		m.turns_n([6, 5, 4][k])
	_c.selected = 0
	_c.set_cutaway(shot == "cutaway")
	_c._reset_view()
	if shot == "cutaway":
		m.set_carriage(0)
		m.set_sliders_value(40961)
		_c._yaw = 0.45
		_c._pitch_cam = -0.35
		_c._update_camera()
	_c._refresh()
