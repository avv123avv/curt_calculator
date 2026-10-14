extends SceneTree
## Автотесты: godot --headless --path . -s tests/run_tests.gd
## Код выхода 0 — всё прошло, 1 — есть провалы (так их видит CI).

const SETTINGS := "user://settings.cfg"

var _failed := 0
var _passed := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  ok   ", what)
	else:
		_failed += 1
		printerr("  FAIL ", what)


# --- Приёмы счёта на модели -------------------------------------------------

## Набрать число в регистре результата (сложением с позиции 1), счётчик обнулить.
func _load_result(m: CurtaModel, value: int) -> void:
	m.clear_registers()
	m.set_subtract(false)
	m.set_carriage(0)
	m.set_sliders_value(value)
	m.turn()
	m.clear_counter()


## Деление повторным вычитанием: счётчик в реверсе показывает частное.
func _divide(m: CurtaModel, dividend: int, divisor: int) -> void:
	_load_result(m, dividend)
	m.set_sliders_value(divisor)
	m.set_counter_reverse(true)
	for k in range(m.carriage_positions() - 1, -1, -1):
		m.set_carriage(k)
		m.set_subtract(true)
		while true:
			m.turn()
			if m.result_signed() < 0:
				# Перебрали — один оборот сложением назад.
				m.set_subtract(false)
				m.turn()
				break
	m.set_subtract(false)
	m.set_carriage(0)


## Корень по Тёплеру: вычитать нечётные числа 1, 3, 5… (с приписанным 20·r),
## на ползунках число сдвинуто на k разрядов, каретка тоже на k → вес 100^k.
func _sqrt(m: CurtaModel, n: int, pairs: int) -> void:
	_load_result(m, n)
	m.set_counter_reverse(true)
	var r := 0
	for k in range(pairs - 1, -1, -1):
		m.set_carriage(k)
		var t := 0
		while true:
			m.set_sliders_value((20 * r + 2 * t + 1) * int(pow(10, k)))
			m.set_subtract(true)
			m.turn()
			if m.result_signed() < 0:
				m.set_subtract(false)
				m.turn()
				break
			t += 1
		r = r * 10 + t
	m.set_subtract(false)


# --- Мышь в 3D ----------------------------------------------------------------

