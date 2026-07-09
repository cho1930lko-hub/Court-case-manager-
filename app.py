"""
⚖️ पैरवी रजिस्टर — Court Case Management System
भिंगा, जनपद श्रावस्ती
"""
import streamlit as st
import pandas as pd
from datetime import datetime
import urllib.parse
import gsheet as gs
import summon_gen as sg
import karyawahi_gen as kg
import dak_gen as dg

st.set_page_config(
    page_title="पैरवी रजिस्टर — भिंगा",
    page_icon="⚖️",
    layout="wide"
)

JANPAD = st.secrets.get("JANPAD", "श्रावस्ती")
THANA  = st.secrets.get("THANA", "कोतवाली भिंगा")

# ── 🔒 Password Protection ───────────────────────────────────────────────────
APP_PASSWORD = st.secrets.get("APP_PASSWORD", "")

def _check_password():
    if not APP_PASSWORD:
        return True  # अगर secrets में APP_PASSWORD सेट नहीं है तो protection बंद रहेगी
    if st.session_state.get("authenticated", False):
        return True

    st.markdown("""
    <style>
    .stApp { background: linear-gradient(180deg, #1e2a4a 0%, #17203a 100%); }
    </style>
    """, unsafe_allow_html=True)

    _, col, _ = st.columns([1, 1.3, 1])
    with col:
        st.markdown(
            "<h2 style='text-align:center; color:white; margin-top:15vh;'>"
            "⚖️ पैरवी रजिस्टर</h2>", unsafe_allow_html=True
        )
        st.markdown(
            f"<p style='text-align:center; color:#c8cfe0;'>भिंगा, जनपद {JANPAD}</p>",
            unsafe_allow_html=True
        )
        pwd = st.text_input("Password डालें", type="password", label_visibility="collapsed",
                            placeholder="🔑 Password डालें")
        if st.button("लॉगिन करें", use_container_width=True, type="primary"):
            if pwd == APP_PASSWORD:
                st.session_state["authenticated"] = True
                st.rerun()
            else:
                st.error("❌ गलत password।")
    return False

if not _check_password():
    st.stop()

# ── Global CSS styling ────────────────────────────────────────────────────────
st.markdown("""
<style>
@import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;500;600;700&family=Poppins:wght@500;600;700&display=swap');

html, body, [class*="css"] {
    font-family: 'Noto Sans Devanagari', 'Poppins', sans-serif !important;
}

.stApp {
    background: linear-gradient(180deg, #f7f8fc 0%, #eef1f8 100%);
}

section[data-testid="stSidebar"] {
    background: linear-gradient(180deg, #1e2a4a 0%, #17203a 100%);
    color: #ffffff !important;
}
section[data-testid="stSidebar"] * {
    color: #f0f2f8 !important;
}
section[data-testid="stSidebar"] .stRadio label {
    padding: 6px 10px;
    border-radius: 8px;
    margin-bottom: 2px;
    transition: background 0.15s ease;
}
section[data-testid="stSidebar"] .stRadio label:hover {
    background: rgba(255,255,255,0.08);
}
section[data-testid="stSidebar"] .stButton button {
    background: linear-gradient(135deg, #4f7cff, #2f56d6);
    color: white !important;
    border: none;
    border-radius: 10px;
    font-weight: 600;
}
section[data-testid="stSidebar"] .stButton button:hover {
    background: linear-gradient(135deg, #5c86ff, #3862e0);
}

h1, h2, h3 {
    font-weight: 700 !important;
    color: #1e2a4a;
}
h1 { border-bottom: 3px solid #4f7cff; padding-bottom: 8px; }

div[data-testid="stMetric"] {
    background: #ffffff;
    border: 1px solid #e6e9f2;
    border-radius: 14px;
    padding: 16px 18px 12px 18px;
    box-shadow: 0 2px 10px rgba(30,42,74,0.06);
    transition: transform 0.15s ease, box-shadow 0.15s ease;
}
div[data-testid="stMetric"]:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 18px rgba(30,42,74,0.12);
}
div[data-testid="stMetricLabel"] { color: #6b7594 !important; font-weight: 600; }
div[data-testid="stMetricValue"] { color: #1e2a4a !important; font-weight: 700; }

div[data-testid="stDataFrame"] {
    border-radius: 12px;
    overflow: hidden;
    border: 1px solid #e6e9f2;
    box-shadow: 0 2px 8px rgba(30,42,74,0.05);
}

.stButton button, .stFormSubmitButton button {
    border-radius: 10px !important;
    font-weight: 600 !important;
}
.stButton button[kind="primary"], .stFormSubmitButton button[kind="primary"] {
    background: linear-gradient(135deg, #4f7cff, #2f56d6) !important;
    border: none !important;
}

div[data-testid="stAlert"] {
    border-radius: 12px;
}

hr { border-color: #dfe3ee !important; }

/* आज की पेशी — mobile-friendly cards (कोई column cut-off नहीं) */
.case-card {
    background: #ffffff;
    border: 1px solid #e6e9f2;
    border-left: 4px solid #4f7cff;
    border-radius: 10px;
    padding: 10px 14px;
    margin-bottom: 8px;
    box-shadow: 0 1px 4px rgba(30,42,74,0.06);
}
.case-card-top {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 8px;
    margin-bottom: 4px;
}
.case-st {
    font-weight: 700;
    color: #1e2a4a;
    font-size: 0.95rem;
}
.case-status {
    font-size: 0.72rem;
    font-weight: 700;
    padding: 2px 9px;
    border-radius: 10px;
    background: #eef1f8;
    color: #4f7cff;
    white-space: nowrap;
}
.case-banam {
    font-weight: 600;
    color: #1e2a4a;
    margin-bottom: 3px;
    word-break: break-word;
}
.case-court, .case-witness {
    font-size: 0.85rem;
    color: #5b6478;
    margin-bottom: 2px;
    word-break: break-word;
    line-height: 1.4;
}

/* Address Book cards */
.addr-card {
    background: #ffffff;
    border: 1px solid #e6e9f2;
    border-left: 4px solid #22a06b;
    border-radius: 10px;
    padding: 10px 14px;
    margin-bottom: 8px;
    box-shadow: 0 1px 4px rgba(30,42,74,0.06);
}
.addr-card-top {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-bottom: 3px;
}
.addr-icon { font-size: 1rem; }
.addr-name {
    font-weight: 700;
    color: #1e2a4a;
    font-size: 0.95rem;
}
.addr-dept, .addr-address {
    font-size: 0.85rem;
    color: #5b6478;
    margin-bottom: 2px;
    word-break: break-word;
    line-height: 1.4;
}
.addr-actions {
    display: flex;
    gap: 8px;
    margin-top: 6px;
    flex-wrap: wrap;
}
.addr-actions a {
    text-decoration: none;
    font-weight: 600;
    font-size: 0.8rem;
    padding: 4px 10px;
    border-radius: 8px;
}
.addr-call { background: #eef1f8; color: #4f7cff; }
.addr-share { background: #e3f6ec; color: #1e9e5c; }
.addr-actions a:hover { filter: brightness(0.95); }
</style>
""", unsafe_allow_html=True)

