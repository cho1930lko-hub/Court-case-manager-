# ⚖️ पैरवी रजिस्टर (Court Case Management App)

भिंगा, जनपद श्रावस्ती — सेशन कोर्ट के मुकदमे, गवाह-समन, Dak और Rimand रजिस्टर मैनेज करने के लिए Streamlit ऐप।

## डेटा कहाँ रहता है

**Google Sheets** — यही ऐप का पूरा डेटाबेस है (लोकल Excel फ़ाइल का इस्तेमाल नहीं होता)।
शीट में 3 sheets होनी चाहिए:

| Sheet नाम | इस्तेमाल |
|---|---|
| `सेशन कोर्ट` | मुकदमों की मुख्य लिस्ट (ST NO, धारा, बनाम, तलब साक्षी, Status आदि) |
| `Dak REGISTER` | डाक की entries (साक्षी सम्मन, अभियुक्त सम्मन, मुसन्ना, तलबाना नोटिस) |
| `RIMAND REGISTER` | रिमांड entries |

कनेक्शन `gsheet.py` में `gspread` + Google service account से होता है।

## Setup (`.streamlit/secrets.toml`)

```toml
APP_PASSWORD = "आपका password"       # खाली छोड़ने पर login screen नहीं दिखेगी
SHEET_URL    = "https://docs.google.com/spreadsheets/d/....."
JANPAD       = "श्रावस्ती"
THANA        = "कोतवाली भिंगा"

GOOGLE_CREDENTIALS = '''
{... service account JSON यहाँ paste करें ...}
'''
```

Google Sheet को उस service account के email के साथ **Editor access** से share करना ज़रूरी है।

## कैसे चलाएं

```bash
pip install -r requirements.txt
streamlit run app.py
```

## ऐप में क्या है

- **📊 Dashboard** — कुल मुकदमे, साक्ष्य stage, pending समन, Dak pending, आज की पेशी — mobile-friendly cards में; overdue केस अलर्ट; आने वाली पेशियां (7 दिन)
- **📋 सेशन कोर्ट** — पूरी केस लिस्ट, search/filter (Status/न्यायालय/सम्मन स्थिति), Excel डाउनलोड, WhatsApp शेयर
- **➕ नया केस / ✏️ केस अपडेट** — Google Sheet में सीधे row जोड़ना/अपडेट करना
- **🖨️ समन जनरेटर** — "सम्मन की स्थिति = बनाना है" वाले cases से 4 तरह के दस्तावेज़ (समन साक्षी / BW / NBW / मृत्यु आख्या) का **HTML** बनाता है — A4 landscape, 2 दस्तावेज़/page, Print/PDF हेतु
- **📝 कृत कार्यवाही रिपोर्ट** — तारीख या धारा के आधार पर filter करके printable HTML रिपोर्ट (auto font-shrink)
- **📬 Dak Register** — List/Update + नई entry जोड़ना; **INCOMPLETE entries को थाने भेजने के लिए एक-क्लिक HTML रिपोर्ट** (print/PDF करके थाना प्रभारी को भेजी जा सकती है)
- **🔒 Rimand Register** — रिमांड entries की list + नई entry

## दस्तावेज़ आउटपुट — सिर्फ HTML

सभी दस्तावेज़ (समन, कृत कार्यवाही रिपोर्ट, Dak रिपोर्ट) **HTML** में ही बनते हैं — कोई `.docx` जनरेट नहीं होता।
HTML फ़ाइल को ब्राउज़र में खोलकर `Ctrl+P` दबाने से सीधे Print या PDF हो जाएगी।

## फ़ाइल संरचना

```
case_management/
├── app.py              # मुख्य Streamlit ऐप (UI + routing)
├── gsheet.py            # Google Sheets read/write/append/update (CRUD)
├── summon_gen.py         # समन/वारंट/मृत्यु आख्या — HTML जनरेशन
├── karyawahi_gen.py       # कृत कार्यवाही रिपोर्ट — HTML जनरेशन
├── dak_gen.py             # Dak Register (INCOMPLETE) — थाने भेजने हेतु HTML रिपोर्ट
├── requirements.txt
└── .streamlit/
    └── secrets.toml       # APP_PASSWORD, SHEET_URL, JANPAD, THANA, GOOGLE_CREDENTIALS
```

> **नोट:** `bulk_generator.py` और `html_generator.py` पुरानी/legacy फाइलें हैं — ये `app.py` में कहीं
> import नहीं होतीं और `bulk_generator.py` को चलाने के लिए `python-docx` चाहिए जो `requirements.txt` में
> है ही नहीं। चूंकि सिर्फ HTML आउटपुट चाहिए, इन दोनों फाइलों को safely डिलीट किया जा सकता है।

## आगे क्या जोड़ा जा सकता है

- सेशन कोर्ट लिस्ट (टैब 2) को भी mobile पर card-view देना (अभी वहां wide table है)
- Dak रिपोर्ट में "थाना" के हिसाब से group करके अलग-अलग PDF बनाना (अगर कई थानों को भेजना हो)
- Rimand Register में भी search/filter जोड़ना
- eCourts से auto-fetch जोड़ना (अभी जानबूझकर manual रखा गया है)
- WhatsApp शेयर की तरह Dak रिपोर्ट के लिए भी सीधा WhatsApp लिंक बटन
