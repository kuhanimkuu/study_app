"""
Turns a document spec (see templates.py's SPEC_SCHEMA) into a designed PDF:
a coloured title band, numbered section bars, callout boxes, glossary
tables, typeset maths, exam questions with answer lines, cut-out
flashcards and an answer key on its own page. The template (one per
doc_type, templates.py) decides colours and layout; the spec is the
content. Loaded by engine.py by file path, like engine.py itself is.

Maths: "$...$" inside any text, and every formula block, is drawn with
matplotlib's mathtext (Computer Modern, the textbook look 1.0.16 brought to
chat) into a transparent PNG and placed inline. What mathtext can't parse
falls back to readable plain text (Greek letters, superscripts), never to
raw LaTeX source.

Fonts: DejaVu Sans, shipped inside matplotlib, so arrows, Greek letters
and ≤ ≥ ≈ print on any server. Helvetica (Latin-1 only) if it's missing.
"""
from __future__ import annotations

import hashlib
import re
from datetime import date
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.lib.utils import simpleSplit
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    CondPageBreak,
    Flowable,
    Frame,
    Image,
    KeepTogether,
    NextPageTemplate,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

PAGE_W, PAGE_H = A4
MARGIN = 18 * mm
CONTENT_W = PAGE_W - 2 * MARGIN

INK = colors.HexColor("#1F2937")
MUTED = colors.HexColor("#6B7280")
RULE = colors.HexColor("#E5E7EB")
LINE = colors.HexColor("#CBD5E1")

# Callout styles are the same in every template, so a "watch out" box
# always looks like one.
CALLOUTS = {
    "tip": ("TIP", "#15803D", "#F0FDF4"),
    "warning": ("WATCH OUT", "#B91C1C", "#FEF2F2"),
    "remember": ("REMEMBER", "#7E22CE", "#FAF5FF"),
    "example": ("WORKED EXAMPLE", "#1D4ED8", "#EFF6FF"),
    "key": ("KEY IDEA", None, None),  # the template's own accent
}

_FONTS: dict[str, str] = {}


def _fonts() -> dict[str, str]:
    if _FONTS:
        return _FONTS
    try:
        import matplotlib

        ttf = Path(matplotlib.get_data_path()) / "fonts" / "ttf"
        for name, file in [
            ("SO-Body", "DejaVuSans.ttf"),
            ("SO-Bold", "DejaVuSans-Bold.ttf"),
            ("SO-Italic", "DejaVuSans-Oblique.ttf"),
            ("SO-BoldItalic", "DejaVuSans-BoldOblique.ttf"),
        ]:
            pdfmetrics.registerFont(TTFont(name, str(ttf / file)))
        pdfmetrics.registerFontFamily(
            "SO-Body", normal="SO-Body", bold="SO-Bold", italic="SO-Italic", boldItalic="SO-BoldItalic"
        )
        _FONTS.update(body="SO-Body", bold="SO-Bold", italic="SO-Italic")
    except Exception:
        _FONTS.update(body="Helvetica", bold="Helvetica-Bold", italic="Helvetica-Oblique")
    return _FONTS


# --- maths ---

_MATH_RE = re.compile(r"\$\$(.+?)\$\$|\\\((.+?)\\\)|\$(?!\s)([^$\n]+?)(?<!\s)\$", re.DOTALL)
_BOLD_RE = re.compile(r"\*\*(.+?)\*\*")

# LaTeX that mathtext doesn't know, rewritten to what it does.
_LATEX_REWRITES = [
    (re.compile(r"\\[dt]frac"), r"\\frac"),
    (re.compile(r"\\(?:text|textrm|operatorname|mbox)\s*\{([^{}]*)\}"), lambda m: r"\mathrm{" + m.group(1).replace(" ", r"\ ") + "}"),
    (re.compile(r"\\textbf\s*\{([^{}]*)\}"), r"\\mathbf{\1}"),
    (re.compile(r"\\(?:displaystyle|limits|nolimits)\b"), ""),
    (re.compile(r"\\left\.|\\right\."), ""),
    (re.compile(r"\\[,;:!]\s*$"), ""),
    (re.compile(r"\\ge\b(?!q)"), r"\\geq"),
    (re.compile(r"\\le\b(?!q)"), r"\\leq"),
    (re.compile(r"\\ne\b(?!q)"), r"\\neq"),
]