# ── Share helper ──────────────────────────────────────────────────────────────
def court_icon(nyayalaya: str) -> str:
    """न्यायालय के प्रकार के हिसाब से अलग आइकॉन — सत्र/विशेष न्यायालय बनाम मजिस्ट्रेट कोर्ट"""
    n = str(nyayalaya).upper()
    if any(k in n for k in ["ASJ", "DJ", "POCSO", "SC/ST", "सत्र"]):
        return "🏛️"
    return "⚖️"


def build_share_text(row: dict) -> str:
    """केस की row (dict) से एक साफ़-सुथरा, emoji-आधारित शेयर करने योग्य text बनाता है"""
    icon = court_icon(row.get("न्यायालय", ""))
    sep = "━━━━━━━━━━━━━━━━━━━━"

    def line(emoji, label, value):
        return f"{emoji} {label:<16}: {value or '-'}"

    lines = [
        f"{icon} पैरवी रिपोर्ट",
        f"{THANA}, जनपद {JANPAD}",
        sep,
        "",
        line("📄", "एस०टी० नं०", row.get("ST NO", "")),
        line("📑", "मु०अ०सं०", row.get("मु0अ0स0", "")),
        line("⚖️", "धाराएँ", row.get("धारा", "")),
        line("🏛️", "न्यायालय", row.get("न्यायालय", "")),
        line("👥", "राज्य बनाम", row.get("बनाम", "")),
        line("👤", "तलब साक्षी", row.get("तलब साक्षी", "")),
        line("📅", "अगली पेशी", row.get("अगली तारीख पेशी", "")),
        line("📌", "वाद की स्थिति", row.get("Status", "")),
        line("🎯", "मॉनिटरिंग प्रकार", row.get("Type Of Moni", "")),
    ]
    krit = str(row.get("कृत कार्यवाही", "")).strip()
    if krit:
        lines += ["", line("📝", "कृत कार्यवाही", krit)]
    lines += ["", sep]
    return "\n".join(lines)


def render_share_block(row: dict, key_prefix: str = ""):
    """किसी भी page पर केस-शेयर UI (copy box + WhatsApp button) दिखाता है"""
    share_text = build_share_text(row)
    with st.expander("📤 यह केस शेयर करें", expanded=False):
        st.code(share_text, language=None)
        st.caption("ऊपर text-box के कोने में 📋 आइकॉन दबाकर copy करें, फिर कहीं भी paste कर दें।")
        wa_url = "https://wa.me/?text=" + urllib.parse.quote(share_text)
        st.link_button("🟢 WhatsApp पर शेयर करें", wa_url, use_container_width=True)


# ── Address Book share helper ────────────────────────────────────────────────
DEPT_ICONS = [
    ("पुलिस", "👮"), ("डॉक्टर", "🩺"), ("डाक्टर", "🩺"),
    ("वकील", "⚖️"), ("कोर्ट", "🏛️"), ("नर्स", "💉"),
]

def dept_icon(dept: str) -> str:
    """विभाग के हिसाब से अलग आइकॉन — पुलिस/डॉक्टर/वकील/आदि"""
    d = str(dept).strip()
    for key, icon in DEPT_ICONS:
        if key in d:
            return icon
    return "📇"


def build_addr_share_text(row: dict) -> str:
    """Address Book की row से WhatsApp शेयर करने योग्य text बनाता है"""
    icon = dept_icon(row.get("विभाग", ""))
    lines = [
        f"{icon} *{row.get('नाम', '') or '-'}*",
        f"विभाग: {row.get('विभाग', '') or '-'}",
        f"पता: {row.get('पता', '') or '-'}",
        f"मोबाइल: {row.get('मोबाइल', '') or '-'}",
        "",
        f"📍 भिंगा, जनपद {JANPAD} — पैरवी रजिस्टर",
    ]
    return "\n".join(lines)


