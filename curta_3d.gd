class_name Curta3D
extends Node3D
## Интерактивная 3D-модель калькулятора Курта. Единицы — сантиметры,
## все детали строятся кодом в _build(). Механика — CurtaModel, здесь
## только геометрия, анимация, пикинг и интерфейс.
##
## Мышь:
##   ползунок — тянуть вверх/вниз (0 сверху, 9 снизу), колесо ±1;
##   ручка — крутить по часовой стрелке (храповик, назад нельзя), полный круг = оборот;
##   головка ручки — щелчок: вытянуть (вычитание) / вдвинуть (сложение);
##   каретка — повернуть на разряд; рычаг сброса — провести полный круг;
##   переключатель счётчика — щелчок; пустое место / правая кнопка — вращать вид, колесо — масштаб.
## Клавиши — как в curta_calculator.gd, плюс Shift+C сброс счётчика, K разрез, Home вид, F1 инструкция.
##
## Пикинг без физики: луч камеры против локальных AABB / цилиндров деталей,
## корпус заслоняет внутренние детали. Поэтому тесты могут подавать
## синтетические события мыши прямо в _unhandled_input в headless-режиме.

@export_range(1, 2) var curta_type: int = 1

const CSV_PATH := "user://curta_log.csv"
const HELP_PAGE := "res://docs/pages/%s/page_%d.png"
const HELP_PDF := "res://docs/instruction_%s.pdf"

## Время автоматического оборота ручки (Enter), с.
const TURN_TIME := 0.6
## Ручку, отпущенную не дальше этого угла после «дома», фиксатор возвращает в ноль.
const CRANK_DETENT := deg_to_rad(15.0)
## Вертикальный угол обзора камеры, градусы.
const VIEW_FOV := 35.0
const ORBIT_SENS := 0.008
const ZOOM_MIN := 8.0
const ZOOM_MAX := 60.0

const C_BODY := Color(0.07, 0.07, 0.08)
const C_BAND := Color(0.17, 0.17, 0.18)
const C_SLOT := Color(0.01, 0.01, 0.012)
const C_METAL := Color(0.8, 0.81, 0.83)
const C_KNOB := Color(0.9, 0.9, 0.87)
const C_SELECT := Color(0.97, 0.75, 0.22)
const C_SUB := Color(0.85, 0.12, 0.1)
const C_DIGIT := Color(0.96, 0.96, 0.92)
const C_DIM := Color(0.62, 0.63, 0.66)
const C_COUNTER := Color(0.98, 0.62, 0.3)
const C_ADD_TOOTH := Color(0.88, 0.72, 0.3)
const C_SUB_TOOTH := Color(0.82, 0.3, 0.25)

# Интерфейс — как в lukyanov_integrator (syringe_rig.gd): строка состояния и ряд кнопок сверху,
# панель регистров справа за линией, подсказки и «F1» внизу.
const C_TEXT := Color(0.92, 0.92, 0.92)
const C_TEXT_DIM := Color(0.55, 0.57, 0.6)
const C_HEAD := Color(0.95, 0.8, 0.3)
const C_BTN := Color(0.24, 0.26, 0.3)
const C_BTN_HOVER := Color(0.34, 0.37, 0.43)
const FS_SMALL := 20
const FS := 24
const FS_BIG := 30
## Правая граница области модели и левый край панели регистров.
const RIG_RIGHT := 1390.0
const PANEL_X := 1440.0
const BTN_Y := 62.0
const BTN_H := 44.0

var model: CurtaModel
var selected := 0
var cutaway := false

# Геометрия текущего типа (см), задаётся в _geometry().
var _R := 2.65
var _pitch := TAU / 16.0
var _body_h := 5.1
var _car_h := 1.36
var _slot_top := 4.2
var _step := 0.41

# Состояние анимации.
## Угол ручки по часовой стрелке от «дома», 0..TAU.
var crank_angle := 0.0
var _crank_auto := false
var _crank_lift := 0.0
var _car_vis := 0.0
var _car_lift := 0.0
var _drum_lift := 0.0
## Накопленный угол рычага сброса (знак — направление).
var lever_angle := 0.0
var _pin_base := PackedFloat32Array()

# Узлы.
var _rig: Node3D
var _carriage: Node3D
var _crank: Node3D
var _lever: Node3D
var _reverse: MeshInstance3D
var _reverse_mat: StandardMaterial3D
var _inner: Node3D
var _drum: Node3D
var _knobs: Array[MeshInstance3D] = []
var _knob_mats: Array[StandardMaterial3D] = []
var _check_labels: Array[Label3D] = []
var _result_labels: Array[Label3D] = []
var _counter_labels: Array[Label3D] = []
var _pinions: Array[Node3D] = []
var _cut_mats: Array[StandardMaterial3D] = []
## Детали для пикинга: {id, node, shape: "box"/"cyl", aabb | r,y0,y1, inner}.
var _parts: Array[Dictionary] = []
var _cam: Camera3D

# Камера.
var _yaw := 0.0
var _pitch_cam := -0.55
var _dist := 24.0
var _target := Vector3(0, 3.5, 0)

# Мышь.
var _drag := ""
var _drag_prev := 0.0
var _drag_start := 0.0
var _drag_start_k := 0
var _hover := ""
var _mouse_pos := Vector2.ZERO

# Интерфейс.
var _hud: CanvasLayer
## Всё, кроме инструкции, рисуется на этом слое в _draw_hud().
var _overlay: Control
var _toast := ""
var _toast_time := 0.0
var _help: Control
var _help_tex: TextureRect
var _help_hint: Label
var _help_open := false
var _help_pages: Array[Texture2D] = []
var _help_page := 0
var _help_lang := ""


func _ready() -> void:
	model = CurtaModel.new(curta_type)
	model.changed.connect(_refresh)
	_build_scene()
	_build()
	_build_hud()
	_reset_view()
	_refresh()


# --- Геометрия ------------------------------------------------------------

