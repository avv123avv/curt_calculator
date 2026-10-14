"""Собирает инструкцию на двух языках: docs/instruction_ru.pdf и docs/instruction_en.pdf,
и рендерит страницы в docs/pages/<lang>/page_N.png для просмотра внутри Godot (F1).

Запуск:  python docs/build_instruction.py
Нужно:   pip install reportlab pypdfium2
Картинки — docs/scheme_<lang>.png и docs/cutaway_<lang>.png (скриншоты программы на этом языке):
         godot --path . -s docs/screenshot.gd -- --lang=ru   (и --lang=en)
Все таблицы с примерами считает Curta ниже — зеркало curta_model.gd.
"""
from pathlib import Path

from reportlab.graphics.shapes import Drawing, Line, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (CondPageBreak, Image, KeepTogether, PageBreak, Paragraph,
                                SimpleDocTemplate, Spacer, Table, TableStyle)

DOCS = Path(__file__).resolve().parent
LANGS = ("ru", "en")
# Высота картинки страницы = высота окна Godot минус поля, чтобы показывать 1:1.
PAGE_PX_HEIGHT = 1054
# Множитель всех размеров шрифта.
FONT_K = 1.6


def _register_fonts() -> str:
	"""Arial из Windows, иначе Liberation Sans (Linux)."""
	for regular, bold in [
		(Path("C:/Windows/Fonts/arial.ttf"), Path("C:/Windows/Fonts/arialbd.ttf")),
		(Path("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"),
		 Path("/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf")),
		(Path("/usr/share/fonts/liberation-sans/LiberationSans-Regular.ttf"),
		 Path("/usr/share/fonts/liberation-sans/LiberationSans-Bold.ttf")),
	]:
		if regular.exists() and bold.exists():
			pdfmetrics.registerFont(TTFont("Sans", str(regular)))
			pdfmetrics.registerFont(TTFont("Sans-Bold", str(bold)))
			pdfmetrics.registerFontFamily("Sans", normal="Sans", bold="Sans-Bold")
			return "Sans"
	raise SystemExit("Нет шрифта: нужен Arial (Windows) или Liberation Sans")


FONT = _register_fonts()

INK = colors.HexColor("#1f2328")
ACCENT = colors.HexColor("#2f6db5")
SOFT = colors.HexColor("#eef3f9")
LINE = colors.HexColor("#b8c4d2")
GOLD = colors.HexColor("#d9b24a")
RED = colors.HexColor("#c8473b")
GREY = colors.HexColor("#555555")

body = ParagraphStyle("body", fontName=FONT, fontSize=12 * FONT_K, leading=16 * FONT_K, textColor=INK, spaceAfter=5 * FONT_K)
small = ParagraphStyle("small", parent=body, fontSize=10.5 * FONT_K, leading=13.5 * FONT_K)
cell = ParagraphStyle("cell", parent=body, fontSize=11 * FONT_K, leading=14 * FONT_K, spaceAfter=0)
cell_b = ParagraphStyle("cell_b", parent=cell, fontName=FONT + "-Bold")
h1 = ParagraphStyle("h1", parent=body, fontName=FONT + "-Bold", fontSize=20 * FONT_K, leading=24 * FONT_K, textColor=ACCENT, spaceAfter=8 * FONT_K, keepWithNext=1)
h2 = ParagraphStyle("h2", parent=body, fontName=FONT + "-Bold", fontSize=14 * FONT_K, leading=18 * FONT_K, textColor=ACCENT, spaceBefore=6 * FONT_K, spaceAfter=4 * FONT_K, keepWithNext=1)
title = ParagraphStyle("title", parent=h1, fontSize=26 * FONT_K, leading=31 * FONT_K, alignment=TA_CENTER, spaceAfter=4 * FONT_K)
subtitle = ParagraphStyle("subtitle", parent=body, fontSize=14 * FONT_K, leading=18 * FONT_K, alignment=TA_CENTER, textColor=GREY)
caption = ParagraphStyle("caption", parent=small, alignment=TA_CENTER, textColor=GREY)

# Текущий язык сборки; меняется в main.
LANG = "ru"


def L(ru: str, en: str) -> str:
	return ru if LANG == "ru" else en


def p(text: str, style=body) -> Paragraph:
	return Paragraph(text, style)


def table(rows: list[list[str]], widths_mm: list[float], mono_cols: tuple[int, ...] = ()) -> Table:
	data = [[p(str(c), cell_b if r == 0 else cell) for c in row] for r, row in enumerate(rows)]
	t = Table(data, colWidths=[w * mm for w in widths_mm], repeatRows=1)
	t.setStyle(TableStyle([
		("BACKGROUND", (0, 0), (-1, 0), SOFT),
		("LINEBELOW", (0, 0), (-1, 0), 1, ACCENT),
		("LINEBELOW", (0, 1), (-1, -1), 0.4, LINE),
		("VALIGN", (0, 0), (-1, -1), "TOP"),
		("TOPPADDING", (0, 0), (-1, -1), 3),
		("BOTTOMPADDING", (0, 0), (-1, -1), 4),
	]))
	return t


def steps(items: list[str]) -> list[Paragraph]:
	return [p(f"<b>{i}.</b> {t}", ParagraphStyle(f"s{i}", parent=body, leftIndent=16 * FONT_K, firstLineIndent=-16 * FONT_K))
			for i, t in enumerate(items, 1)]


