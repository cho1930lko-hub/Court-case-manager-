"""
Court document templates: NBW Warrant, BW Warrant, Mrityu Aakhya, Saman Sakshi, VC Letter.
Har function ek dict of fields leta hai aur HTML string return karta hai (preview/print ke liye).
DOCX generation alag function mein hai.
"""

# ---------------------------------------------------------------------------
# Field definitions per document type — used to build the dynamic form in the UI
# ---------------------------------------------------------------------------

DOC_TYPES = {
    "nbw": "गैर जमानती वारंट (NBW) साक्षी",
    "bw": "जमानती वारंट (BW) साक्षी",
    "mrityu": "मृत्यु आख्या",
    "saman": "समन साक्षी",
    "vc": "VC लेटर (वीडियो कांफ्रेंसिंग पत्र)",
}

# Common fields used across NBW / BW / Mrityu / Saman (the "table" block)
COMMON_TABLE_FIELDS = [
    ("nyayalaya_pad", "न्यायालय पद (जैसे: जिला एवं सत्र / मुख्य न्यायिक मजिस्ट्रेट)"),
    ("janpad", "जनपद"),
    ("rajya_banam", "राज्य बनाम (नाम)"),
    ("mu_no", "मु0न0 (मुकदमा नंबर)"),
    ("mu_apradh_sankhya", "मु0अ0सं0 (मुकदमा अपराध संख्या)"),
    ("dhara", "धारा"),
    ("thana", "थाना"),
    ("tareekh_peshi", "तारीख पेशी"),
]

NAME_ADDRESS_FIELD = ("naam_pata", "नाम पता")

EXTRA_FIELDS = {
    "bw": [("jamanat_rashi", "जमानत राशि (जैसे: 10-10 हजार)")],
    "saman": [("peshi_samay", "उपस्थित होने का समय (जैसे: सुबह 10:30 बजे)")],
    "vc": [
        ("praapak_pad", "प्रेषक पद (जैसे: जिला एवं सत्र)"),
        ("seva_me_pad", "सेवा में पद (जैसे: जिला एवं सत्र न्यायाधीश)"),
        ("seva_me_janpad", "सेवा में जनपद"),
        ("vishay", "विषय (subject line)"),
        ("satra_pareeksha_sankhya", "सत्र परीक्षण संख्या"),
        ("vc_sthan", "VC स्थान (जैसे: जिला न्यायालय अम्बेडकर)"),
        ("vc_tareekh", "VC तारीख"),
        ("vc_samay", "VC समय (जैसे: 12:30 PM)"),
        ("prati_pad", "प्रतिलिपि - पद 1 (जैसे: पुलिस अधीक्षक)"),
        ("prati_janpad", "प्रतिलिपि - जनपद"),
    ],
}

TODAY_FIELD = ("aaj_ki_tareekh", "आज की तारीख (हस्ताक्षर हेतु)")


def get_fields_for_type(doc_type: str):
    """Returns ordered list of (field_key, label) for a given document type."""
    if doc_type == "vc":
        fields = EXTRA_FIELDS["vc"] + [TODAY_FIELD]
        return fields
    fields = list(COMMON_TABLE_FIELDS) + [NAME_ADDRESS_FIELD]
    fields += EXTRA_FIELDS.get(doc_type, [])
    fields.append(TODAY_FIELD)
    return fields


# ---------------------------------------------------------------------------
# HTML rendering (used for live preview + browser print/PDF)
# ---------------------------------------------------------------------------

BASE_CSS = """
<style>
  body { font-family: 'Noto Sans Devanagari', 'Mangal', Arial, sans-serif; margin: 0; padding: 0; }
  .doc-box { border: 1px solid #333; padding: 24px; max-width: 700px; margin: 16px auto; }
  .doc-title { text-align: center; font-size: 20px; font-weight: bold; text-decoration: underline; margin-bottom: 4px;}
  .doc-subtitle { text-align: center; font-size: 15px; margin-bottom: 14px; }
  table.info-table { width: 100%; border-collapse: collapse; margin-bottom: 14px; }
  table.info-table td { border: 1px solid #333; padding: 6px 10px; font-size: 14px; }
  table.info-table td.label { background:#f2f2f2; font-weight: bold; width: 35%; }
  .section-label { font-weight: bold; margin-top: 10px; margin-bottom: 4px; font-size: 14px;}
  .name-pata { font-style: italic; font-size: 15px; margin-bottom: 12px; }
  .body-text { font-size: 14.5px; line-height: 1.7; text-align: justify; margin-bottom: 14px;}
  .note { font-size: 13px; text-decoration: underline; margin-bottom: 20px; }
  .sign-block { text-align: right; font-size: 14px; line-height: 1.6; margin-top: 30px; }
  .vc-header { font-size: 14.5px; line-height: 1.6; margin-bottom: 14px; }
  .vc-subject { font-weight: bold; margin: 14px 0; font-size: 14.5px; }
  .copy-section { margin-top: 24px; border-top: 1px dashed #999; padding-top: 10px; font-size: 13.5px; }
  @media print { .no-print { display: none; } body { margin: 0; } }
</style>
"""


