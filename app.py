"""
केस प्रबंधन ऐप — Case Management for Court Cases
Streamlit app: manage cases, witnesses, generate summon documents (NBW/BW/Mrityu Aakhya/Saman/VC letter)
"""
import streamlit as st
import pandas as pd
from datetime import datetime
import data_store as ds
import templates
import docx_builder

st.set_page_config(page_title="केस प्रबंधन", page_icon="⚖️", layout="wide")

# ---------------------------------------------------------------------------
# Session state init
# ---------------------------------------------------------------------------
if "selected_case_id" not in st.session_state:
    st.session_state.selected_case_id = None
if "page" not in st.session_state:
    st.session_state.page = "list"

# ---------------------------------------------------------------------------
# Sidebar nav
# ---------------------------------------------------------------------------
with st.sidebar:
    st.title("⚖️ केस प्रबंधन")
    if st.button("📋 केस लिस्ट", use_container_width=True):
        st.session_state.page = "list"
        st.session_state.selected_case_id = None
        st.rerun()
    if st.button("➕ नया केस जोड़ें", use_container_width=True):
        st.session_state.page = "new_case"
        st.rerun()
    st.divider()
    st.caption(f"Data file: `{ds.DATA_FILE.split('/')[-1]}`")
    st.caption(f"आज: {ds.today_str()}")


# ---------------------------------------------------------------------------
# Page: Case List
# ---------------------------------------------------------------------------
def page_case_list():
    st.header("📋 सभी केस")
    cases_df = ds.load_cases()

    if cases_df.empty:
        st.info("अभी कोई केस नहीं जोड़ा गया है। 'नया केस जोड़ें' पर क्लिक करें।")
        return

    col1, col2, col3 = st.columns([2, 2, 2])
    with col1:
        search = st.text_input("🔍 खोजें (नाम / केस नंबर / थाना)", "")
    with col2:
        type_filter = st.selectbox("प्रकार से फ़िल्टर करें", ["सभी"] + ds.CASE_TYPES)
    with col3:
        status_filter = st.selectbox("स्थिति से फ़िल्टर करें", ["सभी"] + ds.STATUS_OPTIONS)

    filtered = cases_df.copy()
    if search:
        mask = filtered.apply(lambda r: search.lower() in " ".join(r.astype(str)).lower(), axis=1)
        filtered = filtered[mask]
    if type_filter != "सभी":
        filtered = filtered[filtered["Case_Type"] == type_filter]
    if status_filter != "सभी":
        filtered = filtered[filtered["Status"] == status_filter]

    st.caption(f"कुल {len(filtered)} केस मिले")

    for _, row in filtered.iterrows():
        with st.container(border=True):
            c1, c2, c3 = st.columns([3, 2, 1])
            with c1:
                st.markdown(f"**राज्य बनाम {row['Rajya_Banam']}**  \n"
                            f"मु0न0: {row['Satra_Pareeksha_Sankhya']} | मु0अ0सं0: {row['Mukadma_Apradh_Sankhya']}")
                st.caption(f"{row['Case_Type']} • धारा: {row['Dhara']} • थाना: {row['Thana']}, {row['Janpad']}")
            with c2:
                st.markdown(f"अगली पेशी: **{row['Tareekh_Peshi'] or '—'}**")
                st.caption(f"स्थिति: {row['Status'] or '—'}")
            with c3:
                if st.button("खोलें →", key=f"open_{row['Case_ID']}", use_container_width=True):
                    st.session_state.selected_case_id = row["Case_ID"]
                    st.session_state.page = "detail"
                    st.rerun()


