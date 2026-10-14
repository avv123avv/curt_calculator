class_name CurtaCalculator
extends Node2D
## Абстрактная схема калькулятора Курта: регистры по разрядам, ползунки
## и развёртка ступенчатого вала под каждым ползунком.
## Повесьте скрипт на Node2D в новой сцене и запустите (сцена main.tscn).
##
## Управление:
##   0–9 / Backspace — набрать число на ползунках (цифры вдвигаются справа)
##   ← / →   — выбрать ползунок,  ↑ / ↓ — его значение
##   Enter   — оборот ручки
##   Tab     — ручка вверх / вниз (вычитание / сложение)
##   [ / ]   — каретка на позицию меньше / больше
##   C       — сброс регистров (рычаг сброса), X — сброс ползунков
##   V       — переключатель счётчика, T — тип I / II
##   S       — сохранить журнал в CSV, L — язык

@export_range(1, 2) var curta_type: int = 1

const CSV_PATH := "user://curta_log.csv"

const COL_W := 76.0
const RIGHT_X := 1500.0
const COUNTER_Y := 150.0
const RESULT_Y := 250.0
const SLIDER_Y := 400.0
const SLIDER_STEP := 26.0
const DRUM_Y := 700.0

const COLOR_TEXT := Color(0.92, 0.92, 0.92)
const COLOR_DIM := Color(0.55, 0.57, 0.6)
const COLOR_BOX := Color(0.2, 0.21, 0.24)
const COLOR_ACTIVE := Color(0.95, 0.8, 0.3)
const COLOR_SUB := Color(0.9, 0.35, 0.3)
const COLOR_RIB := Color(0.62, 0.65, 0.7)
const COLOR_COUNTER := Color(0.95, 0.55, 0.3)

var model: CurtaModel
var selected := 0