def _table_rows(f):
    return f"""
    <table class="info-table">
      <tr><td class="label">राज्य बनाम</td><td>{f.get('rajya_banam','')}</td></tr>
      <tr><td class="label">मु0न0</td><td>{f.get('mu_no','')}</td></tr>
      <tr><td class="label">मु0अ0सं0</td><td>{f.get('mu_apradh_sankhya','')}</td></tr>
      <tr><td class="label">धारा</td><td>{f.get('dhara','')}</td></tr>
      <tr><td class="label">थाना</td><td>{f.get('thana','')}</td></tr>
      <tr><td class="label">जनपद</td><td>{f.get('janpad','')}</td></tr>
      <tr><td class="label">तारीख पेशी</td><td>{f.get('tareekh_peshi','')}</td></tr>
    </table>
    """


def _sign_block(pad, janpad, tareekh):
    return f"""
    <div class="sign-block">
      {pad}<br/>
      {janpad}<br/>
      {tareekh}
    </div>
    """


def render_nbw(f):
    html = f"""
    {BASE_CSS}
    <div class="doc-box">
      <div class="doc-title">गैर जमानती वारंट (NBW) साक्षी</div>
      <div class="doc-subtitle">न्यायालय : {f.get('nyayalaya_pad','')} {f.get('janpad','')}</div>
      {_table_rows(f)}
      <div class="section-label">नाम पता साक्षी:</div>
      <div class="name-pata">{f.get('naam_pata','')}</div>
      <div class="body-text">उपरोक्त साक्षी को नियत तारीख पेशी से पूर्व या तक गिरफ्तार कर मेरे समक्ष पेश करें।</div>
      <div class="note">नोट:- तामीलकर्ता साक्षी का मोबाइल नंबर अवश्य अंकित करें।</div>
      {_sign_block(f.get('nyayalaya_pad',''), f.get('janpad',''), f.get('aaj_ki_tareekh',''))}
    </div>
    """
    return html


def render_bw(f):
    html = f"""
    {BASE_CSS}
    <div class="doc-box">
      <div class="doc-title">जमानती वारंट (BW) साक्षी</div>
      <div class="doc-subtitle">न्यायालय : {f.get('nyayalaya_pad','')} {f.get('janpad','')}</div>
      {_table_rows(f)}
      <div class="section-label">नाम पता साक्षी:</div>
      <div class="name-pata">{f.get('naam_pata','')}</div>
      <div class="body-text">उपरोक्त साक्षी से {f.get('jamanat_rashi','')} की दो जमानतें तथा इतनी ही धनराशि का बंधपत्र न्यायालय उपस्थित होने के बाबत दाखिल कराएं। ऐसा ना करने पर उपर्युक्त साक्षी को गिरफ्तार कर मेरे समक्ष पेश करें।</div>
      <div class="note">नोट:- तामीलकर्ता साक्षी का मोबाइल नंबर अवश्य अंकित करें।</div>
      {_sign_block(f.get('nyayalaya_pad',''), f.get('janpad',''), f.get('aaj_ki_tareekh',''))}
    </div>
    """
    return html


def render_mrityu(f):
    html = f"""
    {BASE_CSS}
    <div class="doc-box">
      <div class="doc-title">मृत्यु आख्या</div>
      <div class="doc-subtitle">न्यायालय : {f.get('nyayalaya_pad','')} {f.get('janpad','')}</div>
      {_table_rows(f)}
      <div class="section-label">नाम पता अभियुक्त:</div>
      <div class="name-pata">{f.get('naam_pata','')}</div>
      <div class="body-text">एतद् द्वारा आदेशित किया जाता है कि उपर्युक्त अभियुक्त की मृत्यु से संबंधित प्रमाण-पत्र नियत तिथि पर न्यायालय के समक्ष अनिवार्य रूप से प्रस्तुत किया जाए।</div>
      {_sign_block(f.get('nyayalaya_pad',''), f.get('janpad',''), f.get('aaj_ki_tareekh',''))}
    </div>
    """
    return html


