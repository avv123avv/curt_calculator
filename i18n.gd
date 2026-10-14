class_name I18n
extends RefCounted
## Переводы интерфейса: ru (исходный) и en.
## Ключ — русская строка как в коде; нет перевода — показывается русская.
## Язык: аргумент запуска `-- --lang=en`, иначе сохранённый выбор, иначе язык системы.

const LANGS: PackedStringArray = ["ru", "en"]
const SETTINGS_PATH := "user://settings.cfg"

const EN := {
	# curta_calculator.gd — 2D-схема
	"Результат": "Result",
	"Счётчик оборотов": "Revolution counter",
	"перенос за старший разряд": "carry out of the top digit",
	"ВЫЧИТАНИЕ (ручка вверху)": "SUBTRACTION (crank up)",
	"сложение (ручка внизу)": "addition (crank down)",
	"Курта, тип %s": "Curta, Type %s",
	"Режим: %s": "Mode: %s",
	"Каретка: позиция %d из %d": "Carriage: position %d of %d",
	"Счётчик: %s": "Counter: %s",
	"реверс (вычитание считает +1)": "reversed (subtraction counts +1)",
	"обычный": "normal",
	"Установка %d   результат %d   счётчик %d   оборотов %d": "Setting %d   result %d   counter %d   turns %d",
	"0–9 набор   ←→ ползунок   ↑↓ значение   Enter оборот   Tab ±   [ ] каретка   C сброс   X ползунки   V счётчик   T тип   S CSV   L язык":
		"0–9 type   ←→ slider   ↑↓ value   Enter turn   Tab ±   [ ] carriage   C clear   X sliders   V counter   T type   S CSV   L language",
	# curta_3d.gd — строка состояния, панель, подсказки внизу
	"Курта, тип %s    %s    каретка %d / %d%s": "Curta, Type %s    %s    carriage %d / %d%s",
	"ВЫЧИТАНИЕ": "SUBTRACTION",
	"сложение": "addition",
	"    [РЕВЕРС СЧЁТЧИКА]": "    [COUNTER REVERSED]",
	"#Установка": "#Setting",
	"#Результат": "#Result",
	"#Счётчик оборотов": "#Revolution counter",
	"#Последние операции": "#Last operations",
	"Оборотов: %d": "Turns: %d",
	"поз.": "pos.",
	"Мышь: тяните ползунки, крутите ручку, поворачивайте каретку; щелчок по головке ручки — вычитание.":
		"Mouse: drag the sliders, turn the crank, rotate the carriage; click the crank hub to subtract.",
	"Клавиши: 0–9 набор, Enter оборот, Tab ±, [ ] каретка, C / Shift+C сброс, X, V, K, T, S, L, Home.":
		"Keys: 0–9 type, Enter turn, Tab ±, [ ] carriage, C / Shift+C clear, X, V, K, T, S, L, Home.",
	"F1 — инструкция: устройство и приёмы счёта": "F1 — manual: construction and calculating techniques",
	"Перенос за старший разряд потерян": "Carry out of the top digit is lost",
	"Результат и счётчик сброшены": "Result and counter cleared",
	"Счётчик сброшен": "Counter cleared",
	"Сначала доверните ручку до конца оборота": "Finish the crank turn first",
	"Сохранено: %s": "Saved: %s",
	"Не удалось сохранить CSV": "Could not save CSV",
	# curta_3d.gd — кнопки
	"Оборот": "Turn",
	"Вычитание": "Subtract",
	"Сложение": "Add",
	"◀ Каретка": "◀ Carriage",
	"Каретка ▶": "Carriage ▶",
	"Сброс": "Clear",
	"Реверс": "Reverse",
	"Разрез": "Cutaway",
	"Тип I": "Type I",
	"Тип II": "Type II",
	"CSV": "CSV",
	"Инструкция": "Manual",
	# curta_3d.gd — подсказки к деталям
	"Ползунок разряда %d (= %d): тяните вверх/вниз или колесо": "Setting slider, digit %d (= %d): drag up/down or use the wheel",
	"Шестерня ползунка %d: за оборот ручки поворачивается на %d/10": "Pinion of slider %d: turns %d/10 per crank turn",
	"Ручка: крутите по часовой стрелке, полный круг — одна операция": "Crank: turn clockwise, one full turn = one operation",
	"Головка ручки: щелчок — вытянуть (вычитание) или вдвинуть (сложение)": "Crank hub: click to pull up (subtract) or push in (add)",
	"Каретка: поверните на разряд (сдвиг = умножение на 10)": "Carriage: rotate by one digit (shift = multiply by 10)",
	"Рычаг сброса: проведите полный круг — обнулить результат и счётчик": "Clearing lever: drag a full circle to clear result and counter",
	"Переключатель счётчика: реверс для деления и корня": "Counter reverse switch: for division and square root",
	"Ступенчатый вал: рёбра сложения (жёлтые) и дополнения (красные) чередуются по высоте":
		"Stepped drum: addition teeth (yellow) and complement teeth (red) alternate in height",
	"Корпус: тяните — вращать вид, колесо — масштаб, K — разрез": "Body: drag to orbit, wheel to zoom, K for cutaway",
	# Инструкция (F1)
	"Нет страниц инструкции — запустите docs/build_instruction.py": "No manual pages — run docs/build_instruction.py",
	"стр. %d / %d     ← → листать     O открыть PDF     F1 / Esc закрыть": "page %d / %d     ← → flip     O open PDF     F1 / Esc close",
}

static var lang := ""


static func t(text: String) -> String:
	_ensure_loaded()
	if lang == "en":
		return EN.get(text, text)
	return text


static func current() -> String:
	_ensure_loaded()
	return lang


static func toggle() -> void:
	_ensure_loaded()
	set_lang(LANGS[(LANGS.find(lang) + 1) % LANGS.size()])


static func set_lang(code: String) -> void:
	lang = code if code in LANGS else "en"
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("ui", "lang", lang)
	cfg.save(SETTINGS_PATH)


static func _ensure_loaded() -> void:
	if lang != "":
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="):
			lang = arg.substr(7)
			if lang in LANGS:
				return
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		lang = str(cfg.get_value("ui", "lang", ""))
		if lang in LANGS:
			return
	lang = "ru" if OS.get_locale_language() == "ru" else "en"