# ── Rimand Register share helper ─────────────────────────────────────────────
def build_rimand_share_text(row: dict) -> str:
    """रिमांड रजिस्टर की row से emoji-आधारित शेयर करने योग्य text बनाता है"""
    sep = "━━━━━━━━━━━━━━━━━━━━"

    def line(emoji, label, value):
        return f"{emoji} {label:<16}: {value or '-'}"

    lines = [
        "🔒 रिमांड रिपोर्ट",
        f"{THANA}, जनपद {JANPAD}",
        sep,
        "",
        line("📅", "रिमांड दिनांक", row.get("रिमांड Date", "")),
        line("📑", "मु०अ०सं०", row.get("मु0अ0स0", "")),
        line("⚖️", "धाराएँ", row.get("धारा", "")),
        line("🏛️", "न्यायालय", row.get("कोर्ट", "")),
        line("🕵️", "विवेचक (IO)", row.get("IO", "")),
        line("📅", "प्रथम रिमांड डेट", row.get("First रिमांड डेट", "")),
        line("👤", "अभियुक्त नाम पता", row.get("नाम पता अभियुक्त", "")),
        "",
        sep,
    ]
    return "\n".join(lines)


def render_rimand_share_block(row: dict, key_prefix: str = ""):
    """रिमांड entry के लिए शेयर UI (copy box + WhatsApp button) दिखाता है"""
    share_text = build_rimand_share_text(row)
    with st.expander("📤 यह रिमांड एंट्री शेयर करें", expanded=False):
        st.code(share_text, language=None)
        st.caption("ऊपर text-box के कोने में 📋 आइकॉन दबाकर copy करें, फिर कहीं भी paste कर दें।")
        wa_url = "https://wa.me/?text=" + urllib.parse.quote(share_text)
        st.link_button("🟢 WhatsApp पर शेयर करें", wa_url, use_container_width=True,
                        key=f"{key_prefix}_rimand_wa")


# ── Sidebar Navigation ────────────────────────────────────────────────────────
with st.sidebar:
    st.markdown("### ⚖️ पैरवी रजिस्टर")
    st.markdown(f"📍 **भिंगा, जनपद {JANPAD}**")
    st.divider()

    page = st.radio("", [
        "📊 Dashboard",
        "📋 सेशन कोर्ट",
        "➕ नया केस",
        "✏️ केस अपडेट",
        "🖨️ समन जनरेटर",
        "📝 कृत कार्यवाही रिपोर्ट",
        "📬 Dak Register",
        "🔒 Rimand Register",
    ], label_visibility="collapsed")

    st.divider()
    if st.button("🔄 Data Refresh", use_container_width=True):
        st.cache_data.clear()
        st.rerun()
    if APP_PASSWORD:
        if st.button("🚪 Logout", use_container_width=True):
            st.session_state["authenticated"] = False
            st.rerun()
    st.caption(f"आज: {gs.today_str()}")