_PLAIN_SYMBOLS = {
    "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε", "theta": "θ",
    "lambda": "λ", "mu": "μ", "nu": "ν", "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "phi": "φ",
    "varphi": "φ", "omega": "ω", "Delta": "Δ", "Sigma": "Σ", "Omega": "Ω", "Phi": "Φ", "Gamma": "Γ",
    "Lambda": "Λ", "Theta": "Θ", "Pi": "Π", "chi": "χ", "psi": "ψ", "eta": "η", "kappa": "κ", "zeta": "ζ",
    "times": "×", "cdot": "·", "div": "÷", "pm": "±", "mp": "∓", "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥",
    "neq": "≠", "ne": "≠", "approx": "≈", "equiv": "≡", "propto": "∝", "infty": "∞", "partial": "∂",
    "nabla": "∇", "sum": "Σ", "prod": "Π", "int": "∫", "oint": "∮", "sqrt": "√", "to": "→",
    "rightarrow": "→", "leftarrow": "←", "Rightarrow": "⇒", "Leftrightarrow": "⇔", "leftrightarrow": "↔",
    "rightleftharpoons": "⇌", "degree": "°", "circ": "°", "in": "∈", "notin": "∉", "subset": "⊂",
    "cup": "∪", "cap": "∩", "forall": "∀", "exists": "∃", "angle": "∠", "perp": "⊥", "parallel": "∥",
    "hbar": "ħ", "ell": "ℓ", "cdots": "⋯", "ldots": "…", "dots": "…", "quad": "  ", "qquad": "    ",
}


# What json.loads makes of an unescaped "\frac", "\beta", "\theta" or
# "\rho" when a caller parsed the model's JSON without parse_spec().
_JSON_CONTROL = {"\x0c": "\\f", "\x08": "\\b", "\t": "\\t", "\r": "\\r"}


def _repair_latex(latex: str) -> str:
    for char, command in _JSON_CONTROL.items():
        latex = re.sub(re.escape(char) + r"(?=[A-Za-z])", lambda _m, c=command: c, latex)
    return latex


def _latex_to_plain(latex: str) -> str:
    """Readable text for maths mathtext couldn't draw: "\\frac{a}{b}" ->
    "(a)/(b)", "x^{2}" -> x², Greek letters as letters."""
    latex = re.sub(r"\\(?:begin|end)\s*\{[^{}]*\}", " ", latex).replace("&", "")
    s = re.sub(r"\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}", r"(\1)/(\2)", latex)
    s = re.sub(r"\\sqrt\s*\{([^{}]*)\}", r"√(\1)", s)
    s = re.sub(r"\\(?:mathrm|mathbf|text|operatorname|mathit)\s*\{([^{}]*)\}", r"\1", s)
    s = re.sub(r"\\([A-Za-z]+)", lambda m: _PLAIN_SYMBOLS.get(m.group(1), m.group(1)), s)
    s = escape(s.replace("\\,", " ").replace("\\ ", " ").replace("\\\\", " "))
    s = re.sub(r"\^\{([^{}]*)\}|\^(\S)", lambda m: f"<super>{m.group(1) or m.group(2)}</super>", s)
    s = re.sub(r"_\{([^{}]*)\}|_(\S)", lambda m: f"<sub>{m.group(1) or m.group(2)}</sub>", s)
    return s.replace("{", "").replace("}", "")


class _Maths:
    """Draws LaTeX to PNGs in this build's temporary folder."""

    def __init__(self, folder: Path) -> None:
        self.folder = folder
        self.cache: dict[tuple, tuple[str, float, float, float] | None] = {}

    def draw(self, latex: str, size: float, color: str = "#111827") -> tuple[str, float, float, float] | None:
        """(png path, width pt, height pt, depth pt), or None if mathtext
        can't parse it."""
        latex = _repair_latex(latex).strip()
        for pattern, repl in _LATEX_REWRITES:
            latex = pattern.sub(repl, latex)
        key = (latex, size, color)
        if key in self.cache:
            return self.cache[key]
        result = None
        if latex:
            try:
                from matplotlib import figure
                from matplotlib.font_manager import FontProperties
                from matplotlib.mathtext import MathTextParser

                prop = FontProperties(size=size, math_fontfamily="cm")
                text = f"${latex}$"
                width, height, depth, _, _ = MathTextParser("path").parse(text, dpi=72, prop=prop)
                if width > 0 and height > 0:
                    path = self.folder / f"m{hashlib.sha1(repr(key).encode()).hexdigest()[:16]}.png"
                    fig = figure.Figure(figsize=(width / 72.0, height / 72.0))
                    fig.text(0, depth / height, text, fontproperties=prop, color=color)
                    fig.savefig(path, dpi=300, format="png", transparent=True)
                    result = (str(path), float(width), float(height), float(depth))
            except Exception:
                result = None
        self.cache[key] = result
        return result