def render_saman(f):
    html = f"""
    {BASE_CSS}
    <div class="doc-box">
      <div class="doc-title">समन साक्षी</div>
      <div class="doc-subtitle">न्यायालय : {f.get('nyayalaya_pad','')} {f.get('janpad','')}</div>
      {_table_rows(f)}
      <div class="section-label">नाम पता साक्षी:</div>
      <div class="name-pata">{f.get('naam_pata','')}</div>
      <div class="body-text">साक्षी मुकदमा उपरोक्त के संबंध में अपना साक्ष्य देने के लिए अपने पहचान पत्र / आधार कार्ड व एक पासपोर्ट साइज फोटो के साथ उपर्युक्त नियत तारीख पेशी पर {f.get('peshi_samay','')} उपस्थित होना सुनिश्चित करें। ऐसा करने में कोई त्रुटि न हो।</div>
      <div class="note">नोट:- तामीलकर्ता साक्षी का मोबाइल नंबर अवश्य अंकित करें।</div>
      {_sign_block(f.get('nyayalaya_pad',''), f.get('janpad',''), f.get('aaj_ki_tareekh',''))}
    </div>
    """
    return html


def render_vc(f):
    html = f"""
    {BASE_CSS}
    <div class="doc-box">
      <div class="vc-header">
        प्रेषक,<br/>
        &nbsp;&nbsp;&nbsp;{f.get('praapak_pad','')},<br/>
        &nbsp;&nbsp;&nbsp;{f.get('janpad','')} ।
      </div>
      <div class="vc-header">
        सेवा में,<br/>
        &nbsp;&nbsp;&nbsp;{f.get('seva_me_pad','')},<br/>
        &nbsp;&nbsp;&nbsp;जनपद {f.get('seva_me_janpad','')}।
      </div>
      <div class="vc-subject">विषय - {f.get('vishay','')}</div>
      <div class="body-text">
        महोदय,<br/>
        सविनय निवेदन है कि इस न्यायालय में लंबित निम्नलिखित विवरण के अनुसार साक्षी का साक्ष्य अंकन जरिए वीडियो कांफ्रेंसिंग कराया जाना है:
      </div>
      <table class="info-table">
        <tr><td class="label">सत्र परीक्षण संख्या</td><td>{f.get('satra_pareeksha_sankhya','')}</td></tr>
        <tr><td class="label">मुकदमा अपराध संख्या</td><td>{f.get('mu_apradh_sankhya','')}</td></tr>
        <tr><td class="label">राज्य बनाम</td><td>{f.get('rajya_banam','')}</td></tr>
        <tr><td class="label">धारा</td><td>{f.get('dhara','')}</td></tr>
        <tr><td class="label">थाना</td><td>{f.get('thana','')}</td></tr>
        <tr><td class="label">जनपद</td><td>{f.get('janpad','')}</td></tr>
        <tr><td class="label">तारीख पेशी</td><td>{f.get('tareekh_peshi','')}</td></tr>
      </table>
      <div class="body-text">
        अतः आपसे निवेदन है कि साक्षी का साक्ष्य अंकन {f.get('vc_tareekh','')} को जिला न्यायालय {f.get('vc_sthan','')} में वीडियो कांफ्रेंसिंग के माध्यम से करवाने हेतु आवश्यक निर्देश प्रदान करने की कृपा करें।
      </div>
      {_sign_block('भवदीय,<br/>'+f.get('praapak_pad',''), f.get('janpad',''), f.get('aaj_ki_tareekh',''))}
      <div class="copy-section">
        <strong>प्रतिलिपि-</strong><br/>
        1. {f.get('prati_pad','')} जनपद {f.get('prati_janpad','')} को इस आशय के साथ प्रेषित कि संबंधित अधीनस्थ को उपरोक्तानुसार निर्देश प्रदान करने का कष्ट करें।<br/>
        2. {f.get('naam_pata','')} दिनांक {f.get('vc_tareekh','')} को समय {f.get('vc_samay','')} पर जिला न्यायालय {f.get('vc_sthan','')} में अपनी पहचान संबंधित दस्तावेज के साथ वीडियो कांफ्रेंसिंग हेतु उपस्थित रहें।
        {_sign_block(f.get('praapak_pad',''), f.get('janpad',''), f.get('aaj_ki_tareekh',''))}
      </div>
    </div>
    """
    return html


RENDERERS = {
    "nbw": render_nbw,
    "bw": render_bw,
    "mrityu": render_mrityu,
    "saman": render_saman,
    "vc": render_vc,
}


def render_document_html(doc_type: str, fields: dict) -> str:
    renderer = RENDERERS.get(doc_type)
    if not renderer:
        return "<p>Unknown document type</p>"
    return renderer(fields)

