"""
HTML Bulk Generator — Landscape, 2-column layout
Browser से Ctrl+P → PDF save
"""

import re
import io
from datetime import datetime
import pandas as pd

COL = {
    "st_no":    "ST NO",
    "mu_apradh":"मु0अ0स0",
    "dhara":    "धारा",
    "banam":    "बनाम",
    "nyayalaya":"न्यायालय",
    "saakshi":  "तलब साक्षी",
    "tareekh":  "अगली तारीख पेशी",
}

NYAYALAYA_MAP = {
    "ASJ":   ("अपर सत्र न्यायाधीश", True),
    "DJ":    ("जिला एवं सत्र न्यायाधीश", True),
    "POCSO": ("विशेष न्यायालय POCSO", True),
    "CJM":   ("मुख्य न्यायिक मजिस्ट्रेट", False),
    "JM":    ("न्यायिक मजिस्ट्रेट", False),
    "ACJM":  ("अपर मुख्य न्यायिक मजिस्ट्रेट", False),
    "MM":    ("महानगर मजिस्ट्रेट", False),
}

def resolve_court(raw, janpad):
    """Returns (court_name_only, full_display, is_session)"""
    raw_up = str(raw).upper().strip()
    for key, (name, is_session) in NYAYALAYA_MAP.items():
        if key in raw_up:
            return name, f"{name} जनपद {janpad}", is_session
    return str(raw).strip(), f"{str(raw).strip()} जनपद {janpad}", False

def clean_col(name):
    return re.sub(r'\s+', ' ', str(name)).strip()

def detect_type(field):
    w = str(field).strip()
    if re.match(r'^NBW', w, re.IGNORECASE): return "NBW"
    if re.match(r'^BW',  w, re.IGNORECASE): return "BW"
    if re.match(r'^MRITYU', w, re.IGNORECASE): return "MRITYU"
    return "SAMAN"

def clean_prefix(name):
    return re.sub(r'^\s*(BW|NBW|MRITYU|VC)\s*', '', name, flags=re.IGNORECASE).strip()

def fmt_date(val):
    if isinstance(val, datetime): return val.strftime('%d/%m/%Y')
    s = str(val).strip()
    for fmt in ('%d/%m/%Y', '%d-%m-%Y', '%Y-%m-%d'):
        try: return datetime.strptime(s, fmt).strftime('%d/%m/%Y')
        except: pass
    return s

TITLES = {
    "SAMAN":  "समन साक्षी",
    "BW":     "जमानती वारंट (BW) साक्षी",
    "NBW":    "गैर जमानती वारंट (NBW) साक्षी",
    "MRITYU": "मृत्यु आख्या",
}

BODY = {
    "SAMAN": ("साक्षी मुकदमा उपरोक्त के संबंध में अपना साक्ष्य देने के लिए अपने पहचान पत्र / "
              "आधार कार्ड व एक पासपोर्ट साइज फोटो के साथ उपर्युक्त नियत तारीख पेशी पर "
              "सुबह 10:30 बजे उपस्थित होना सुनिश्चित करें। ऐसा करने में कोई त्रुटि न हो।"),
    "BW":    ("उपरोक्त साक्षी से 5-5 हजार की दो जमानतें तथा इतनी ही धनराशि का बंधपत्र "
              "न्यायालय में साक्ष्य हेतु उपस्थित होने के बाबत दाखिल कराएं। ऐसा ना करने पर "
              "उपर्युक्त साक्षी को गिरफ्तार कर नियत पेशी पर इस न्यायालय पर प्रस्तुत करें।"),
    "NBW":   "उपरोक्त साक्षी को नियत तारीख पेशी से पूर्व या तक गिरफ्तार कर मेरे समक्ष पेश करें।",
    "MRITYU":("एतद् द्वारा आदेशित किया जाता है कि उपर्युक्त अभियुक्त की मृत्यु से संबंधित "
              "प्रमाण-पत्र नियत तिथि पर न्यायालय के समक्ष अनिवार्य रूप से प्रस्तुत किया जाए।"),
}