# ---------------------------------------------------------------------------
# Page: New Case
# ---------------------------------------------------------------------------
def page_new_case():
    st.header("➕ नया केस जोड़ें")
    if st.button("← वापस लिस्ट पर जाएं"):
        st.session_state.page = "list"
        st.rerun()

    with st.form("new_case_form"):
        col1, col2 = st.columns(2)
        with col1:
            case_type = st.selectbox("केस प्रकार", ds.CASE_TYPES)
            satra = st.text_input("सत्र परीक्षण संख्या / मु0न0 (केस नंबर)", placeholder="जैसे: 7133/2023")
            mu_apradh = st.text_input("मु0अ0सं0 (मुकदमा अपराध संख्या)", placeholder="जैसे: 166/2023")
            rajya_banam = st.text_input("राज्य/वादी बनाम (प्रतिवादी का नाम)", placeholder="जैसे: शाहरूख")
            dhara = st.text_input("धारा", placeholder="जैसे: 4/25 आयुध अधि0")
            thana = st.text_input("थाना")
        with col2:
            janpad = st.text_input("जनपद")
            nyayalaya = st.text_input("न्यायालय (पद + जनपद)", placeholder="जैसे: जिला एवं सत्र श्रावस्ती")
            tareekh_peshi = st.text_input("अगली पेशी तारीख (DD-MM-YYYY)", placeholder="21-04-2026")
            status = st.selectbox("स्थिति", ds.STATUS_OPTIONS)
            notes = st.text_area("नोट्स (वैकल्पिक)")

        submitted = st.form_submit_button("✅ केस सेव करें", use_container_width=True)
        if submitted:
            if not rajya_banam or not satra:
                st.error("कृपया कम से कम 'बनाम नाम' और 'केस नंबर' भरें।")
            else:
                case_id = ds.add_case({
                    "Case_Type": case_type,
                    "Satra_Pareeksha_Sankhya": satra,
                    "Mukadma_Apradh_Sankhya": mu_apradh,
                    "Rajya_Banam": rajya_banam,
                    "Dhara": dhara,
                    "Thana": thana,
                    "Janpad": janpad,
                    "Nyayalaya": nyayalaya,
                    "Tareekh_Peshi": tareekh_peshi,
                    "Status": status,
                    "Notes": notes,
                })
                st.success(f"केस सफलतापूर्वक जोड़ा गया! (ID: {case_id})")
                st.session_state.selected_case_id = case_id
                st.session_state.page = "detail"
                st.rerun()