def group(s: str) -> str:
	"""Разряды тройками через узкий пробел: 00 000 056 088."""
	out = ""
	for i, ch in enumerate(s):
		if i > 0 and (len(s) - i) % 3 == 0:
			out += "\u2009"
		out += ch
	return out


def num(v: int) -> str:
	"""Число с разделителем тысяч по правилам языка."""
	s = f"{v:,}"
	return s.replace(",", "\u00a0") if LANG == "ru" else s


# --- Зеркало CurtaModel (curta_model.gd) ------------------------------------

TYPES = {1: {"sliders": 8, "counter": 6, "result": 11, "diameter_mm": 53, "height_mm": 85},
		 2: {"sliders": 11, "counter": 8, "result": 15, "diameter_mm": 65, "height_mm": 90}}


class Curta:
	def __init__(self, type_id: int = 1) -> None:
		t = TYPES[type_id]
		self.sliders = [0] * t["sliders"]
		self.result = [0] * t["result"]
		self.counter = [0] * t["counter"]
		self.carriage = 0
		self.subtract = False
		self.counter_reverse = False
		self.overflow = False
		self.turns = 0

	def set_sliders(self, v: int) -> None:
		for i in range(len(self.sliders)):
			self.sliders[i] = v % 10
			v //= 10

	def drum_input(self, j: int) -> int:
		if j < self.carriage:
			return 0
		i = j - self.carriage
		n = self.sliders[i] if i < len(self.sliders) else 0
		add = 9 - n if self.subtract else n
		if self.subtract and j == self.carriage:
			add += 1
		return add

	def turn(self) -> None:
		carry = 0
		for j in range(len(self.result)):
			s = self.result[j] + self.drum_input(j) + carry
			self.result[j] = s % 10
			carry = s // 10
		self.overflow = carry > 0
		step = -1 if self.subtract else 1
		if self.counter_reverse:
			step = -step
		c = step
		for j in range(self.carriage, len(self.counter)):
			s = self.counter[j] + c
			c = 0
			if s >= 10:
				s, c = s - 10, 1
			elif s < 0:
				s, c = s + 10, -1
			self.counter[j] = s
			if c == 0:
				break
		self.turns += 1

	def clear(self) -> None:
		self.result = [0] * len(self.result)
		self.counter = [0] * len(self.counter)

	@staticmethod
	def digits(d: list[int]) -> str:
		return "".join(str(x) for x in reversed(d))

	@staticmethod
	def value(d: list[int]) -> int:
		return int(Curta.digits(d))

	@staticmethod
	def signed(d: list[int]) -> int:
		v = Curta.value(d)
		return v - 10 ** len(d) if d[-1] == 9 else v

	def r(self) -> str:
		return group(self.digits(self.result))

	def c(self) -> str:
		return group(self.digits(self.counter))


def load_result(m: Curta, value: int) -> None:
	"""Число в регистр результата сложением с позиции 1, счётчик — в ноль."""
	m.clear()
	m.subtract = False
	m.carriage = 0
	m.set_sliders(value)
	m.turn()
	m.counter = [0] * len(m.counter)


def pos(k: int) -> str:
	return str(k + 1)


def op_name(sub: bool) -> str:
	return L("вычитание", "subtract") if sub else L("сложение", "add")


# --- Таблицы примеров --------------------------------------------------------

def addsub_rows() -> tuple[list[list[str]], Curta]:
	m = Curta()
	rows = [[L("Шаг", "Step"), L("Ползунки", "Sliders"), L("Ручка", "Crank"), L("Результат", "Result"), L("Счётчик", "Counter")]]
	for i, (v, sub) in enumerate([(1234, False), (5678, False), (999, True)], 1):
		m.set_sliders(v)
		m.subtract = sub
		m.turn()
		rows.append([str(i), num(v), op_name(sub), m.r(), m.c()])
	assert m.value(m.result) == 1234 + 5678 - 999
	return rows, m


def zero_minus_one() -> Curta:
	m = Curta()
	m.set_sliders(1)
	m.subtract = True
	m.turn()
	assert m.digits(m.result) == "9" * 11 and m.signed(m.result) == -1
	return m


def mul_rows(a: int, b: int) -> list[list[str]]:
	m = Curta()
	m.set_sliders(a)
	rows = [[L("Позиция каретки", "Carriage position"), L("Цифра множителя", "Multiplier digit"),
			 L("Оборотов", "Turns"), L("Результат", "Result"), L("Счётчик", "Counter")]]
	digits = [int(d) for d in reversed(str(b))]
	for k, d in enumerate(digits):
		m.carriage = k
		for _ in range(d):
			m.turn()
		rows.append([pos(k), str(d), f"{d} × +", m.r(), m.c()])
	assert m.value(m.result) == a * b and m.value(m.counter) == b
	return rows


def mul99_rows() -> list[list[str]]:
	m = Curta()
	m.set_sliders(123)
	rows = [[L("Позиция", "Position"), L("Ручка", "Crank"), L("Результат", "Result"), L("Счётчик", "Counter")]]
	m.carriage, m.subtract = 0, True
	m.turn()
	rows.append(["1", L("1 × вычитание", "1 × subtract"), m.r(), m.c()])
	m.carriage, m.subtract = 2, False
	m.turn()
	rows.append(["3", L("1 × сложение", "1 × add"), m.r(), m.c()])
	assert m.value(m.result) == 123 * 99 and m.value(m.counter) == 99
	return rows


