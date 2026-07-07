"""
Google Sheets data layer — read / write / append / update
तीनों sheets: सेशन कोर्ट | Dak REGISTER | RIMAND REGISTER
"""
import json
import streamlit as st
import pandas as pd
from datetime import datetime
import gspread
from google.oauth2.service_account import Credentials

# ── Sheet names ──────────────────────────────────────────────────────────────
SH_SESSION  = "सेशन कोर्ट"
SH_DAK      = "Dak REGISTER"
SH_RIMAND   = "RIMAND REGISTER"

# ── Column definitions ────────────────────────────────────────────────────────
SESSION_COLS = [
    "ST NO", "मु0अ0स0", "धारा", "बनाम", "न्यायालय",
    "तलब साक्षी", "पिछली पेशी", "अगली तारीख पेशी",
    "Status", "सम्मन की स्थिति", "Type Of Moni",
    "कृत कार्यवाही", "कुल गवाह", "Fir दिनांक",
    "आरोप पत्र प्रेषित", "प्रसंज्ञान दिनांक",
    "चार्ज फ्रेम", "थाने पर देने का दिनाँक"
]

DAK_COLS = [
    "STN", "बनाम", "status", "Type", "नाम पता",
    "संबंधित थाना", "कोर्ट का नाम",
    "थाने पर लाने का दिनांक", "तारीख़ पेशी", "रिमार्क", "लिंक"
]

RIMAND_COLS = [
    "रिमांड Date", "मु0अ0स0", "धारा", "कोर्ट",
    "IO", "First रिमांड डेट", "नाम पता अभियुक्त"
]

STATUS_OPTIONS = [
    "साक्ष्य", "हाजिरी", "बहस", "313 सीआरपीसी",
    "सफाई साक्ष्य", "जजमेंट", "सजा", "दोष मुक्त", "अभियुक्त NBW"
]

SAMMAN_OPTIONS = ["बनाना है", "ISSUED", "NOT ISSUED", "जारी", ""]

NYAYALAYA_OPTIONS = [
    "ASJ", "DJ", "SPL पॉक्सो", "ASJ EX POCSO",
    "SC/ST", "ASJ SC/ST ACT", "CJM", "जिला एवं सत्र"
]

DAK_TYPE_OPTIONS = [
    "साक्षी सम्मन", "अभियुक्त सम्मन", "मुसन्ना", "तलबाना नोटिस"
]


# ── gspread client ────────────────────────────────────────────────────────────
@st.cache_resource
def get_client():
    creds_dict = json.loads(st.secrets["GOOGLE_CREDENTIALS"])
    creds = Credentials.from_service_account_info(
        creds_dict,
        scopes=[
            "https://spreadsheets.google.com/feeds",
            "https://www.googleapis.com/auth/drive"
        ]
    )
    return gspread.authorize(creds)


def get_sheet(ws_name: str):
    client = get_client()
    sh = client.open_by_url(st.secrets["SHEET_URL"])
    return sh.worksheet(ws_name)


# ── Load ──────────────────────────────────────────────────────────────────────
@st.cache_data(ttl=60)
def load_session() -> pd.DataFrame:
    try:
        ws = get_sheet(SH_SESSION)
        data = ws.get_all_records(default_blank="")
        df = pd.DataFrame(data).fillna("")
        for col in SESSION_COLS:
            if col not in df.columns:
                df[col] = ""
        return df[SESSION_COLS]
    except Exception as e:
        st.error(f"सेशन कोर्ट sheet load error: {e}")
        return pd.DataFrame(columns=SESSION_COLS)


@st.cache_data(ttl=60)
def load_dak() -> pd.DataFrame:
    try:
        ws = get_sheet(SH_DAK)
        data = ws.get_all_records(default_blank="")
        df = pd.DataFrame(data).fillna("")
        for col in DAK_COLS:
            if col not in df.columns:
                df[col] = ""
        return df[DAK_COLS]
    except Exception as e:
        st.error(f"Dak Register load error: {e}")
        return pd.DataFrame(columns=DAK_COLS)