func _geometry() -> void:
	var t: Dictionary = CurtaModel.TYPES[model.model_type]
	_R = float(t["diameter_mm"]) / 20.0
	var h := float(t["height_mm"]) / 10.0
	_pitch = TAU / (16.0 if model.model_type == 1 else 20.0)
	_body_h = h * 0.6
	_car_h = h * 0.16
	_slot_top = _body_h - 0.9
	_step = (_body_h - 1.4) / 9.0


## Угол ползунка i: старший разряд слева, если смотреть спереди (+Z).
func slider_angle(i: int) -> float:
	return (float(model.slider_digits() - 1) * 0.5 - i) * _pitch


## Высота ползунка со значением n: 0 вверху, 9 внизу.
func slider_y(n: float) -> float:
	return _slot_top - n * _step


## Угол метки позиции каретки на корпусе (правее ползунка единиц).
func _index_angle() -> float:
	return slider_angle(0) + _pitch


## Середина свободной от цифр результата дуги каретки (в её системе).
func _free_arc() -> Vector2:
	var start := slider_angle(0) + _pitch * 0.5
	var width := TAU - model.result_digits() * _pitch
	return Vector2(start + width * 0.5, width)


func _lever_rest() -> float:
	var f := _free_arc()
	return f.x + f.y * 0.25


func _reverse_angle() -> float:
	var f := _free_arc()
	return f.x - f.y * 0.25


## Угол рычага ручки «дома»: справа сзади.
func _crank_home() -> float:
	return deg_to_rad(135.0)


static func _polar(a: float, r: float, y: float) -> Vector3:
	return Vector3(r * sin(a), y, r * cos(a))


## Базис «лицом наружу» на угле a (локальная +Z смотрит по радиусу).
static func _out_basis(a: float) -> Basis:
	return Basis(Vector3.UP, a)


## Базис для надписи, лежащей на верхней плоскости: верх цифры — к оси.
static func _top_basis(a: float) -> Basis:
	return Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -PI * 0.5)


func _mat(c: Color, metal := 0.0, rough := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, basis := Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, basis := Basis()) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mesh(parent, m, pos, mat, basis)


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, segments := 64) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = segments
	m.rings = 1
	return _mesh(parent, m, pos, mat)


func _label(parent: Node3D, text: String, pos: Vector3, basis: Basis, height: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	# Высота цифры ≈ 0,72 кегля.
	l.pixel_size = height / (64.0 * 0.72)
	l.modulate = color
	l.outline_size = 0
	l.transform = Transform3D(basis, pos)
	parent.add_child(l)
	return l


func _add_box_part(id: String, node: Node3D, size: Vector3, inner := false) -> void:
	_parts.append({"id": id, "node": node, "shape": "box", "aabb": AABB(-size * 0.5, size), "inner": inner})


func _add_cyl_part(id: String, node: Node3D, r: float, y0: float, y1: float, inner := false) -> void:
	_parts.append({"id": id, "node": node, "shape": "cyl", "r": r, "y0": y0, "y1": y1, "inner": inner})


## Камера, свет, окружение — один раз.
func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-30), 0)
	key.light_energy = 1.3
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20), deg_to_rad(150), 0)
	fill.light_energy = 0.5
	add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = VIEW_FOV
	_cam.near = 0.5
	_cam.far = 300.0
	add_child(_cam)


## Весь механизм; вызывается заново при смене типа.
func _build() -> void:
	if _rig != null:
		remove_child(_rig)
		_rig.queue_free()
	_parts.clear()
	_knobs.clear()
	_knob_mats.clear()
	_check_labels.clear()
	_result_labels.clear()
	_counter_labels.clear()
	_pinions.clear()
	_cut_mats.clear()
	_geometry()
	crank_angle = 0.0
	_crank_auto = false
	lever_angle = 0.0
	_car_vis = model.carriage * _pitch
	_car_lift = 0.0
	_crank_lift = 0.35 if model.subtract else 0.0
	_drum_lift = _step * 0.5 if model.subtract else 0.0
	_pin_base = PackedFloat32Array()
	_pin_base.resize(model.slider_digits())
	selected = clampi(selected, 0, model.slider_digits() - 1)

	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	var metal := _mat(C_METAL, 0.85, 0.28)
	var body_mat := _mat(C_BODY, 0.25, 0.35)
	var band_mat := _mat(C_BAND, 0.2, 0.5)
	var slot_mat := _mat(C_SLOT, 0.0, 0.8)
	_cut_mats.append_array([body_mat, band_mat, slot_mat])

	# Корпус и окно контроля установки над прорезями.
	_cyl(_rig, _R, _body_h, Vector3(0, _body_h * 0.5, 0), body_mat)
	_add_cyl_part("body", _rig, _R, 0.0, _body_h)
	_cyl(_rig, _R + 0.025, 0.16, Vector3(0, 0.1, 0), metal)
	_cyl(_rig, _R + 0.008, 0.6, Vector3(0, _body_h - 0.45, 0), band_mat)
	var ia := _index_angle()
	_box(_rig, Vector3(0.08, 0.22, 0.02), _polar(ia, _R + 0.01, _body_h - 0.11), _mat(C_DIGIT), _out_basis(ia))

	# Ползунки: прорезь, ручка, шкала 0–9, цифра в окне контроля.
	var n := model.slider_digits()
	for i in n:
		var a := slider_angle(i)
		var ob := _out_basis(a)
		var span := 9.0 * _step + 0.45
		_box(_rig, Vector3(0.2, span, 0.03), _polar(a, _R + 0.004, _slot_top - 4.5 * _step), slot_mat, ob)
		var km := _mat(C_KNOB, 0.4, 0.35)
		var knob := _box(_rig, Vector3(0.3, 0.24, 0.32), Vector3.ZERO, km, ob)
		_add_box_part("slider:%d" % i, knob, Vector3(0.3, 0.24, 0.32))
		_knobs.append(knob)
		_knob_mats.append(km)
		var da := a + 0.3 / _R
		for v in 10:
			_label(_rig, str(v), _polar(da, _R + 0.012, slider_y(v)), _out_basis(da), 0.16, C_DIM)
		_check_labels.append(_label(_rig, "0", _polar(a, _R + 0.03, _body_h - 0.45), ob, 0.3, C_DIGIT))

	_build_carriage(metal)
	_build_crank(metal)
	_build_inner(metal)


