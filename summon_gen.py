"""
HTML Summon Generator
सम्मन की स्थिति = "बनाना है" वाली rows से HTML generate करता है
Landscape, 2-column per page, browser से Print/PDF
"""
import re
from datetime import datetime
import pandas as pd

# न्यायालय → display name mapping
NYAYALAYA_MAP = {
    "ASJ EX POCSO": ("अपर सत्र न्यायाधीश (POCSO)", True),
    "ASJ SC/ST ACT": ("अपर सत्र न्यायाधीश SC/ST", True),
    "ASJ SCST":      ("अपर सत्र न्यायाधीश SC/ST", True),
    "SPL पॉक्सो":   ("विशेष न्यायालय POCSO", True),
    "SC/ST":         ("विशेष न्यायालय SC/ST", True),
    "ASJ":           ("अपर सत्र न्यायाधीश", True),
    "DJ":            ("जिला एवं सत्र न्यायाधीश", True),
    "जिला एवं सत्र": ("जिला एवं सत्र न्यायाधीश", True),
    "CJM":           ("मुख्य न्यायिक मजिस्ट्रेट", False),
    "cjsd":          ("मुख्य न्यायिक मजिस्ट्रेट", False),
    "ACJM":          ("अपर मुख्य न्यायिक मजिस्ट्रेट", False),
}


def resolve_court(raw, janpad):
    raw_s = str(raw).strip()
    raw_up = raw_s.upper()
    for key, (name, is_session) in NYAYALAYA_MAP.items():
        if key.upper() in raw_up:
            return name, f"{name} जनपद {janpad}", is_session
    return raw_s, f"{raw_s} जनपद {janpad}", False


def detect_type(field):
    w = str(field).strip()
    if re.match(r'^NBW', w, re.IGNORECASE): return "NBW"
    if re.match(r'^BW',  w, re.IGNORECASE): return "BW"
    if re.match(r'^MRITYU', w, re.IGNORECASE): return "MRITYU"
    return "SAMAN"


def clean_prefix(name):
    return re.sub(r'^\s*(BW|NBW|MRITYU)\s*', '', name, flags=re.IGNORECASE).strip()


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

CSS = """<style>
@import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;700&display=swap');
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family:'Noto Sans Devanagari','Mangal',Arial,sans-serif; font-size:11pt; background:#fff; }

@page { size:A4 landscape; margin:8mm 7mm; }
@media print {
  body { margin:0; }
  .no-print { display:none !important; }
  .page { page-break-after:always; border:none; }
  .page:last-child { page-break-after:avoid; }
}

.page {
  width:277mm; height:190mm;
  display:grid; grid-template-columns:1fr 1fr;
  margin:0 auto 6mm auto;
  border:1px solid #aaa; overflow:hidden;
}

.block {
  padding:5mm 6mm;
  border-right:1px solid #666;
  display:flex; flex-direction:column;
  height:190mm; overflow:hidden;
}
.block:last-child { border-right:none; }

.block-title {
  text-align:center; font-weight:bold;
  font-size:15pt; text-decoration:underline;
  margin-bottom:2mm;
}
.block-court {
  text-align:center; font-size:12pt;
  font-weight:bold; margin-bottom:3mm;
}
.block-court.session { color:#00008B; }

table.info {
  width:100%; border-collapse:collapse;
  margin-bottom:3mm; font-size:11.5pt;
}
table.info td {
  border:1px solid #444;
  padding:2mm 3mm; vertical-align:middle;
}
table.info td.label {
  background:#f0f0f0; font-weight:bold;
  width:36%; white-space:nowrap;
}

.witness-label { font-weight:bold; font-size:11pt; margin-bottom:1mm; }
.witness-name  { font-style:italic; font-size:12pt; margin-bottom:3mm; line-height:1.45; }

.body-text {
  font-size:11pt; line-height:1.6;
  text-align:justify; flex-grow:1;
}
.note {
  font-size:10.5pt; font-weight:bold;
  text-decoration:underline;
  margin-top:3mm; margin-bottom:3mm;
}
.sign { text-align:right; font-size:11pt; margin-top:auto; }
.sign-space { height:12mm; display:block; }
.sign-lines div { margin:0; padding:0; line-height:1.3; }

.print-btn {
  position:fixed; top:10px; right:10px;
  background:#1F4E78; color:white;
  border:none; padding:10px 22px;
  font-size:14px; border-radius:6px;
  cursor:pointer; z-index:999;
}
.print-btn:hover { background:#163d5e; }
</style>"""


def block_html(row, stype, janpad):
    court_name, court_disp, is_session = resolve_court(row.get("न्यायालय",""), janpad)
    st_no   = str(row.get("ST NO",    "")).strip()
    mu_no   = str(row.get("मु0अ0स0", "")).strip()
    banam   = str(row.get("बनाम",    "")).strip()
    dhara   = str(row.get("धारा",    "")).strip()
    tareekh = fmt_date(row.get("अगली तारीख पेशी", ""))
    witness = clean_prefix(str(row.get("तलब साक्षी", "")).strip())
    today   = datetime.today().strftime('%d/%m/%Y')

    court_cls = "block-court session" if is_session else "block-court"
    label     = "नाम पता अभियुक्त:" if stype == "MRITYU" else "नाम पता साक्षी:"
    note_html = ("" if stype == "MRITYU" else
                 '<div class="note">नोट:- तामीलकर्ता साक्षी का मोबाइल नंबर अवश्य अंकित करें।</div>')

    return f"""<div class="block">
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


def generate_html(df: pd.DataFrame, janpad: str) -> str:
    """
    df: सेशन कोर्ट sheet का DataFrame
    सम्मन की स्थिति = "बनाना है" वाली rows filter करके HTML बनाता है
    """
    # Filter
    pending = df[df["सम्मन की स्थिति"].astype(str).str.strip() == "बनाना है"].copy()

    if pending.empty:
        return None, []

    # Collect all blocks
    saman, bw, nbw, mrityu = [], [], [], []
    st_nos_used = []

    for _, row in pending.iterrows():
        field = str(row.get("तलब साक्षी", "")).strip()
        if not field: continue
        stype = detect_type(field)
        # comma-separated witnesses
        names = [n.strip() for n in re.sub(r'^\s*(BW|NBW|MRITYU)\s*', '', field, flags=re.IGNORECASE).split(',') if n.strip()]
        for name in names:
            r = row.copy()
            r["तलब साक्षी"] = name
            {"SAMAN": saman, "BW": bw, "NBW": nbw, "MRITYU": mrityu}[stype].append((r, stype))
        st_nos_used.append(str(row.get("ST NO", "")).strip())

    all_blocks = saman + bw + nbw + mrityu

    pages = []
    for i in range(0, len(all_blocks), 2):
        pair = all_blocks[i:i+2]
        blocks = "".join(block_html(r, t, janpad) for r, t in pair)
        if len(pair) == 1:
            blocks += '<div class="block"></div>'
        pages.append(f'<div class="page">{blocks}</div>')

    today = datetime.today().strftime('%d/%m/%Y')
    html = f"""<!DOCTYPE html>
<html lang="hi">
<head>
  <meta charset="UTF-8"/>
  <title>समन दस्तावेज़ — {today}</title>
  {CSS}
</head>
<body>
  <button class="print-btn no-print" onclick="window.print()">🖨️ Print / PDF</button>
  {"".join(pages)}
</body>
</html>"""

    return html, list(set(st_nos_used))