def div_rows(dividend: int, divisor: int, start: int) -> tuple[list[list[str]], Curta]:
	"""Деление повторным вычитанием, по строке на позицию каретки."""
	m = Curta()
	load_result(m, dividend)
	m.set_sliders(divisor)
	m.counter_reverse = True
	rows = [[L("Позиция", "Position"), L("Вычитаний до «перебора»", "Subtractions until overdraw"),
			 L("Возврат", "Undo"), L("Цифра частного", "Quotient digit"), L("Результат", "Result"), L("Счётчик", "Counter")]]
	for k in range(start, -1, -1):
		m.carriage = k
		m.subtract = True
		n = 0
		while True:
			m.turn()
			n += 1
			if m.signed(m.result) < 0:
				m.subtract = False
				m.turn()
				break
		rows.append([pos(k), str(n), L("1 × сложение", "1 × add"), str(n - 1), m.r(), m.c()])
	q, r = divmod(dividend, divisor)
	assert m.value(m.counter) == q and m.value(m.result) == r
	return rows, m


def sqrt_rows(n: int, pairs: int) -> tuple[list[list[str]], Curta]:
	"""Корень вычитанием нечётных чисел (Тёплер)."""
	m = Curta()
	load_result(m, n)
	m.counter_reverse = True
	rows = [[L("Позиция", "Position"), L("Вычитаемые числа (ползунки)", "Numbers subtracted (sliders)"),
			 L("Цифра корня", "Root digit"), L("Результат", "Result"), L("Счётчик", "Counter")]]
	r = 0
	for k in range(pairs - 1, -1, -1):
		m.carriage = k
		t = 0
		used = []
		while True:
			odd = 20 * r + 2 * t + 1
			m.set_sliders(odd * 10 ** k)
			m.subtract = True
			m.turn()
			if m.signed(m.result) < 0:
				m.subtract = False
				m.turn()
				used.append(f"<font color='#c8473b'>{odd * 10 ** k}</font>")
				break
			used.append(str(odd * 10 ** k))
			t += 1
		r = r * 10 + t
		rows.append([pos(k), ", ".join(used), str(t), m.r(), m.c()])
	assert m.value(m.counter) == int(n ** 0.5) and m.value(m.result) == n - int(n ** 0.5) ** 2
	return rows, m


# --- Рисунок: развёртка ступенчатого вала --------------------------------------

def drum_drawing(highlight: int) -> Drawing:
	"""9 рёбер × 10 уровней; каждый уровень — полоса сложения (сверху) и дополнения (снизу)."""
	cw, ch = 15 * mm, 6.2 * mm
	left, top = 40 * mm, 8 * mm
	w = left + 9 * cw + 75 * mm
	h = top + 10 * ch + 14 * mm
	d = Drawing(w, h)
	fs = 9 * FONT_K
	y0 = h - top
	for r in range(1, 10):
		x = left + (r - 1) * cw
		d.add(String(x + cw / 2, y0 + 2, str(r), fontName=FONT, fontSize=fs * 0.8, textAnchor="middle", fillColor=GREY))
	d.add(String(left - 4, y0 + 2, L("ребро", "rib"), fontName=FONT, fontSize=fs * 0.8, textAnchor="end", fillColor=GREY))
	for lvl in range(10):
		yt = y0 - lvl * ch
		hot = lvl == highlight
		if hot:
			d.add(Rect(left - 3, yt - ch, 9 * cw + 6, ch, fillColor=colors.HexColor("#fff3c4"), strokeColor=None))
		d.add(String(left - 4, yt - ch * 0.72, f"n = {lvl}", fontName=FONT + ("-Bold" if hot else ""), fontSize=fs * 0.8,
					 textAnchor="end", fillColor=INK))
		for r in range(1, 10):
			x = left + (r - 1) * cw + 2
			if lvl >= r:
				d.add(Rect(x, yt - ch * 0.48, cw - 4, ch * 0.42, fillColor=GOLD, strokeColor=None))
			if lvl <= 9 - r:
				d.add(Rect(x, yt - ch * 0.98, cw - 4, ch * 0.42, fillColor=RED, strokeColor=None))
		add, sub = lvl, 9 - lvl
		d.add(String(left + 9 * cw + 6, yt - ch * 0.72, f"+{add}   /   +{sub}", fontName=FONT + ("-Bold" if hot else ""),
					 fontSize=fs * 0.8, fillColor=INK))
	d.add(String(left + 9 * cw + 6, y0 + 2, L("сложение / дополнение", "add / complement"), fontName=FONT,
				 fontSize=fs * 0.8, fillColor=GREY))
	yb = y0 - 10 * ch - 6 * mm
	d.add(Rect(left, yb, 6 * mm, 3 * mm, fillColor=GOLD, strokeColor=None))
	d.add(String(left + 8 * mm, yb, L("зуб сложения", "addition tooth"), fontName=FONT, fontSize=fs * 0.8, fillColor=INK))
	d.add(Rect(left + 60 * mm, yb, 6 * mm, 3 * mm, fillColor=RED, strokeColor=None))
	d.add(String(left + 68 * mm, yb, L("зуб дополнения (на полшага ниже)", "complement tooth (half a step lower)"),
				 fontName=FONT, fontSize=fs * 0.8, fillColor=INK))
	d.add(Line(left - 3, y0, left + 9 * cw + 3, y0, strokeColor=LINE))
	return d


