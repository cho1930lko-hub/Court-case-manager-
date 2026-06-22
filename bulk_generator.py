"""
समन/वारंट/मृत्यु आख्या/VC लेटर — Bulk DOCX Generator
आपके पुराने code को base रखकर बनाया गया।
Prefix नियम (नाम पता साक्षी column में):
  BW     → जमानती वारंट
  NBW    → गैर जमानती वारंट
  MRITYU → मृत्यु आख्या
  VC     → VC लेटर (अलग sheet "VC" से पढ़ेगा)
  बिना prefix → साधारण समन साक्षी
"""

import re
import io
from datetime import datetime

import pandas as pd
from docx import Document
from docx.shared import Cm, Pt, RGBColor
from docx.enum.text import WD_PARAGRAPH_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement


# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

def clean_col(name):
    return re.sub(r'\s+', ' ', str(name)).strip()


def fmt(doc, text, bold=False, underline=False, italic=False,
        size=17, align=None, color=None, space_before=0, space_after=0):
    p = doc.add_paragraph()
    r = p.add_run(str(text))
    r.font.name = "Kokila"
    r.font.size = Pt(size)
    r.bold = bold
    r.underline = underline
    r.italic = italic
    if color:
        r.font.color.rgb = color
    if align:
        p.alignment = align
    pf = p.paragraph_format
    pf.space_before = Pt(space_before)
    pf.space_after = Pt(space_after)
    return p


def set_cell_font(cell, size=17, bold=False):
    for para in cell.paragraphs:
        for run in para.runs:
            run.font.name = "Kokila"
            run.font.size = Pt(size)
            run.bold = bold


def clean_prefix(name):
    return re.sub(r'^\s*(BW|NBW|MRITYU|VC)\s*', '', name, flags=re.IGNORECASE).strip()


def detect_type(witness_field):
    w = str(witness_field).strip()
    if re.match(r'^NBW', w, re.IGNORECASE):
        return "NBW"
    if re.match(r'^BW', w, re.IGNORECASE):
        return "BW"
    if re.match(r'^MRITYU', w, re.IGNORECASE):
        return "MRITYU"
    return "SAMAN"


def fmt_date(val):
    if isinstance(val, datetime):
        return val.strftime('%d/%m/%Y')
    s = str(val).strip()
    # Excel sometimes gives float like 45123.0
    try:
        n = int(float(s))
        dt = datetime.fromordinal(datetime(1900, 1, 1).toordinal() + n - 2)
        return dt.strftime('%d/%m/%Y')
    except Exception:
        return s


def base_doc():
    doc = Document()
    sec = doc.sections[0]
    sec.page_width = Cm(29.7)
    sec.page_height = Cm(21.0)
    sec.left_margin = Cm(1.27)
    sec.right_margin = Cm(1.27)
    sec.top_margin = Cm(1.27)
    sec.bottom_margin = Cm(1.27)
    return doc


# ─────────────────────────────────────────────
# Per-document renderers
# ─────────────────────────────────────────────