# ══════════════════════════════════════════════════════════════════════════════
# 1. DASHBOARD
# ══════════════════════════════════════════════════════════════════════════════
if page == "📊 Dashboard":
    st.header("📊 Dashboard")

    df_s = gs.load_session()
    df_d = gs.load_dak()
    df_addr = gs.load_address_book()

    if df_s.empty:
        st.warning("सेशन कोर्ट sheet से data नहीं मिला।")
        st.stop()

    # ── 🔍 Global Quick Search ──────────────────────────────────────────────
    search_q = st.text_input("🔍 Quick Search — ST NO या बनाम नाम टाइप करें",
                              placeholder="जैसे: 193/2025 या रामकुमार")
    if search_q:
        search_res = df_s[
            df_s["ST NO"].astype(str).str.contains(search_q, case=False, na=False) |
            df_s["बनाम"].astype(str).str.contains(search_q, case=False, na=False)
        ]
        if search_res.empty:
            st.info("कोई मुकदमा नहीं मिला।")
        else:
            st.caption(f"मिले: **{len(search_res)}** मुकदमे")
            st.dataframe(
                search_res[["ST NO", "बनाम", "न्यायालय", "Status", "अगली तारीख पेशी"]],
                use_container_width=True, hide_index=True
            )
            sel_st = st.selectbox("शेयर के लिए ST NO चुनें", search_res["ST NO"].astype(str).tolist(),
                                   key="dash_search_share")
            render_share_block(search_res[search_res["ST NO"].astype(str) == sel_st].iloc[0].to_dict(),
                               key_prefix="dashsearch")
        st.divider()

    # ── Stats row ────────────────────────────────────────────────────────────
    c1, c2, c3, c4, c5, c6 = st.columns(6)

    total   = len(df_s[df_s["ST NO"].astype(str).str.strip() != ""])
    sakshya = len(df_s[df_s["Status"] == "साक्ष्य"])
    pending_samman = len(df_s[df_s["सम्मन की स्थिति"].astype(str).str.strip() == "बनाना है"])
    dak_incomplete = len(df_d[df_d["status"].astype(str).str.strip() == "INCOMPLETE"])
    today_str = gs.today_str()
    aaj_peshi = len(df_s[df_s["अगली तारीख पेशी"].astype(str).str.strip() == today_str])
    addr_total = len(df_addr[df_addr["नाम"].astype(str).str.strip() != ""])

    c1.metric("कुल मुकदमे", total)
    c2.metric("साक्ष्य stage", sakshya)
    c3.metric("समन बनाने हैं", pending_samman, delta=f"बनाना है")
    c4.metric("Dak Pending", dak_incomplete)
    c5.metric("आज की पेशी", aaj_peshi)
    c6.metric("📇 Address Book", addr_total)

    # ── ⚠️ Overdue केस हाइलाइट ───────────────────────────────────────────────
    today_dt_check = datetime.strptime(today_str, '%d/%m/%Y')

    def _is_overdue(v):
        d = kg.parse_date(v)
        return d is not None and d < today_dt_check

    overdue_df = df_s[df_s["अगली तारीख पेशी"].apply(_is_overdue)]
    if not overdue_df.empty:
        st.error(f"⚠️ **{len(overdue_df)} मुकदमों की तारीख पेशी निकल चुकी है** — status/अगली तारीख अपडेट करना बाकी है")
        with st.expander("देखें कौन-कौन से मुकदमे", expanded=False):
            st.dataframe(
                overdue_df[["ST NO", "बनाम", "न्यायालय", "Status", "अगली तारीख पेशी"]]
                .sort_values(by="अगली तारीख पेशी", key=lambda c: c.map(lambda x: kg.parse_date(x) or datetime.max)),
                use_container_width=True, hide_index=True
            )

    st.divider()

    # ── 📇 Address Book ──────────────────────────────────────────────────────
    with st.expander(f"📇 Address Book खोलें / खोजें ({addr_total} entries)", expanded=False):
        if df_addr.empty:
            st.info("Address Book में कोई entry नहीं मिली (या 'Address Book' शीट नहीं मिली)।")
        else:
            addr_q = st.text_input("🔍 नाम / विभाग से खोजें", placeholder="जैसे: राम या पुलिस अधीक्षक",
                                   key="addr_search")
            addr_view = df_addr
            if addr_q:
                addr_view = df_addr[
                    df_addr["नाम"].astype(str).str.contains(addr_q, case=False, na=False) |
                    df_addr["विभाग"].astype(str).str.contains(addr_q, case=False, na=False)
                ]
            if addr_view.empty:
                st.info("कोई मिलान नहीं मिला।")
            else:
                st.caption(f"{len(addr_view)} entries")
                addr_cards = []
                for _, r in addr_view.iterrows():
                    icon   = dept_icon(r["विभाग"])
                    mobile = str(r["मोबाइल"]).strip()
                    call_html = (f'<a class="addr-call" href="tel:{mobile}">📞 कॉल</a>'
                                 if mobile else "")
                    wa_url = "https://wa.me/?text=" + urllib.parse.quote(build_addr_share_text(r.to_dict()))
                    share_html = f'<a class="addr-share" href="{wa_url}" target="_blank">🟢 शेयर</a>'
                    addr_cards.append(f"""<div class="addr-card">
  <div class="addr-card-top">
    <span class="addr-icon">{icon}</span>
    <span class="addr-name">{r['नाम'] or '—'}</span>
  </div>
  <div class="addr-dept">🏢 {r['विभाग'] or '—'}</div>
  <div class="addr-address">📍 {r['पता'] or '—'}</div>
  <div class="addr-actions">{call_html}{share_html}</div>
</div>""")
                st.markdown("".join(addr_cards), unsafe_allow_html=True)

    st.divider()

    col1, col2 = st.columns(2)

    # ── Status chart ─────────────────────────────────────────────────────────
    with col1:
        st.subheader("📌 Status-wise मुकदमे")
        status_count = df_s[df_s["Status"] != ""]["Status"].value_counts().reset_index()
        status_count.columns = ["Status", "Count"]
        st.dataframe(status_count, use_container_width=True, hide_index=True)

    # ── आज की पेशी ───────────────────────────────────────────────────────────
    with col2:
        st.subheader(f"📅 आज की पेशी ({today_str})")
        aaj = df_s[df_s["अगली तारीख पेशी"].astype(str).str.strip() == today_str]
        if aaj.empty:
            st.info("आज कोई पेशी नहीं।")
        else:
            cards = []
            for _, r in aaj.iterrows():
                cards.append(f"""<div class="case-card">
  <div class="case-card-top">
    <span class="case-st">ST NO: {r['ST NO']}</span>
    <span class="case-status">{r['Status'] or '—'}</span>
  </div>
  <div class="case-banam">बनाम: {r['बनाम'] or '—'}</div>
  <div class="case-court">🏛️ {r['न्यायालय'] or '—'}</div>
  <div class="case-witness">👤 {r['तलब साक्षी'] or '—'}</div>
</div>""")
            st.markdown("".join(cards), unsafe_allow_html=True)

    st.divider()

    # ── आने वाली पेशियां (अगले 7 दिन) ────────────────────────────────────────
    st.subheader("🗓️ आने वाली पेशियां (अगले 7 दिन)")
    from datetime import timedelta

    def _parse_date(s):
        s = str(s).strip()
        for fmt in ('%d/%m/%Y', '%d-%m-%Y', '%Y-%m-%d'):
            try:
                return datetime.strptime(s, fmt)
            except Exception:
                pass
        return None

    today_dt = datetime.strptime(today_str, '%d/%m/%Y')
    upcoming_rows = []
    for _, r in df_s.iterrows():
        d = _parse_date(r["अगली तारीख पेशी"])
        if d and today_dt < d <= today_dt + timedelta(days=7):
            upcoming_rows.append(r)

    if not upcoming_rows:
        st.info("अगले 7 दिन में कोई पेशी नहीं।")
    else:
        upcoming_df = pd.DataFrame(upcoming_rows).sort_values(
            by="अगली तारीख पेशी",
            key=lambda col: col.map(lambda x: _parse_date(x) or datetime.max)
        )
        st.dataframe(
            upcoming_df[["ST NO", "बनाम", "न्यायालय", "Status", "अगली तारीख पेशी"]],
            use_container_width=True, hide_index=True
        )

    st.divider()

    # ── Pending समन ──────────────────────────────────────────────────────────
    st.subheader("🖨️ समन बनाने हैं")
    pending = df_s[df_s["सम्मन की स्थिति"].astype(str).str.strip() == "बनाना है"]
    if pending.empty:
        st.success("कोई समन pending नहीं।")
    else:
        st.dataframe(
            pending[["ST NO", "बनाम", "न्यायालय", "तलब साक्षी", "अगली तारीख पेशी"]],
            use_container_width=True, hide_index=True
        )