@st.cache_data(ttl=60)
def load_rimand() -> pd.DataFrame:
    try:
        ws = get_sheet(SH_RIMAND)
        data = ws.get_all_records(default_blank="")
        df = pd.DataFrame(data).fillna("")
        for col in RIMAND_COLS:
            if col not in df.columns:
                df[col] = ""
        return df[RIMAND_COLS]
    except Exception as e:
        st.error(f"Rimand Register load error: {e}")
        return pd.DataFrame(columns=RIMAND_COLS)


# ── Write helpers ─────────────────────────────────────────────────────────────
def append_row_session(row_dict: dict) -> bool:
    try:
        ws = get_sheet(SH_SESSION)
        headers = ws.row_values(1)
        new_row = [str(row_dict.get(h, "")) for h in headers]
        ws.append_row(new_row, value_input_option="USER_ENTERED")
        st.cache_data.clear()
        return True
    except Exception as e:
        st.error(f"Row add error: {e}")
        return False


def append_row_dak(row_dict: dict) -> bool:
    try:
        ws = get_sheet(SH_DAK)
        headers = ws.row_values(1)
        new_row = [str(row_dict.get(h, "")) for h in headers]
        ws.append_row(new_row, value_input_option="USER_ENTERED")
        st.cache_data.clear()
        return True
    except Exception as e:
        st.error(f"Dak row add error: {e}")
        return False


def append_row_rimand(row_dict: dict) -> bool:
    try:
        ws = get_sheet(SH_RIMAND)
        headers = ws.row_values(1)
        new_row = [str(row_dict.get(h, "")) for h in headers]
        ws.append_row(new_row, value_input_option="USER_ENTERED")
        st.cache_data.clear()
        return True
    except Exception as e:
        st.error(f"Rimand row add error: {e}")
        return False


def update_cell_session(st_no: str, col_name: str, value: str) -> bool:
    """ST NO से row ढूंढकर specific column update करता है"""
    try:
        ws = get_sheet(SH_SESSION)
        headers = ws.row_values(1)
        if col_name not in headers:
            st.error(f"Column '{col_name}' नहीं मिला")
            return False
        col_idx = headers.index(col_name) + 1

        # ST NO column find
        st_col_idx = headers.index("ST NO") + 1
        st_no_col = ws.col_values(st_col_idx)
        for r_idx, val in enumerate(st_no_col):
            if str(val).strip() == str(st_no).strip():
                ws.update_cell(r_idx + 1, col_idx, value)
                st.cache_data.clear()
                return True
        st.error(f"ST NO '{st_no}' नहीं मिला")
        return False
    except Exception as e:
        st.error(f"Update error: {e}")
        return False


def update_row_session(st_no: str, updates: dict) -> bool:
    """एक साथ कई columns update करता है"""
    try:
        ws = get_sheet(SH_SESSION)
        headers = ws.row_values(1)
        st_col_idx = headers.index("ST NO") + 1
        st_no_col = ws.col_values(st_col_idx)

        row_idx = None
        for i, val in enumerate(st_no_col):
            if str(val).strip() == str(st_no).strip():
                row_idx = i + 1
                break

        if not row_idx:
            st.error(f"ST NO '{st_no}' नहीं मिला")
            return False

        for col_name, value in updates.items():
            if col_name in headers:
                col_idx = headers.index(col_name) + 1
                ws.update_cell(row_idx, col_idx, str(value))

        st.cache_data.clear()
        return True
    except Exception as e:
        st.error(f"Update error: {e}")
        return False


def update_dak_status(row_num: int, new_status: str) -> bool:
    """Dak Register में row number से status update"""
    try:
        ws = get_sheet(SH_DAK)
        headers = ws.row_values(1)
        col_idx = headers.index("status") + 1
        ws.update_cell(row_num + 1, col_idx, new_status)
        st.cache_data.clear()
        return True
    except Exception as e:
        st.error(f"Dak status update error: {e}")
        return False


def fmt_date(val):
    if isinstance(val, datetime):
        return val.strftime('%d/%m/%Y')
    s = str(val).strip()
    for fmt in ('%d/%m/%Y', '%d-%m-%Y', '%Y-%m-%d'):
        try:
            return datetime.strptime(s, fmt).strftime('%d/%m/%Y')
        except:
            pass
    return s


def today_str():
    return datetime.today().strftime('%d/%m/%Y')

