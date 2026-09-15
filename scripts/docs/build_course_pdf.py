#!/usr/bin/env python3
"""把本仓库课程 Markdown 渲染为统一风格的 A4 PDF。

该脚本只实现课程目前使用的 Markdown 子集，避免引入 Pandoc/浏览器等额外
工具链。PDF 是发布物，Markdown 是唯一可编辑源；修改课程后应重新生成并
检查页数、文本抽取和逐页渲染图。
"""

from __future__ import annotations

import argparse
import html
import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    KeepTogether,
    LongTable,
    PageBreak,
    PageTemplate,
    Paragraph,
    Preformatted,
    Spacer,
    Table,
    TableStyle,
)
from reportlab.platypus.tableofcontents import TableOfContents


BLUE = colors.HexColor("#17365D")
MID_BLUE = colors.HexColor("#2F5597")
LIGHT_BLUE = colors.HexColor("#D9EAF7")
TEXT = colors.HexColor("#28323C")
MUTED = colors.HexColor("#66717D")
LIGHT = colors.HexColor("#F3F5F7")
GRID = colors.HexColor("#CCD4DC")


def register_fonts() -> None:
    # 文泉驿 Micro Hei 是 TrueType outline，可完整嵌入 PDF；ReportLab 的内建
    # CID Font 会在部分阅读器中把拉丁字符异常拉开，Noto CJK 则是 CFF outline。
    regular = "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"
    pdfmetrics.registerFont(TTFont("NotoSansCJKSC", regular, subfontIndex=0))
    pdfmetrics.registerFont(TTFont("NotoSansCJKSC-Bold", regular, subfontIndex=0))
    pdfmetrics.registerFontFamily(
        "NotoSansCJKSC",
        normal="NotoSansCJKSC",
        bold="NotoSansCJKSC-Bold",
    )


def inline_markup(text: str) -> str:
    """转义正文并支持课程用到的 inline code 与 bold。"""
    placeholders: list[str] = []

    def stash_code(match: re.Match[str]) -> str:
        placeholders.append(
            '<font name="Courier" color="#7A2433">'
            + html.escape(match.group(1))
            + "</font>"
        )
        return f"\x00{len(placeholders) - 1}\x00"

    text = re.sub(r"`([^`]+)`", stash_code, text)
    text = html.escape(text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    for index, value in enumerate(placeholders):
        text = text.replace(f"\x00{index}\x00", value)
    return text


def make_styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "body": ParagraphStyle(
            "CourseBody",
            parent=base["BodyText"],
            fontName="NotoSansCJKSC",
            fontSize=10.2,
            leading=17,
            textColor=TEXT,
            spaceAfter=6,
            wordWrap="CJK",
        ),
        "cover_title": ParagraphStyle(
            "CoverTitle",
            fontName="NotoSansCJKSC",
            fontSize=28,
            leading=42,
            alignment=TA_CENTER,
            textColor=BLUE,
            spaceAfter=16,
            wordWrap="CJK",
        ),
        "cover_meta": ParagraphStyle(
            "CoverMeta",
            fontName="NotoSansCJKSC",
            fontSize=11,
            leading=19,
            alignment=TA_CENTER,
            textColor=MUTED,
            wordWrap="CJK",
        ),
        "h1": ParagraphStyle(
            "H1",
            fontName="NotoSansCJKSC",
            fontSize=22,
            leading=30,
            textColor=BLUE,
            spaceAfter=12,
            wordWrap="CJK",
        ),
        "h2": ParagraphStyle(
            "H2",
            fontName="NotoSansCJKSC",
            fontSize=17,
            leading=24,
            textColor=BLUE,
            spaceAfter=13,
            wordWrap="CJK",
            keepWithNext=True,
        ),
        "h3": ParagraphStyle(
            "H3",
            fontName="NotoSansCJKSC",
            fontSize=12.2,
            leading=19,
            textColor=MID_BLUE,
            spaceBefore=8,
            spaceAfter=7,
            wordWrap="CJK",
            keepWithNext=True,
        ),
        "quote": ParagraphStyle(
            "Quote",
            fontName="NotoSansCJKSC",
            fontSize=10.2,
            leading=17,
            leftIndent=8 * mm,
            rightIndent=5 * mm,
            borderColor=MID_BLUE,
            borderWidth=0,
            borderPadding=(5, 8, 5, 9),
            backColor=LIGHT_BLUE,
            textColor=TEXT,
            wordWrap="CJK",
            spaceAfter=8,
        ),
        "bullet": ParagraphStyle(
            "Bullet",
            fontName="NotoSansCJKSC",
            fontSize=10.2,
            leading=16.5,
            leftIndent=7 * mm,
            firstLineIndent=-3.5 * mm,
            bulletIndent=1.5 * mm,
            textColor=TEXT,
            wordWrap="CJK",
            spaceAfter=3,
        ),
        "code": ParagraphStyle(
            "Code",
            # 课程的伪代码和诊断输出中包含中文。Courier 不含 CJK Glyph，
            # Poppler 文本抽取会得到方块；统一使用已嵌入的中文 TrueType 字体。
            fontName="NotoSansCJKSC",
            fontSize=7.6,
            leading=11,
            leftIndent=4 * mm,
            rightIndent=4 * mm,
            borderColor=GRID,
            borderWidth=0.5,
            borderPadding=7,
            backColor=LIGHT,
            textColor=colors.HexColor("#1F2933"),
            spaceBefore=3,
            spaceAfter=9,
        ),
        "toc_title": ParagraphStyle(
            "TOCTitle",
            fontName="NotoSansCJKSC",
            fontSize=20,
            leading=28,
            textColor=BLUE,
            spaceAfter=10,
        ),
        "top_guard": ParagraphStyle(
            "TopGuard",
            fontName="NotoSansCJKSC",
            fontSize=1,
            leading=1,
            textColor=colors.white,
            spaceAfter=0,
        ),
    }