func _ready() -> void:
	model = CurtaModel.new(curta_type)
	model.changed.connect(queue_redraw)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode >= KEY_0 and key.keycode <= KEY_9:
		model.type_digit(key.keycode - KEY_0)
	elif key.keycode >= KEY_KP_0 and key.keycode <= KEY_KP_9:
		model.type_digit(key.keycode - KEY_KP_0)
	else:
		match key.keycode:
			KEY_BACKSPACE:
				model.backspace()
			KEY_LEFT:
				selected = mini(selected + 1, model.slider_digits() - 1)
			KEY_RIGHT:
				selected = maxi(selected - 1, 0)
			KEY_UP:
				model.set_slider(selected, model.sliders[selected] + 1)
			KEY_DOWN:
				model.set_slider(selected, model.sliders[selected] - 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				model.turn()
			KEY_TAB:
				model.set_subtract(not model.subtract)
			KEY_BRACKETLEFT:
				model.set_carriage(model.carriage - 1)
			KEY_BRACKETRIGHT:
				model.set_carriage(model.carriage + 1)
			KEY_C:
				model.clear_registers()
			KEY_X:
				model.clear_sliders()
			KEY_V:
				model.set_counter_reverse(not model.counter_reverse)
			KEY_T:
				curta_type = 2 if model.model_type == 1 else 1
				model.set_type(curta_type)
				selected = 0
			KEY_S:
				model.save_csv(CSV_PATH)
			KEY_L:
				I18n.toggle()
			_:
				return
	get_viewport().set_input_as_handled()
	queue_redraw()


# --- Отрисовка ----------------------------------------------------------

## Левый край столбца разряда j регистра результата.
func _col_x(j: int) -> float:
	return RIGHT_X - (j + 1) * COL_W


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var k := model.carriage

	# Счётчик оборотов
	draw_string(font, Vector2(_col_x(model.counter_digits() - 1) - 260, COUNTER_Y + 44), I18n.t("Счётчик оборотов"),
			HORIZONTAL_ALIGNMENT_RIGHT, 240, 24, COLOR_COUNTER)
	for j in model.counter_digits():
		_digit_box(font, _col_x(j), COUNTER_Y, model.counter[j], COLOR_COUNTER, j == k)

	# Результат
	draw_string(font, Vector2(_col_x(model.result_digits() - 1) - 260, RESULT_Y + 44), I18n.t("Результат"),
			HORIZONTAL_ALIGNMENT_RIGHT, 240, 24, COLOR_TEXT)
	for j in model.result_digits():
		_digit_box(font, _col_x(j), RESULT_Y, model.result[j], COLOR_TEXT, j >= k and j < k + model.slider_digits())
	if model.overflow:
		draw_string(font, Vector2(_col_x(model.result_digits() - 1), RESULT_Y - 12), I18n.t("перенос за старший разряд"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, COLOR_SUB)

	# Ползунки: ползунок i стоит под разрядом i + k
	var sub := model.subtract
	for i in model.slider_digits():
		var x := _col_x(i + k)
		var cx := x + COL_W * 0.5
		var n := model.sliders[i]
		draw_line(Vector2(cx, SLIDER_Y), Vector2(cx, SLIDER_Y + 9 * SLIDER_STEP), COLOR_BOX, 10.0)
		for v in 10:
			draw_string(font, Vector2(cx + 10, SLIDER_Y + v * SLIDER_STEP + 7), str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_DIM)
		var knob := Vector2(cx, SLIDER_Y + n * SLIDER_STEP)
		draw_rect(Rect2(knob - Vector2(14, 8), Vector2(28, 16)), COLOR_ACTIVE if i == selected else COLOR_RIB)
		draw_string(font, Vector2(x, SLIDER_Y - 14), str(n), HORIZONTAL_ALIGNMENT_CENTER, COL_W, 28, COLOR_TEXT)
		_draw_drum_column(font, x, n, sub, i == 0)

	# Подписи
	var mode := I18n.t("ВЫЧИТАНИЕ (ручка вверху)") if sub else I18n.t("сложение (ручка внизу)")
	var info := PackedStringArray([
		I18n.t("Курта, тип %s") % ("I" if model.model_type == 1 else "II"),
		I18n.t("Режим: %s") % mode,
		I18n.t("Каретка: позиция %d из %d") % [k + 1, model.carriage_positions()],
		I18n.t("Счётчик: %s") % (I18n.t("реверс (вычитание считает +1)") if model.counter_reverse else I18n.t("обычный")),
		I18n.t("Установка %d   результат %d   счётчик %d   оборотов %d") % [model.slider_value(), model.result_signed(), model.counter_signed(), model.turns],
	])
	for i in info.size():
		draw_string(font, Vector2(24, 36 + i * 28), info[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
				COLOR_SUB if i == 1 and sub else COLOR_TEXT)
	draw_string(font, Vector2(24, 1050),
			I18n.t("0–9 набор   ←→ ползунок   ↑↓ значение   Enter оборот   Tab ±   [ ] каретка   C сброс   X ползунки   V счётчик   T тип   S CSV   L язык"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, COLOR_DIM)


func _digit_box(font: Font, x: float, y: float, d: int, color: Color, hot: bool) -> void:
	var r := Rect2(x + 4, y, COL_W - 8, 64)
	draw_rect(r, COLOR_BOX)
	if hot:
		draw_rect(r, COLOR_ACTIVE, false, 2.0)
	draw_string(font, Vector2(x, y + 48), str(d), HORIZONTAL_ALIGNMENT_CENTER, COL_W, 44, color)


## Развёртка вала: 9 рёбер разной длины. Шестерня ползунка на уровне n
## цепляет n рёбер (сложение) или 9 − n рёбер нижней ступени (вычитание).
func _draw_drum_column(font: Font, x: float, n: int, sub: bool, units: bool) -> void:
	var rib_w := (COL_W - 16) / 9.0
	var h := SLIDER_STEP
	for r in 9:
		var rx := x + 8 + r * rib_w
		# Ребро r (длина r+1) занимает уровни 9−r..9 на ступени сложения и 0..r на ступени вычитания.
		var lo := 9 - r if not sub else 0
		var hi := 9 if not sub else r
		var engaged := n >= lo and n <= hi
		draw_rect(Rect2(rx + 1, DRUM_Y + lo * h * 0.8, rib_w - 2, (hi - lo + 1) * h * 0.8),
				(COLOR_SUB if sub else COLOR_ACTIVE) if engaged else COLOR_RIB.darkened(0.4))
	var py := DRUM_Y + (n + 0.5) * h * 0.8
	draw_line(Vector2(x + 4, py), Vector2(x + COL_W - 4, py), COLOR_TEXT, 2.0)
	var t := CurtaModel.teeth(n, sub) + (1 if sub and units else 0)
	draw_string(font, Vector2(x, DRUM_Y + 10 * h * 0.8 + 26), ("+%d" % t), HORIZONTAL_ALIGNMENT_CENTER, COL_W, 22,
			COLOR_SUB if sub else COLOR_ACTIVE)