def footer(canvas, doc) -> None:
	canvas.saveState()
	canvas.setFont(FONT, 9 * FONT_K)
	canvas.setFillColor(colors.HexColor("#777"))
	w, _ = landscape(A4)
	canvas.drawString(15 * mm, 8 * mm, L("Калькулятор «Курта» — инструкция к 3D-модели", "Curta calculator — 3D model manual"))
	canvas.drawRightString(w - 15 * mm, 8 * mm, L("стр. ", "p. ") + str(doc.page))
	canvas.restoreState()


def image(name: str, width_mm: float) -> Image:
	return Image(str(DOCS / f"{name}_{LANG}.png"), width=width_mm * mm, height=width_mm * mm * 1080 / 1920)


def story() -> list:
	s: list = []

	# --- Титул -------------------------------------------------------------
	s += [
		Spacer(1, 2 * mm),
		p(L("Механический калькулятор «Курта»", "The Curta mechanical calculator"), title),
		p(L("Интерактивная 3D-модель: устройство, управление и приёмы счёта",
			"Interactive 3D model: construction, controls and calculating techniques"), subtitle),
		Spacer(1, 4 * mm),
		image("scheme", 165),
		p(L("Модель в программе после примера 123 × 456 (раздел 6). F1 — открыть/закрыть эту инструкцию, ← / → — листать.",
			"The model after the 123 × 456 example (section 6). F1 opens/closes this manual, ← / → flip pages."), caption),
		PageBreak(),
	]

	# --- 1. История ----------------------------------------------------------
	s += [
		p(L("1. История", "1. History"), h1),
		p(L("«Курта» — самый маленький механический калькулятор на четыре действия, когда-либо выпускавшийся "
			"серийно. Цилиндр размером с перечницу держат в левой руке, правой крутят ручку сверху. За это её "
			"прозвали «мельницей для перца» и «математической гранатой».",
			"The Curta is the smallest four-function mechanical calculator ever made in series. You hold the "
			"pepper-grinder-sized cylinder in your left hand and turn the crank on top with your right. Hence its "
			"nicknames: the “pepper grinder” and the “math grenade”.")),
		p(L("Её придумал венский инженер <b>Курт Херцштарк</b> (1902–1988), сын владельца фабрики арифмометров. "
			"Идею карманной машины он обдумывал с конца 1930-х. В 1943 году его арестовали и отправили в концлагерь "
			"Бухенвальд; там его поставили на работу в лагерной мастерской и разрешили чертить калькулятор. "
			"К освобождению в 1945 году чертежи были почти готовы.",
			"It was invented by the Viennese engineer <b>Curt Herzstark</b> (1902–1988), son of a calculating-machine "
			"factory owner. He had been thinking about a pocket machine since the late 1930s. In 1943 he was arrested "
			"and sent to the Buchenwald concentration camp; there he was put to work in the camp workshop and allowed "
			"to draw the calculator. By the liberation in 1945 the drawings were almost complete.")),
		p(L("После войны производство наладила компания Contina AG в Лихтенштейне. <b>Тип I</b> вышел в 1948 году, "
			"более крупный <b>тип II</b> — в 1954-м. Машины выпускали до начала 1970-х, пока их не вытеснили "
			"электронные калькуляторы. Всего, по разным данным, сделано около 140 тысяч экземпляров. «Курту» любили "
			"пилоты раллийных команд, геодезисты и инженеры: она считала быстро, точно и без батареек.",
			"After the war production was set up by Contina AG in Liechtenstein. <b>Type I</b> appeared in 1948, the "
			"larger <b>Type II</b> in 1954. They were made until the early 1970s, when electronic calculators took "
			"over; about 140 thousand were built according to various sources. Rally navigators, surveyors and "
			"engineers loved the Curta: fast, exact and with no batteries.")),
		KeepTogether([table([
			["", L("Тип I", "Type I"), L("Тип II", "Type II")],
			[L("Ползунки установки", "Setting sliders"), str(TYPES[1]["sliders"]), str(TYPES[2]["sliders"])],
			[L("Счётчик оборотов", "Revolution counter"), str(TYPES[1]["counter"]), str(TYPES[2]["counter"])],
			[L("Регистр результата", "Result register"), str(TYPES[1]["result"]), str(TYPES[2]["result"])],
			[L("Позиций каретки", "Carriage positions"), str(TYPES[1]["counter"]), str(TYPES[2]["counter"])],
			[L("Диаметр × высота, мм", "Diameter × height, mm"), "53 × 85", "65 × 90"],
		], [100, 60, 60]),
		p(L("В программе тип переключается клавишей T (ниже все примеры — для типа I).",
			"Switch the type with T in the program (all examples below are for Type I)."), small)]),
		Spacer(1, 4 * mm),
	]

	# --- 2. Устройство ----------------------------------------------------------
	s += [
		p(L("2. Из чего состоит машина", "2. Parts of the machine"), h1),
		p(L("<b>Блокировка.</b> Пока ручка не вернулась «домой», каретку нельзя сдвинуть, ручку нельзя вытянуть или "
			"вдвинуть, рычаг сброса не работает — так машина защищает себя от поломки, и модель ведёт себя так же.",
			"<b>Interlock.</b> While the crank is away from home you cannot shift the carriage, pull or push the crank, "
			"or use the clearing lever — the machine protects itself, and the model behaves the same way.")),
		table([
			[L("Деталь", "Part"), L("Что делает", "What it does")],
			[L("Ползунки установки", "Setting sliders"),
			 L("Вертикальные прорези на корпусе, по одной на разряд; старший разряд слева. Сверху 0, внизу 9. "
			   "Число на ползунках — «установка», его видно в окне контроля над прорезями.",
			   "Vertical slots on the body, one per digit; the highest digit on the left. 0 at the top, 9 at the bottom. "
			   "The number on the sliders is the “setting”; it shows in the check window above the slots.")],
			[L("Каретка", "Carriage"),
			 L("Верхняя часть, поворачивается относительно корпуса на шаг разряда. На ней два регистра: результат "
			   "(внешнее кольцо, белые цифры) и счётчик оборотов (внутреннее кольцо, оранжевые). Номер позиции — "
			   "на боку каретки против метки на корпусе.",
			   "The top part; it rotates relative to the body one digit at a time. It carries two registers: the result "
			   "(outer ring, white digits) and the revolution counter (inner ring, orange). The position number is on the "
			   "carriage side next to the mark on the body.")],
			[L("Ручка", "Crank"),
			 L("Один полный оборот по часовой стрелке прибавляет установку к результату и +1 к счётчику. "
			   "Ручка вытянута вверх (красное кольцо) — оборот вычитает. Назад ручка не крутится (храповик).",
			   "One full clockwise turn adds the setting to the result and 1 to the counter. With the crank pulled up "
			   "(red ring visible) a turn subtracts. The crank cannot turn backwards (ratchet).")],
			[L("Рычаг сброса", "Clearing lever"),
			 L("Кольцевой рычаг на каретке: провести его полный круг — обнулить результат и счётчик.",
			   "A ring lever on the carriage: sweep it a full circle to clear the result and the counter.")],
			[L("Переключатель счётчика", "Counter reverse switch"),
			 L("Меняет знак счёта оборотов: при делении и извлечении корня вычитания считаются +1, и в счётчике "
			   "сразу получается ответ.",
			   "Flips the counting sign: in division and square root subtractions count +1, so the counter shows the answer.")],
			[L("Ступенчатый вал", "Stepped drum"),
			 L("Цилиндр в центре корпуса, крутится вместе с ручкой. Его рёбра поворачивают шестерни ползунков — см. раздел 3.",
			   "The cylinder in the centre of the body, turning with the crank. Its teeth turn the slider pinions — see section 3.")],
		], [62, 205]),
		CondPageBreak(95 * mm),
	]

	# --- 3. Ступенчатый вал ------------------------------------------------------
	zm = zero_minus_one()
	s += [
		KeepTogether([p(L("3. Как работает ступенчатый вал", "3. How the stepped drum works"), h1),
		p(L("Вал придумал Лейбниц ещё в XVII веке: на цилиндре девять рёбер разной длины. Шестерня ползунка "
			"скользит вдоль вала; на уровне n за один оборот вала её цепляют ровно n рёбер — шестерня и связанное с ней "
			"колесо результата поворачиваются на n десятых. У «Курты» один вал на все разряды: шестерни всех ползунков "
			"стоят вокруг него.",
			"The drum goes back to Leibniz in the 17th century: nine teeth of different lengths on a cylinder. The slider "
			"pinion slides along the drum; at level n exactly n teeth catch it per revolution, so the pinion and its "
			"result wheel turn by n tenths. The Curta has one drum for all digits: the pinions of all sliders stand around it.")),
		drum_drawing(3),
		p(L("Развёртка вала. Шестерня ползунка со значением 3 (жёлтая полоса) при сложении цепляет 3 зуба, "
			"при вычитании — 6.", "The unrolled drum. A pinion at value 3 (yellow band) catches 3 teeth when adding, 6 when subtracting."),
		  caption)]),
		CondPageBreak(95 * mm),
		p(L("Вычитание сложением дополнения", "Subtraction by adding the complement"), h2),
		p(L("Главная находка Херцштарка: между зубьями сложения на валу стоят зубья <b>дополнения до 9</b> — на уровне n "
			"их 9 − n. Когда ручку вытягивают вверх, вал поднимается на полшага, и под шестернями оказываются они. "
			"Ещё один зуб «+1» добавляется в младший разряд под кареткой. В сумме к результату прибавляется "
			"10<super>w</super> − x, где w — число разрядов регистра, а перенос из старшего разряда теряется. "
			"Значит, R + (10<super>w</super> − x) = R − x: машина вычитает, ничего не крутя назад.",
			"Herzstark’s key idea: between the addition teeth the drum carries <b>nines-complement</b> teeth — 9 − n at "
			"level n. Pulling the crank up lifts the drum half a step, and these teeth come under the pinions. One more "
			"“+1” tooth acts on the lowest digit under the carriage. Altogether 10<super>w</super> − x is added, where w is "
			"the number of register digits and the carry out of the top digit is lost. So R + (10<super>w</super> − x) = "
			"R − x: the machine subtracts without turning anything backwards.")),
		p(L(f"Пример: 0 − 1. Ползунки 00000001, ручка вверху. Вал даёт 8 нулевым разрядам по 9 зубьев и единицам 8 + 1 = 9 — "
			f"в результате <b>{group(Curta.digits(zm.result))}</b>, в счётчике {group(Curta.digits(zm.counter))}. "
			"Одни девятки сверху — это отрицательное число в дополнительном коде: −1. Программа показывает его и "
			"знаковое значение на правой панели.",
			f"Example: 0 − 1. Sliders 00000001, crank up. The drum gives each zero digit 9 teeth and the units 8 + 1 = 9 — "
			f"the result is <b>{group(Curta.digits(zm.result))}</b>, the counter {group(Curta.digits(zm.counter))}. "
			"Nines at the top mean a negative number in complement form: −1. The program shows it with the signed value "
			"on the right panel.")),
		p(L("Перенос десятков", "Tens carry"), h2),
		p(L("Когда колесо результата проходит 9 → 0, специальный палец добавляет 1 в соседний разряд; перенос может "
			"пробежать по всей цепочке девяток. Перенос из самого старшего разряда теряется — поэтому и работает "
			"вычитание дополнением.",
			"When a result wheel passes 9 → 0, a finger adds 1 to the next digit; the carry can ripple through a chain "
			"of nines. The carry out of the top digit is lost — which is exactly why complement subtraction works.")),
		image("cutaway", 120),
		p(L("Разрез (K): корпус прозрачный, видны вал, шестерни на квадратных валах и их красные метки.",
			"Cutaway (K): the body is transparent; the drum, the pinions on square shafts and their red marks are visible."), caption),
		CondPageBreak(95 * mm),
	]

	# --- 4. Управление -----------------------------------------------------------
	s += [
		p(L("4. Управление в программе", "4. Program controls"), h1),
		table([
			[L("Мышь (и касания на Steam Deck)", "Mouse (and touch on Steam Deck)"), L("Что происходит", "Effect")],
			[L("Тянуть ручку ползунка вверх / вниз", "Drag a slider knob up / down"), L("Значение 0–9; колесо над ползунком — ±1", "Value 0–9; wheel over a slider — ±1")],
			[L("Крутить ручку по часовой стрелке", "Turn the crank clockwise"),
			 L("Полный круг — одна операция; назад не идёт; отпущенная чуть дальше «дома» встаёт на место",
			   "A full circle is one operation; it won’t go back; released just past home it snaps home")],
			[L("Щелчок по головке ручки", "Click the crank hub"), L("Вытянуть (вычитание) / вдвинуть (сложение)", "Pull up (subtract) / push in (add)")],
			[L("Повернуть каретку за верх", "Rotate the carriage by its top"), L("Сдвиг на разряд", "Shift by one digit")],
			[L("Провести рычаг сброса по кругу", "Sweep the clearing lever around"), L("Сброс результата и счётчика", "Clear result and counter")],
			[L("Щелчок по переключателю на каретке", "Click the switch on the carriage"), L("Реверс счётчика (красный — включён)", "Counter reverse (red = on)")],
			[L("Тянуть по пустому месту / правой кнопкой", "Drag empty space / right button"), L("Вращать вид; колесо — масштаб", "Orbit the view; wheel — zoom")],
		], [120, 147]),
		CondPageBreak(120 * mm),
		p(L("Клавиатура", "Keyboard"), h2),
		table([
			[L("Клавиша", "Key"), L("Действие", "Action"), L("Клавиша", "Key"), L("Действие", "Action")],
			["0–9, Backspace", L("Набрать число (цифры вдвигаются справа)", "Type a number (digits shift in from the right)"), "C", L("Сброс регистров (Shift+C — только счётчик)", "Clear registers (Shift+C — counter only)")],
			["← / →", L("Выбрать ползунок", "Select a slider"), "X", L("Ползунки в 0", "Sliders to 0")],
			["↑ / ↓", L("Ползунок выше / ниже (−1 / +1)", "Slider up / down (−1 / +1)"), "V", L("Реверс счётчика", "Counter reverse")],
			[L("Enter, Пробел", "Enter, Space"), L("Оборот ручки", "Turn the crank"), "K", L("Разрез", "Cutaway")],
			["Tab", L("Ручка вверх / вниз", "Crank up / down"), "T", L("Тип I / II", "Type I / II")],
			["[ / ]", L("Каретка на позицию меньше / больше", "Carriage one position down / up"), "S", L("Журнал в CSV", "Log to CSV")],
			["Home", L("Исходный вид", "Reset view"), "L", L("Язык", "Language")],
			["F1", L("Эта инструкция (O — открыть PDF)", "This manual (O opens the PDF)"), "", ""],
		], [46, 92, 34, 95]),
		p(L("Справа — панель регистров со знаковыми значениями и последними операциями. S сохраняет журнал "
			"user://curta_log.csv: n, op, carriage, setting, result, counter — по строке на оборот и сброс.",
			"On the right is the register panel with signed values and the last operations. S saves the log "
			"user://curta_log.csv: n, op, carriage, setting, result, counter — one row per turn and per clear."), small),
		CondPageBreak(95 * mm),
	]

	# --- 5. Сложение и вычитание ---------------------------------------------------
	rows, m = addsub_rows()
	s += [
		p(L("5. Сложение и вычитание", "5. Addition and subtraction"), h1),
		p(L("Пример: 1234 + 5678 − 999.", "Example: 1234 + 5678 − 999."), h2),
		*steps([
			L("Сбросьте регистры (рычаг или C), каретка в позиции 1, ручка вдвинута.",
			  "Clear the registers (lever or C), carriage at position 1, crank pushed in."),
			L("Наберите 1234 и сделайте оборот: число перешло в результат, счётчик 1.",
			  "Set 1234 and make a turn: the number goes to the result, counter 1."),
			L("Наберите 5678 и снова оборот — в результате сумма.", "Set 5678 and turn again — the sum is in the result."),
			L("Наберите 999, вытяните ручку (головка или Tab) и сделайте оборот — 999 вычтено, счётчик уменьшился.",
			  "Set 999, pull the crank up (hub or Tab) and turn — 999 is subtracted, the counter goes down."),
		]),
		table(rows, [25, 45, 45, 80, 60]),
		Spacer(1, 2 * mm),
		p(L(f"Ответ: {num(m.value(m.result))}. Счётчик показывает «сумму оборотов» 1 + 1 − 1 = {m.value(m.counter)}: "
			"для сложения он не нужен, но в умножении и делении именно он даёт множитель и частное.",
			f"Answer: {num(m.value(m.result))}. The counter holds the “sum of turns” 1 + 1 − 1 = {m.value(m.counter)}: "
			"not needed for addition, but in multiplication and division it gives the multiplier and the quotient.")),
		CondPageBreak(95 * mm),
	]

	# --- 6. Умножение --------------------------------------------------------------
	s += [
		p(L("6. Умножение: обороты и сдвиги", "6. Multiplication: turns and shifts"), h1),
		p(L("Умножение — это повторное сложение, а сдвиг каретки на позицию умножает установку на 10. "
			"Поэтому множитель «прокручивают» цифра за цифрой: единицы — в позиции 1, десятки — в позиции 2 и т. д. "
			"Счётчик при этом сам собирает множитель — по нему удобно проверить, что не ошиблись.",
			"Multiplication is repeated addition, and shifting the carriage one position multiplies the setting by 10. "
			"So the multiplier is “cranked in” digit by digit: units at position 1, tens at position 2 and so on. "
			"The counter builds up the multiplier itself — a handy check that nothing went wrong.")),
		p(L("Пример: 123 × 456.", "Example: 123 × 456."), h2),
		table(mul_rows(123, 456), [55, 55, 35, 70, 52]),
		Spacer(1, 2 * mm),
		p(L(f"Ответ: {num(123 * 456)}, в счётчике 456. Всего 15 оборотов.",
			f"Answer: {num(123 * 456)}, the counter shows 456. 15 turns in total.")),
		p(L("Сокращённое умножение", "Short-cut multiplication"), h2),
		p(L("Цифры 7, 8, 9 выгоднее набирать вычитанием: 99 = 100 − 1. Для 123 × 99 вместо 18 оборотов хватит двух: "
			"один вычитанием в позиции 1 и один сложением в позиции 3.",
			"Digits 7, 8, 9 are cheaper by subtraction: 99 = 100 − 1. For 123 × 99 two turns are enough instead of 18: "
			"one subtracting at position 1 and one adding at position 3.")),
		KeepTogether([table(mul99_rows(), [40, 70, 90, 67]),
		p(L("Счётчик снова показывает 99: −1 в позиции 1 и +1 в позиции 3 дают 100 − 1.",
			"The counter again shows 99: −1 at position 1 and +1 at position 3 make 100 − 1."), small)]),
		CondPageBreak(95 * mm),
	]

	# --- 7. Деление ----------------------------------------------------------------
	rows, m = div_rows(56090, 123, 2)
	s += [
		p(L("7. Деление: вычитание до «перебора»", "7. Division: subtract until overdraw"), h1),
		*steps([
			L("Сбросьте регистры. Наберите делимое 56090 и сделайте оборот в позиции 1 — оно в результате. "
			  "Обнулите только счётчик: Shift+C.",
			  "Clear the registers. Set the dividend 56090 and turn once at position 1 — it is now in the result. "
			  "Clear only the counter: Shift+C."),
			L("Включите реверс счётчика (V): теперь каждое вычитание считается +1.",
			  "Switch on the counter reverse (V): every subtraction now counts +1."),
			L("Наберите делитель 123. Сдвиньте каретку так, чтобы старший разряд делителя встал под старший разряд "
			  "делимого: для 56090 и 123 — позиция 3.",
			  "Set the divisor 123. Shift the carriage so the divisor’s top digit is under the dividend’s top digit: "
			  "for 56090 and 123 — position 3."),
			L("Вытяните ручку и крутите, пока результат не станет «отрицательным» (сверху появятся девятки). "
			  "Это один лишний оборот — верните его одним оборотом с вдвинутой ручкой.",
			  "Pull the crank up and turn until the result goes “negative” (nines appear at the top). That is one turn "
			  "too many — undo it with one turn with the crank pushed in."),
			L("Сдвиньте каретку на позицию левее и повторите. После позиции 1 в счётчике — частное, в результате — остаток.",
			  "Shift the carriage one position down and repeat. After position 1 the counter holds the quotient, the "
			  "result holds the remainder."),
		]),
		CondPageBreak(80 * mm),
		KeepTogether([p(L("Пример: 56090 : 123.", "Example: 56090 : 123."), h2),
		table(rows, [32, 62, 42, 40, 52, 39]),
		Spacer(1, 2 * mm),
		p(L(f"Ответ: 56090 = 123 × <b>{m.value(m.counter)}</b> + <b>{m.value(m.result)}</b>. "
			"«Вычитаний до перебора» на одно больше цифры частного — последний оборот и его возврат взаимно "
			"гасятся и в результате, и в счётчике.",
			f"Answer: 56090 = 123 × <b>{m.value(m.counter)}</b> + <b>{m.value(m.result)}</b>. "
			"“Subtractions until overdraw” is one more than the quotient digit — the last turn and its undo cancel out "
			"in both the result and the counter."))]),
		p(L("Чтобы получить десятичные знаки, сдвиньте делимое на ползунках влево (умножьте на 10<super>k</super>) "
			"и запомните, где ставить запятую.",
			"For decimal places, shift the dividend left on the sliders (multiply by 10<super>k</super>) and remember "
			"where the decimal point goes."), small),
		CondPageBreak(95 * mm),
	]

	# --- 8. Корень -----------------------------------------------------------------
	rows, m = sqrt_rows(15129, 3)
	s += [
		p(L("8. Квадратный корень нечётными числами", "8. Square root by odd numbers"), h1),
		p(L("Метод Тёплера (1865) опирается на тождество 1 + 3 + 5 + … + (2n − 1) = n². Значит, если из числа "
			"вычитать подряд нечётные числа, пока хватает, их количество и есть корень. Для многозначного корня "
			"берут по две цифры подкоренного числа на каждую цифру корня: если уже найдена часть корня r, "
			"вычитают нечётные числа 20r + 1, 20r + 3, 20r + 5, …",
			"Toepler’s method (1865) relies on 1 + 3 + 5 + … + (2n − 1) = n². Subtract consecutive odd numbers while you "
			"can, and their count is the root. For a multi-digit root take two digits of the radicand per root digit: "
			"once part r of the root is known, subtract the odd numbers 20r + 1, 20r + 3, 20r + 5, …")),
		p(L("На «Курте» каждая цифра корня — своя позиция каретки k, а нечётное число набирают на ползунках со сдвигом "
			"на те же k разрядов. Вместе получается вес 100<super>k</super> — ровно пара цифр. Счётчик в реверсе "
			"собирает цифры корня. Лишнее вычитание, как при делении, возвращают одним сложением.",
			"On the Curta each root digit has its own carriage position k, and the odd number is set on the sliders "
			"shifted by the same k digits. Together this gives the weight 100<super>k</super> — exactly a pair of digits. "
			"With the counter reversed it collects the root digits. The extra subtraction is undone by one addition, as in division.")),
		KeepTogether([p(L("Пример: √15129 (пары 1 | 51 | 29 → три цифры корня, позиции 3, 2, 1).",
			"Example: √15129 (pairs 1 | 51 | 29 → three root digits, positions 3, 2, 1)."), h2),
		table(rows, [32, 100, 36, 56, 43]),
		Spacer(1, 2 * mm),
		p(L(f"Красным — число, давшее «перебор» и возвращённое сложением. Ответ: √15129 = <b>{m.value(m.counter)}</b>, "
			f"остаток {m.value(m.result)}.",
			f"In red — the number that overdrew and was added back. Answer: √15129 = <b>{m.value(m.counter)}</b>, "
			f"remainder {m.value(m.result)}."))]),
		p(L("Практики на настоящей «Курте» не перенабирают число целиком: меняют только младший ползунок на 2 "
			"(1 → 3 → 5 …), а при переходе к новой цифре удваивают её на соседнем ползунке — это и есть 20r.",
			"Real Curta users don’t reset the whole number each time: they move only the lowest slider by 2 "
			"(1 → 3 → 5 …), and when moving to the next digit they double it on the neighbouring slider — that is the 20r."), small),
	]
	return s