def render_saman(doc, row, summon_type, janpad):
    """समन / BW / NBW / मृत्यु आख्या — एक block"""
    court_type = str(row["न्यायालय"]).strip()
    case_name  = str(row["राज्य बनाम"]).strip()
    st_no      = str(row.get("मु0न0", "")).strip()
    mu_no      = str(row.get("मु0अ0स0", "")).strip()
    sections   = str(row.get("धारा", "")).strip()
    thana      = str(row.get("थाना", "")).strip()
    hearing    = fmt_date(row.get("तारीख पेशी", ""))
    witness    = clean_prefix(str(row["नाम पता साक्षी"]).strip())

    # Court display name
    if "न्यायिक मजिस्ट्रेट" in court_type or "lower" in court_type.lower():
        court_disp = f"मुख्य न्यायिक मजिस्ट्रेट जनपद {janpad}"
        court_color = None
    elif "सेशन" in court_type or "session" in court_type.lower() or "सत्र" in court_type:
        court_disp = f"जिला एवं सत्र जनपद {janpad}"
        court_color = RGBColor(0, 0, 139)
    else:
        court_disp = f"{court_type} जनपद {janpad}"
        court_color = None

    # Title
    titles = {
        "SAMAN":  "समन साक्षी",
        "BW":     "जमानती वारंट (BW) साक्षी",
        "NBW":    "गैर जमानती वारंट (NBW) साक्षी",
        "MRITYU": "मृत्यु आख्या",
    }
    fmt(doc, titles[summon_type], bold=True, underline=True, size=22,
        align=WD_PARAGRAPH_ALIGNMENT.CENTER, space_after=2)

    # Court name
    p = fmt(doc, f"न्यायालय : {court_disp}", bold=True, size=18,
            align=WD_PARAGRAPH_ALIGNMENT.CENTER, space_after=4)
    if court_color:
        p.runs[0].font.color.rgb = court_color

    # Table
    table = doc.add_table(rows=7, cols=2)
    table.style = 'Table Grid'
    fields = ["राज्य बनाम", "ST NO/मु0न0", "मु0अ0स0", "धारा", "थाना", "जनपद-", "तारीख पेशी"]
    values = [case_name, st_no, mu_no, sections, thana or "—", janpad, hearing]
    for r_i, (f, v) in enumerate(zip(fields, values)):
        cl = table.cell(r_i, 0)
        cr = table.cell(r_i, 1)
        cl.text = f
        set_cell_font(cl)
        cr.text = str(v)
        set_cell_font(cr, bold=(f == "थाना"))

    # Witness label — changes for Mrityu
    label = "नाम पता अभियुक्त:" if summon_type == "MRITYU" else "नाम पता साक्षी:"
    fmt(doc, "\n" + label, bold=True, size=17)
    fmt(doc, witness, italic=True, size=17)

    # Body text
    body = {
        "SAMAN": ("साक्षी मुकदमा उपरोक्त के संबंध में अपना साक्ष्य देने के लिए अपने पहचान पत्र / आधार कार्ड "
                  "व एक पासपोर्ट साइज फोटो के साथ उपर्युक्त नियत तारीख पेशी पर सुबह 10:30 बजे उपस्थित होना "
                  "सुनिश्चित करें। ऐसा करने में कोई त्रुटि न हो।"),
        "BW":    ("उपरोक्त साक्षी से 5-5 हजार की दो जमानतें तथा इतनी ही धनराशि का बंधपत्र न्यायालय में "
                  "साक्ष्य हेतु उपस्थित होने के बाबत दाखिल कराएं। ऐसा ना करने पर उपर्युक्त साक्षी को "
                  "गिरफ्तार कर नियत पेशी पर इस न्यायालय पर प्रस्तुत करें।"),
        "NBW":   ("उपरोक्त साक्षी को नियत तारीख पेशी से पूर्व या तक गिरफ्तार कर मेरे समक्ष पेश करें।"),
        "MRITYU":("एतद् द्वारा आदेशित किया जाता है कि उपर्युक्त अभियुक्त की मृत्यु से संबंधित प्रमाण-पत्र "
                  "नियत तिथि पर न्यायालय के समक्ष अनिवार्य रूप से प्रस्तुत किया जाए।"),
    }
    fmt(doc, body[summon_type], size=16)

    # Note (not for Mrityu)
    if summon_type != "MRITYU":
        fmt(doc, "नोट:- तामीलकर्ता साक्षी का मोबाइल नंबर अवश्य अंकित करें।",
            bold=True, underline=True, size=15)

    # Signature
    today = datetime.today().strftime('%d/%m/%Y')
    fmt(doc, f"\n{court_disp}\n{today}",
        align=WD_PARAGRAPH_ALIGNMENT.RIGHT, size=17)


def render_vc(doc, row, janpad):
    """VC लेटर — letter format"""
    court_type   = str(row.get("न्यायालय", "जिला एवं सत्र")).strip()
    st_no        = str(row.get("मु0न0", "")).strip()
    mu_no        = str(row.get("मु0अ0स0", "")).strip()
    case_name    = str(row.get("राज्य बनाम", "")).strip()
    sections     = str(row.get("धारा", "")).strip()
    thana        = str(row.get("थाना", "")).strip()
    hearing      = fmt_date(row.get("तारीख पेशी", ""))
    witness      = str(row.get("नाम पता साक्षी", "")).strip()
    seva_janpad  = str(row.get("सेवा जनपद", "")).strip()   # जहाँ VC होगी
    vc_sthan     = str(row.get("VC स्थान", "पुलिस कार्यालय")).strip()
    vc_samay     = str(row.get("VC समय", "12:30 PM")).strip()
    prati_pad    = str(row.get("प्रति पद", "पुलिस अधीक्षक")).strip()

    today = datetime.today().strftime('%d/%m/%Y')

    # Determine court display
    if "सेशन" in court_type or "सत्र" in court_type:
        praapak = f"जिला एवं सत्र जनपद {janpad}"
    else:
        praapak = f"मुख्य न्यायिक मजिस्ट्रेट जनपद {janpad}"

    # Header
    fmt(doc, f"प्रेषक,\n    {praapak} ।", size=16)
    fmt(doc, f"\nसेवा में,\n    {court_type} न्यायाधीश,\n    जनपद {seva_janpad or '___'}।", size=16)

    # Subject
    vishay = (f"विषय - {witness} का साक्ष्य जरिए वीडियो कांफ्रेंसिंग "
              f"अंकित कराने के सम्बन्ध में।")
    fmt(doc, "\n" + vishay, bold=True, size=16)

    fmt(doc, "\nमहोदय,", size=16)
    fmt(doc, ("सविनय निवेदन है कि इस न्यायालय में लंबित निम्नलिखित विवरण के अनुसार "
              "साक्षी का साक्ष्य अंकन जरिए वीडियो कांफ्रेंसिंग कराया जाना है:"), size=16)

    # Table
    table = doc.add_table(rows=7, cols=2)
    table.style = 'Table Grid'
    fields = ["सत्र परीक्षण संख्या", "मुकदमा अपराध संख्या", "राज्य बनाम",
              "धारा", "थाना", "जनपद", "तारीख पेशी"]
    values = [st_no, mu_no, case_name, sections, thana or "—", janpad, hearing]
    for r_i, (f, v) in enumerate(zip(fields, values)):
        table.cell(r_i, 0).text = f
        set_cell_font(table.cell(r_i, 0))
        table.cell(r_i, 1).text = str(v)
        set_cell_font(table.cell(r_i, 1))

    fmt(doc, (f"\nअतः आपसे निवेदन है कि साक्षी का साक्ष्य अंकन {hearing} को "
              f"{vc_sthan} जनपद {seva_janpad or '___'} में वीडियो कांफ्रेंसिंग के माध्यम से "
              f"करवाने हेतु आवश्यक निर्देश प्रदान करने की कृपा करें।"), size=16)

    fmt(doc, f"\nभवदीय,\n{praapak}\n{today}",
        align=WD_PARAGRAPH_ALIGNMENT.RIGHT, size=16)

    # Pratilipi
    fmt(doc, "\n" + "─" * 80, size=10)
    fmt(doc, "प्रतिलिपि-", bold=True, size=15)
    fmt(doc, f"1. {prati_pad} जनपद {seva_janpad or '___'} को इस आशय के साथ प्रेषित कि "
             f"संबंधित अधीनस्थ को उपरोक्तानुसार निर्देश प्रदान करने का कष्ट करें।", size=15)
    fmt(doc, f"2. {witness} दिनांक {hearing} को समय {vc_samay} पर {vc_sthan} जनपद "
             f"{seva_janpad or '___'} में अपनी पहचान संबंधित दस्तावेज के साथ "
             f"वीडियो कांफ्रेंसिंग हेतु उपस्थित रहें।", size=15)
    fmt(doc, f"\n{praapak}\n{today}",
        align=WD_PARAGRAPH_ALIGNMENT.RIGHT, size=15)