class CourseDocTemplate(BaseDocTemplate):
    def __init__(self, filename: str, course_header: str, subject: str):
        super().__init__(
            filename,
            pagesize=A4,
            leftMargin=20 * mm,
            rightMargin=20 * mm,
            topMargin=20 * mm,
            bottomMargin=18 * mm,
            title=course_header,
            author="Skynet MMO Learning",
            subject=subject,
        )
        self.course_header = course_header
        frame = Frame(
            self.leftMargin,
            self.bottomMargin,
            self.width,
            self.height,
            id="course",
        )
        # 页眉页脚在 Flowable 完成后绘制。长表格或 keepWithNext 组合偶尔会
        # 覆盖先绘制的页眉；onPageEnd 能保证发布版每页的导航信息一致。
        self.addPageTemplates(PageTemplate(id="normal", frames=frame, onPageEnd=self.draw_page))

    def draw_page(self, canvas, doc) -> None:
        canvas.saveState()
        page_number = canvas.getPageNumber()
        if page_number > 1:
            canvas.setFont("NotoSansCJKSC", 8)
            canvas.setFillColor(MUTED)
            canvas.drawString(20 * mm, A4[1] - 10.5 * mm, self.course_header)
            canvas.setStrokeColor(GRID)
            canvas.setLineWidth(0.4)
            canvas.line(20 * mm, A4[1] - 13 * mm, A4[0] - 20 * mm, A4[1] - 13 * mm)
        canvas.setFont("NotoSansCJKSC", 8)
        canvas.setFillColor(MUTED)
        canvas.drawCentredString(A4[0] / 2, 9 * mm, str(page_number))
        canvas.restoreState()

    def afterFlowable(self, flowable) -> None:
        if isinstance(flowable, Paragraph) and flowable.style.name in {"H1", "H2", "H3"}:
            level = {"H1": 0, "H2": 0, "H3": 1}[flowable.style.name]
            text = flowable.getPlainText()
            key = f"heading-{self.seq.nextf('heading')}"
            self.canv.bookmarkPage(key)
            self.canv.addOutlineEntry(text, key, level=level, closed=False)
            self.notify("TOCEntry", (level, text, self.page, key))


def parse_table(lines: list[str], styles: dict[str, ParagraphStyle]) -> LongTable:
    rows: list[list[Paragraph]] = []
    for line in lines:
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells):
            continue
        rows.append([Paragraph(inline_markup(cell), styles["body"]) for cell in cells])

    col_count = max(len(row) for row in rows)
    width = 170 * mm
    table = LongTable(rows, colWidths=[width / col_count] * col_count, repeatRows=1, hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), BLUE),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, -1), "NotoSansCJKSC"),
                ("FONTSIZE", (0, 0), (-1, -1), 8.6),
                ("LEADING", (0, 0), (-1, -1), 13),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("GRID", (0, 0), (-1, -1), 0.45, GRID),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, LIGHT]),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return table


