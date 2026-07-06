"""
⚖️ Court Case Manager
- Google Sheet से case data पढ़ना/लिखना
- नया case जोड़ना, नया column जोड़ना
- Bulk समन/वारंट DOCX generate करना
"""
import streamlit as st
import pandas as pd
import json
import io
from datetime import datetime

st.set_page_config(page_title="Court Case Manager", page_icon="⚖️", layout="wide")

# ── Google Sheets connection ─────────────────────────────────────────────────
def get_gsheet_client():
    try:
        import gspread
        from google.oauth2.service_account import Credentials
        creds_dict = json.loads(st.secrets["GOOGLE_CREDENTIALS"])
        creds = Credentials.from_service_account_info(
            creds_dict,
            scopes=["https://spreadsheets.google.com/feeds",
                    "https://www.googleapis.com/auth/drive"]
        )
        return gspread.authorize(creds)
    except Exception as e:
        st.error(f"Google Sheets connection failed: {e}")
        return None


@st.cache_data(ttl=60)
def load_sheet(sheet_url: str, worksheet_name: str = None):
    """Sheet से data load करता है — 60 sec cache"""
    client = get_gsheet_client()
    if not client: return pd.DataFrame()
    try:
        sh = client.open_by_url(sheet_url)
        ws = sh.worksheet(worksheet_name) if worksheet_name else sh.get_worksheet(0)
        data = ws.get_all_records()
        return pd.DataFrame(data).fillna("")
    except Exception as e:
        st.error(f"Sheet load error: {e}")
        return pd.DataFrame()


def append_row(sheet_url: str, row_data: dict, worksheet_name: str = None):
    """Sheet में नई row जोड़ता है"""
    client = get_gsheet_client()
    if not client: return False
    try:
        sh = client.open_by_url(sheet_url)
        ws = sh.worksheet(worksheet_name) if worksheet_name else sh.get_worksheet(0)
        headers = ws.row_values(1)
        new_row = [str(row_data.get(h, "")) for h in headers]
        ws.append_row(new_row)
        return True
    except Exception as e:
        st.error(f"Row append error: {e}")
        return False


def add_column(sheet_url: str, col_name: str, worksheet_name: str = None):
    """Sheet में नया column जोड़ता है"""
    client = get_gsheet_client()
    if not client: return False
    try:
        sh = client.open_by_url(sheet_url)
        ws = sh.worksheet(worksheet_name) if worksheet_name else sh.get_worksheet(0)
        headers = ws.row_values(1)
        if col_name in headers:
            return "exists"
        next_col = len(headers) + 1
        ws.update_cell(1, next_col, col_name)
        return True
    except Exception as e:
        st.error(f"Column add error: {e}")
        return False


# ── Session state init ────────────────────────────────────────────────────────
if "sheet_url" not in st.session_state:
    st.session_state.sheet_url = st.secrets.get("DEFAULT_SHEET_URL", "")
if "ws_name" not in st.session_state:
    st.session_state.ws_name = ""

# ── Sidebar ──────────────────────────────────────────────────────────────────
with st.sidebar:
    st.title("⚖️ Court Case Manager")
    st.divider()

    st.subheader("🔗 Google Sheet")
    sheet_url = st.text_input("Sheet URL", value=st.session_state.sheet_url,
                               placeholder="https://docs.google.com/spreadsheets/d/...")
    ws_name = st.text_input("Worksheet नाम (खाली = पहली sheet)",
                             value=st.session_state.ws_name,
                             placeholder="जैसे: पैरवी रजिस्टर")
    janpad = st.text_input("जनपद", value=st.secrets.get("DEFAULT_JANPAD", "श्रावस्ती"))

    if sheet_url:
        st.session_state.sheet_url = sheet_url
        st.session_state.ws_name = ws_name

    st.divider()
    page = st.radio("📌 पेज", ["📋 केस लिस्ट", "➕ नया केस जोड़ें",
                                 "🖨️ समन जनरेटर", "⚙️ Column जोड़ें"])

# ── Main area ────────────────────────────────────────────────────────────────

def load_data():
    if not st.session_state.sheet_url:
        st.warning("Sidebar में Google Sheet URL डालें।")
        return pd.DataFrame()
    ws = st.session_state.ws_name or None
    return load_sheet(st.session_state.sheet_url, ws)