func _build_carriage(metal: StandardMaterial3D) -> void:
	_carriage = Node3D.new()
	_carriage.name = "Carriage"
	_rig.add_child(_carriage)
	_cyl(_carriage, _R, _car_h, Vector3(0, _car_h * 0.5, 0), _mat(C_BODY, 0.3, 0.3))
	_add_cyl_part("carriage", _carriage, _R, 0.0, _car_h)
	_cyl(_carriage, _R + 0.02, 0.1, Vector3(0, _car_h - 0.07, 0), metal)
	_cyl(_carriage, _R * 0.42, 0.04, Vector3(0, _car_h + 0.02, 0), metal)
	var win := _mat(Color(0.2, 0.2, 0.21), 0.1, 0.6)
	var top := _car_h + 0.016
	# Результат — внешнее кольцо, счётчик — внутреннее; разряд j на угле ползунка j при каретке 0.
	for j in model.result_digits():
		var a := slider_angle(j)
		_box(_carriage, Vector3(0.4, 0.02, 0.46), _polar(a, _R * 0.8, _car_h), win, _out_basis(a))
		_result_labels.append(_label(_carriage, "0", _polar(a, _R * 0.8, top), _top_basis(a), 0.36, C_DIGIT))
	for j in model.counter_digits():
		var a := slider_angle(j)
		_box(_carriage, Vector3(0.34, 0.02, 0.4), _polar(a, _R * 0.58, _car_h), win, _out_basis(a))
		_counter_labels.append(_label(_carriage, "0", _polar(a, _R * 0.58, top), _top_basis(a), 0.28, C_COUNTER))
	# Номера позиций каретки на боку: номер p стоит над меткой при сдвиге p.
	for p in model.carriage_positions():
		var a := _index_angle() - p * _pitch
		_label(_carriage, str(p + 1), _polar(a, _R + 0.012, _car_h * 0.3), _out_basis(a), 0.2, C_DIM)

	# Рычаг сброса: ходит по кругу над кромкой каретки.
	_lever = Node3D.new()
	_lever.position = Vector3(0, _car_h, 0)
	_carriage.add_child(_lever)
	_box(_lever, Vector3(0.14, 0.08, _R * 0.55), Vector3(0, 0.1, _R * 0.68), metal)
	var tab := _box(_lever, Vector3(0.36, 0.34, 0.24), Vector3(0, 0.18, _R * 0.98), metal)
	_add_box_part("lever", tab, Vector3(0.36, 0.34, 0.24))

	# Переключатель счётчика.
	var ra := _reverse_angle()
	_reverse_mat = _mat(C_METAL, 0.6, 0.3)
	_reverse = _box(_carriage, Vector3(0.36, 0.2, 0.22), _polar(ra, _R * 0.6, _car_h + 0.1), _reverse_mat, _out_basis(ra))
	_add_box_part("reverse", _reverse, Vector3(0.36, 0.2, 0.22))


func _build_crank(metal: StandardMaterial3D) -> void:
	_crank = Node3D.new()
	_crank.name = "Crank"
	_rig.add_child(_crank)
	var hub_r := _R * 0.15
	var hub := _cyl(_crank, hub_r, 0.55, Vector3(0, 0.3, 0), metal, 32)
	_add_cyl_part("hub", hub, hub_r, -0.275, 0.275)
	# Красное кольцо на валу видно, только когда ручка вытянута (вычитание).
	_cyl(_crank, hub_r * 0.75, 0.3, Vector3(0, -0.13, 0), _mat(C_SUB, 0.1, 0.4), 32)
	var arm_node := Node3D.new()
	arm_node.rotation.y = _crank_home()
	_crank.add_child(arm_node)
	var arm_len := _R * 0.85
	var arm_size := Vector3(0.34, 0.16, arm_len)
	var arm := _box(arm_node, arm_size, Vector3(0, 0.5, arm_len * 0.5), metal)
	_add_box_part("crank", arm, arm_size)
	var handle := _cyl(arm_node, 0.22, 1.0, Vector3(0, 1.0, arm_len), _mat(C_BODY, 0.2, 0.3), 24)
	_add_cyl_part("crank", handle, 0.22, -0.5, 0.5)


## Внутренности (видны в разрезе): ступенчатый вал и шестерни ползунков.
func _build_inner(metal: StandardMaterial3D) -> void:
	_inner = Node3D.new()
	_inner.name = "Inner"
	_rig.add_child(_inner)
	_drum = Node3D.new()
	_inner.add_child(_drum)
	var core_r := _R * 0.36
	var rib_out := _R * 0.51
	var drum := _cyl(_drum, core_r, 9.0 * _step + 0.6, Vector3(0, _slot_top - 4.5 * _step, 0), metal, 32)
	_add_cyl_part("drum", drum, core_r, -(9.0 * _step + 0.6) * 0.5, (9.0 * _step + 0.6) * 0.5, true)
	_cyl(_inner, 0.12, _body_h + _car_h, Vector3(0, (_body_h + _car_h) * 0.5, 0), metal, 16)
	# Ребро r (1..9) сложения есть на уровнях n ≥ r — шестерня на уровне n цепляет n рёбер.
	# Ребро дополнения есть на уровнях n ≤ 9 − r — цепляет 9 − n; его слой на полшага ниже,
	# в режиме вычитания вал поднимается на полшага и под шестернями оказывается он.
	var add_mat := _mat(C_ADD_TOOTH, 0.6, 0.35)
	var sub_mat := _mat(C_SUB_TOOTH, 0.4, 0.4)
	var rib_len := rib_out - core_r
	for r in range(1, 10):
		var a := deg_to_rad(18.0 * (r - 1))
		var pos_r := core_r + rib_len * 0.5
		for lvl in 10:
			if lvl >= r:
				_box(_drum, Vector3(0.16, _step * 0.42, rib_len), _polar(a, pos_r, slider_y(lvl)), add_mat, _out_basis(a))
			if lvl <= 9 - r:
				_box(_drum, Vector3(0.16, _step * 0.42, rib_len), _polar(a, pos_r, slider_y(lvl) - _step * 0.5), sub_mat, _out_basis(a))
	# Шестерни ползунков на квадратных валах.
	var pin_r := _R * 0.09
	var pin_c := rib_out + pin_r
	var pin_mat := _mat(Color(0.75, 0.6, 0.35), 0.7, 0.3)
	# Нулевой зуб шестерни красный — чтобы был виден её поворот.
	var mark_mat := _mat(C_SUB, 0.2, 0.4)
	for i in model.slider_digits():
		var a := slider_angle(i)
		_box(_inner, Vector3(0.08, _body_h - 0.4, 0.08), _polar(a, pin_c, _body_h * 0.5 + 0.1), metal)
		var pin := Node3D.new()
		pin.position = _polar(a, pin_c, slider_y(0))
		_inner.add_child(pin)
		var disc := _cyl(pin, pin_r, 0.2, Vector3.ZERO, pin_mat, 20)
		_add_cyl_part("pinion:%d" % i, disc, pin_r + 0.05, -0.1, 0.1, true)
		for tooth in 10:
			var ta := TAU * tooth / 10.0
			_box(pin, Vector3(0.05, 0.2, 0.1), _polar(ta, pin_r + 0.04, 0.0), mark_mat if tooth == 0 else pin_mat, _out_basis(ta))
		_pinions.append(pin)