def render_pages(pdf: Path, pages: Path) -> int:
	import pypdfium2 as pdfium
	pages.mkdir(parents=True, exist_ok=True)
	# Вместе с .import, иначе Godot продолжит видеть удалённые страницы.
	for old in [*pages.glob("page_*.png"), *pages.glob("page_*.png.import")]:
		old.unlink()
	doc = pdfium.PdfDocument(str(pdf))
	for i, page in enumerate(doc, 1):
		scale = PAGE_PX_HEIGHT / page.get_height()
		page.render(scale=scale).to_pil().save(pages / f"page_{i}.png")
	n = len(doc)
	doc.close()
	return n


if __name__ == "__main__":
	for LANG in LANGS:
		pdf = DOCS / f"instruction_{LANG}.pdf"
		SimpleDocTemplate(
			str(pdf), pagesize=landscape(A4),
			leftMargin=15 * mm, rightMargin=15 * mm, topMargin=12 * mm, bottomMargin=14 * mm,
			title=L("Калькулятор «Курта» — инструкция", "Curta calculator — manual"),
			author="curt_calculator",
		).build(story(), onFirstPage=footer, onLaterPages=footer)
		n = render_pages(pdf, DOCS / "pages" / LANG)
		print(f"{LANG}: {pdf.name}, {n} pages")