# ─────────────────────────────────────────────
# Main entry point
# ─────────────────────────────────────────────

def generate_bulk(excel_bytes: bytes, janpad: str) -> bytes:
    """
    excel_bytes: uploaded Excel file bytes
    janpad: user-entered जनपद name (e.g. श्रावस्ती)
    Returns: DOCX bytes
    """
    xls = pd.ExcelFile(io.BytesIO(excel_bytes))

    # ── Sheet 1: समन (main sheet) ──────────────────
    df = pd.read_excel(xls, sheet_name=0)
    df = df.fillna("").rename(columns=clean_col)

    required = ['न्यायालय', 'राज्य बनाम', 'मु0न0', 'मु0अ0स0', 'धारा', 'तारीख पेशी', 'नाम पता साक्षी']
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise ValueError(f"इन columns की ज़रूरत है: {missing}")

    # Collect all summons
    saman_rows, bw_rows, nbw_rows, mrityu_rows = [], [], [], []

    for _, row in df.iterrows():
        wit_field = str(row["नाम पता साक्षी"]).strip()
        if not wit_field:
            continue
        stype = detect_type(wit_field)
        # Multiple witnesses separated by comma
        names = [n.strip() for n in clean_prefix(wit_field).split(',') if n.strip()]
        for name in names:
            new_row = row.copy()
            new_row["नाम पता साक्षी"] = name
            bucket = {"SAMAN": saman_rows, "BW": bw_rows,
                      "NBW": nbw_rows, "MRITYU": mrityu_rows}[stype]
            bucket.append((new_row, stype))

    all_saman = saman_rows + bw_rows + nbw_rows + mrityu_rows

    # ── Sheet 2: VC (optional) ─────────────────────
    vc_rows = []
    if "VC" in xls.sheet_names:
        df_vc = pd.read_excel(xls, sheet_name="VC").fillna("").rename(columns=clean_col)
        for _, row in df_vc.iterrows():
            vc_rows.append(row)

    # ── Build document ─────────────────────────────
    doc = base_doc()
    first = True

    # समन / BW / NBW / मृत्यु — 2 per page (landscape A4)
    for idx, (row, stype) in enumerate(all_saman):
        if not first and idx % 2 == 0:
            doc.add_page_break()
        elif not first and idx % 2 == 1:
            # separator line between two on same page
            p = doc.add_paragraph()
            p.paragraph_format.space_before = Pt(4)
            p.paragraph_format.space_after = Pt(4)
            run = p.add_run("─" * 100)
            run.font.size = Pt(8)
        render_saman(doc, row, stype, janpad)
        first = False

    # VC letters — प्रति पृष्ठ 1
    for row in vc_rows:
        doc.add_page_break()
        render_vc(doc, row, janpad)

    # Fix zoom attribute
    zoom = doc.settings.element.find(qn('w:zoom'))
    if zoom is not None and zoom.get(qn('w:percent')) is None:
        zoom.set(qn('w:percent'), '100')

    buf = io.BytesIO()
    doc.save(buf)
    buf.seek(0)
    return buf.read()