# --- Обновление и анимация ----------------------------------------------

func _process(delta: float) -> void:
	if _crank_auto:
		crank_angle += TAU * delta / TURN_TIME
		if crank_angle >= TAU:
			_complete_turn()
	var target := model.carriage * _pitch
	var moving := absf(_car_vis - target) > 1e-4
	_car_vis = move_toward(_car_vis, target, delta * _pitch * 10.0)
	_car_lift = move_toward(_car_lift, 0.25 if moving else 0.0, delta * 3.0)
	_crank_lift = move_toward(_crank_lift, 0.35 if model.subtract else 0.0, delta * 2.5)
	_drum_lift = move_toward(_drum_lift, _step * 0.5 if model.subtract else 0.0, delta * 2.0)
	if _drag != "lever":
		lever_angle = move_toward(lever_angle, 0.0, delta * 10.0)
	_toast_time = maxf(_toast_time - delta, 0.0)
	_apply_pose()
	if _overlay != null:
		_overlay.queue_redraw()


## Положения деталей по модели и состоянию анимации.
func _apply_pose() -> void:
	if _rig == null:
		return
	_carriage.position = Vector3(0, _body_h + _car_lift, 0)
	_carriage.rotation.y = _car_vis
	_lever.rotation.y = _lever_rest() + lever_angle
	_crank.position = Vector3(0, _body_h + _car_h + _car_lift + _crank_lift, 0)
	# По часовой стрелке, если смотреть сверху, — отрицательный поворот вокруг +Y.
	_crank.rotation.y = -crank_angle
	_drum.rotation.y = -crank_angle
	_drum.position.y = _drum_lift
	var ra := _reverse_angle() + (0.12 if model.counter_reverse else -0.12) / (_R * 0.6)
	_reverse.position = _polar(ra, _R * 0.6, _car_h + 0.1)
	_reverse.basis = _out_basis(ra)
	var frac := crank_angle / TAU
	for i in _knobs.size():
		var a := slider_angle(i)
		var y := slider_y(model.sliders[i])
		_knobs[i].position = _polar(a, _R + 0.15, y)
		_pinions[i].position.y = y
		var t := CurtaModel.teeth(model.sliders[i], model.subtract)
		_pinions[i].rotation.y = _pin_base[i] + TAU * t / 10.0 * frac


func _complete_turn() -> void:
	for i in _pin_base.size():
		_pin_base[i] = fmod(_pin_base[i] + TAU * CurtaModel.teeth(model.sliders[i], model.subtract) / 10.0, TAU)
	crank_angle = 0.0
	_crank_auto = false
	model.turn()
	if model.overflow:
		_show_toast(I18n.t("Перенос за старший разряд потерян"))


## Ручка не «дома» — каретка, режим, сброс и тип заблокированы.
func crank_locked() -> bool:
	return _crank_auto or crank_angle > 1e-4


func _refresh() -> void:
	if _rig == null or _result_labels.size() != model.result_digits():
		return
	for j in _result_labels.size():
		_result_labels[j].text = str(model.result[j])
	for j in _counter_labels.size():
		_counter_labels[j].text = str(model.counter[j])
	for i in _check_labels.size():
		_check_labels[i].text = str(model.sliders[i])
		_knob_mats[i].albedo_color = C_SELECT if i == selected else C_KNOB
	_reverse_mat.albedo_color = C_SUB if model.counter_reverse else C_METAL
	_apply_pose()
	_refresh_hud()


# --- Действия ------------------------------------------------------------

func turn_crank() -> void:
	_crank_auto = true


func toggle_subtract() -> void:
	if _locked_toast():
		return
	model.set_subtract(not model.subtract)


func shift_carriage(dir: int) -> void:
	if _locked_toast():
		return
	model.set_carriage(model.carriage + dir)


func clear_registers() -> void:
	if _locked_toast():
		return
	model.clear_registers()
	_show_toast(I18n.t("Результат и счётчик сброшены"))


## Только счётчик — после загрузки делимого или подкоренного числа.
func clear_counter() -> void:
	if _locked_toast():
		return
	model.clear_counter()
	_show_toast(I18n.t("Счётчик сброшен"))


func toggle_reverse() -> void:
	model.set_counter_reverse(not model.counter_reverse)


func set_cutaway(on: bool) -> void:
	cutaway = on
	for m in _cut_mats:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else BaseMaterial3D.TRANSPARENCY_DISABLED
		m.albedo_color.a = 0.16 if on else 1.0
	_inner.visible = on
	_refresh_hud()


func switch_type() -> void:
	if _locked_toast():
		return
	curta_type = 2 if model.model_type == 1 else 1
	_drag = ""
	model.set_type(curta_type)
	_build()
	set_cutaway(cutaway)
	_reset_view()
	_refresh()