# ══════════════════════════════════════════════════════════════════════════════
# 2. SESSION COURT LIST
# ══════════════════════════════════════════════════════════════════════════════
elif page == "📋 सेशन कोर्ट":
    st.header("📋 सेशन कोर्ट — केस लिस्ट")

    df = gs.load_session()
    if df.empty:
        st.warning("Data नहीं मिला।")
        st.stop()

    # ── Filters ──────────────────────────────────────────────────────────────
    f1, f2, f3, f4 = st.columns(4)
    with f1:
        search = st.text_input("🔍 खोजें", placeholder="नाम / ST NO / धारा")
    with f2:
        status_f = st.selectbox("Status", ["सभी"] + gs.STATUS_OPTIONS)
    with f3:
        ny_f = st.selectbox("न्यायालय", ["सभी"] + gs.NYAYALAYA_OPTIONS)
    with f4:
        samman_f = st.selectbox("सम्मन स्थिति", ["सभी"] + gs.SAMMAN_OPTIONS)

    # Apply filters
    filtered = df[df["ST NO"].astype(str).str.strip() != ""].copy()
    if search:
        mask = filtered.apply(lambda r: search.lower() in " ".join(r.astype(str)).lower(), axis=1)
        filtered = filtered[mask]
    if status_f != "सभी":
        filtered = filtered[filtered["Status"] == status_f]
    if ny_f != "सभी":
        filtered = filtered[filtered["न्यायालय"].str.contains(ny_f, na=False)]
    if samman_f != "सभी":
        filtered = filtered[filtered["सम्मन की स्थिति"].astype(str).str.strip() == samman_f]

    st.caption(f"दिख रहे हैं: **{len(filtered)}** / कुल {len(df)} मुकदमे")

    # Show table
    show_cols = ["ST NO", "मु0अ0स0", "धारा", "बनाम", "न्यायालय",
                 "तलब साक्षी", "अगली तारीख पेशी", "Status", "सम्मन की स्थिति", "कृत कार्यवाही"]
    st.dataframe(filtered[show_cols], use_container_width=True,
                 hide_index=True, height=500)

    # Download
    buf = __import__('io').BytesIO()
    filtered.to_excel(buf, index=False)
    buf.seek(0)
    st.download_button("⬇️ Excel डाउनलोड", buf, file_name="session_filtered.xlsx",
                       mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

    # ── किसी एक केस को शेयर करें ────────────────────────────────────────────
    st.divider()
    st.subheader("📤 किसी एक केस को शेयर करें")
    if not filtered.empty:
        share_options = filtered["ST NO"].astype(str).tolist()
        share_st_no = st.selectbox("ST NO चुनें", share_options, key="share_select")
        share_row = filtered[filtered["ST NO"].astype(str) == share_st_no].iloc[0]
        render_share_block(share_row.to_dict(), key_prefix="list")


# ══════════════════════════════════════════════════════════════════════════════
# 3. नया केस
# ══════════════════════════════════════════════════════════════════════════════
elif page == "➕ नया केस":
    st.header("➕ नया केस जोड़ें")

    with st.form("new_case"):
        c1, c2 = st.columns(2)
        with c1:
            st_no    = st.text_input("ST NO *", placeholder="जैसे: 193/2025")
            mu_apradh= st.text_input("मु0अ0स0", placeholder="जैसे: 691/2017")
            dhara    = st.text_input("धारा", placeholder="जैसे: 8/20 NDPS ACT")
            banam    = st.text_input("बनाम (अभियुक्त का नाम) *")
            nyayalaya= st.selectbox("न्यायालय", gs.NYAYALAYA_OPTIONS)
            status   = st.selectbox("Status", gs.STATUS_OPTIONS)
        with c2:
            saakshi  = st.text_area("तलब साक्षी (नाम पता)", height=80,
                                     placeholder="BW / NBW prefix लगाएं अगर वारंट हो")
            pichli   = st.text_input("पिछली पेशी (DD/MM/YYYY)")
            agli     = st.text_input("अगली तारीख पेशी (DD/MM/YYYY) *")
            samman_st= st.selectbox("सम्मन की स्थिति", gs.SAMMAN_OPTIONS)
            kul_gawah= st.text_input("कुल गवाह", placeholder="जैसे: 5/2/3")
            fir_date = st.text_input("FIR दिनांक")
            krit_karya= st.text_input("कृत कार्यवाही")

        submitted = st.form_submit_button("✅ केस जोड़ें (Sheet में save होगा)",
                                          use_container_width=True, type="primary")
        if submitted:
            if not st_no or not banam or not agli:
                st.error("ST NO, बनाम और अगली तारीख पेशी ज़रूरी हैं।")
            else:
                existing_df = gs.load_session()
                dup = existing_df[existing_df["ST NO"].astype(str).str.strip() == st_no.strip()]
                if not dup.empty:
                    dup_row = dup.iloc[0]
                    st.error(
                        f"⚠️ ST NO **{st_no}** पहले से मौजूद है! "
                        f"(बनाम: {dup_row['बनाम']}, न्यायालय: {dup_row['न्यायालय']}, "
                        f"Status: {dup_row['Status']}). कृपया ST NO चेक करें या "
                        f"'केस अपडेट' पेज से मौजूदा केस को अपडेट करें।"
                    )
                else:
                    row = {
                        "ST NO": st_no, "मु0अ0स0": mu_apradh, "धारा": dhara,
                        "बनाम": banam, "न्यायालय": nyayalaya, "तलब साक्षी": saakshi,
                        "पिछली पेशी": pichli, "अगली तारीख पेशी": agli,
                        "Status": status, "सम्मन की स्थिति": samman_st,
                        "कुल गवाह": kul_gawah, "Fir दिनांक": fir_date,
                        "कृत कार्यवाही": krit_karya
                    }
                    if gs.append_row_session(row):
                        st.success(f"✅ केस जोड़ा गया! ST NO: {st_no}")


# ══════════════════════════════════════════════════════════════════════════════
# 4. केस अपडेट
# ══════════════════════════════════════════════════════════════════════════════
elif page == "✏️ केस अपडेट":
    st.header("✏️ केस अपडेट करें")

    df = gs.load_session()
    if df.empty:
        st.warning("Data नहीं मिला।")
        st.stop()

    # Search
    st_no_input = st.text_input("🔍 ST NO डालें", placeholder="जैसे: 193/2025")

    case_row = None
    if st_no_input:
        match = df[df["ST NO"].astype(str).str.strip() == st_no_input.strip()]
        if not match.empty:
            case_row = match.iloc[0]
            st.success(f"मिला: **राज्य बनाम {case_row['बनाम']}** | {case_row['न्यायालय']}")
            render_share_block(case_row.to_dict())
        else:
            st.error("ST NO नहीं मिला।")

    if case_row is not None:
        st.divider()
        with st.form("update_case"):
            c1, c2 = st.columns(2)
            with c1:
                new_status   = st.selectbox("Status", gs.STATUS_OPTIONS,
                    index=gs.STATUS_OPTIONS.index(case_row["Status"]) if case_row["Status"] in gs.STATUS_OPTIONS else 0)
                new_saakshi  = st.text_area("तलब साक्षी", value=case_row["तलब साक्षी"], height=80)
                new_agli     = st.text_input("अगली तारीख पेशी", value=case_row["अगली तारीख पेशी"])
                new_pichli   = st.text_input("पिछली पेशी", value=case_row["पिछली पेशी"])
            with c2:
                new_samman   = st.selectbox("सम्मन की स्थिति", gs.SAMMAN_OPTIONS,
                    index=gs.SAMMAN_OPTIONS.index(case_row["सम्मन की स्थिति"]) if case_row["सम्मन की स्थिति"] in gs.SAMMAN_OPTIONS else 0)
                new_krit     = st.text_input("कृत कार्यवाही", value=case_row["कृत कार्यवाही"])
                new_gawah    = st.text_input("कुल गवाह", value=case_row["कुल गवाह"])
                new_thana_date = st.text_input("थाने पर देने का दिनाँक", value=case_row["थाने पर देने का दिनाँक"])

            save = st.form_submit_button("💾 अपडेट करें (Sheet में save होगा)",
                                         use_container_width=True, type="primary")
            if save:
                updates = {
                    "Status": new_status,
                    "तलब साक्षी": new_saakshi,
                    "अगली तारीख पेशी": new_agli,
                    "पिछली पेशी": new_pichli,
                    "सम्मन की स्थिति": new_samman,
                    "कृत कार्यवाही": new_krit,
                    "कुल गवाह": new_gawah,
                    "थाने पर देने का दिनाँक": new_thana_date,
                }
                if gs.update_row_session(st_no_input.strip(), updates):
                    st.success("✅ अपडेट हो गया!")


# ══════════════════════════════════════════════════════════════════════════════
# 5. समन जनरेटर
# ══════════════════════════════════════════════════════════════════════════════
elif page == "🖨️ समन जनरेटर":
    st.header("🖨️ समन जनरेटर")
    st.caption("सम्मन की स्थिति = **'बनाना है'** वाले cases का समन बनेगा")

    df = gs.load_session()
    if df.empty:
        st.warning("Data नहीं मिला।")
        st.stop()

    pending = df[df["सम्मन की स्थिति"].astype(str).str.strip() == "बनाना है"]
    st.info(f"**{len(pending)}** मुकदमों का समन बनना है")

    if not pending.empty:
        st.dataframe(
            pending[["ST NO", "बनाम", "न्यायालय", "तलब साक्षी", "अगली तारीख पेशी"]],
            use_container_width=True, hide_index=True
        )

    st.divider()

    # Date filter
    dates = ["सभी"] + sorted(df["अगली तारीख पेशी"].astype(str).unique().tolist())
    sel_date = st.selectbox("किस तारीख की पेशी का समन बनाएं?", dates)

    gen_df = pending.copy()
    if sel_date != "सभी":
        gen_df = pending[pending["अगली तारीख पेशी"].astype(str).str.strip() == sel_date]
    st.caption(f"{len(gen_df)} rows select")

    col1, col2 = st.columns(2)
    with col1:
        auto_update = st.checkbox("Generate के बाद status → 'ISSUED' करें", value=True)

    if st.button("🖨️ समन Generate करें", type="primary",
                 use_container_width=True, disabled=gen_df.empty):
        html, st_nos = sg.generate_html(gen_df, JANPAD)
        if html is None:
            st.warning("कोई pending समन नहीं।")
        else:
            st.success(f"✅ {len(st_nos)} मुकदमों का समन तैयार!")
            today = datetime.today().strftime('%d-%m-%Y')
            st.download_button(
                "⬇️ समन HTML डाउनलोड करें (Browser से Print/PDF करें)",
                data=html.encode("utf-8"),
                file_name=f"समन_{today}.html",
                mime="text/html",
                use_container_width=True,
            )
            st.info("📌 File download करें → Chrome में खोलें → Ctrl+P → Save as PDF → Landscape")

            # Auto status update
            if auto_update and st_nos:
                with st.spinner("Status update हो रहा है..."):
                    success_count = 0
                    for st_no in st_nos:
                        if gs.update_cell_session(st_no, "सम्मन की स्थिति", "ISSUED"):
                            success_count += 1
                    st.success(f"✅ {success_count} cases की status → ISSUED")


# ══════════════════════════════════════════════════════════════════════════════
# 5b. कृत कार्यवाही रिपोर्ट
# ══════════════════════════════════════════════════════════════════════════════
elif page == "📝 कृत कार्यवाही रिपोर्ट":
    st.header("📝 कृत कार्यवाही रिपोर्ट")
    st.caption("किसी दिनांक या धारा (कलम) के आधार पर मुकदमों की कृत कार्यवाही की printable रिपोर्ट बनाएं")

    df = gs.load_session()
    if df.empty:
        st.warning("Data नहीं मिला।")
        st.stop()

    mode = st.radio("किस आधार पर रिपोर्ट बनानी है?",
                     ["📅 दिनांक (तारीख पेशी) से", "📖 धारा / कलम से"],
                     horizontal=True)

    filtered = pd.DataFrame()
    sub_heading = ""

    if mode == "📅 दिनांक (तारीख पेशी) से":
        c1, c2 = st.columns(2)
        with c1:
            range_mode = st.checkbox("दिनांक रेंज चुनें (from - to)", value=False)
        if range_mode:
            c1, c2 = st.columns(2)
            with c1:
                from_date = st.date_input("से (From)")
            with c2:
                to_date = st.date_input("तक (To)")
            from_s, to_s = from_date.strftime('%d/%m/%Y'), to_date.strftime('%d/%m/%Y')

            def _in_range(v):
                d = kg.parse_date(v)
                return d is not None and from_date <= d.date() <= to_date.date()

            filtered = df[df["अगली तारीख पेशी"].apply(_in_range)]
            sub_heading = f"दिनांक: {from_s} से {to_s} तक"
        else:
            sel_date = st.date_input("तारीख पेशी चुनें")
            sel_date_s = sel_date.strftime('%d/%m/%Y')
            filtered = df[df["अगली तारीख पेशी"].apply(
                lambda v: kg.fmt_date(v) == sel_date_s)]
            sub_heading = f"दिनांक: {sel_date_s}"

    else:  # धारा / कलम से
        keyword = st.text_input("धारा / कलम खोजें", placeholder="जैसे: 323 या POCSO या NDPS")
        if keyword:
            filtered = df[df["धारा"].astype(str).str.contains(keyword, case=False, na=False)]
            sub_heading = f"धारा / कलम: {keyword}"

    if not filtered.empty:
        st.caption(f"मिले: **{len(filtered)}** मुकदमे")
        st.dataframe(
            filtered[["ST NO", "मु0अ0स0", "धारा", "बनाम", "न्यायालय",
                     "तलब साक्षी", "अगली तारीख पेशी", "कृत कार्यवाही"]],
            use_container_width=True, hide_index=True
        )
        est_pages = "1 पेज" if len(filtered) <= 50 else ("~2 पेज" if len(filtered) <= 130 else "2+ पेज (filter और सीमित करें)")
        st.caption(f"अनुमानित प्रिंट साइज़: {est_pages} (font अपने-आप छोटा होकर fit होगा)")

        if st.button("📝 रिपोर्ट Generate करें", type="primary", use_container_width=True):
            html = kg.generate_karyawahi_html(filtered, JANPAD, THANA, sub_heading)
            if html is None:
                st.warning("कोई data नहीं मिला।")
            else:
                st.success("✅ रिपोर्ट तैयार!")
                today = datetime.today().strftime('%d-%m-%Y')
                st.download_button(
                    "⬇️ रिपोर्ट HTML डाउनलोड करें (Browser से Print/PDF करें)",
                    data=html.encode("utf-8"),
                    file_name=f"कृत_कार्यवाही_{today}.html",
                    mime="text/html",
                    use_container_width=True,
                )
                st.info("📌 File download करें → Chrome में खोलें → Ctrl+P → Save as PDF → Landscape")
    else:
        st.info("ऊपर दिनांक या धारा चुनें, मिलान वाले मुकदमे यहां दिखेंगे।")


# ══════════════════════════════════════════════════════════════════════════════
# 6. DAK REGISTER
# ══════════════════════════════════════════════════════════════════════════════
elif page == "📬 Dak Register":
    st.header("📬 Dak Register")

    tab1, tab2 = st.tabs(["📋 List / Update", "➕ नई Entry"])

    with tab1:
        df_d = gs.load_dak()
        if df_d.empty:
            st.info("कोई entry नहीं।")
        else:
            f1, f2, f3 = st.columns(3)
            with f1:
                type_f = st.selectbox("Type", ["सभी"] + gs.DAK_TYPE_OPTIONS)
            with f2:
                status_f = st.selectbox("Status", ["सभी", "INCOMPLETE", "COMPLETE"])
            with f3:
                date_f = st.text_input("तारीख़ पेशी से filter (DD/MM/YYYY)",
                                        placeholder="जैसे: 10/07/2026 या सिर्फ 07/2026")

            filtered = df_d.copy()
            if type_f != "सभी":
                filtered = filtered[filtered["Type"] == type_f]
            if status_f != "सभी":
                filtered = filtered[filtered["status"] == status_f]
            if date_f:
                filtered = filtered[filtered["तारीख़ पेशी"].astype(str)
                                     .str.contains(date_f, case=False, na=False)]

            st.caption(f"{len(filtered)} entries")
            st.dataframe(
                filtered, use_container_width=True, hide_index=True, height=400,
                column_config={
                    "लिंक": st.column_config.LinkColumn("लिंक", display_text="🔗 खोलें")
                }
            )

            # ── 📄 INCOMPLETE Dak को थाने भेजने के लिए HTML रिपोर्ट ───────────
            st.divider()
            st.subheader("📄 थाने भेजने हेतु HTML रिपोर्ट")
            incomplete_df = filtered[filtered["status"].astype(str).str.strip() == "INCOMPLETE"]
            if incomplete_df.empty:
                st.success("✅ चुने हुए filter में कोई INCOMPLETE dak नहीं।")
            else:
                st.caption(f"**{len(incomplete_df)}** entries अभी INCOMPLETE हैं (ऊपर के filter अनुसार)")
                if st.button("📄 INCOMPLETE Dak की HTML रिपोर्ट बनाएं",
                             use_container_width=True, type="primary"):
                    html = dg.generate_dak_html(incomplete_df, JANPAD, THANA, status="INCOMPLETE")
                    if html is None:
                        st.warning("कोई data नहीं मिला।")
                    else:
                        st.success("✅ रिपोर्ट तैयार!")
                        today = datetime.today().strftime('%d-%m-%Y')
                        st.download_button(
                            "⬇️ रिपोर्ट HTML डाउनलोड करें (थाने भेजने के लिए Print/PDF करें)",
                            data=html.encode("utf-8"),
                            file_name=f"Dak_INCOMPLETE_{today}.html",
                            mime="text/html",
                            use_container_width=True,
                        )
                        st.info("📌 File download करें → Chrome में खोलें → Ctrl+P → Save as PDF → थाने भेजें")

            # Status update
            st.divider()
            st.subheader("✅ Status Update (INCOMPLETE → COMPLETE)")
            row_num = st.number_input("Row number (1 = पहली data row)", min_value=1, step=1)
            new_st = st.selectbox("नया Status", ["COMPLETE", "INCOMPLETE"])
            if st.button("Status Update करें", type="primary"):
                if gs.update_dak_status(int(row_num), new_st):
                    st.success(f"Row {row_num} → {new_st}")

    with tab2:
        st.subheader("➕ नई Dak Entry")
        with st.form("new_dak"):
            c1, c2 = st.columns(2)
            with c1:
                stn      = st.text_input("STN (ST NO)", placeholder="जैसे: 193/2025")
                banam    = st.text_input("बनाम")
                dak_type = st.selectbox("Type", gs.DAK_TYPE_OPTIONS)
                naam_pata= st.text_area("नाम पता", height=80)
                thana    = st.text_input("संबंधित थाना", placeholder="जैसे: कोतवाली भिंगा जनपद श्रावस्ती")
            with c2:
                court    = st.text_input("कोर्ट का नाम", placeholder="जैसे: ASJ")
                thane_date = st.text_input("थाने पर लाने का दिनांक (DD/MM/YYYY)")
                peshi_date = st.text_input("तारीख़ पेशी (DD/MM/YYYY)")
                remark   = st.text_input("रिमार्क")
                link     = st.text_input("Google Drive Link (document)")

            sub = st.form_submit_button("✅ Entry जोड़ें", use_container_width=True, type="primary")
            if sub:
                if not banam or not dak_type:
                    st.error("बनाम और Type ज़रूरी हैं।")
                else:
                    row = {
                        "STN": stn, "बनाम": banam, "status": "INCOMPLETE",
                        "Type": dak_type, "नाम पता": naam_pata,
                        "संबंधित थाना": thana, "कोर्ट का नाम": court,
                        "थाने पर लाने का दिनांक": thane_date,
                        "तारीख़ पेशी": peshi_date, "रिमार्क": remark, "लिंक": link
                    }
                    if gs.append_row_dak(row):
                        st.success("✅ Dak entry जोड़ी गई!")


# ══════════════════════════════════════════════════════════════════════════════
# 7. RIMAND REGISTER
# ══════════════════════════════════════════════════════════════════════════════
elif page == "🔒 Rimand Register":
    st.header("🔒 Rimand Register")

    tab1, tab2 = st.tabs(["📋 List", "➕ नई Entry"])

    with tab1:
        df_r = gs.load_rimand()
        if df_r.empty:
            st.info("कोई रिमांड entry नहीं।")
        else:
            st.dataframe(df_r, use_container_width=True,
                         hide_index=True, height=400)

            st.divider()
            st.subheader("📤 रिमांड एंट्री शेयर करें")
            options = [
                f"{i+1}. {r['मु0अ0स0'] or '—'} — {str(r['नाम पता अभियुक्त'])[:30] or '—'}"
                for i, r in df_r.iterrows()
            ]
            sel = st.selectbox("शेयर के लिए Entry चुनें", options, key="rimand_share_sel")
            sel_idx = options.index(sel)
            render_rimand_share_block(df_r.iloc[sel_idx].to_dict(), key_prefix="rimandlist")

    with tab2:
        st.subheader("➕ नई रिमांड Entry")
        with st.form("new_rimand"):
            c1, c2 = st.columns(2)
            with c1:
                rimand_date = st.text_input("रिमांड Date (DD/MM/YYYY)",
                                             value=gs.today_str())
                mu_apradh   = st.text_input("मु0अ0स0")
                dhara       = st.text_input("धारा")
            with c2:
                court       = st.text_input("कोर्ट")
                io_name     = st.text_input("IO (विवेचक)")
                first_date  = st.text_input("First रिमांड डेट")
                naam_pata   = st.text_area("नाम पता अभियुक्त", height=80)

            sub = st.form_submit_button("✅ Entry जोड़ें",
                                         use_container_width=True, type="primary")
            if sub:
                if not mu_apradh:
                    st.error("मु0अ0स0 ज़रूरी है।")
                else:
                    row = {
                        "रिमांड Date": rimand_date, "मु0अ0स0": mu_apradh,
                        "धारा": dhara, "कोर्ट": court, "IO": io_name,
                        "First रिमांड डेट": first_date,
                        "नाम पता अभियुक्त": naam_pata
                    }
                    if gs.append_row_rimand(row):
                        st.success("✅ रिमांड entry जोड़ी गई!")

