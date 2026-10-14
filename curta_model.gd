class_name CurtaModel
extends RefCounted
## Механика калькулятора Курта (Curt Herzstark, 1948) без отрисовки.
##
## Цифры хранятся массивами, индекс 0 — единицы.
## Один оборот ручки = одна операция над всеми разрядами сразу:
##   сложение  — каждый ползунок n проворачивает колесо результата на n зубцов
##               ступенчатого вала (Лейбница);
##   вычитание — ручка вытянута вверх, вал поднят, работает дополнительная
##               ступень с 9 − n зубцами, плюс отдельный зубец «+1» в младшем
##               разряде каретки: R + (10^w − x) = R − x по модулю 10^w.
## Перенос десятков проходит по всем разрядам регистра результата, перенос
## из старшего разряда теряется (как в настоящей машине).
## Каретка сдвинута на k позиций: ползунок i работает на разряд результата i + k,
## счётчик оборотов получает ±1 в разряд k.

## Тип I: 8 ползунков, счётчик 6, результат 11. Тип II: 11 / 8 / 15.
const TYPES := {
	1: {"sliders": 8, "counter": 6, "result": 11, "diameter_mm": 53.0, "height_mm": 85.0},
	2: {"sliders": 11, "counter": 8, "result": 15, "diameter_mm": 65.0, "height_mm": 90.0},
}

signal changed

var model_type := 1
var sliders := PackedInt32Array()
var result := PackedInt32Array()
var counter := PackedInt32Array()
## Сдвиг каретки: 0 — позиция «1» на машине.
var carriage := 0
## Ручка вытянута вверх — вычитание.
var subtract := false
## Переключатель счётчика: при включении вычитание считает +1 (для деления и корня).
var counter_reverse := false
## Последний оборот вызвал перенос за старший разряд (результат «перешёл через ноль»).
var overflow := false
var turns := 0
## Журнал операций, строки CSV (первая — заголовок).
var log_rows: PackedStringArray = []


func _init(type_id: int = 1) -> void:
	set_type(type_id)


func set_type(type_id: int) -> void:
	model_type = type_id if TYPES.has(type_id) else 1
	sliders = PackedInt32Array()
	sliders.resize(slider_digits())
	result = PackedInt32Array()
	result.resize(result_digits())
	counter = PackedInt32Array()
	counter.resize(counter_digits())
	carriage = 0
	subtract = false
	counter_reverse = false
	overflow = false
	turns = 0
	log_rows = PackedStringArray([csv_header()])
	changed.emit()


func slider_digits() -> int:
	return TYPES[model_type]["sliders"]


func result_digits() -> int:
	return TYPES[model_type]["result"]


func counter_digits() -> int:
	return TYPES[model_type]["counter"]


## Позиций каретки столько же, сколько разрядов у счётчика оборотов.
func carriage_positions() -> int:
	return counter_digits()


# --- Органы управления ---------------------------------------------------

func set_slider(i: int, value: int) -> void:
	if i < 0 or i >= sliders.size():
		return
	sliders[i] = clampi(value, 0, 9)
	changed.emit()


## Выставить число на ползунках (лишние старшие разряды отбрасываются).
func set_sliders_value(value: int) -> void:
	var v := absi(value)
	for i in sliders.size():
		sliders[i] = v % 10
		v /= 10
	changed.emit()


## Набор числа «как на клавиатуре»: цифры вдвигаются справа.
func type_digit(d: int) -> void:
	for i in range(sliders.size() - 1, 0, -1):
		sliders[i] = sliders[i - 1]
	sliders[0] = clampi(d, 0, 9)
	changed.emit()


func backspace() -> void:
	for i in sliders.size() - 1:
		sliders[i] = sliders[i + 1]
	sliders[sliders.size() - 1] = 0
	changed.emit()


func clear_sliders() -> void:
	sliders.fill(0)
	changed.emit()


func set_carriage(k: int) -> void:
	carriage = clampi(k, 0, carriage_positions() - 1)
	changed.emit()


func set_subtract(on: bool) -> void:
	subtract = on
	changed.emit()


func set_counter_reverse(on: bool) -> void:
	counter_reverse = on
	changed.emit()


## Рычаг сброса: полный оборот обнуляет регистр результата и счётчик.
func clear_registers() -> void:
	result.fill(0)
	counter.fill(0)
	overflow = false
	_log("clear")
	changed.emit()


func clear_result() -> void:
	result.fill(0)
	overflow = false
	_log("clear_result")
	changed.emit()


func clear_counter() -> void:
	counter.fill(0)
	_log("clear_counter")
	changed.emit()


# --- Ступенчатый вал ------------------------------------------------------

## Сколько зубцов вала зацепит шестерня ползунка со значением n за один оборот.
static func teeth(n: int, sub: bool) -> int:
	return 9 - n if sub else n


## Сколько единиц получит разряд результата j за оборот (без переносов).
func drum_input(j: int) -> int:
	if j < carriage:
		return 0
	var i := j - carriage
	var n := sliders[i] if i < sliders.size() else 0
	var add := teeth(n, subtract)
	# Зубец «+1» дополнения до 10 стоит в младшем разряде под кареткой.
	if subtract and j == carriage:
		add += 1
	return add


## Один полный оборот ручки.
func turn() -> void:
	var carry := 0
	for j in result.size():
		var s := result[j] + drum_input(j) + carry
		result[j] = s % 10
		carry = s / 10
	overflow = carry > 0
	# Счётчик оборотов: ±1 в разряд под кареткой, с переносом/заёмом по модулю 10^w.
	var step := -1 if subtract else 1
	if counter_reverse:
		step = -step
	var c := step
	for j in range(carriage, counter.size()):
		var s := counter[j] + c
		c = 0
		if s >= 10:
			s -= 10
			c = 1
		elif s < 0:
			s += 10
			c = -1
		counter[j] = s
		if c == 0:
			break
	turns += 1
	_log("-" if subtract else "+")
	changed.emit()


func turns_n(count: int) -> void:
	for k in count:
		turn()


# --- Чтение регистров -----------------------------------------------------

static func digits_value(d: PackedInt32Array) -> int:
	var v := 0
	for i in range(d.size() - 1, -1, -1):
		v = v * 10 + d[i]
	return v


static func digits_string(d: PackedInt32Array) -> String:
	var s := ""
	for i in range(d.size() - 1, -1, -1):
		s += str(d[i])
	return s


func slider_value() -> int:
	return digits_value(sliders)


func result_value() -> int:
	return digits_value(result)


func counter_value() -> int:
	return digits_value(counter)


## Результат со знаком: число из одних девяток сверху читается как дополнение.
func result_signed() -> int:
	var v := result_value()
	if result[result.size() - 1] == 9:
		return v - int(pow(10, result.size()))
	return v


func counter_signed() -> int:
	var v := counter_value()
	if counter[counter.size() - 1] == 9:
		return v - int(pow(10, counter.size()))
	return v


# --- CSV ------------------------------------------------------------------

func csv_header() -> String:
	return "n,op,carriage,setting,result,counter"


func _log(op: String) -> void:
	log_rows.append("%d,%s,%d,%s,%s,%s" % [turns, op, carriage + 1,
			digits_string(sliders), digits_string(result), digits_string(counter)])


func save_csv(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Не удалось сохранить CSV: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string("\n".join(log_rows) + "\n")
	f.close()
	print("Сохранено: ", ProjectSettings.globalize_path(path))
	return true