# ══ Page 1: Case List ════════════════════════════════════════════════════════
if page == "📋 केस लिस्ट":
    st.header("📋 केस लिस्ट")

    col_refresh, col_search, col_filter = st.columns([1, 3, 2])
    with col_refresh:
        if st.button("🔄 Refresh", use_container_width=True):
            st.cache_data.clear()

    df = load_data()
    if df.empty:
        st.info("Sheet से data नहीं मिला।")
        st.stop()

    with col_search:
        search = st.text_input("🔍 खोजें (नाम / ST NO / धारा)", "")
    with col_filter:
        if "अगली तारीख पेशी" in df.columns:
            dates = ["सभी तारीखें"] + sorted(df["अगली तारीख पेशी"].unique().tolist())
            date_filter = st.selectbox("तारीख से फ़िल्टर", dates)
        else:
            date_filter = "सभी तारीखें"

    # Apply filters
    filtered = df.copy()
    if search:
        mask = filtered.apply(
            lambda r: search.lower() in " ".join(r.astype(str)).lower(), axis=1)
        filtered = filtered[mask]
    if date_filter != "सभी तारीखें" and "अगली तारीख पेशी" in filtered.columns:
        filtered = filtered[filtered["अगली तारीख पेशी"] == date_filter]

    st.caption(f"कुल {len(filtered)} / {len(df)} केस")
    st.dataframe(filtered, use_container_width=True, height=500)

    # Download filtered as Excel
    buf = io.BytesIO()
    filtered.to_excel(buf, index=False)
    buf.seek(0)
    st.download_button("⬇️ Filtered Excel डाउनलोड करें", buf,
                       file_name="filtered_cases.xlsx",
                       mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")


# ══ Page 2: नया केस जोड़ें ════════════════════════════════════════════════════
elif page == "➕ नया केस जोड़ें":
    st.header("➕ नया केस जोड़ें")

    df = load_data()
    if df.empty:
        st.info("पहले Sheet URL डालें।")
        st.stop()

    cols = list(df.columns)
    st.caption(f"Sheet के columns: {', '.join(cols)}")

    with st.form("add_case_form"):
        st.subheader("केस की जानकारी भरें")
        field_values = {}
        # 2 columns में form fields
        half = len(cols) // 2 + len(cols) % 2
        fc1, fc2 = st.columns(2)
        for i, col in enumerate(cols):
            with fc1 if i < half else fc2:
                # Smart defaults
                default = ""
                if col == "अगली तारीख पेशी":
                    default = datetime.today().strftime('%d/%m/%Y')
                elif col == "न्यायालय":
                    default = "ASJ"
                field_values[col] = st.text_input(col, value=default, key=f"new_{col}")

        submitted = st.form_submit_button("✅ केस जोड़ें (Sheet में save होगा)",
                                          use_container_width=True, type="primary")
        if submitted:
            st.no = field_values.get("ST NO", "")
            if not st.no:
                st.error("ST NO ज़रूरी है।")
            else:
                with st.spinner("Sheet में save हो रहा है..."):
                    ws = st.session_state.ws_name or None
                    ok = append_row(st.session_state.sheet_url, field_values, ws)
                if ok:
                    st.success(f"✅ केस जोड़ा गया! ST NO: {field_values.get('ST NO','')}")
                    st.cache_data.clear()
                else:
                    st.error("Sheet में save नहीं हो सका।")


# ══ Page 3: समन जनरेटर ════════════════════════════════════════════════════════
elif page == "🖨️ समन जनरेटर":
    st.header("🖨️ समन / वारंट जनरेटर")

    with st.expander("📋 तलब साक्षी column में prefix कैसे लिखें"):
        st.markdown("""
| prefix | document type |
|---|---|
| `रामलाल थाना xyz` | साधारण **समन** |
| `BW रामलाल थाना xyz` | **जमानती वारंट (BW)** |
| `NBW रामलाल थाना xyz` | **गैर जमानती वारंट (NBW)** |
| `MRITYU कोई नहीं` | **मृत्यु आख्या** |

एक row में कई साक्षी — comma से अलग करें।  
VC लेटर के लिए Sheet में "VC" नाम की अलग sheet बनाएं।
        """)

    st.divider()
    source = st.radio("Data कहाँ से लें?",
                      ["Google Sheet से (live)", "Excel file upload करें"],
                      horizontal=True)

    df_main = pd.DataFrame()
    df_vc   = None

    if source == "Google Sheet से (live)":
        col1, col2 = st.columns([3, 1])
        with col1:
            if st.button("🔄 Sheet से load करें", use_container_width=True):
                st.cache_data.clear()
        with col2:
            if st.button("Refresh", use_container_width=True):
                st.cache_data.clear()

        df_main = load_data()
        if not df_main.empty:
            st.success(f"✅ {len(df_main)} rows मिली")
            st.dataframe(df_main.head(5), use_container_width=True)

    else:
        uploaded = st.file_uploader("📂 Excel अपलोड करें (.xlsx)", type=["xlsx"])
        if uploaded:
            xls = pd.ExcelFile(io.BytesIO(uploaded.read()))
            df_main = pd.read_excel(xls, sheet_name=0).fillna("")
            if "VC" in xls.sheet_names:
                df_vc = pd.read_excel(xls, sheet_name="VC").fillna("")
            st.success(f"✅ {len(df_main)} rows मिली")
            st.dataframe(df_main.head(5), use_container_width=True)

    st.divider()

    # Date filter for summon generation
    if not df_main.empty and "अगली तारीख पेशी" in df_main.columns:
        dates = ["सभी तारीखें"] + sorted(df_main["अगली तारीख पेशी"].unique().tolist())
        sel_date = st.selectbox("किस तारीख के केस का समन बनाएं?", dates)
        if sel_date != "सभी तारीखें":
            df_main = df_main[df_main["अगली तारीख पेशी"] == sel_date]
        st.caption(f"{len(df_main)} rows select हुईं")

    if not df_main.empty:
        if st.button("🖨️ सभी समन Generate करें", use_container_width=True, type="primary"):
            from bulk_generator import generate_bulk
            import re

            def clean_col(name):
                return re.sub(r'\s+', ' ', str(name)).strip()

            df_main = df_main.rename(columns=clean_col)
            if df_vc is not None:
                df_vc = df_vc.rename(columns=clean_col)

            with st.spinner("दस्तावेज़ बन रहे हैं..."):
                try:
                    docx_bytes = generate_bulk(df_main, janpad, df_vc)
                    st.success("✅ दस्तावेज़ तैयार!")
                    st.download_button(
                        "⬇️ समन_दस्तावेज़.docx डाउनलोड करें",
                        data=docx_bytes,
                        file_name=f"समन_{datetime.today().strftime('%d-%m-%Y')}.docx",
                        mime="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                        use_container_width=True,
                    )
                except ValueError as ve:
                    st.error(f"❌ Column मिसिंग: {ve}")
                except Exception as e:
                    st.error(f"❌ Error: {e}")
    else:
        st.info("ऊपर से data load करें।")


# ══ Page 4: Column जोड़ें ═════════════════════════════════════════════════════
elif page == "⚙️ Column जोड़ें":
    st.header("⚙️ Sheet में नया Column जोड़ें")

    df = load_data()
    if not df.empty:
        st.info(f"मौजूदा columns: **{', '.join(df.columns.tolist())}**")

    st.divider()
    new_col = st.text_input("नए column का नाम", placeholder="जैसे: वकील का नाम")

    if st.button("➕ Column जोड़ें", type="primary", use_container_width=True):
        if not new_col.strip():
            st.error("Column नाम खाली नहीं हो सकता।")
        else:
            ws = st.session_state.ws_name or None
            result = add_column(st.session_state.sheet_url, new_col.strip(), ws)
            if result == "exists":
                st.warning(f"'{new_col}' पहले से मौजूद है।")
            elif result:
                st.success(f"✅ '{new_col}' column जोड़ा गया!")
                st.cache_data.clear()
            else:
                st.error("Column नहीं जुड़ा। Permission check करें।")

    st.divider()
    st.caption("नोट: Column Sheet में सबसे अंत में जुड़ेगा, सभी rows में खाली रहेगा।")