def markdown_to_story(source: Path, styles: dict[str, ParagraphStyle]) -> tuple[str, list]:
    lines = source.read_text(encoding="utf-8").splitlines()
    if not lines or not lines[0].startswith("# "):
        raise ValueError("课程 Markdown 第一行必须是一级标题")

    title = lines[0][2:].strip()
    story: list = [Spacer(1, 47 * mm), Paragraph(inline_markup(title), styles["cover_title"])]

    index = 1
    cover_quotes: list[str] = []
    while index < len(lines) and (not lines[index].strip() or lines[index].startswith(">")):
        if lines[index].startswith(">"):
            cover_quotes.append(lines[index].lstrip("> ").rstrip("  "))
        index += 1
    if cover_quotes:
        story.append(Paragraph("<br/>".join(inline_markup(x) for x in cover_quotes), styles["cover_meta"]))
    story.extend([Spacer(1, 32 * mm), Paragraph("SKYNET MMO LEARNING", styles["cover_meta"]), PageBreak()])

    toc = TableOfContents()
    toc.levelStyles = [
        ParagraphStyle("TOC0", fontName="NotoSansCJKSC", fontSize=10.5, leading=18, textColor=TEXT, leftIndent=0),
        ParagraphStyle("TOC1", fontName="NotoSansCJKSC", fontSize=9.5, leading=16, textColor=MUTED, leftIndent=8 * mm),
    ]
    story.extend([Paragraph("目录", styles["toc_title"]), toc, PageBreak()])

    paragraph: list[str] = []

    def flush_paragraph() -> None:
        if paragraph:
            text = " ".join(part.strip().rstrip("  ") for part in paragraph)
            story.append(Paragraph(inline_markup(text), styles["body"]))
            paragraph.clear()

    first_h2 = True
    while index < len(lines):
        line = lines[index]
        stripped = line.strip()

        if stripped.startswith("```"):
            flush_paragraph()
            index += 1
            code: list[str] = []
            while index < len(lines) and not lines[index].strip().startswith("```"):
                code.append(lines[index])
                index += 1
            story.append(Preformatted("\n".join(code), styles["code"], maxLineLength=100))
        elif stripped.startswith("## "):
            flush_paragraph()
            if not first_h2:
                story.append(PageBreak())
            first_h2 = False
            # 一个真实 Paragraph 可阻止 keepWithNext 组合在个别“整页刚好容纳”
            # 的章节越过 Frame 上边界；普通 Spacer 在页首会被 ReportLab 丢弃。
            story.append(Paragraph("&#160;", styles["top_guard"]))
            story.append(Paragraph(inline_markup(stripped[3:]), styles["h2"]))
        elif stripped.startswith("### "):
            flush_paragraph()
            story.append(Paragraph(inline_markup(stripped[4:]), styles["h3"]))
        elif stripped.startswith(">"):
            flush_paragraph()
            quote_lines: list[str] = []
            while index < len(lines) and lines[index].strip().startswith(">"):
                quote_lines.append(lines[index].strip().lstrip("> "))
                index += 1
            index -= 1
            story.append(Paragraph("<br/>".join(inline_markup(x) for x in quote_lines), styles["quote"]))
        elif stripped == "<!-- PAGEBREAK -->":
            flush_paragraph()
            story.append(PageBreak())
        elif stripped.startswith("|") and index + 1 < len(lines) and lines[index + 1].strip().startswith("|"):
            flush_paragraph()
            table_lines: list[str] = []
            while index < len(lines) and lines[index].strip().startswith("|"):
                table_lines.append(lines[index])
                index += 1
            index -= 1
            story.append(parse_table(table_lines, styles))
            story.append(Spacer(1, 7))
        elif re.match(r"^[-*] ", stripped):
            flush_paragraph()
            story.append(Paragraph(inline_markup(stripped[2:]), styles["bullet"], bulletText="•"))
        elif re.match(r"^\d+\. ", stripped):
            flush_paragraph()
            number, content = stripped.split(". ", 1)
            story.append(Paragraph(inline_markup(content), styles["bullet"], bulletText=number + "."))
        elif stripped in {"---", ""}:
            flush_paragraph()
            if stripped == "---":
                story.append(Spacer(1, 3))
        else:
            paragraph.append(line)
        index += 1

    flush_paragraph()
    return title, story


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--header", help="页眉；默认使用课程完整标题")
    args = parser.parse_args()

    register_fonts()
    styles = make_styles()
    title, story = markdown_to_story(args.source, styles)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    doc = CourseDocTemplate(str(args.output), args.header or title, title)
    doc.multiBuild(story)
    print(f"generated: {args.output} ({args.output.stat().st_size} bytes) title={title}")


if __name__ == "__main__":
    main()