func save_csv() -> bool:
	var ok := model.save_csv(CSV_PATH)
	_show_toast(I18n.t("Сохранено: %s") % ProjectSettings.globalize_path(CSV_PATH) if ok else I18n.t("Не удалось сохранить CSV"))
	return ok


func _locked_toast() -> bool:
	if crank_locked():
		_show_toast(I18n.t("Сначала доверните ручку до конца оборота"))
		return true
	return false


func _reset_view() -> void:
	_yaw = 0.0
	_pitch_cam = -0.55
	_dist = 21.5 if model.model_type == 1 else 25.0
	_target = Vector3(0, (_body_h + _car_h) * 0.55, 0)
	_update_camera()


func _update_camera() -> void:
	_pitch_cam = clampf(_pitch_cam, -1.45, 0.6)
	_dist = clampf(_dist, ZOOM_MIN, ZOOM_MAX)
	var off := Basis.from_euler(Vector3(_pitch_cam, _yaw, 0)) * Vector3(0, 0, _dist)
	_cam.transform = Transform3D(Basis(), _target + off).looking_at(_target, Vector3.UP)
	# Модель — посередине области слева от панели (до RIG_RIGHT), а не экрана. Сдвигаем
	# пирамиду видимости, а не камеру (h_offset сдвинул бы глаз и изменил ракурс).
	var size := 2.0 * _cam.near * tan(deg_to_rad(VIEW_FOV) * 0.5)
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_cam.size = size
	_cam.frustum_offset = Vector2(size * 0.5 * (960.0 - RIG_RIGHT * 0.5) / 540.0, 0.0)


# --- Пикинг ----------------------------------------------------------------

## Расстояние вдоль луча до пересечения с вертикальным цилиндром (локальная Y), −1 — мимо.
static func _ray_cyl(o: Vector3, d: Vector3, r: float, y0: float, y1: float) -> float:
	var best := INF
	var a := d.x * d.x + d.z * d.z
	if a > 1e-9:
		var b := 2.0 * (o.x * d.x + o.z * d.z)
		var c := o.x * o.x + o.z * o.z - r * r
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			for t in [(-b - sq) / (2.0 * a), (-b + sq) / (2.0 * a)]:
				var y: float = o.y + d.y * t
				if t >= 0.0 and y >= y0 and y <= y1:
					best = minf(best, t)
	if absf(d.y) > 1e-9:
		for cap in [y0, y1]:
			var t: float = (cap - o.y) / d.y
			var p := o + d * t
			if t >= 0.0 and p.x * p.x + p.z * p.z <= r * r:
				best = minf(best, t)
	return best if best < INF else -1.0


func _ray_part(p: Dictionary, o: Vector3, d: Vector3) -> float:
	var node: Node3D = p["node"]
	if not node.is_visible_in_tree():
		return -1.0
	var inv := node.global_transform.affine_inverse()
	var lo := inv * o
	var ld := (inv.basis * d).normalized()
	if p["shape"] == "box":
		var hit: Variant = (p["aabb"] as AABB).intersects_ray(lo, ld)
		if hit == null:
			return -1.0
		return maxf(((hit as Vector3) - lo).dot(ld), 0.0)
	return _ray_cyl(lo, ld, p["r"], p["y0"], p["y1"])


## Деталь под точкой экрана. В обычном виде корпус заслоняет внутренности,
## в разрезе он прозрачный и сам не ловится (кроме промаха по всему остальному).
func pick(screen: Vector2) -> String:
	var o := _cam.global_position
	var d := ray_dir(screen)
	var best := ""
	var best_t := INF
	var body_t := -1.0
	for p in _parts:
		if p["id"] == "body":
			body_t = _ray_part(p, o, d)
			if cutaway:
				continue
		elif p["inner"] and not cutaway:
			continue
		var t := _ray_part(p, o, d)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = p["id"]
	if best == "" and body_t >= 0.0:
		return "body"
	return best


## Мировая точка детали (центр её формы) — для тестов и подсказок.
func part_point(id: String) -> Vector3:
	for p in _parts:
		if p["id"] == id:
			var node: Node3D = p["node"]
			if p["shape"] == "box":
				return node.global_transform * (p["aabb"] as AABB).get_center()
			return node.global_transform * Vector3(0, (float(p["y0"]) + float(p["y1"])) * 0.5, 0)
	return Vector3.ZERO


## Направление луча из глаза камеры через точку экрана. Считаем сами: project_ray_normal()
## не учитывает frustum_offset, которым кадр сдвинут влево от панели.
func ray_dir(screen: Vector2) -> Vector3:
	var view := get_viewport().get_visible_rect().size
	var hh := _cam.size * 0.5
	var hw := hh * view.x / view.y
	var local := Vector3(_cam.frustum_offset.x + (screen.x / view.x * 2.0 - 1.0) * hw,
			_cam.frustum_offset.y + (1.0 - screen.y / view.y * 2.0) * hh, -_cam.near)
	return (_cam.global_transform.basis * local).normalized()


func screen_of(world: Vector3) -> Vector2:
	return _cam.unproject_position(world)


## Пересечение луча с горизонтальной плоскостью y = h; null — нет.
func _hit_plane_y(screen: Vector2, h: float) -> Variant:
	return Plane(Vector3.UP, h).intersects_ray(_cam.global_position, ray_dir(screen))


## Угол точки экрана вокруг оси машины на высоте h (как у _polar), NAN — мимо.
func _axis_angle(screen: Vector2, h: float) -> float:
	var hit: Variant = _hit_plane_y(screen, h)
	if hit == null:
		return NAN
	var p: Vector3 = hit
	return atan2(p.x, p.z)


## Значение ползунка i под курсором: вертикальная плоскость через прорезь лицом к камере.
func _slider_value_at(i: int, screen: Vector2) -> int:
	var a := slider_angle(i)
	var p0 := _polar(a, _R + 0.15, 0.0)
	var n := _cam.global_transform.basis.z
	n.y = 0.0
	if n.length() < 1e-4:
		return model.sliders[i]
	var hit: Variant = Plane(n.normalized(), p0).intersects_ray(_cam.global_position, ray_dir(screen))
	if hit == null:
		return model.sliders[i]
	return clampi(roundi((_slot_top - (hit as Vector3).y) / _step), 0, 9)