CSS = """
<style>
  @import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;700&display=swap');

  * { margin: 0; padding: 0; box-sizing: border-box; }

  body {
    font-family: 'Noto Sans Devanagari', 'Mangal', Arial, sans-serif;
    font-size: 11pt;
    background: #fff;
  }

  @page {
    size: A4 landscape;
    margin: 10mm 8mm;
  }

  @media print {
    body { margin: 0; }
    .no-print { display: none !important; }
    .page { page-break-after: always; }
    .page:last-child { page-break-after: avoid; }
  }

  .page {
    width: 277mm;
    min-height: 190mm;
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0;
    margin: 0 auto 8mm auto;
    border: 1px solid #ccc;
  }

  .block {
    padding: 6mm 5mm;
    border-right: 1px solid #555;
    display: flex;
    flex-direction: column;
  }

  .block:last-child {
    border-right: none;
  }

  .block-title {
    text-align: center;
    font-weight: bold;
    font-size: 13pt;
    text-decoration: underline;
    margin-bottom: 2mm;
  }

  .block-court {
    text-align: center;
    font-size: 11pt;
    font-weight: bold;
    margin-bottom: 3mm;
  }

  .block-court.session { color: #00008B; }

  table.info {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 3mm;
    font-size: 10pt;
  }

  table.info td {
    border: 1px solid #444;
    padding: 1.5mm 2mm;
    vertical-align: top;
  }

  table.info td.label {
    background: #f0f0f0;
    font-weight: bold;
    width: 38%;
    white-space: nowrap;
  }

  .witness-label {
    font-weight: bold;
    font-size: 10pt;
    margin-top: 2mm;
  }

  .witness-name {
    font-style: italic;
    font-size: 11pt;
    margin: 1mm 0 2mm 0;
    line-height: 1.4;
  }

  .body-text {
    font-size: 10pt;
    line-height: 1.5;
    text-align: justify;
    margin-bottom: 2mm;
    flex-grow: 1;
  }

  .note {
    font-size: 9.5pt;
    font-weight: bold;
    text-decoration: underline;
    margin-bottom: 2mm;
  }

  .sign {
    text-align: right;
    font-size: 10pt;
    margin-top: auto;
  }
  .sign-space {
    height: 14mm;
    display: block;
  }
  .sign-lines div {
    margin: 0;
    padding: 0;
    line-height: 1.25;
  }

  /* VC Letter */
  .vc-block {
    padding: 8mm 10mm;
    font-size: 11pt;
    line-height: 1.7;
  }

  .vc-subject {
    font-weight: bold;
    margin: 4mm 0;
  }

  .divider {
    border: none;
    border-top: 1px dashed #999;
    margin: 3mm 0;
  }

  .pratilipi { font-size: 10pt; }

  /* Print button */
  .print-btn {
    position: fixed;
    top: 10px;
    right: 10px;
    background: #1F4E78;
    color: white;
    border: none;
    padding: 10px 20px;
    font-size: 14px;
    border-radius: 6px;
    cursor: pointer;
    z-index: 999;
  }
  .print-btn:hover { background: #163d5e; }
</style>
"""

def block_html(row_data, stype, janpad):
    court_name, court_disp, is_session = resolve_court(row_data.get(COL["nyayalaya"], ""), janpad)
    st_no   = str(row_data.get(COL["st_no"],    "")).strip()
    mu_no   = str(row_data.get(COL["mu_apradh"],"")).strip()
    banam   = str(row_data.get(COL["banam"],    "")).strip()
    dhara   = str(row_data.get(COL["dhara"],    "")).strip()
    tareekh = fmt_date(row_data.get(COL["tareekh"], ""))
    witness = clean_prefix(str(row_data.get(COL["saakshi"], "")).strip())
    today   = datetime.today().strftime('%d/%m/%Y')

    court_cls = "block-court session" if is_session else "block-court"
    label = "नाम पता अभियुक्त:" if stype == "MRITYU" else "नाम पता साक्षी:"
    note_html = "" if stype == "MRITYU" else (
        '<div class="note">नोट:- तामीलकर्ता साक्षी का मोबाइल नंबर अवश्य अंकित करें।</div>')

    return f"""
    <div class="block">
      <div class="block-title">{TITLES[stype]}</div>
      <div class="{court_cls}">न्यायालय : {court_disp}</div>
      <table class="info">
        <tr><td class="label">राज्य बनाम</td><td>{banam}</td></tr>
        <tr><td class="label">ST NO / मु0न0</td><td>{st_no}</td></tr>
        <tr><td class="label">मु0अ0स0</td><td>{mu_no}</td></tr>
        <tr><td class="label">धारा</td><td>{dhara}</td></tr>
        <tr><td class="label">जनपद</td><td>{janpad}</td></tr>
        <tr><td class="label">तारीख पेशी</td><td><strong>{tareekh}</strong></td></tr>
      </table>
      <div class="witness-label">{label}</div>
      <div class="witness-name">{witness}</div>
      <div class="body-text">{BODY[stype]}</div>
      {note_html}
      <div class="sign">
        <span class="sign-space"></span>
        <div class="sign-lines">
          <div>{court_name}</div>
          <div>जनपद {janpad}</div>
          <div>{today}</div>
        </div>
      </div>
    </div>"""


