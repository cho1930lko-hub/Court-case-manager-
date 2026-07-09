"""
HTML "Dak Register" रिपोर्ट जनरेटर
Status = INCOMPLETE (या चुना हुआ status) वाली entries को थाने पर भेजने के लिए
printable HTML (A4 landscape) — समन / कृत-कार्यवाही जनरेटर जैसी ही शैली में बनाता है।
"""
from datetime import datetime
import pandas as pd


def _build_css(font_pt: float = 10.5, pad_mm: float = 2.2) -> str:
    return f"""<style>
@import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;700&display=swap');
* {{ margin:0; padding:0; box-sizing:border-box; }}
body {{ font-family:'Noto Sans Devanagari','Mangal',Arial,sans-serif; background:#fff; color:#000; }}

@page {{ size:A4 landscape; margin:8mm 7mm; }}
@media print {{
  body {{ margin:0; }}
  .no-print {{ display:none !important; }}
}}

.report-title {{
  text-align:center; font-weight:bold; font-size:16pt;
  text-decoration:underline; margin-bottom:1mm;
}}
.report-sub {{
  text-align:center; font-size:11pt; font-weight:600; margin-bottom:4mm; color:#333;
}}

table.dak {{
  width:100%; border-collapse:collapse; font-size:{font_pt}pt;
}}
table.dak thead {{ display: table-header-group; }}
table.dak tr {{ page-break-inside: avoid; }}
table.dak th, table.dak td {{
  border:1px solid #444; padding:{pad_mm}mm {pad_mm + 0.5}mm;
  text-align:left; vertical-align:top; line-height:1.3;
}}
table.dak th {{
  background:#1F4E78; color:#fff; font-weight:bold; text-align:center;
}}
table.dak tr:nth-child(even) td {{ background:#f7f9fc; }}
table.dak td.center {{ text-align:center; white-space:nowrap; }}
table.dak td.type-col {{ text-align:center; }}
.badge {{
  display:inline-block; padding:0.8mm 2.5mm; border-radius:3mm;
  background:#fdecea; color:#c0392b; font-weight:bold; font-size:{font_pt - 0.5}pt;
  white-space:nowrap;
}}

.print-btn {{
  position:fixed; top:10px; right:10px;
  background:#1F4E78; color:white;
  border:none; padding:10px 22px;
  font-size:14px; border-radius:6px;
  cursor:pointer; z-index:999;
}}
.print-btn:hover {{ background:#163d5e; }}

.sign-row {{
  margin-top:9mm; display:flex; justify-content:space-between;
  font-size:11pt; padding:0 4mm;
}}
</style>"""


def generate_dak_html(df: pd.DataFrame, janpad: str, thana: str,
                       status: str = "INCOMPLETE") -> str:
    """
    df: Dak Register का DataFrame (पहले से status/type से filter किया हुआ)
    janpad, thana: heading में दिखाने के लिए
    status: heading में दिखाने के लिए लेबल (जैसे "INCOMPLETE")
    थाने पर भेजने के लिए तैयार, print-friendly A4 landscape HTML बनाता है।
    """
    if df.empty:
        return None

    rows = df.copy()
    css = _build_css()

    trs = []
    for _, r in rows.iterrows():
        stn      = str(r.get("STN", "")).strip()
        banam    = str(r.get("बनाम", "")).strip()
        dtype    = str(r.get("Type", "")).strip()
        naampata = str(r.get("नाम पता", "")).strip()
        thana_r  = str(r.get("संबंधित थाना", "")).strip()
        court    = str(r.get("कोर्ट का नाम", "")).strip()
        thane_dt = str(r.get("थाने पर लाने का दिनांक", "")).strip()
        peshi_dt = str(r.get("तारीख़ पेशी", "")).strip()
        remark   = str(r.get("रिमार्क", "")).strip() or "-"
        trs.append(
            f"<tr><td class='center'>{stn}</td><td>{banam}</td>"
            f"<td class='type-col'><span class='badge'>{dtype}</span></td>"
            f"<td>{naampata}</td><td class='center'>{thana_r}</td>"
            f"<td class='center'>{court}</td><td class='center'>{thane_dt}</td>"
            f"<td class='center'>{peshi_dt}</td><td>{remark}</td></tr>"
        )

    today = datetime.today().strftime('%d/%m/%Y')
    html = f"""<!DOCTYPE html>
<html lang="hi">
<head>
  <meta charset="UTF-8"/>
  <title>Dak Register — {status} — {today}</title>
  {css}
</head>
<body>
  <button class="print-btn no-print" onclick="window.print()">🖨️ Print / PDF</button>
  <div class="report-title">Dak Register — {status} सूची</div>
  <div class="report-sub">थाना {thana}, जनपद {janpad} &nbsp;|&nbsp; बनाई गई: {today} &nbsp;|&nbsp; कुल: {len(rows)}</div>
  <table class="dak">
    <thead>
      <tr>
        <th>STN</th><th>बनाम</th><th>Type</th><th>नाम पता</th>
        <th>संबंधित थाना</th><th>कोर्ट का नाम</th>
        <th>थाने पर लाने का दिनांक</th><th>तारीख़ पेशी</th><th>रिमार्क</th>
      </tr>
    </thead>
    <tbody>
      {"".join(trs)}
    </tbody>
  </table>
  <div class="sign-row">
    <div>तैयार कर्ता: ___________________</div>
    <div>थाना प्रभारी हस्ताक्षर व मुहर: ___________________</div>
  </div>
</body>
</html>"""
    return html