# --- small flowables ---


class _AnswerLines(Flowable):
    """Ruled lines to write an answer on."""

    def __init__(self, count: int, width: float = CONTENT_W - 2 * mm, gap: float = 8 * mm, indent: float = 0) -> None:
        super().__init__()
        self.count, self.width_, self.gap, self.indent = count, width, gap, indent

    def wrap(self, avail_w: float, avail_h: float) -> tuple[float, float]:
        return self.width_, self.count * self.gap

    def draw(self) -> None:
        self.canv.setStrokeColor(LINE)
        self.canv.setLineWidth(0.6)
        for i in range(self.count):
            y = (self.count - i - 1) * self.gap + 1
            self.canv.line(self.indent, y, self.width_, y)


def _s(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, (list, tuple)):
        return " ".join(_s(v) for v in value)
    return str(value).strip()


def _items(value: object) -> list[str]:
    if isinstance(value, (list, tuple)):
        return [t for t in (_s(v) for v in value) if t]
    text = _s(value)
    return [line.lstrip("-•* ").strip() for line in text.splitlines() if line.strip()] if text else []


def _hex(color: colors.Color) -> str:
    return "#" + color.hexval()[2:]


# --- the renderer ---


class Renderer:
    def __init__(self, template: dict, folder: Path) -> None:
        self.t = template
        self.f = _fonts()
        self.maths = _Maths(folder)
        self.accent = colors.HexColor(template["accent"])
        self.tint = colors.HexColor(template["tint"])
        self.size = template.get("body_size", 10)
        self.question_no = 0
        self.section_no = 0
        size, f = self.size, self.f
        self.st = {
            "body": ParagraphStyle("body", fontName=f["body"], fontSize=size, leading=size * 1.5,
                                   textColor=INK, spaceAfter=size * 0.6, autoLeading="max"),
            "item": ParagraphStyle("item", fontName=f["body"], fontSize=size, leading=size * 1.45,
                                   textColor=INK, autoLeading="max"),
            "small": ParagraphStyle("small", fontName=f["body"], fontSize=size - 1.5, leading=(size - 1.5) * 1.4,
                                    textColor=MUTED, autoLeading="max"),
            "label": ParagraphStyle("label", fontName=f["bold"], fontSize=7.5, leading=10, textColor=self.accent),
            "h2": ParagraphStyle("h2", fontName=f["bold"], fontSize=size + 4, leading=(size + 4) * 1.25,
                                 textColor=INK),
            "num": ParagraphStyle("num", fontName=f["bold"], fontSize=size + 2, leading=(size + 2) * 1.2,
                                  textColor=colors.white, alignment=TA_CENTER),
            "term": ParagraphStyle("term", fontName=f["bold"], fontSize=size, leading=size * 1.4,
                                   textColor=self.accent, autoLeading="max"),
            "qno": ParagraphStyle("qno", fontName=f["bold"], fontSize=size + 1, leading=size * 1.5,
                                  textColor=self.accent),
            "marks": ParagraphStyle("marks", fontName=f["body"], fontSize=size - 1, leading=size * 1.5,
                                    textColor=MUTED, alignment=2),
            "th": ParagraphStyle("th", fontName=f["bold"], fontSize=size - 0.5, leading=(size - 0.5) * 1.35,
                                 textColor=colors.white, autoLeading="max"),
            "td": ParagraphStyle("td", fontName=f["body"], fontSize=size - 0.5, leading=(size - 0.5) * 1.4,
                                 textColor=INK, autoLeading="max"),
        }

    # inline text: escaped, **bold**, $maths$, line breaks
    def rich(self, text: object, size: float | None = None, color: str = "#111827") -> str:
        text = _s(text)
        size = size or self.size
        out: list[str] = []
        pos = 0
        for m in _MATH_RE.finditer(text):
            out.append(self._plain(text[pos:m.start()]))
            latex = _repair_latex(m.group(1) or m.group(2) or m.group(3))
            drawn = self.maths.draw(latex, size * 1.1, color)
            if drawn:
                path, w, h, depth = drawn
                out.append(f'<img src="{path}" width="{w:.2f}" height="{h:.2f}" valign="{-depth:.2f}"/>')
            else:
                out.append(f"<i>{_latex_to_plain(latex)}</i>")
            pos = m.end()
        out.append(self._plain(text[pos:]))
        return "".join(out)

    @staticmethod
    def _plain(text: str) -> str:
        text = _BOLD_RE.sub(lambda m: f"\x00{m.group(1)}\x01", text)
        text = escape(text).replace("\x00", "<b>").replace("\x01", "</b>")
        return text.replace("\n", "<br/>")

    def para(self, text: object, style: str = "body", **kw) -> Paragraph:
        return Paragraph(self.rich(text, **kw), self.st[style])

    # --- page furniture ---

    def _band_height(self, spec: dict) -> float:
        lines = simpleSplit(_s(spec.get("title")), self.f["bold"], 22, CONTENT_W - 25 * mm)[:3]
        return 26 * mm + len(lines) * 27 + (14 if spec.get("subtitle") else 0)

    def _first_page(self, canvas, doc) -> None:
        spec = doc._so_spec
        band = self._band_height(spec)
        canvas.saveState()
        canvas.setFillColor(self.accent)
        canvas.rect(0, PAGE_H - band, PAGE_W, band, fill=1, stroke=0)
        canvas.setFillColor(colors.Color(1, 1, 1, alpha=0.09))
        canvas.circle(PAGE_W - 22 * mm, PAGE_H - 8 * mm, 34 * mm, fill=1, stroke=0)
        canvas.circle(PAGE_W - 58 * mm, PAGE_H - band + 4 * mm, 14 * mm, fill=1, stroke=0)
        y = PAGE_H - 15 * mm
        canvas.setFillColor(colors.Color(1, 1, 1, alpha=0.85))
        canvas.setFont(self.f["bold"], 8.5)
        canvas.drawString(MARGIN, y, "  ".join(self.t["kicker"].upper()))
        canvas.setFillColor(colors.white)
        canvas.setFont(self.f["bold"], 22)
        for line in simpleSplit(_s(spec.get("title")), self.f["bold"], 22, CONTENT_W - 25 * mm)[:3]:
            y -= 27
            canvas.drawString(MARGIN, y, line)
        if spec.get("subtitle"):
            y -= 17
            canvas.setFillColor(colors.Color(1, 1, 1, alpha=0.85))
            canvas.setFont(self.f["body"], 10)
            canvas.drawString(MARGIN, y, simpleSplit(_s(spec["subtitle"]), self.f["body"], 10, CONTENT_W)[0])
        canvas.restoreState()
        self._footer(canvas, doc)

    def _later_page(self, canvas, doc) -> None:
        canvas.saveState()
        canvas.setFont(self.f["body"], 8)
        canvas.setFillColor(MUTED)
        title = simpleSplit(_s(doc._so_spec.get("title")), self.f["body"], 8, CONTENT_W - 50 * mm)[:1]
        canvas.drawString(MARGIN, PAGE_H - 12 * mm, title[0] if title else "")
        canvas.setFillColor(self.accent)
        canvas.setFont(self.f["bold"], 8)
        canvas.drawRightString(PAGE_W - MARGIN, PAGE_H - 12 * mm, self.t["kicker"].upper())
        canvas.setStrokeColor(self.accent)
        canvas.setLineWidth(1.2)
        canvas.line(MARGIN, PAGE_H - 14 * mm, PAGE_W - MARGIN, PAGE_H - 14 * mm)
        canvas.restoreState()
        self._footer(canvas, doc)

    def _footer(self, canvas, doc) -> None:
        canvas.saveState()
        canvas.setStrokeColor(RULE)
        canvas.setLineWidth(0.6)
        canvas.line(MARGIN, 13 * mm, PAGE_W - MARGIN, 13 * mm)
        canvas.setFont(self.f["body"], 7.5)
        canvas.setFillColor(MUTED)
        canvas.drawString(MARGIN, 9 * mm, f"Study OS  ·  {date.today().strftime('%d %B %Y').lstrip('0')}")
        canvas.drawRightString(PAGE_W - MARGIN, 9 * mm, f"Page {doc.page}")
        canvas.restoreState()

    # --- building ---

    def build(self, spec: dict, output_path: str) -> None:
        band = self._band_height(spec)
        doc = BaseDocTemplate(
            output_path, pagesize=A4, leftMargin=MARGIN, rightMargin=MARGIN, topMargin=20 * mm,
            bottomMargin=18 * mm, title=_s(spec.get("title")), author="Study OS",
            subject=self.t["label"],
        )
        doc._so_spec = spec
        first = Frame(MARGIN, 18 * mm, CONTENT_W, PAGE_H - band - 8 * mm - 18 * mm, id="first")
        later = Frame(MARGIN, 18 * mm, CONTENT_W, PAGE_H - 20 * mm - 18 * mm, id="later")
        doc.addPageTemplates([
            PageTemplate("first", [first], onPage=self._first_page),
            PageTemplate("later", [later], onPage=self._later_page),
        ])
        doc.build([NextPageTemplate("later"), *self.story(spec)])

    def story(self, spec: dict) -> list:
        story: list = []
        if self.t.get("name_line"):
            story += [self._name_line(), Spacer(1, 4 * mm)]
        intro = _s(spec.get("intro"))
        if intro:
            if self.t.get("intro_box"):
                story += [self._callout({"style": "key", "label": self.t["intro_box"], "text": intro}), Spacer(1, 3 * mm)]
            else:
                story += [self.para(intro, size=self.size + 1), Spacer(1, 2 * mm)]
        objectives = _items(spec.get("objectives"))
        if objectives:
            story += [self._checklist(self.t.get("objectives_title", "In this document"), objectives), Spacer(1, 4 * mm)]
        if self.t.get("cards_note") and any(
            b.get("type") == "card" for s in spec.get("sections") or [] for b in (s.get("blocks") or []) if isinstance(b, dict)
        ):
            story += [self.para(self.t["cards_note"], "small"), Spacer(1, 3 * mm)]

        for section in spec.get("sections") or []:
            if not isinstance(section, dict):
                continue
            story += self._section(section)

        answers = [a for a in spec.get("answers") or [] if isinstance(a, dict)]
        if answers:
            story += [PageBreak(), self._heading(self.t.get("answers_title", "Answers"), numbered=False), Spacer(1, 3 * mm)]
            for i, answer in enumerate(answers, start=1):
                story.append(self._answer(i, answer))
        return story

    def _name_line(self) -> Table:
        cells = [["Name", "", "Date", "", "Score", ""]]
        table = Table(cells, colWidths=[14 * mm, 62 * mm, 13 * mm, 34 * mm, 15 * mm, CONTENT_W - 138 * mm])
        table.setStyle(TableStyle([
            ("FONT", (0, 0), (-1, -1), self.f["bold"], 8.5),
            ("TEXTCOLOR", (0, 0), (-1, -1), MUTED),
            ("LINEBELOW", (1, 0), (1, 0), 0.7, LINE),
            ("LINEBELOW", (3, 0), (3, 0), 0.7, LINE),
            ("LINEBELOW", (5, 0), (5, 0), 0.7, LINE),
            ("VALIGN", (0, 0), (-1, -1), "BOTTOM"),
        ]))
        return table

    def _checklist(self, title: str, items: list[str]) -> Table:
        rows = [[Paragraph(escape(title.upper()), self.st["label"]), ""]]
        rows += [[Paragraph("☐", self.st["term"]), self.para(item, "item")] for item in items]
        table = Table(rows, colWidths=[7 * mm, None])
        table.setStyle(TableStyle([
            ("SPAN", (0, 0), (1, 0)),
            ("BACKGROUND", (0, 0), (-1, -1), self.tint),
            ("ROUNDEDCORNERS", [6, 6, 6, 6]),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 3),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
            ("TOPPADDING", (0, 0), (-1, 0), 9),
            ("BOTTOMPADDING", (0, -1), (-1, -1), 9),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ]))
        return table

    def _heading(self, text: str, numbered: bool = True) -> Table:
        if numbered and self.t.get("number_sections", True):
            self.section_no += 1
            table = Table(
                [[Paragraph(f"{self.section_no:02d}", self.st["num"]), Paragraph(self.rich(text, self.size + 4), self.st["h2"])]],
                colWidths=[12 * mm, None],
            )
            style = [
                ("BACKGROUND", (0, 0), (0, 0), self.accent),
                ("BACKGROUND", (1, 0), (1, 0), self.tint),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (1, 0), (1, 0), 10),
            ]
        else:
            table = Table([[Paragraph(self.rich(text, self.size + 4), self.st["h2"])]], colWidths=[None])
            style = [
                ("BACKGROUND", (0, 0), (-1, -1), self.tint),
                ("LINEBEFORE", (0, 0), (0, 0), 4, self.accent),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
            ]
        table.setStyle(TableStyle(style + [("TOPPADDING", (0, 0), (-1, -1), 7), ("BOTTOMPADDING", (0, 0), (-1, -1), 8)]))
        return table

    def _section(self, section: dict) -> list:
        out: list = [CondPageBreak(45 * mm), Spacer(1, 3 * mm)]
        heading = _s(section.get("heading"))
        if heading:
            out += [self._heading(heading), Spacer(1, 3.5 * mm)]
        blocks = [b for b in section.get("blocks") or [] if isinstance(b, dict)]
        i = 0
        while i < len(blocks):
            kind = _s(blocks[i].get("type")).lower()
            # Runs of the same kind become one table.
            if kind in ("definition", "formula", "card"):
                j = i
                while j < len(blocks) and _s(blocks[j].get("type")).lower() == kind:
                    j += 1
                run = blocks[i:j]
                if kind == "definition":
                    out.append(self._glossary(run))
                elif kind == "formula":
                    out += self._formulas(run)
                else:
                    out.append(self._cards(run))
                out.append(Spacer(1, 3.5 * mm))
                i = j
                continue
            out += self._block(blocks[i], kind)
            i += 1
        return out

    def _block(self, block: dict, kind: str) -> list:
        if kind in ("bullets", "list"):
            return [self._bullets(_items(block.get("items") or block.get("text"))), Spacer(1, 2.5 * mm)]
        if kind in ("steps", "numbered"):
            return [self._bullets(_items(block.get("items") or block.get("text")), numbered=True), Spacer(1, 2.5 * mm)]
        if kind in CALLOUTS or kind == "callout":
            if kind != "callout":
                block = {**block, "style": kind}
            return [KeepTogether([self._callout(block)]), Spacer(1, 3.5 * mm)]
        if kind == "table":
            table = self._table(block)
            return [table, Spacer(1, 3.5 * mm)] if table else []
        if kind == "question":
            return [self._question(block), Spacer(1, 3 * mm)]
        if kind == "blank":
            lines = max(1, min(int(block.get("lines") or 3), 14))
            return [KeepTogether([self.para(block.get("label") or block.get("text"), "term"), Spacer(1, 1 * mm),
                                  _AnswerLines(lines)]), Spacer(1, 3 * mm)]
        if kind in ("definition", "formula", "card"):
            return self._section({"blocks": [block]})[2:]
        if block.get("items"):
            return [self._bullets(_items(block["items"])), Spacer(1, 2.5 * mm)]
        text = _s(block.get("text"))
        return [self.para(text)] if text else []

    def _bullets(self, items: list[str], numbered: bool = False) -> Table | Spacer:
        if not items:
            return Spacer(1, 0)
        if numbered:
            marks = [Paragraph(f"{i}", self.st["num"]) for i in range(1, len(items) + 1)]
        else:
            marks = [Paragraph(f'<font color="{_hex(self.accent)}">●</font>', ParagraphStyle(
                "dot", fontName=self.f["body"], fontSize=self.size - 3, leading=self.size * 1.45)) for _ in items]
        rows = [[mark, self.para(item, "item")] for mark, item in zip(marks, items)]
        width = 7 * mm if numbered else 5 * mm
        table = Table(rows, colWidths=[width, None])
        style = [
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 0),
            ("TOPPADDING", (0, 0), (-1, -1), 1.5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5),
            ("LEFTPADDING", (1, 0), (1, -1), 4),
        ]
        if numbered:
            for r in range(len(rows)):
                style.append(("BACKGROUND", (0, r), (0, r), self.accent))
            style += [("TOPPADDING", (0, 0), (0, -1), 0), ("BOTTOMPADDING", (0, 0), (0, -1), 0),
                      ("VALIGN", (0, 0), (0, -1), "MIDDLE"), ("LINEBELOW", (0, 0), (0, -1), 3, colors.white)]
        table.setStyle(TableStyle(style))
        return table

    def _callout(self, block: dict) -> Table:
        style_name = _s(block.get("style")).lower()
        label, fg, bg = CALLOUTS.get(style_name, CALLOUTS["key"])
        label = _s(block.get("label")) or label
        fg = colors.HexColor(fg) if fg else self.accent
        bg = colors.HexColor(bg) if bg else self.tint
        title = _s(block.get("title"))
        head = escape(label) + (f'  <font color="#374151">{self.rich(title)}</font>' if title else "")
        rows: list = [[Paragraph(head, ParagraphStyle("cl", parent=self.st["label"], textColor=fg))]]
        text = _s(block.get("text"))
        lines = [ln for ln in text.splitlines() if ln.strip()]
        if lines and all(re.match(r"\s*([-•*]|\d+[.)])\s", ln) for ln in lines) and len(lines) > 1:
            numbered = all(re.match(r"\s*\d+[.)]\s", ln) for ln in lines)
            rows.append([self._bullets([re.sub(r"^\s*([-•*]|\d+[.)])\s+", "", ln) for ln in lines], numbered)])
        elif text:
            rows.append([self.para(text, "item")])
        for item in _items(block.get("items") or block.get("steps")):
            rows.append([self.para(item, "item")])
        table = Table(rows, colWidths=[None])
        table.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), bg),
            ("LINEBEFORE", (0, 0), (0, -1), 3.5, fg),
            ("LEFTPADDING", (0, 0), (-1, -1), 11),
            ("RIGHTPADDING", (0, 0), (-1, -1), 10),
            ("TOPPADDING", (0, 0), (-1, -1), 2.5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5),
            ("TOPPADDING", (0, 0), (-1, 0), 8),
            ("BOTTOMPADDING", (0, -1), (-1, -1), 8),
        ]))
        return table

    def _glossary(self, run: list[dict]) -> Table:
        rows = [[self.para(b.get("term") or b.get("title"), "term"), self.para(b.get("text") or b.get("definition"), "item")]
                for b in run]
        table = Table(rows, colWidths=[46 * mm, None])
        table.setStyle(TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("BACKGROUND", (0, 0), (0, -1), self.tint),
            ("LINEBELOW", (0, 0), (-1, -2), 0.6, colors.white),
            ("LINEBELOW", (1, 0), (1, -2), 0.6, RULE),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 6),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
        ]))
        return table

    def _formula_image(self, latex: str, size: float, max_w: float) -> Flowable:
        drawn = self.maths.draw(latex, size)
        if not drawn:
            return Paragraph(f"<i>{_latex_to_plain(_repair_latex(latex))}</i>", ParagraphStyle(
                "fx", parent=self.st["body"], fontSize=size, leading=size * 1.4, alignment=TA_CENTER))
        path, w, h, _ = drawn
        scale = min(1.0, max_w / w)
        image = Image(path, width=w * scale, height=h * scale)
        return image

    def _formulas(self, run: list[dict]) -> list:
        if len(run) == 1 and not self.t.get("compact"):
            b = run[0]
            rows: list = []
            if b.get("label") or b.get("title"):
                rows.append([Paragraph(escape(_s(b.get("label") or b.get("title")).upper()), self.st["label"])])
            rows.append([self._formula_image(_s(b.get("latex") or b.get("text")), self.size + 6, CONTENT_W - 30 * mm)])
            if b.get("note"):
                rows.append([self.para(b["note"], "small")])
            table = Table(rows, colWidths=[CONTENT_W - 20 * mm])
            table.setStyle(TableStyle([
                ("BOX", (0, 0), (-1, -1), 1, self.accent),
                ("BACKGROUND", (0, 0), (-1, -1), colors.white),
                ("ROUNDEDCORNERS", [6, 6, 6, 6]),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, 0), 9),
                ("BOTTOMPADDING", (0, -1), (-1, -1), 9),
            ]))
            return [table]
        right_w = CONTENT_W * 0.55
        rows = []
        for b in run:
            left = [Paragraph(self.rich(b.get("label") or b.get("title") or "Formula"), self.st["term"])]
            if b.get("note"):
                left.append(self.para(b["note"], "small"))
            rows.append([left, self._formula_image(_s(b.get("latex") or b.get("text")), self.size + 3, right_w - 12)])
        table = Table(rows, colWidths=[CONTENT_W - right_w, right_w])
        table.setStyle(TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("ALIGN", (1, 0), (1, -1), "CENTER"),
            ("BACKGROUND", (0, 0), (0, -1), self.tint),
            ("BOX", (0, 0), (-1, -1), 0.8, self.accent),
            ("LINEBELOW", (0, 0), (-1, -2), 0.6, RULE),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 7),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
        ]))
        return [table]

    def _table(self, block: dict) -> Table | None:
        header = [_s(h) for h in block.get("header") or block.get("headers") or []]
        rows = [r for r in block.get("rows") or [] if isinstance(r, (list, tuple))]
        cols = max([len(header)] + [len(r) for r in rows] + [0])
        if not cols:
            return None
        data = []
        if header:
            data.append([Paragraph(self.rich(h, color="#FFFFFF"), self.st["th"]) for h in header + [""] * (cols - len(header))])
        for r in rows:
            cells = [_s(c) for c in r] + [""] * (cols - len(r))
            data.append([self.para(c, "td") for c in cells])
        empty_rows = [i for i, r in enumerate(rows) if not any(_s(c) for c in r)]
        table = Table(data, colWidths=[CONTENT_W / cols] * cols, repeatRows=1 if header else 0,
                      rowHeights=None)
        style = [
            ("GRID", (0, 0), (-1, -1), 0.5, RULE),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ]
        start = 1 if header else 0
        if header:
            style.append(("BACKGROUND", (0, 0), (-1, 0), self.accent))
        for i in range(start, len(data)):
            if (i - start) % 2 == 1:
                style.append(("BACKGROUND", (0, i), (-1, i), colors.HexColor("#F9FAFB")))
        for i in empty_rows:  # fill-in rows (a lab results table) get room to write
            style.append(("BOTTOMPADDING", (0, i + start), (-1, i + start), 18))
        title = _s(block.get("title") or block.get("caption"))
        table.setStyle(TableStyle(style))
        if title:
            return KeepTogether([Paragraph(escape(title.upper()), self.st["label"]), Spacer(1, 1.5 * mm), table]) if len(data) < 12 else table
        return table

    def _question(self, block: dict) -> KeepTogether:
        self.question_no += 1
        marks = block.get("marks")
        marks_text = ""
        if marks not in (None, "", 0):
            marks_text = f"[{_s(marks)} mark{'s' if _s(marks) != '1' else ''}]"
        row = [Paragraph(f"Q{self.question_no}", self.st["qno"]), self.para(block.get("text") or block.get("question"), "item")]
        widths = [11 * mm, CONTENT_W - 11 * mm]
        if marks_text:
            row.append(Paragraph(escape(marks_text), self.st["marks"]))
            widths = [11 * mm, CONTENT_W - 33 * mm, 22 * mm]
        head = Table([row], colWidths=widths)
        head.setStyle(TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 0),
            ("RIGHTPADDING", (0, 0), (-1, -1), 2),
            ("TOPPADDING", (0, 0), (-1, -1), 0),
        ]))
        parts: list = [head]
        options = _items(block.get("options"))
        if options:
            rows = []
            for letter, option in zip("ABCDEFGH", options):
                option = re.sub(rf"^\(?{letter}[).:]\s*", "", option)
                rows.append([Paragraph(f'<font color="{_hex(self.accent)}">○</font>  <b>{letter}</b>', self.st["item"]),
                             self.para(option, "item")])
            table = Table(rows, colWidths=[24 * mm, None])
            table.setStyle(TableStyle([
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (0, -1), 11 * mm),
                ("LEFTPADDING", (1, 0), (1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 1),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
            ]))
            parts += [Spacer(1, 1.5 * mm), table]
        lines = block.get("lines")
        if lines is None:
            lines = 0 if options else self.t.get("default_lines", 3)
        try:
            lines = max(0, min(int(lines), 16))
        except (TypeError, ValueError):
            lines = 3
        if lines:
            parts += [Spacer(1, 2 * mm), _AnswerLines(lines, indent=11 * mm)]
        return KeepTogether(parts)

    def _cards(self, run: list[dict]) -> Table:
        rows = []
        for b in run:
            front = [Paragraph("QUESTION", self.st["label"]), Spacer(1, 1.5 * mm),
                     Paragraph(self.rich(b.get("front") or b.get("term"), self.size + 1),
                               ParagraphStyle("cf", parent=self.st["item"], fontName=self.f["bold"], fontSize=self.size + 1,
                                              leading=(self.size + 1) * 1.4))]
            back = [Paragraph("ANSWER", ParagraphStyle("cb", parent=self.st["label"], textColor=MUTED)), Spacer(1, 1.5 * mm),
                    self.para(b.get("back") or b.get("text"), "item")]
            rows.append([front, back])
        table = Table(rows, colWidths=[CONTENT_W / 2] * 2, rowHeights=None)
        table.setStyle(TableStyle([
            ("GRID", (0, 0), (-1, -1), 0.9, LINE, None, (4, 3)),
            ("BACKGROUND", (0, 0), (0, -1), self.tint),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 12),
            ("RIGHTPADDING", (0, 0), (-1, -1), 12),
            ("TOPPADDING", (0, 0), (-1, -1), 16),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 16),
        ]))
        return table

    def _answer(self, i: int, answer: dict) -> KeepTogether:
        number = _s(answer.get("q") or answer.get("number")) or str(i)
        number = number if number.upper().startswith("Q") else f"Q{number}"
        body = [Paragraph(f"<b>{self.rich(answer.get('answer'))}</b>", self.st["item"])]
        if answer.get("explanation"):
            body += [Spacer(1, 1 * mm), self.para(answer["explanation"], "small")]
        table = Table([[Paragraph(escape(number), self.st["qno"]), body]], colWidths=[13 * mm, None])
        table.setStyle(TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 0),
            ("LINEBELOW", (0, 0), (-1, -1), 0.5, RULE),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
        ]))
        return KeepTogether([table])
