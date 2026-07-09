"""
HTML "कृत कार्यवाही" रिपोर्ट जनरेटर
किसी एक दिनांक (तारीख पेशी) या धारा (कलम) के आधार पर filter करके
समन जनरेटर जैसा ही printable HTML रिपोर्ट बनाता है — A4 landscape,
थाना/जनपद स्तर पर, max ~2 pages में fit करने के लिए auto font-shrink।
"""
from datetime import datetime
import pandas as pd


def fmt_date(val):
    if isinstance(val, datetime):
        return val.strftime('%d/%m/%Y')
    s = str(val).strip()
    for fmt in ('%d/%m/%Y', '%d-%m-%Y', '%Y-%m-%d'):
        try:
            return datetime.strptime(s, fmt).strftime('%d/%m/%Y')
        except Exception:
            pass
    return s


def parse_date(s):
    s = str(s).strip()
    for fmt in ('%d/%m/%Y', '%d-%m-%Y', '%Y-%m-%d'):
        try:
            return datetime.strptime(s, fmt)
        except Exception:
            pass
    return None


def _font_scale(n_rows: int):
    """rows की संख्या के हिसाब से font-size (pt) और cell padding (mm) तय करता है
    ताकि पूरा डाटा लगभग 2 pages (A4 landscape) में fit हो जाए।
    ये एक अनुमानित (approximate) scaling है — बहुत ज़्यादा rows होने पर
    फिर भी 3rd page बन सकता है, तब filter को और सीमित करें (जैसे धारा/दिनांक और specific करें)।"""
    if n_rows <= 20:
        return 10.5, 3.0
    if n_rows <= 35:
        return 9.5, 2.3
    if n_rows <= 50:
        return 8.5, 1.8
    if n_rows <= 70:
        return 7.5, 1.3
    if n_rows <= 95:
        return 6.5, 1.0
    if n_rows <= 130:
        return 5.8, 0.7
    return 5.2, 0.5


def _build_css(font_pt: float, pad_mm: float) -> str:
    return f"""<style>
@import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;700&display=swap');
* {{ margin:0; padding:0; box-sizing:border-box; }}
body {{ font-family:'Noto Sans Devanagari','Mangal',Arial,sans-serif; background:#fff; color:#000; }}

@page {{
  size:A4 landscape; margin:8mm 7mm 14mm 7mm;
  @bottom-right {{
    content: "Page " counter(page) " of " counter(pages);
    font-size:9pt;
  }}
}}
@media print {{
  body {{ margin:0; }}
  .no-print {{ display:none !important; }}
}}

.report-title {{
  text-align:center; font-weight:bold; font-size:15pt;
  text-decoration:underline; margin-bottom:1mm;
}}
.report-sub {{
  text-align:center; font-size:11pt; font-weight:600; margin-bottom:4mm;
}}
.report-footer {{
  text-align:right; font-weight:600; font-size:11pt;
  margin-top:8mm; padding-right:2mm;
}}

table.karya {{
  width:100%; border-collapse:collapse; font-size:{font_pt}pt;
}}
table.karya thead {{ display: table-header-group; }}
table.karya tr {{ page-break-inside: avoid; }}
table.karya th, table.karya td {{
  border:1px solid #444; padding:{pad_mm}mm {pad_mm + 0.5}mm;
  text-align:left; vertical-align:top; line-height:1.25;
}}
table.karya th {{
  background:#e6e6e6; font-weight:bold; text-align:center;
}}
table.karya td.center {{ text-align:center; white-space:nowrap; }}

.print-btn {{
  position:fixed; top:10px; right:10px;
  background:#1F4E78; color:white;
  border:none; padding:10px 22px;
  font-size:14px; border-radius:6px;
  cursor:pointer; z-index:999;
}}
.print-btn:hover {{ background:#163d5e; }}
</style>"""


def generate_karyawahi_html(df: pd.DataFrame, janpad: str, thana: str, sub_heading: str) -> str:
    """
    df: filter की हुई सेशन कोर्ट rows (columns: ST NO, मु0अ0स0, धारा, बनाम,
        न्यायालय, तलब साक्षी, अगली तारीख पेशी, Type Of Moni, कृत कार्यवाही)
    janpad, thana: शीर्षक (heading) में दिखाने के लिए
    sub_heading: फ़िल्टर की जानकारी (जैसे "दिनांक: 07/07/2026" या "धारा/कलम: 323")
    """
    if df.empty:
        return None

    rows = df.copy()
    rows["_sort_date"] = rows["अगली तारीख पेशी"].apply(parse_date)
    rows = rows.sort_values(by="_sort_date", na_position="last")

    font_pt, pad_mm = _font_scale(len(rows))
    css = _build_css(font_pt, pad_mm)

    trs = []
    for _, r in rows.iterrows():
        st_no   = str(r.get("ST NO", "")).strip()
        mu_no   = str(r.get("मु0अ0स0", "")).strip()
        dhara   = str(r.get("धारा", "")).strip()
        banam   = str(r.get("बनाम", "")).strip()
        court   = str(r.get("न्यायालय", "")).strip()
        saakshi = str(r.get("तलब साक्षी", "")).strip()
        tareekh = fmt_date(r.get("अगली तारीख पेशी", ""))
        prakar  = str(r.get("Type Of Moni", "")).strip() or "सामान्य"
        karya   = str(r.get("कृत कार्यवाही", "")).strip() or "-"
        trs.append(
            f"<tr><td class='center'>{st_no}</td><td class='center'>{mu_no}</td>"
            f"<td>{dhara}</td><td>{banam}</td><td class='center'>{court}</td>"
            f"<td>{saakshi}</td><td class='center'>{tareekh}</td>"
            f"<td class='center'>{prakar}</td><td>{karya}</td></tr>"
        )

    today = datetime.today().strftime('%d/%m/%Y')
    html = f"""<!DOCTYPE html>
<html lang="hi">
<head>
  <meta charset="UTF-8"/>
  <title>आज की कार्यवाही — {today}</title>
  {css}
</head>
<body>
  <button class="print-btn no-print" onclick="window.print()">🖨️ Print / PDF</button>
  <p class="no-print" style="text-align:center;font-size:10pt;color:#555;margin:0 0 4mm;">
    📌 पेज नंबर ("Page 1 of 2") सही दिखने के लिए Print dialog में "Headers and footers" चालू रखें।
  </p>
  <div class="report-title">आज की कार्यवाही — थाना {thana}, जनपद {janpad}</div>
  <div class="report-sub">{sub_heading} &nbsp;|&nbsp; कुल मुकदमे: {len(rows)}</div>
  <table class="karya">
    <thead>
      <tr>
        <th>मु0न0</th><th>मु0अ0स0</th><th>धारा</th><th>बनाम</th>
        <th>न्यायालय</th><th>नाम पता साक्षी</th><th>तारीख पेशी</th>
        <th>प्रकार</th><th>कृत कार्यवाही</th>
      </tr>
    </thead>
    <tbody>
      {"".join(trs)}
    </tbody>
  </table>
  <div class="report-footer">आरक्षी मो शादाब, पैरोकार सेशन कोर्ट भिंगा</div>
</body>
</html>"""
    return html