func _mouse_button(c: Curta3D, pos: Vector2, pressed := true, index := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	c._unhandled_input(e)


func _mouse_move(c: Curta3D, pos: Vector2, rel := Vector2.ZERO) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	c._unhandled_input(e)


## Протащить мышь по дуге вокруг оси машины на высоте h от угла a0 до a1.
func _drag_arc(c: Curta3D, r: float, h: float, a0: float, a1: float, steps: int) -> void:
	_mouse_button(c, c.screen_of(Curta3D._polar(a0, r, h)))
	for s in range(1, steps + 1):
		_mouse_move(c, c.screen_of(Curta3D._polar(lerpf(a0, a1, float(s) / steps), r, h)))
	_mouse_button(c, c.screen_of(Curta3D._polar(a1, r, h)), false)


func _settle(c: Curta3D, seconds := 2.0) -> void:
	var t := 0.0
	while t < seconds:
		c._process(0.05)
		t += 0.05


## Все ключи I18n.t("…") из исходников.
func _i18n_keys(path: String) -> PackedStringArray:
	var re := RegEx.new()
	re.compile("I18n\\.t\\(\"((?:[^\"\\\\]|\\\\.)*)\"\\)")
	var out := PackedStringArray()
	for m in re.search_all(FileAccess.get_file_as_string(path)):
		out.append(m.get_string(1).c_unescape())
	return out


func _initialize() -> void:
	var had_settings := FileAccess.file_exists(SETTINGS)
	I18n.lang = "ru"

	print("Сложение и вычитание")
	var m := CurtaModel.new(1)
	m.set_sliders_value(123)
	m.turn()
	m.set_sliders_value(456)
	m.turn()
	_check(m.result_value() == 579 and m.counter_value() == 2, "123 + 456 = 579, счётчик 2")
	m.set_type(1)
	m.set_sliders_value(1)
	m.set_subtract(true)
	m.turn()
	_check(CurtaModel.digits_string(m.result) == "99999999999", "0 − 1 = 99999999999")
	_check(m.result_signed() == -1 and m.counter_signed() == -1, "0 − 1 читается как −1, счётчик −1")
	_check(m.overflow == false, "0 − 1 без переноса за старший разряд")
	m.set_subtract(false)
	m.turn()
	_check(m.result_value() == 0 and m.overflow, "−1 + 1 = 0 с потерей переноса")
	_check(CurtaModel.teeth(3, false) == 3 and CurtaModel.teeth(3, true) == 6, "зубцы вала: n и 9 − n")

	print("Умножение сдвигами")
	m.set_type(1)
	m.set_sliders_value(123)
	for k in 3:
		m.set_carriage(k)
		m.turns_n([6, 5, 4][k])
	_check(m.result_value() == 56088 and m.counter_value() == 456, "123 × 456 = 56088, счётчик 456")
	# Сокращённое умножение: 99 = 100 − 1.
	m.clear_registers()
	m.set_carriage(0)
	m.set_subtract(true)
	m.turn()
	m.set_subtract(false)
	m.set_carriage(2)
	m.turn()
	_check(m.result_value() == 123 * 99, "123 × 99 = 123·100 − 123 (%d)" % m.result_value())

	print("Деление")
	_divide(m, 56090, 123)
	_check(m.counter_value() == 456 and m.result_value() == 2, "56090 : 123 = 456, остаток 2 (%d, %d)" % [m.counter_value(), m.result_value()])
	_divide(m, 1000000, 7)
	_check(m.counter_value() == 142857 and m.result_value() == 1, "1000000 : 7 = 142857, остаток 1")

	print("Квадратный корень (Тёплер)")
	_sqrt(m, 15129, 3)
	_check(m.counter_value() == 123 and m.result_value() == 0, "√15129 = 123, остаток 0 (%d)" % m.counter_value())
	_sqrt(m, 200, 2)
	_check(m.counter_value() == 14 and m.result_value() == 4, "√200 = 14, остаток 4")

	print("Счётчик оборотов")
	m.set_type(1)
	m.set_sliders_value(1)
	m.turns_n(10)
	_check(CurtaModel.digits_string(m.counter) == "000010", "перенос в счётчике: 9 + 1 = 10")
	m.set_subtract(true)
	m.turns_n(11)
	_check(CurtaModel.digits_string(m.counter) == "999999" and m.counter_signed() == -1, "заём в счётчике: 10 − 11 = −1")
	m.set_counter_reverse(true)
	m.turn()
	_check(m.counter_signed() == 0, "реверс: вычитание считает +1")
	m.set_carriage(3)
	m.set_subtract(false)
	m.set_counter_reverse(false)
	m.turn()
	_check(m.counter_value() == 1000, "каретка 4 → счётчик +1000")

	print("Тип и набор")
	m.set_type(2)
	_check(m.slider_digits() == 11 and m.counter_digits() == 8 and m.result_digits() == 15, "тип II: 11 / 8 / 15")
	for d in [9, 8, 7]:
		m.type_digit(d)
	_check(m.slider_value() == 987, "набор 9, 8, 7 → 987")
	m.backspace()
	_check(m.slider_value() == 98, "Backspace → 98")

	print("CSV")
	m.set_type(1)
	m.set_sliders_value(5)
	m.turn()
	_check(m.save_csv("user://curta_test.csv"), "сохранение CSV")
	var csv := FileAccess.get_file_as_string("user://curta_test.csv")
	_check(csv.begins_with("n,op,carriage,setting,result,counter\n"), "заголовок CSV")
	_check(csv.contains("\n1,+,1,00000005,00000000005,000001\n"), "строка оборота в CSV")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://curta_test.csv"))

	await _test_3d()

	print("Язык")
	var keys := PackedStringArray()
	for path in ["res://curta_3d.gd", "res://curta_calculator.gd"]:
		keys.append_array(_i18n_keys(path))
	var missing := PackedStringArray()
	for k in keys:
		if not I18n.EN.has(k) and not k in missing:
			missing.append(k)
	_check(keys.size() > 30 and missing.is_empty(), "у всех %d строк есть английский перевод %s" % [keys.size(), missing])
	var empty := PackedStringArray()
	for k in I18n.EN:
		if str(I18n.EN[k]).is_empty():
			empty.append(k)
	_check(empty.is_empty(), "в I18n.EN нет пустых переводов")

	# Тест не должен оставлять после себя выбранный язык.
	if not had_settings and FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))

	print("Итого: %d прошло, %d провалено" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_3d() -> void:
	print("3D-модель")
	var c: Curta3D = load("res://curta_3d.tscn").instantiate()
	root.add_child(c)
	await process_frame
	var m := c.model
	_check(c.pick(c.screen_of(c.part_point("slider:3"))) == "slider:3", "пикинг ползунка 4")

	# Ползунок: перетащить на 7.
	var a3 := c.slider_angle(3)
	_mouse_button(c, c.screen_of(c.part_point("slider:3")))
	_mouse_move(c, c.screen_of(Curta3D._polar(a3, c._R + 0.15, c.slider_y(7))))
	_mouse_button(c, c.screen_of(Curta3D._polar(a3, c._R + 0.15, c.slider_y(7))), false)
	_check(m.sliders[3] == 7 and c.selected == 3, "перетаскивание ползунка 4 на 7 (%d)" % m.sliders[3])
	_mouse_button(c, c.screen_of(c.part_point("slider:0")), true, MOUSE_BUTTON_WHEEL_DOWN)
	_mouse_button(c, c.screen_of(c.part_point("slider:0")), true, MOUSE_BUTTON_WHEEL_DOWN)
	_check(m.sliders[0] == 2, "колесо над ползунком 1: +2")
	var setting := m.slider_value()

	# Ручка: полный круг по часовой стрелке (сверху угол убывает).
	_settle(c)
	var h: float = c._crank.position.y + 0.5
	var arm: float = c._R * 0.85
	var home := c._crank_home()
	_check(c.pick(c.screen_of(Curta3D._polar(home, arm, h))) == "crank", "пикинг ручки")
	_drag_arc(c, arm, h, home, home + PI * 0.5, 12)
	_check(c.crank_angle == 0.0 and m.turns == 0, "храповик: против часовой ручка не идёт")
	_drag_arc(c, arm, h, home, home - PI * 0.5, 12)
	_check(c.crank_locked() and m.turns == 0, "четверть оборота — операция ещё не прошла")
	c.shift_carriage(1)
	c.toggle_subtract()
	_check(m.carriage == 0 and not m.subtract, "каретка и режим заблокированы, пока ручка не дома")
	var a := home - PI * 0.5
	_drag_arc(c, arm, h, a, a - PI * 1.55, 30)
	_check(m.turns == 1 and m.result_value() == setting and not c.crank_locked(),
			"доворот ручки → один оборот, фиксатор вернул её домой, результат %d" % m.result_value())

	# Enter — анимированный оборот.
	c.turn_crank()
	_check(c.crank_locked(), "Enter: ручка пошла")
	_settle(c, 1.0)
	_check(m.turns == 2 and m.result_value() == 2 * setting, "Enter: оборот завершён (%d)" % m.result_value())

	# Головка ручки — вычитание, красное кольцо.
	_mouse_button(c, c.screen_of(c.part_point("hub")))
	_mouse_button(c, c.screen_of(c.part_point("hub")), false)
	_check(m.subtract, "щелчок по головке — вычитание")
	_settle(c)
	_check(is_equal_approx(c._crank_lift, 0.35) and is_equal_approx(c._drum_lift, c._step * 0.5),
			"ручка вытянута, вал поднят на полшага")
	c.turn_crank()
	_settle(c, 1.0)
	_check(m.result_value() == setting, "оборот с вытянутой ручкой вычитает")
	c.toggle_subtract()

	# Каретка: повернуть на два шага.
	_settle(c)
	var top: float = c._body_h + c._car_h
	_check(c.pick(c.screen_of(Curta3D._polar(0.0, c._R * 0.9, top))) == "carriage", "пикинг каретки")
	_drag_arc(c, c._R * 0.9, top, 0.0, c._pitch * 2.0, 6)
	_check(m.carriage == 2, "поворот каретки на 2 шага (%d)" % m.carriage)
	_settle(c)
	_check(is_equal_approx(c._carriage.rotation.y, 2 * c._pitch) and c._car_lift == 0.0, "каретка доехала и опустилась")
	c.shift_carriage(-2)
	_settle(c)

	# Переключатель счётчика.
	_mouse_button(c, c.screen_of(c.part_point("reverse")))
	_mouse_button(c, c.screen_of(c.part_point("reverse")), false)
	_check(m.counter_reverse, "щелчок по переключателю счётчика")
	c.toggle_reverse()

	# Рычаг сброса: неполный круг — пружинит обратно, полный — сброс.
	var lever_world: float = c._carriage.rotation.y + c._lever_rest()
	var lr: float = c._R * 0.98
	var lh: float = top + 0.18
	_check(c.pick(c.screen_of(Curta3D._polar(lever_world, lr, lh))) == "lever", "пикинг рычага сброса")
	_drag_arc(c, lr, lh, lever_world, lever_world + PI, 12)
	_check(m.result_value() != 0, "пол-круга рычагом — без сброса")
	_settle(c)
	_check(c.lever_angle == 0.0, "рычаг вернулся на место")
	_drag_arc(c, lr, lh, lever_world, lever_world + TAU * 1.02, 40)
	_check(m.result_value() == 0 and m.counter_value() == 0, "полный круг рычагом — результат и счётчик сброшены")

	# Разрез: шестерни и вал ловятся только в разрезе.
	var drum_screen := c.screen_of(Vector3(0, c._slot_top - 2.0, 0))
	_check(c.pick(drum_screen) == "body", "без разреза корпус заслоняет вал")
	c.set_cutaway(true)
	_check(c.pick(drum_screen) == "drum", "в разрезе виден ступенчатый вал")
	_check(c.pick(c.screen_of(c._pinions[0].global_position)) == "pinion:0", "в разрезе ловится шестерня ползунка 1")
	var p0: float = c._pinions[0].rotation.y
	c.turn_crank()
	_settle(c, 1.0)
	_check(is_equal_approx(wrapf(c._pinions[0].rotation.y - p0, 0.0, TAU), TAU * m.sliders[0] / 10.0),
			"шестерня ползунка повернулась на n/10 оборота")
	c.set_cutaway(false)

	# Орбита и масштаб.
	var yaw := c._yaw
	_mouse_button(c, Vector2(100, 500))
	_mouse_move(c, Vector2(150, 500), Vector2(50, 0))
	_mouse_button(c, Vector2(150, 500), false)
	_check(c._yaw != yaw, "перетаскивание по пустому месту вращает вид")
	var dist := c._dist
	_mouse_button(c, Vector2(100, 500), true, MOUSE_BUTTON_WHEEL_UP)
	_check(c._dist < dist, "колесо по пустому месту приближает")
	c._reset_view()

	# Shift+C — только счётчик.
	m.set_sliders_value(5)
	c.turn_crank()
	_settle(c, 1.0)
	var shift_c := InputEventKey.new()
	shift_c.keycode = KEY_C
	shift_c.shift_pressed = true
	shift_c.pressed = true
	c._unhandled_input(shift_c)
	_check(m.counter_value() == 0 and m.result_value() != 0, "Shift+C обнуляет только счётчик")

	# Смена типа и кнопки.
	c.press_button("type")
	_check(m.model_type == 2 and c._knobs.size() == 11 and c._result_labels.size() == 15, "тип II: 11 ползунков, 15 разрядов")
	_check(c.pick(c.screen_of(c.part_point("slider:10"))) == "slider:10", "тип II: пикинг старшего ползунка")
	c.press_button("type")
	_check(m.model_type == 1, "обратно тип I")
	c.press_button("lang")
	_check(I18n.current() == "en" and (c._buttons["turn"] as Button).text == "Turn (Enter)", "кнопка языка → английский")
	c.press_button("help")
	var ru_pages := c._help_pages.size()
	c._set_help(false)
	c.press_button("lang")
	c.press_button("help")
	var en_pages := c._help_pages.size()
	_check(ru_pages > 0 and en_pages > 0, "страницы инструкции есть: ru %d, en %d" % [ru_pages, en_pages])
	_check(FileAccess.file_exists("res://docs/instruction_ru.pdf") and FileAccess.file_exists("res://docs/instruction_en.pdf"),
			"PDF инструкции на обоих языках в docs/")
	_check(c._help_open, "F1 — инструкция открыта")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	c._unhandled_input(esc)
	_check(not c._help_open, "Esc закрывает инструкцию")
	c.queue_free()
	await process_frame