# --- Ввод ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F1:
		_set_help(not _help_open)
	elif _help_open:
		if not _help_input(event):
			return
	elif key != null:
		if not key.pressed or not _key(key):
			return
	elif event is InputEventMouseButton:
		if not _mouse_button(event as InputEventMouseButton):
			return
	elif event is InputEventMouseMotion:
		_mouse_motion(event as InputEventMouseMotion)
		return
	else:
		return
	get_viewport().set_input_as_handled()


func _key(key: InputEventKey) -> bool:
	if key.keycode >= KEY_0 and key.keycode <= KEY_9:
		model.type_digit(key.keycode - KEY_0)
		return true
	if key.keycode >= KEY_KP_0 and key.keycode <= KEY_KP_9:
		model.type_digit(key.keycode - KEY_KP_0)
		return true
	match key.keycode:
		KEY_BACKSPACE:
			model.backspace()
		KEY_LEFT:
			select_slider(selected + 1)
		KEY_RIGHT:
			select_slider(selected - 1)
		KEY_UP:
			model.set_slider(selected, model.sliders[selected] - 1)
		KEY_DOWN:
			model.set_slider(selected, model.sliders[selected] + 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			turn_crank()
		KEY_TAB:
			toggle_subtract()
		KEY_BRACKETLEFT:
			shift_carriage(-1)
		KEY_BRACKETRIGHT:
			shift_carriage(1)
		KEY_C:
			if key.shift_pressed:
				clear_counter()
			else:
				clear_registers()
		KEY_X:
			model.clear_sliders()
		KEY_V:
			toggle_reverse()
		KEY_K:
			set_cutaway(not cutaway)
		KEY_T:
			switch_type()
		KEY_S:
			if not key.echo:
				save_csv()
		KEY_L:
			if not key.echo:
				_toggle_lang()
		KEY_HOME:
			_reset_view()
		_:
			return false
	return true


func select_slider(i: int) -> void:
	selected = clampi(i, 0, model.slider_digits() - 1)
	_refresh()


func _mouse_button(ev: InputEventMouseButton) -> bool:
	_mouse_pos = ev.position
	match ev.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not ev.pressed:
				return true
			var dir := -1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			var id := pick(ev.position)
			if id.begins_with("slider:"):
				var i := id.get_slice(":", 1).to_int()
				select_slider(i)
				model.set_slider(i, model.sliders[i] + dir)
			else:
				_dist *= 1.1 if dir > 0 else 1.0 / 1.1
				_update_camera()
			return true
		MOUSE_BUTTON_RIGHT:
			_drag = "orbit" if ev.pressed else ""
			return true
		MOUSE_BUTTON_LEFT:
			if ev.pressed and _button_at(ev.position) != "":
				press_button(_button_at(ev.position))
			elif ev.pressed:
				_press(ev.position)
			else:
				# Фиксатор «дома»: ручка, отпущенная чуть дальше нуля, встаёт на место.
				if _drag == "crank" and crank_angle < CRANK_DETENT:
					crank_angle = 0.0
					_apply_pose()
				_drag = ""
			return true
	return false


func _press(pos: Vector2) -> void:
	var id := pick(pos)
	_drag = ""
	if id.begins_with("slider:"):
		var i := id.get_slice(":", 1).to_int()
		select_slider(i)
		_drag = id
		model.set_slider(i, _slider_value_at(i, pos))
	elif id == "crank":
		_drag = "crank"
		_crank_auto = false
		_drag_prev = _axis_angle(pos, _crank.position.y + 0.5)
	elif id == "hub":
		toggle_subtract()
	elif id == "carriage":
		if not _locked_toast():
			_drag = "carriage"
			_drag_start = _axis_angle(pos, _body_h + _car_h)
			_drag_start_k = model.carriage
	elif id == "lever":
		if not _locked_toast():
			_drag = "lever"
			_drag_prev = _axis_angle(pos, _body_h + _car_h)
	elif id == "reverse":
		toggle_reverse()
	else:
		_drag = "orbit"


func _mouse_motion(ev: InputEventMouseMotion) -> void:
	_mouse_pos = ev.position
	if _drag == "":
		var b := _button_at(ev.position)
		_set_hover("btn:" + b if b != "" else pick(ev.position))
		return
	if _drag == "orbit":
		_yaw -= ev.relative.x * ORBIT_SENS
		_pitch_cam -= ev.relative.y * ORBIT_SENS
		_update_camera()
	elif _drag.begins_with("slider:"):
		var i := _drag.get_slice(":", 1).to_int()
		var v := _slider_value_at(i, ev.position)
		if v != model.sliders[i]:
			model.set_slider(i, v)
	elif _drag == "crank":
		var a := _axis_angle(ev.position, _crank.position.y + 0.5)
		if is_nan(a) or is_nan(_drag_prev):
			_drag_prev = a
			return
		# Храповик: по часовой стрелке (угол убывает) — крутим, назад — ручка стоит.
		var cw := -wrapf(a - _drag_prev, -PI, PI)
		_drag_prev = a
		if cw > 0.0:
			crank_angle += cw
			if crank_angle >= TAU:
				_complete_turn()
			_apply_pose()
	elif _drag == "carriage":
		var a := _axis_angle(ev.position, _body_h + _car_h)
		if is_nan(a) or is_nan(_drag_start):
			return
		var k := _drag_start_k + roundi(wrapf(a - _drag_start, -PI, PI) / _pitch)
		if clampi(k, 0, model.carriage_positions() - 1) != model.carriage:
			model.set_carriage(k)
	elif _drag == "lever":
		var a := _axis_angle(ev.position, _body_h + _car_h)
		if is_nan(a) or is_nan(_drag_prev):
			_drag_prev = a
			return
		lever_angle += wrapf(a - _drag_prev, -PI, PI)
		_drag_prev = a
		if absf(lever_angle) >= TAU:
			lever_angle = 0.0
			_drag = ""
			clear_registers()
		_apply_pose()


func _set_hover(id: String) -> void:
	_hover = id
	if _overlay != null:
		_overlay.queue_redraw()


func _tooltip_text(id: String) -> String:
	if id.begins_with("slider:"):
		var i := id.get_slice(":", 1).to_int()
		return I18n.t("Ползунок разряда %d (= %d): тяните вверх/вниз или колесо") % [i + 1, model.sliders[i]]
	if id.begins_with("pinion:"):
		var i := id.get_slice(":", 1).to_int()
		return I18n.t("Шестерня ползунка %d: за оборот ручки поворачивается на %d/10") % [i + 1,
				CurtaModel.teeth(model.sliders[i], model.subtract)]
	match id:
		"crank":
			return I18n.t("Ручка: крутите по часовой стрелке, полный круг — одна операция")
		"hub":
			return I18n.t("Головка ручки: щелчок — вытянуть (вычитание) или вдвинуть (сложение)")
		"carriage":
			return I18n.t("Каретка: поверните на разряд (сдвиг = умножение на 10)")
		"lever":
			return I18n.t("Рычаг сброса: проведите полный круг — обнулить результат и счётчик")
		"reverse":
			return I18n.t("Переключатель счётчика: реверс для деления и корня")
		"drum":
			return I18n.t("Ступенчатый вал: рёбра сложения (жёлтые) и дополнения (красные) чередуются по высоте")
		"body":
			return I18n.t("Корпус: тяните — вращать вид, колесо — масштаб, K — разрез")
	return ""


# --- Интерфейс -------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_hud)
	_hud.add_child(_overlay)

	_help = ColorRect.new()
	(_help as ColorRect).color = Color(0.05, 0.05, 0.06, 0.94)
	_help.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.visible = false
	_hud.add_child(_help)
	_help_tex = TextureRect.new()
	_help_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help_tex.offset_bottom = -30
	_help_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_help_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_help_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.add_child(_help_tex)
	_help_hint = Label.new()
	_help_hint.add_theme_font_size_override("font_size", FS_SMALL)
	_help_hint.add_theme_color_override("font_color", C_TEXT_DIM)
	_help_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_help.add_child(_help_hint)
	_help_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Кнопки: id, текст, прямоугольник, «включено». Ширина по тексту; не влезли до RIG_RIGHT — новый ряд.
func _buttons() -> Array[Dictionary]:
	var font := ThemeDB.fallback_font
	var defs := [
		["turn", I18n.t("Оборот"), false],
		# Кнопка режима показывает, на что переключит; рамка — «сейчас вычитание».
		["mode", I18n.t("Сложение") if model.subtract else I18n.t("Вычитание"), model.subtract],
		["car_left", I18n.t("◀ Каретка"), false],
		["car_right", I18n.t("Каретка ▶"), false],
		["clear", I18n.t("Сброс"), false],
		["reverse", I18n.t("Реверс"), model.counter_reverse],
		["cutaway", I18n.t("Разрез"), cutaway],
		["type", I18n.t("Тип II") if model.model_type == 1 else I18n.t("Тип I"), false],
		["csv", I18n.t("CSV"), false],
		["help", I18n.t("Инструкция"), false],
		# Кнопка показывает язык, на который переключит.
		["lang", "English" if I18n.current() == "ru" else "Русский", false],
	]
	var out: Array[Dictionary] = []
	var x := 24.0
	var y := BTN_Y
	for d in defs:
		var w := font.get_string_size(d[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x + 18.0
		if x + w > RIG_RIGHT:
			x = 24.0
			y += BTN_H + 8.0
		out.append({"id": d[0], "text": d[1], "rect": Rect2(x, y, w, BTN_H), "on": d[2]})
		x += w + 8.0
	return out


func _button_at(pos: Vector2) -> String:
	if _help_open:
		return ""
	for b in _buttons():
		if (b["rect"] as Rect2).has_point(pos):
			return b["id"]
	return ""


func press_button(id: String) -> void:
	match id:
		"turn": turn_crank()
		"mode": toggle_subtract()
		"car_left": shift_carriage(-1)
		"car_right": shift_carriage(1)
		"clear": clear_registers()
		"sliders": model.clear_sliders()
		"reverse": toggle_reverse()
		"cutaway": set_cutaway(not cutaway)
		"type": switch_type()
		"csv": save_csv()
		"lang": _toggle_lang()
		"help": _set_help(true)
		"view": _reset_view()


func _toggle_lang() -> void:
	I18n.toggle()
	_refresh_hud()
	if _help_open:
		_load_help()


func _group(s: String) -> String:
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += " "
		out += s[i]
	return out


func _refresh_hud() -> void:
	if _overlay != null:
		_overlay.queue_redraw()


func _show_toast(text: String) -> void:
	_toast = text
	_toast_time = 4.0
	_refresh_hud()


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var ci := _overlay
	# Строка состояния и версия (в репозитории "dev", в релизе её проставляет CI).
	var status := I18n.t("Курта, тип %s    %s    каретка %d / %d%s") % [
		"I" if model.model_type == 1 else "II",
		I18n.t("ВЫЧИТАНИЕ") if model.subtract else I18n.t("сложение"),
		model.carriage + 1, model.carriage_positions(),
		I18n.t("    [РЕВЕРС СЧЁТЧИКА]") if model.counter_reverse else ""]
	ci.draw_string(font, Vector2(24, 44), status, HORIZONTAL_ALIGNMENT_LEFT, RIG_RIGHT - 340, FS_BIG,
			C_SUB.lightened(0.35) if model.subtract else C_TEXT)
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	ci.draw_string(font, Vector2(RIG_RIGHT - 300, 40), version if version == "dev" else "v" + version,
			HORIZONTAL_ALIGNMENT_RIGHT, 300, FS_SMALL, C_TEXT_DIM)
	# Кнопки: подсветка под мышью, рамка — включённый режим.
	var buttons := _buttons()
	for b in buttons:
		var r: Rect2 = b["rect"]
		var on: bool = b["on"]
		ci.draw_rect(r, C_BTN_HOVER if _hover == "btn:" + str(b["id"]) else C_BTN)
		ci.draw_rect(r, C_HEAD if on else C_TEXT_DIM, false, 2.0 if on else 1.0)
		ci.draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + FS * 0.36), str(b["text"]),
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, FS, C_TEXT)
	if _toast_time > 0.0:
		var bottom: float = (buttons.back()["rect"] as Rect2).end.y
		ci.draw_string(font, Vector2(24, bottom + 34), _toast, HORIZONTAL_ALIGNMENT_LEFT, RIG_RIGHT - 24, FS_SMALL, C_HEAD)
	_draw_footer(font)
	_draw_panel(font)
	_draw_tooltip(font)


## Строки панели: «#» в начале — заголовок (крупнее, жёлтый).
func _draw_lines(font: Font, x: float, y: float, lines: PackedStringArray, step: float) -> float:
	for line in lines:
		var head := line.begins_with("#")
		var text := line.substr(1) if head else line
		_overlay.draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_BIG if head else FS,
				C_HEAD if head else C_TEXT)
		y += step + (8.0 if head else 0.0)
	return y


