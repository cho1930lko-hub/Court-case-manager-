"""
⚖️ समन / वारंट जनरेटर — Bulk DOCX
Streamlit Cloud compatible (कोई local file dependency नहीं)
"""
import streamlit as st
from bulk_generator import generate_bulk

st.set_page_config(page_title="समन जनरेटर", page_icon="⚖️", layout="centered")

st.title("⚖️ समन / वारंट जनरेटर")
st.caption("Excel अपलोड करें → एक क्लिक में सभी दस्तावेज़ Word file में डाउनलोड करें")

st.divider()

# ─── Instructions ───────────────────────────────────────────────────────────
with st.expander("📋 Excel format कैसा होना चाहिए? (क्लिक करें)"):
    st.markdown("""
**Sheet 1 (मुख्य — समन/वारंट)** — ये columns होने चाहिए:

| Column | उदाहरण |
|---|---|
| न्यायालय | न्यायिक मजिस्ट्रेट / सेशन न्यायालय |
| राज्य बनाम | शाहरूख |
| मु0न0 | 7133/2023 |
| मु0अ0स0 | 166/2023 |
| धारा | 4/25 आयुध अधि0 |
| थाना | हरदत्तनगर |
| तारीख पेशी | 21-04-2026 |
| नाम पता साक्षी | **prefix देखें नीचे** |

**नाम पता साक्षी column में prefix नियम:**
- `रामलाल थाना कोतवाली` → साधारण **समन**
- `BW रामलाल थाना कोतवाली` → **जमानती वारंट (BW)**
- `NBW रामलाल थाना कोतवाली` → **गैर जमानती वारंट (NBW)**
- `MRITYU कोई नहीं` → **मृत्यु आख्या**

एक row में कई साक्षी — comma से अलग करें:
`रामलाल, श्यामलाल, सीतादेवी`

---

**Sheet 2 — "VC" (वैकल्पिक — VC लेटर के लिए)** — इस नाम की sheet बनाएं:

| Column | उदाहरण |
|---|---|
| न्यायालय | जिला एवं सत्र |
| राज्य बनाम | रहमान |
| मु0न0 | 7985/2023 |
| मु0अ0स0 | 192/2023 |
| धारा | 323,504 IPC |
| थाना | कोतवाली |
| तारीख पेशी | 21-05-2026 |
| नाम पता साक्षी | शमसुद्दीन पुत्र शरीफ खान निवासी लखनऊ |
| सेवा जनपद | लखनऊ |
| VC स्थान | पुलिस कार्यालय |
| VC समय | 12:30 PM |
| प्रति पद | पुलिस आयुक्त |
    """)

st.divider()

# ─── Inputs ─────────────────────────────────────────────────────────────────
col1, col2 = st.columns([2, 1])
with col1:
    uploaded = st.file_uploader("📂 Excel फ़ाइल अपलोड करें (.xlsx)", type=["xlsx"])
with col2:
    janpad = st.text_input("जनपद का नाम", value="श्रावस्ती",
                           help="यह जनपद सभी दस्तावेज़ों में उपयोग होगा")

st.divider()

# ─── Generate ────────────────────────────────────────────────────────────────
if uploaded:
    excel_bytes = uploaded.read()

    # Preview the uploaded sheet
    import pandas as pd, io
    try:
        df_preview = pd.read_excel(io.BytesIO(excel_bytes), sheet_name=0).fillna("")
        st.subheader("📊 अपलोड की गई Excel (Sheet 1 — प्रीव्यू)")
        st.dataframe(df_preview, use_container_width=True)

        xls = pd.ExcelFile(io.BytesIO(excel_bytes))
        if "VC" in xls.sheet_names:
            df_vc = pd.read_excel(io.BytesIO(excel_bytes), sheet_name="VC").fillna("")
            st.subheader("📊 VC Sheet — प्रीव्यू")
            st.dataframe(df_vc, use_container_width=True)
    except Exception as e:
        st.warning(f"Preview error: {e}")

    st.divider()

    if st.button("🖨️ सभी दस्तावेज़ Generate करें", use_container_width=True, type="primary"):
        if not janpad.strip():
            st.error("कृपया जनपद का नाम भरें।")
        else:
            with st.spinner("दस्तावेज़ बन रहे हैं..."):
                try:
                    docx_bytes = generate_bulk(excel_bytes, janpad.strip())
                    st.success("✅ दस्तावेज़ तैयार है! नीचे से डाउनलोड करें।")
                    st.download_button(
                        label="⬇️ समन_दस्तावेज़.docx डाउनलोड करें",
                        data=docx_bytes,
                        file_name="समन_दस्तावेज़.docx",
                        mime="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                        use_container_width=True,
                    )
                except ValueError as ve:
                    st.error(f"❌ Excel में column गायब है:\n{ve}")
                except Exception as e:
                    st.error(f"❌ Error: {e}")
else:
    st.info("👆 ऊपर Excel फ़ाइल अपलोड करें।")

st.divider()
st.caption("समन = साधारण | BW = जमानती वारंट | NBW = गैर जमानती वारंट | MRITYU = मृत्यु आख्या | VC Sheet = वीडियो कांफ्रेंसिंग पत्र")