# ---------------------------------------------------------------------------
# Page: Case Detail (+ witnesses + summon)
# ---------------------------------------------------------------------------
def page_case_detail():
    case_id = st.session_state.selected_case_id
    case = ds.get_case(case_id)
    if not case:
        st.error("केस नहीं मिला।")
        if st.button("← वापस लिस्ट पर जाएं"):
            st.session_state.page = "list"
            st.rerun()
        return

    if st.button("← वापस लिस्ट पर जाएं"):
        st.session_state.page = "list"
        st.session_state.selected_case_id = None
        st.rerun()

    st.header(f"राज्य बनाम {case['Rajya_Banam']}")
    st.caption(f"मु0न0: {case['Satra_Pareeksha_Sankhya']} | मु0अ0सं0: {case['Mukadma_Apradh_Sankhya']} | {case['Case_Type']}")

    tab1, tab2, tab3 = st.tabs(["📄 केस विवरण", "👥 गवाह (Witnesses)", "📨 समन / दस्तावेज़ जनरेटर"])

    # --- Tab 1: Case details (editable) ---
    with tab1:
        with st.form("edit_case_form"):
            col1, col2 = st.columns(2)
            with col1:
                case_type = st.selectbox("केस प्रकार", ds.CASE_TYPES,
                                          index=ds.CASE_TYPES.index(case["Case_Type"]) if case["Case_Type"] in ds.CASE_TYPES else 0)
                satra = st.text_input("सत्र परीक्षण संख्या / मु0न0", value=case["Satra_Pareeksha_Sankhya"])
                mu_apradh = st.text_input("मु0अ0सं0", value=case["Mukadma_Apradh_Sankhya"])
                rajya_banam = st.text_input("राज्य/वादी बनाम", value=case["Rajya_Banam"])
                dhara = st.text_input("धारा", value=case["Dhara"])
                thana = st.text_input("थाना", value=case["Thana"])
            with col2:
                janpad = st.text_input("जनपद", value=case["Janpad"])
                nyayalaya = st.text_input("न्यायालय (पद + जनपद)", value=case["Nyayalaya"])
                tareekh_peshi = st.text_input("अगली पेशी तारीख", value=case["Tareekh_Peshi"])
                status = st.selectbox("स्थिति", ds.STATUS_OPTIONS,
                                       index=ds.STATUS_OPTIONS.index(case["Status"]) if case["Status"] in ds.STATUS_OPTIONS else 0)
                notes = st.text_area("नोट्स", value=case["Notes"])

            c1, c2 = st.columns([1, 1])
            with c1:
                save_btn = st.form_submit_button("💾 बदलाव सेव करें", use_container_width=True)
            with c2:
                delete_btn = st.form_submit_button("🗑️ केस हटाएं", use_container_width=True, type="secondary")

            if save_btn:
                ds.update_case(case_id, {
                    "Case_Type": case_type, "Satra_Pareeksha_Sankhya": satra,
                    "Mukadma_Apradh_Sankhya": mu_apradh, "Rajya_Banam": rajya_banam,
                    "Dhara": dhara, "Thana": thana, "Janpad": janpad,
                    "Nyayalaya": nyayalaya, "Tareekh_Peshi": tareekh_peshi,
                    "Status": status, "Notes": notes,
                })
                st.success("बदलाव सेव हो गए!")
                st.rerun()

            if delete_btn:
                ds.delete_case(case_id)
                st.success("केस हटा दिया गया।")
                st.session_state.page = "list"
                st.session_state.selected_case_id = None
                st.rerun()

    # --- Tab 2: Witnesses ---
    with tab2:
        st.subheader("गवाह जोड़ें")
        with st.form("add_witness_form", clear_on_submit=True):
            wc1, wc2 = st.columns(2)
            with wc1:
                w_naam = st.text_input("नाम")
                w_pata = st.text_input("पता (थाना/जनपद सहित)")
            with wc2:
                w_mobile = st.text_input("मोबाइल नंबर")
                w_bhumika = st.selectbox("भूमिका", ds.BHUMIKA_OPTIONS)
            w_note = st.text_input("कोई अतिरिक्त नोट (वैकल्पिक)")
            add_w = st.form_submit_button("➕ गवाह जोड़ें", use_container_width=True)
            if add_w:
                if not w_naam:
                    st.error("नाम भरना ज़रूरी है।")
                else:
                    ds.add_witness(case_id, {
                        "Naam": w_naam, "Pata": w_pata, "Mobile": w_mobile,
                        "Bhumika": w_bhumika, "Custom_Note": w_note,
                    })
                    st.success("गवाह जोड़ा गया!")
                    st.rerun()

        st.divider()
        st.subheader("गवाहों की सूची")
        witnesses = ds.get_witnesses_for_case(case_id)
        if witnesses.empty:
            st.info("अभी कोई गवाह नहीं जोड़ा गया।")
        else:
            for _, w in witnesses.iterrows():
                with st.container(border=True):
                    wcol1, wcol2 = st.columns([4, 1])
                    with wcol1:
                        st.markdown(f"**{w['Naam']}** ({w['Bhumika']})")
                        st.caption(f"पता: {w['Pata'] or '—'} | मोबाइल: {w['Mobile'] or '—'}")
                        if w["Custom_Note"]:
                            st.caption(f"नोट: {w['Custom_Note']}")
                    with wcol2:
                        if st.button("🗑️ हटाएं", key=f"del_w_{w['Witness_ID']}", use_container_width=True):
                            ds.delete_witness(w["Witness_ID"])
                            st.rerun()

    # --- Tab 3: Summon / document generator ---
    with tab3:
        st.subheader("दस्तावेज़ प्रकार चुनें")
        doc_type_label = st.selectbox("दस्तावेज़ प्रकार", list(templates.DOC_TYPES.values()))
        doc_type_key = [k for k, v in templates.DOC_TYPES.items() if v == doc_type_label][0]

        witnesses = ds.get_witnesses_for_case(case_id)
        witness_options = ["— कोई नहीं / मैन्युअल भरें —"]
        witness_map = {}
        if not witnesses.empty:
            for _, w in witnesses.iterrows():
                label = f"{w['Naam']} ({w['Bhumika']})"
                witness_options.append(label)
                witness_map[label] = w

        selected_witness_label = st.selectbox("गवाह/अभियुक्त चुनें (वैकल्पिक — auto-fill के लिए)", witness_options)

        st.divider()
        st.subheader("फ़ील्ड भरें / जाँचें")

        fields_def = templates.get_fields_for_type(doc_type_key)

        # Build auto-fill defaults from case + selected witness
        defaults = {
            "nyayalaya_pad": case.get("Nyayalaya", ""),
            "janpad": case.get("Janpad", ""),
            "rajya_banam": case.get("Rajya_Banam", ""),
            "mu_no": case.get("Satra_Pareeksha_Sankhya", ""),
            "mu_apradh_sankhya": case.get("Mukadma_Apradh_Sankhya", ""),
            "dhara": case.get("Dhara", ""),
            "thana": case.get("Thana", ""),
            "tareekh_peshi": case.get("Tareekh_Peshi", ""),
            "satra_pareeksha_sankhya": case.get("Satra_Pareeksha_Sankhya", ""),
            "aaj_ki_tareekh": ds.today_str(),
            "praapak_pad": case.get("Nyayalaya", ""),
        }
        if selected_witness_label in witness_map:
            w = witness_map[selected_witness_label]
            naam_pata_parts = [p for p in [w.get("Naam", ""), w.get("Pata", "")] if p]
            defaults["naam_pata"] = " निवासी ".join(naam_pata_parts) if len(naam_pata_parts) > 1 else (naam_pata_parts[0] if naam_pata_parts else "")
            defaults["seva_me_janpad"] = case.get("Janpad", "")

        # Render the dynamic form
        with st.form("doc_fields_form"):
            field_values = {}
            n_cols = 2
            cols = st.columns(n_cols)
            for idx, (key, label) in enumerate(fields_def):
                with cols[idx % n_cols]:
                    field_values[key] = st.text_input(label, value=defaults.get(key, ""), key=f"field_{doc_type_key}_{key}")
            generate_clicked = st.form_submit_button("🔄 प्रीव्यू / जनरेट करें", use_container_width=True)

        if generate_clicked or st.session_state.get("last_doc_fields"):
            if generate_clicked:
                st.session_state.last_doc_fields = field_values
                st.session_state.last_doc_type = doc_type_key

            final_fields = st.session_state.get("last_doc_fields", field_values)
            final_doc_type = st.session_state.get("last_doc_type", doc_type_key)

            st.divider()
            st.subheader("📃 प्रीव्यू")
            html_preview = templates.render_document_html(final_doc_type, final_fields)
            st.components.v1.html(html_preview, height=700, scrolling=True)

            dl_col1, dl_col2 = st.columns(2)
            with dl_col1:
                docx_bytes = docx_builder.generate_docx_bytes(final_doc_type, final_fields)
                fname_base = f"{templates.DOC_TYPES[final_doc_type]}_{final_fields.get('rajya_banam') or final_fields.get('naam_pata','')}".strip()
                fname = "".join(c for c in fname_base if c not in '<>:"/\\|?*')[:80] + ".docx"
                st.download_button("⬇️ Word (.docx) डाउनलोड करें", data=docx_bytes,
                                    file_name=fname,
                                    mime="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                                    use_container_width=True)
            with dl_col2:
                print_html = f"""
                <html><head><meta charset="utf-8">{templates.BASE_CSS if False else ''}</head>
                <body>{html_preview}
                <script>window.onload = function(){{}}</script>
                </body></html>
                """
                st.download_button("⬇️ HTML (Print/PDF हेतु) डाउनलोड करें", data=html_preview,
                                    file_name=fname.replace(".docx", ".html"),
                                    mime="text/html",
                                    use_container_width=True)
                st.caption("HTML फ़ाइल को ब्राउज़र में खोलकर Ctrl+P से सीधे PDF/Print कर सकते हैं।")


# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------
if st.session_state.page == "list":
    page_case_list()
elif st.session_state.page == "new_case":
    page_new_case()
elif st.session_state.page == "detail":
    page_case_detail()