## Подробности — в инструкции (F1), здесь только подсказка.
func _draw_footer(font: Font) -> void:
	var lines := PackedStringArray([
		I18n.t("Мышь: тяните ползунки, крутите ручку, поворачивайте каретку; щелчок по головке ручки — вычитание."),
		I18n.t("Клавиши: 0–9 набор, Enter оборот, Tab ±, [ ] каретка, C / Shift+C сброс, X, V, K, T, S, L, Home."),
	])
	for i in lines.size():
		_overlay.draw_string(font, Vector2(24, 935 + i * 38), lines[i], HORIZONTAL_ALIGNMENT_LEFT, RIG_RIGHT - 24, FS, C_TEXT)
	_overlay.draw_string(font, Vector2(24, 1040), I18n.t("F1 — инструкция: устройство и приёмы счёта"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS_BIG, C_HEAD)


func _draw_panel(font: Font) -> void:
	_overlay.draw_line(Vector2(PANEL_X - 20, 14), Vector2(PANEL_X - 20, 1066), C_TEXT_DIM, 1.5)
	var lines := PackedStringArray([
		I18n.t("#Установка"),
		_group(CurtaModel.digits_string(model.sliders)) + "   = %d" % model.slider_value(),
		"",
		I18n.t("#Результат"),
		_group(CurtaModel.digits_string(model.result)),
		"= %d" % model.result_signed(),
		"",
		I18n.t("#Счётчик оборотов"),
		_group(CurtaModel.digits_string(model.counter)) + "   = %d" % model.counter_signed(),
		I18n.t("Оборотов: %d") % model.turns,
		"",
		I18n.t("#Последние операции"),
	])
	var first := maxi(1, model.log_rows.size() - 8)
	for r in range(first, model.log_rows.size()):
		var c := model.log_rows[r].split(",")
		var res := c[4].lstrip("0")
		lines.append("%s.  %s  %s %s  →  %s" % [c[0], c[1], I18n.t("поз."), c[2], res if res != "" else "0"])
	_draw_lines(font, PANEL_X, 50, lines, 38)


## Подсказка к детали под мышью.
func _draw_tooltip(font: Font) -> void:
	var text := _tooltip_text(_hover)
	if text == "" or _drag != "":
		return
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_SMALL) + Vector2(16, 12)
	var pos := (_mouse_pos + Vector2(22, 18)).clamp(Vector2.ZERO, _overlay.size - size)
	_overlay.draw_rect(Rect2(pos, size), Color(0.02, 0.02, 0.03, 0.88))
	_overlay.draw_string(font, pos + Vector2(8, 6 + FS_SMALL * 0.8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_SMALL, C_TEXT)


# --- Инструкция (F1) -------------------------------------------------------
# Godot не умеет показывать PDF — страницы заранее отрендерены в PNG
# скриптом docs/build_instruction.py.

func _set_help(open: bool) -> void:
	_help_open = open
	_drag = ""
	_help.visible = open
	if open:
		_set_hover("")
		_load_help()


func _load_help() -> void:
	var lang := I18n.current()
	if _help_lang != lang:
		_help_lang = lang
		_help_pages.clear()
		_help_page = 0
		var i := 1
		while ResourceLoader.exists(HELP_PAGE % [lang, i]):
			_help_pages.append(load(HELP_PAGE % [lang, i]) as Texture2D)
			i += 1
	_show_help_page()


func _show_help_page() -> void:
	if _help_pages.is_empty():
		_help_tex.texture = null
		_help_hint.text = I18n.t("Нет страниц инструкции — запустите docs/build_instruction.py")
		_help_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return
	_help_tex.texture = _help_pages[_help_page]
	_help_hint.text = I18n.t("стр. %d / %d     ← → листать     O открыть PDF     F1 / Esc закрыть") % [_help_page + 1, _help_pages.size()]
	_help_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM


func _flip_help(dir: int) -> void:
	_help_page = clampi(_help_page + dir, 0, maxi(_help_pages.size() - 1, 0))
	_show_help_page()


## В собранной игре PDF лежат рядом с .exe, в проекте — в docs/.
func _help_pdf_path() -> String:
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join((HELP_PDF % I18n.current()).get_file())
	return ProjectSettings.globalize_path(HELP_PDF % I18n.current())


func _help_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	var mouse := event as InputEventMouseButton
	if key != null and key.pressed:
		match key.keycode:
			KEY_ESCAPE:
				_set_help(false)
			KEY_RIGHT, KEY_PAGEDOWN, KEY_DOWN:
				_flip_help(1)
			KEY_LEFT, KEY_PAGEUP, KEY_UP:
				_flip_help(-1)
			KEY_HOME:
				_help_page = 0
				_show_help_page()
			KEY_O:
				if not key.echo:
					OS.shell_open(_help_pdf_path())
			KEY_L:
				if not key.echo:
					_toggle_lang()
			_:
				return false
		return true
	if mouse != null and mouse.pressed:
		match mouse.button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				_flip_help(1)
			MOUSE_BUTTON_WHEEL_UP:
				_flip_help(-1)
			MOUSE_BUTTON_LEFT:
				_flip_help(1 if mouse.position.x > get_viewport().get_visible_rect().size.x * 0.5 else -1)
		return true
	return false
