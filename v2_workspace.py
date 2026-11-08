"""
V2 workspace for Court Case Manager.
Additive modules: document library/versioning, timeline, checklist,
OCR review, AI drafting workspace, and audit log.

All worksheet creation is explicit and additive. Existing worksheets and rows
are never renamed, cleared, or deleted by this module.
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime
from io import BytesIO

import pandas as pd
import streamlit as st
from googleapiclient.http import MediaIoBaseUpload

import gsheet as gs


SHEETS = {
    "CASE MASTER": ["Case ID", "ST NO", "FIR No", "Banam", "Court", "Created At"],
    "CASE DOCUMENTS": [
        "Document ID", "Case ID", "ST NO", "Document Group ID", "Document Name",
        "Category", "Drive File ID", "Drive Link", "Version", "Uploaded At",
        "Uploaded By", "Remarks"
    ],
    "CASE TIMELINE": [
        "Event ID", "Case ID", "ST NO", "Event Date", "Event Type",
        "Description", "Document ID", "Created At", "Created By"
    ],
    "CASE CHECKLIST": [
        "Task ID", "Case ID", "ST NO", "Task Name", "Status", "Due Date",
        "Completed Date", "Assigned To", "Remarks", "Updated At", "Updated By"
    ],
    "DOCUMENT ANALYSIS": [
        "Analysis ID", "Case ID", "ST NO", "Document ID", "Source File",
        "Extracted Text", "AI Summary", "Review Status", "Created At", "Reviewed By"
    ],
    "AI DRAFTS": [
        "Draft ID", "Case ID", "ST NO", "Draft Type", "Draft Text",
        "Status", "Created At", "Created By"
    ],
    "DOCUMENT VERSIONS": [
        "Version ID", "Document Group ID", "Document ID", "Case ID", "ST NO",
        "Version Number", "Drive File ID", "Drive Link", "Change Remarks",
        "Uploaded At", "Uploaded By"
    ],
    "AUDIT LOG": [
        "Audit ID", "User ID", "Action", "Module", "Record ID",
        "Timestamp", "Details"
    ],
}

DEFAULT_TASKS = [
    "FIR / मूल मुकदमा विवरण उपलब्ध",
    "आरोपपत्र / चार्जशीट की स्थिति जाँची",
    "प्रसंज्ञान की स्थिति दर्ज",
    "आरोप निर्धारण की स्थिति दर्ज",
    "गवाह / साक्षी की स्थिति अपडेट",
    "सम्मन / वारंट की स्थिति अपडेट",
    "न्यायालय आदेश की प्रति प्राप्त",
    "अगली पेशी की तारीख अपडेट",
]

CATEGORIES = [
    "FIR", "आरोपपत्र / चार्जशीट", "न्यायालय आदेश", "जमानत आदेश",
    "गवाही / बयान", "मेडिकल रिपोर्ट", "सम्मन / वारंट",
    "रिमांड दस्तावेज", "अन्य"
]


def _now():
    return datetime.now().astimezone().isoformat(timespec="seconds")


def _user():
    return str(st.session_state.get("user_id") or st.session_state.get("username") or "app-user")


def _spreadsheet():
    return gs.get_client().open_by_url(st.secrets["SHEET_URL"])


def _worksheet(name, create=False):
    sh = _spreadsheet()
    try:
        return sh.worksheet(name)
    except Exception:
        if not create:
            return None
        return sh.add_worksheet(title=name, rows=1000, cols=max(12, len(SHEETS[name])))


def _ensure_sheets():
    sh = _spreadsheet()
    created, existing = [], []
    for name, headers in SHEETS.items():
        try:
            ws = sh.worksheet(name)
            existing.append(name)
        except Exception:
            ws = sh.add_worksheet(title=name, rows=1000, cols=max(12, len(headers)))
            ws.append_row(headers, value_input_option="USER_ENTERED")
            created.append(name)
            continue
        values = ws.row_values(1)
        if not values:
            ws.append_row(headers, value_input_option="USER_ENTERED")
    return created, existing


def _rows(name):
    ws = _worksheet(name)
    if ws is None:
        return pd.DataFrame(columns=SHEETS[name])
    values = ws.get_all_records()
    return pd.DataFrame(values, columns=SHEETS[name]) if values else pd.DataFrame(columns=SHEETS[name])


def _append(name, row):
    ws = _worksheet(name)
    if ws is None:
        raise RuntimeError(f"'{name}' शीट उपलब्ध नहीं है। पहले V2 डेटा शीट तैयार करें।")
    ws.append_row([row.get(col, "") for col in SHEETS[name]], value_input_option="USER_ENTERED")


def _audit(action, module, record_id="", details=""):
    try:
        _append("AUDIT LOG", {
            "Audit ID": str(uuid.uuid4()),
            "User ID": _user(),
            "Action": action,
            "Module": module,
            "Record ID": record_id,
            "Timestamp": _now(),
            "Details": str(details)[:1000],
        })
    except Exception:
        # A user-facing operation must not be falsely reported as failed solely
        # because the optional audit worksheet is not initialized.
        pass


def _case_frame():
    df = gs.load_session()
    if df is None or df.empty:
        return pd.DataFrame()
    required = ["ST NO", "मु0अ0स0", "बनाम", "न्यायालय"]
    for col in required:
        if col not in df.columns:
            df[col] = ""
    df = df[df["ST NO"].astype(str).str.strip() != ""].copy()
    df["_label"] = df.apply(
        lambda r: f"{str(r['ST NO']).strip()} — {str(r['बनाम']).strip() or 'नाम उपलब्ध नहीं'}",
        axis=1
    )
    return df


def _case_id(row):
    st_no = str(row.get("ST NO", "")).strip()
    if not st_no:
        raise ValueError("ST NO उपलब्ध नहीं है।")
    ws = _worksheet("CASE MASTER")
    if ws is None:
        raise RuntimeError("V2 डेटा शीट पहले तैयार करें।")
    records = ws.get_all_records()
    for item in records:
        if str(item.get("ST NO", "")).strip() == st_no:
            return str(item.get("Case ID", "")).strip()
    new_id = str(uuid.uuid4())
    _append("CASE MASTER", {
        "Case ID": new_id,
        "ST NO": st_no,
        "FIR No": row.get("मु0अ0स0", ""),
        "Banam": row.get("बनाम", ""),
        "Court": row.get("न्यायालय", ""),
        "Created At": _now(),
    })
    _audit("CASE_ID_CREATED", "CASE MASTER", new_id, f"ST NO={st_no}")
    return new_id


def _drive_upload(uploaded, safe_name):
    folder_id = str(st.secrets.get("CASE_DOCUMENTS_FOLDER_ID", "")).strip()
    if not folder_id:
        raise RuntimeError(
            "Streamlit Secrets में CASE_DOCUMENTS_FOLDER_ID सेट नहीं है। "
            "Google Drive में निजी folder बनाकर उसका ID यहाँ दें।"
        )
    service = gs.get_drive_service()
    metadata = {"name": safe_name, "parents": [folder_id]}
    media = MediaIoBaseUpload(
        BytesIO(uploaded.getvalue()),
        mimetype=getattr(uploaded, "type", None) or "application/octet-stream",
        resumable=True,
    )
    created = service.files().create(
        body=metadata,
        media_body=media,
        fields="id,name,webViewLink",
    ).execute()
    file_id = created.get("id", "")
    link = created.get("webViewLink") or (
        f"https://drive.google.com/file/d/{file_id}/view" if file_id else ""
    )
    if not file_id:
        raise RuntimeError("Google Drive ने File ID नहीं लौटाई।")
    return file_id, link


def _case_picker(df, key):
    if df.empty:
        st.info("सेशन कोर्ट में कोई मुकदमा उपलब्ध नहीं है।")
        return None
    labels = df["_label"].tolist()
    selected = st.selectbox("मुकदमा चुनें", labels, key=key)
    return df[df["_label"] == selected].iloc[0].to_dict()


def _ensure_ready():
    missing = []
    try:
        sh = _spreadsheet()
        existing = {ws.title for ws in sh.worksheets()}
        missing = [name for name in SHEETS if name not in existing]
    except Exception as exc:
        st.error(f"Google Sheets कनेक्शन उपलब्ध नहीं: {exc}")
        return False
    if missing:
        st.warning("V2 की नई डेटा शीट अभी तैयार नहीं हैं। मौजूदा चार रजिस्टर शीट को छुए बिना केवल नई शीट बनाई जाएँगी।")
        st.write("बनाई जाने वाली शीट:", ", ".join(missing))
        if st.button("V2 की नई डेटा शीट तैयार करें", type="primary", key="v2_init_sheets"):
            try:
                created, existing_names = _ensure_sheets()
                st.success(f"{len(created)} नई शीट बनाई गईं। पहले से मौजूद: {len(existing_names)}")
                st.rerun()
            except Exception as exc:
                st.error(f"शीट तैयार नहीं हो सकीं: {exc}")
        return False
    return True


def render_v2_workspace(janpad="श्रावस्ती", thana="कोतवाली भिंगा"):
    st.header("🧩 Case Manager V2 Workspace")
    st.caption(f"{thana}, जनपद {janpad} | नए मॉड्यूल — मौजूदा पैरवी रजिस्टर के साथ")
    st.info(
        "V2 के नए रिकॉर्ड अलग worksheets में रखे जाते हैं। मौजूदा सेशन कोर्ट, Dak, "
        "Rimand और Address Book शीट में कोई बदलाव नहीं किया जाता।"
    )
    if not _ensure_ready():
        st.stop()

    df_cases = _case_frame()
    tabs = st.tabs([
        "📁 Documents", "🕒 Timeline", "✅ Checklist", "🔎 OCR Analysis",
        "🗂️ Versions", "✍️ AI Drafting", "🛡️ Audit Log"
    ])

    # 1. Document library
    with tabs[0]:
        st.subheader("📁 मुकदमा दस्तावेज लाइब्रेरी")
        case = _case_picker(df_cases, "v2_doc_case")
        if case:
            case_id = _case_id(case)
            with st.form("v2_upload_document", clear_on_submit=True):
                title = st.text_input("दस्तावेज का नाम")
                category = st.selectbox("दस्तावेज श्रेणी", CATEGORIES)
                remarks = st.text_input("विवरण / टिप्पणी")
                file = st.file_uploader(
                    "PDF / फोटो / DOCX अपलोड करें",
                    type=["pdf", "jpg", "jpeg", "png", "docx"],
                    accept_multiple_files=False,
                )
                submitted = st.form_submit_button("🔒 निजी Drive में अपलोड करें", type="primary")
            if submitted:
                if not title.strip() or file is None:
                    st.error("दस्तावेज का नाम और फाइल दोनों आवश्यक हैं।")
                else:
                    try:
                        file_id, link = _drive_upload(
                            file, f"{case_id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{file.name}"
                        )
                        group_id = str(uuid.uuid4())
                        doc_id = str(uuid.uuid4())
                        row = {
                            "Document ID": doc_id, "Case ID": case_id, "ST NO": case["ST NO"],
                            "Document Group ID": group_id, "Document Name": title.strip(),
                            "Category": category, "Drive File ID": file_id, "Drive Link": link,
                            "Version": 1, "Uploaded At": _now(), "Uploaded By": _user(),
                            "Remarks": remarks,
                        }
                        _append("CASE DOCUMENTS", row)
                        _append("DOCUMENT VERSIONS", {
                            "Version ID": str(uuid.uuid4()), "Document Group ID": group_id,
                            "Document ID": doc_id, "Case ID": case_id, "ST NO": case["ST NO"],
                            "Version Number": 1, "Drive File ID": file_id, "Drive Link": link,
                            "Change Remarks": "प्रारंभिक संस्करण", "Uploaded At": _now(),
                            "Uploaded By": _user(),
                        })
                        _audit("DOCUMENT_UPLOADED", "DOCUMENTS", doc_id, title)
                        st.success("दस्तावेज निजी Google Drive में अपलोड और रजिस्टर हो गया।")
                    except Exception as exc:
                        st.error(f"दस्तावेज अपलोड नहीं हुआ: {exc}")
            docs = _rows("CASE DOCUMENTS")
            docs = docs[docs["Case ID"].astype(str) == case_id] if not docs.empty else docs
            st.divider()
            st.write(f"**इस मुकदमे के दस्तावेज: {len(docs)}**")
            if docs.empty:
                st.caption("अभी कोई दस्तावेज अपलोड नहीं है।")
            else:
                st.dataframe(docs[["Document Name", "Category", "Version", "Uploaded At", "Remarks"]],
                             use_container_width=True, hide_index=True)
                for _, doc in docs.iterrows():
                    if str(doc.get("Drive Link", "")).startswith("https://"):
                        st.link_button(f"📄 {doc.get('Document Name', 'दस्तावेज')} खोलें",
                                       str(doc["Drive Link"]))

    # 2. Timeline
    with tabs[1]:
        st.subheader("🕒 Case History Timeline")
        case = _case_picker(df_cases, "v2_timeline_case")
        if case:
            case_id = _case_id(case)
            with st.form("v2_timeline_add", clear_on_submit=True):
                event_date = st.date_input("घटना / कार्यवाही की तारीख")
                event_type = st.selectbox("कार्यवाही का प्रकार", [
                    "पेशी", "न्यायालय आदेश", "गवाह उपस्थिति", "सम्मन / वारंट",
                    "जमानत", "चार्ज फ्रेम", "अन्य"
                ])
                description = st.text_area("विवरण", max_chars=2000)
                save_event = st.form_submit_button("Timeline में जोड़ें", type="primary")
            if save_event:
                if not description.strip():
                    st.error("कार्यवाही का विवरण लिखना आवश्यक है।")
                else:
                    event_id = str(uuid.uuid4())
                    _append("CASE TIMELINE", {
                        "Event ID": event_id, "Case ID": case_id, "ST NO": case["ST NO"],
                        "Event Date": event_date.strftime("%d/%m/%Y"), "Event Type": event_type,
                        "Description": description.strip(), "Document ID": "",
                        "Created At": _now(), "Created By": _user(),
                    })
                    _audit("TIMELINE_ADDED", "TIMELINE", event_id, event_type)
                    st.success("Timeline में प्रविष्टि जोड़ दी गई।")
            events = _rows("CASE TIMELINE")
            if not events.empty:
                events = events[events["Case ID"].astype(str) == case_id].copy()
                if not events.empty:
                    st.dataframe(events.sort_values("Event Date", ascending=False),
                                 use_container_width=True, hide_index=True)

    # 3. Checklist
    with tabs[2]:
        st.subheader("✅ मुकदमा कार्यवाही Checklist")
        case = _case_picker(df_cases, "v2_check_case")
        if case:
            case_id = _case_id(case)
            tasks = _rows("CASE CHECKLIST")
            current = tasks[tasks["Case ID"].astype(str) == case_id] if not tasks.empty else tasks
            if current.empty and st.button("मानक Checklist तैयार करें", key="v2_seed_tasks"):
                for task in DEFAULT_TASKS:
                    _append("CASE CHECKLIST", {
                        "Task ID": str(uuid.uuid4()), "Case ID": case_id, "ST NO": case["ST NO"],
                        "Task Name": task, "Status": "लंबित", "Due Date": "",
                        "Completed Date": "", "Assigned To": "", "Remarks": "",
                        "Updated At": _now(), "Updated By": _user(),
                    })
                _audit("CHECKLIST_CREATED", "CHECKLIST", case_id, "Default tasks")
                st.rerun()
            elif not current.empty:
                st.dataframe(current[["Task Name", "Status", "Due Date", "Completed Date", "Remarks"]],
                             use_container_width=True, hide_index=True)
                options = current["Task ID"].astype(str).tolist()
                chosen = st.selectbox("अपडेट करने के लिए कार्य चुनें", options, key="v2_task_select")
                task_row = current[current["Task ID"].astype(str) == chosen].iloc[0]
                with st.form("v2_task_update"):
                    status = st.selectbox("स्थिति", ["लंबित", "प्रगति पर", "पूर्ण", "लागू नहीं"],
                                          index=["लंबित", "प्रगति पर", "पूर्ण", "लागू नहीं"].index(
                                              task_row["Status"]) if task_row["Status"] in
                                              ["लंबित", "प्रगति पर", "पूर्ण", "लागू नहीं"] else 0)
                    due = st.text_input("नियत तारीख (DD/MM/YYYY)", value=str(task_row["Due Date"]))
                    remarks = st.text_input("टिप्पणी", value=str(task_row["Remarks"]))
                    update = st.form_submit_button("कार्य अपडेट करें")
                if update:
                    ws = _worksheet("CASE CHECKLIST")
                    row_num = current.index[current["Task ID"].astype(str) == chosen][0] + 2
                    headers = ws.row_values(1)
                    for col, value in {
                        "Status": status, "Due Date": due, "Completed Date": _now()[:10] if status == "पूर्ण" else "",
                        "Remarks": remarks, "Updated At": _now(), "Updated By": _user()
                    }.items():
                        ws.update_cell(row_num, headers.index(col) + 1, value)
                    _audit("CHECKLIST_UPDATED", "CHECKLIST", chosen, status)
                    st.success("Checklist अपडेट हो गई।")
                    st.rerun()
            else:
                st.caption("इस मुकदमे की Checklist अभी नहीं बनी है।")

    # 4. OCR / document analysis - review-first; no automatic writeback.
    with tabs[3]:
        st.subheader("🔎 OCR एवं Document Analysis")
        st.warning("यह मॉड्यूल अभी सुरक्षित Review Workspace के रूप में शुरू किया गया है। OCR इंजन और AI provider की पुष्टि के बाद ही टेक्स्ट निकाला जाएगा।")
        case = _case_picker(df_cases, "v2_ocr_case")
        if case:
            source = st.file_uploader("विश्लेषण हेतु PDF / फोटो चुनें",
                                      type=["pdf", "jpg", "jpeg", "png"], key="v2_ocr_file")
            if source:
                st.write(f"फाइल: **{source.name}** | आकार: {len(source.getvalue()) / 1024:.1f} KB")
                st.info("फाइल अभी केवल इस स्क्रीन पर चयनित है। इसे किसी बाहरी AI सेवा पर नहीं भेजा गया है और कोई डेटा स्वतः सेव नहीं हुआ है।")
                st.text_area("निकाला गया टेक्स्ट (OCR इंजन जोड़ने के बाद यहाँ आएगा)", disabled=True,
                             key="v2_ocr_placeholder")
        st.caption("अगले तकनीकी चरण में स्थानीय OCR, PDF text extraction और मानवीय सत्यापन जोड़ा जाएगा।")

    # 5. Version history
    with tabs[4]:
        st.subheader("🗂️ Document Version History")
        case = _case_picker(df_cases, "v2_version_case")
        if case:
            case_id = _case_id(case)
            docs = _rows("CASE DOCUMENTS")
            docs = docs[docs["Case ID"].astype(str) == case_id] if not docs.empty else docs
            if docs.empty:
                st.info("पहले Documents टैब से प्रारंभिक दस्तावेज अपलोड करें।")
            else:
                labels = [f"{r['Document Name']} — {r['Category']} (v{r['Version']})"
                          for _, r in docs.iterrows()]
                selected = st.selectbox("दस्तावेज चुनें", labels, key="v2_version_doc")
                doc = docs.iloc[labels.index(selected)]
                group_id = str(doc["Document Group ID"])
                with st.form("v2_new_version"):
                    new_file = st.file_uploader("नया संशोधित संस्करण", type=["pdf", "jpg", "jpeg", "png", "docx"])
                    change = st.text_input("इस संस्करण में क्या बदला?")
                    add_version = st.form_submit_button("नया संस्करण अपलोड करें")
                if add_version:
                    if new_file is None or not change.strip():
                        st.error("नई फाइल और बदलाव का विवरण दोनों आवश्यक हैं।")
                    else:
                        try:
                            versions = _rows("DOCUMENT VERSIONS")
                            group_rows = versions[versions["Document Group ID"].astype(str) == group_id]
                            next_version = int(pd.to_numeric(group_rows["Version Number"], errors="coerce").max() or 1) + 1
                            file_id, link = _drive_upload(
                                new_file, f"{case_id}_{group_id}_v{next_version}_{new_file.name}"
                            )
                            doc_id = str(uuid.uuid4())
                            _append("CASE DOCUMENTS", {
                                "Document ID": doc_id, "Case ID": case_id, "ST NO": case["ST NO"],
                                "Document Group ID": group_id, "Document Name": doc["Document Name"],
                                "Category": doc["Category"], "Drive File ID": file_id, "Drive Link": link,
                                "Version": next_version, "Uploaded At": _now(), "Uploaded By": _user(),
                                "Remarks": change,
                            })
                            _append("DOCUMENT VERSIONS", {
                                "Version ID": str(uuid.uuid4()), "Document Group ID": group_id,
                                "Document ID": doc_id, "Case ID": case_id, "ST NO": case["ST NO"],
                                "Version Number": next_version, "Drive File ID": file_id, "Drive Link": link,
                                "Change Remarks": change, "Uploaded At": _now(), "Uploaded By": _user(),
                            })
                            _audit("DOCUMENT_VERSION_ADDED", "VERSIONS", doc_id, change)
                            st.success(f"Version {next_version} सुरक्षित हो गया। पुराना संस्करण नहीं हटाया गया।")
                            st.rerun()
                        except Exception as exc:
                            st.error(f"नया संस्करण सेव नहीं हुआ: {exc}")
                versions = _rows("DOCUMENT VERSIONS")
                versions = versions[versions["Document Group ID"].astype(str) == group_id] if not versions.empty else versions
                if not versions.empty:
                    st.dataframe(versions.sort_values("Version Number", ascending=False),
                                 use_container_width=True, hide_index=True)

    # 6. AI drafting workspace - no external transmission until configured.
    with tabs[5]:
        st.subheader("✍️ AI Legal Drafting Assistant")
        st.warning("AI provider अभी कनेक्ट नहीं है। इस स्क्रीन पर कोई केस डेटा बाहरी सेवा को नहीं भेजा जाता।")
        case = _case_picker(df_cases, "v2_ai_case")
        if case:
            draft_type = st.selectbox("दस्तावेज का प्रारूप", [
                "गवाह अनुपस्थिति संबंधी पत्र", "न्यायालय को प्रार्थना पत्र",
                "जमानत आपत्ति का प्रारूप", "कृत कार्यवाही रिपोर्ट", "अन्य कार्यालयीन पत्र"
            ], key="v2_ai_type")
            facts = st.text_area("सत्यापित तथ्य / निर्देश", max_chars=6000,
                                 placeholder="केवल आवश्यक और सत्यापित तथ्य लिखें…")
            st.caption("AI सेवा, डेटा गोपनीयता और कानूनी स्रोत सत्यापित होने के बाद Generate सुविधा सक्रिय की जाएगी।")
            if st.button("ड्राफ्ट Workspace में सेव करें", key="v2_save_draft"):
                if not facts.strip():
                    st.error("ड्राफ्ट के लिए तथ्य / निर्देश आवश्यक हैं।")
                else:
                    draft_id = str(uuid.uuid4())
                    _append("AI DRAFTS", {
                        "Draft ID": draft_id, "Case ID": _case_id(case), "ST NO": case["ST NO"],
                        "Draft Type": draft_type, "Draft Text": facts,
                        "Status": "मानवीय समीक्षा लंबित", "Created At": _now(), "Created By": _user(),
                    })
                    _audit("DRAFT_NOTES_SAVED", "AI DRAFTS", draft_id, draft_type)
                    st.success("आपके दिए तथ्य सुरक्षित हो गए हैं। यह AI से तैयार ड्राफ्ट नहीं, समीक्षा हेतु नोट्स हैं।")

    # 7. Audit log
    with tabs[6]:
        st.subheader("🛡️ Activity & Audit Log")
        logs = _rows("AUDIT LOG")
        if logs.empty:
            st.info("अभी कोई V2 गतिविधि दर्ज नहीं है।")
        else:
            st.caption(f"कुल गतिविधियाँ: {len(logs)}")
            st.dataframe(logs.sort_values("Timestamp", ascending=False),
                         use_container_width=True, hide_index=True)