def vc_html(row, janpad):
    court_raw   = str(row.get("न्यायालय", "जिला एवं सत्र")).strip()
    st_no       = str(row.get("ST NO", "")).strip()
    mu_no       = str(row.get("मु0अ0स0", "")).strip()
    banam       = str(row.get("बनाम", "")).strip()
    dhara       = str(row.get("धारा", "")).strip()
    tareekh     = fmt_date(row.get("अगली तारीख पेशी", ""))
    witness     = str(row.get("तलब साक्षी", "")).strip()
    seva_janpad = str(row.get("सेवा जनपद", "")).strip()
    vc_sthan    = str(row.get("VC स्थान", "पुलिस कार्यालय")).strip()
    vc_samay    = str(row.get("VC समय", "12:30 PM")).strip()
    prati_pad   = str(row.get("प्रति पद", "पुलिस अधीक्षक")).strip()
    _, praapak, _ = resolve_court(court_raw, janpad)
    today = datetime.today().strftime('%d/%m/%Y')

    return f"""
    <div class="page">
      <div class="vc-block" style="grid-column: 1 / -1;">
        <div>प्रेषक,<br/>&nbsp;&nbsp;&nbsp;{praapak} ।</div><br/>
        <div>सेवा में,<br/>&nbsp;&nbsp;&nbsp;जिला एवं सत्र न्यायाधीश,<br/>&nbsp;&nbsp;&nbsp;जनपद {seva_janpad} ।</div>
        <div class="vc-subject">विषय - {witness} का साक्ष्य जरिए वीडियो कांफ्रेंसिंग अंकित कराने के सम्बन्ध में।</div>
        <div>महोदय,<br/>सविनय निवेदन है कि इस न्यायालय में लंबित निम्नलिखित विवरण के अनुसार साक्षी का साक्ष्य अंकन जरिए वीडियो कांफ्रेंसिंग कराया जाना है:</div>
        <table class="info" style="margin-top:3mm; width:60%;">
          <tr><td class="label">ST NO / सत्र परीक्षण संख्या</td><td>{st_no}</td></tr>
          <tr><td class="label">मुकदमा अपराध संख्या</td><td>{mu_no}</td></tr>
          <tr><td class="label">राज्य बनाम</td><td>{banam}</td></tr>
          <tr><td class="label">धारा</td><td>{dhara}</td></tr>
          <tr><td class="label">जनपद</td><td>{janpad}</td></tr>
          <tr><td class="label">तारीख पेशी</td><td>{tareekh}</td></tr>
        </table>
        <div style="margin-top:3mm;">अतः आपसे निवेदन है कि साक्षी का साक्ष्य अंकन {tareekh} को {vc_sthan} जनपद {seva_janpad} में वीडियो कांफ्रेंसिंग के माध्यम से करवाने हेतु आवश्यक निर्देश प्रदान करने की कृपा करें।</div>
        <div style="text-align:right; margin-top:5mm;">भवदीय,<br/>{praapak}<br/>{today}</div>
        <hr class="divider"/>
        <div class="pratilipi"><strong>प्रतिलिपि-</strong><br/>
        1. {prati_pad} जनपद {seva_janpad} को इस आशय के साथ प्रेषित कि संबंधित अधीनस्थ को उपरोक्तानुसार निर्देश प्रदान करने का कष्ट करें।<br/>
        2. {witness} दिनांक {tareekh} को समय {vc_samay} पर {vc_sthan} जनपद {seva_janpad} में अपनी पहचान संबंधित दस्तावेज के साथ वीडियो कांफ्रेंसिंग हेतु उपस्थित रहें।
        <div style="text-align:right; margin-top:3mm;">{praapak}<br/>{today}</div>
        </div>
      </div>
    </div>"""


def generate_html(df_main: pd.DataFrame, janpad: str,
                  df_vc: pd.DataFrame = None) -> str:
    missing = [c for c in COL.values() if c not in df_main.columns]
    if missing:
        raise ValueError(f"इन columns की ज़रूरत है: {missing}")

    saman, bw, nbw, mrityu = [], [], [], []

    for _, row in df_main.iterrows():
        field = str(row.get(COL["saakshi"], "")).strip()
        if not field: continue
        stype = detect_type(field)
        names = [n.strip() for n in clean_prefix(field).split(',') if n.strip()]
        for name in names:
            r = row.copy()
            r[COL["saakshi"]] = name
            {"SAMAN": saman, "BW": bw, "NBW": nbw, "MRITYU": mrityu}[stype].append((r, stype))

    all_blocks = saman + bw + nbw + mrityu

    pages_html = []
    for i in range(0, len(all_blocks), 2):
        pair = all_blocks[i:i+2]
        blocks = "".join(block_html(r, t, janpad) for r, t in pair)
        # अगर single block है तो दूसरा column खाली रखें
        if len(pair) == 1:
            blocks += '<div class="block"></div>'
        pages_html.append(f'<div class="page">{blocks}</div>')

    # VC letters
    if df_vc is not None and not df_vc.empty:
        for _, row in df_vc.iterrows():
            pages_html.append(vc_html(row, janpad))

    all_pages = "\n".join(pages_html)
    today = datetime.today().strftime('%d/%m/%Y')

    return f"""<!DOCTYPE html>
<html lang="hi">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>समन दस्तावेज़ — {today}</title>
  {CSS}
</head>
<body>
  <button class="print-btn no-print" onclick="window.print()">🖨️ Print / PDF</button>
  {all_pages}
</body>
</html>"""


def generate_html_from_excel(excel_bytes: bytes, janpad: str) -> str:
    xls = pd.ExcelFile(io.BytesIO(excel_bytes))
    df_main = pd.read_excel(xls, sheet_name=0).fillna("").rename(columns=clean_col)
    df_vc = None
    if "VC" in xls.sheet_names:
        df_vc = pd.read_excel(xls, sheet_name="VC").fillna("").rename(columns=clean_col)
    return generate_html(df_main, janpad, df_vc)
