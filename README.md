# ⚖️ पैरवी रजिस्टर — Court Case Manager

भिंगा, जनपद श्रावस्ती के सेशन कोर्ट से संबंधित मुकदमों, गवाह/सम्मन, डाक और रिमांड रजिस्टर के प्रबंधन के लिए मोबाइल-अनुकूल Streamlit वेब ऐप।

> **डेटा स्रोत:** ऐप Google Sheets से डेटा पढ़ती और उसी में बदलाव सेव करती है। Excel फ़ाइल मुख्य डेटाबेस नहीं है। ऐप की UI खाली डेटा के साथ भी खुल सकती है, लेकिन रिकॉर्ड जोड़ने/बदलने के लिए Google Sheets कनेक्शन सही होना चाहिए।

## मुख्य सुविधाएँ

- **📊 Dashboard:** त्वरित पहुँच बटन, केस खोज, और उपलब्ध रिकॉर्ड का सारांश।
- **📋 सेशन कोर्ट:** ST NO, अभियुक्त/बनाम, मु0अ0सं0 या धारा से खोज; स्थिति, न्यायालय और सम्मन स्थिति के फ़िल्टर; मोबाइल कार्ड दृश्य और डेस्कटॉप टेबल दृश्य; अगली पेशी की तारीख अपडेट और केस शेयर/अपडेट के विकल्प।
- **➕ नया केस / ✏️ केस अपडेट:** Google Sheet में केस जोड़ना और मौजूदा केस अपडेट करना।
- **🖨️ समन जनरेटर:** उपलब्ध केस डेटा से समन/वारंट/अन्य संबंधित दस्तावेज़ों के लिए HTML तैयार करना।
- **📝 कृत कार्यवाही रिपोर्ट:** उपलब्ध केस डेटा से फ़िल्टर की हुई, प्रिंट करने योग्य HTML रिपोर्ट।
- **📬 Dak Register:** डाक की entries देखना/अपडेट करना, नई entry जोड़ना और उपलब्ध रिपोर्ट बनाना; नई entry में मोबाइल कैमरे से फोटो लेना या गैलरी से एक/अधिक फोटो चुनकर निजी Google Drive में अपलोड करना। फोटो लिंक `लिंक` कॉलम में सेव होते हैं।
- **🔒 Rimand Register:** रिमांड entries देखना और नई entry जोड़ना।
- **📱 Responsive UI:** मोबाइल और बड़े स्क्रीन के लिए अनुकूल लेआउट।

ऐप के दस्तावेज़ जनरेटर HTML आउटपुट बनाते हैं। ब्राउज़र से HTML को Print करके PDF में सेव किया जा सकता है; ऐप को स्वतः DOCX जनरेटर न समझें।

## Google Sheets सेटअप

ऐप को एक Google Spreadsheet चाहिए, जिसमें नीचे दिए गए **चार worksheet tabs** मौजूद हों। टैब के नाम बिल्कुल वैसे ही रखें:

| Worksheet tab का नाम | उपयोग |
|---|---|
| `सेशन कोर्ट` | मुख्य मुकदमा सूची |
| `Dak REGISTER` | डाक रजिस्टर |
| `RIMAND REGISTER` | रिमांड रजिस्टर |
| `Address Book` | संपर्क सूची |

मुख्य कॉलमों के नाम भी कोड के अनुसार होने चाहिए। विशेष रूप से सेशन कोर्ट शीट में `ST NO`, `मु0अ0स0`, `धारा`, `बनाम`, `न्यायालय`, `तलब साक्षी`, `पिछली पेशी`, `अगली तारीख पेशी`, `Status` और `सम्मन की स्थिति` जैसे हेडर रखें। ऐप कुछ अनुपस्थित कॉलम खाली जोड़कर संभाल सकती है, लेकिन डेटा लिखने के लिए अपेक्षित हेडर मौजूद होना ज़रूरी है।

### Google Cloud और Service Account

1. Google Cloud Console में प्रोजेक्ट बनाएं या चुनें।
2. **Google Sheets API** और **Google Drive API** सक्षम करें।
3. एक Service Account बनाकर उसकी JSON key प्राप्त करें।
4. JSON में मौजूद `client_email` को Google Spreadsheet के **Share** विकल्प में **Editor** अनुमति दें। शीट को सार्वजनिक करने की आवश्यकता नहीं है।
5. Spreadsheet URL कॉपी करें। उसे Streamlit Secrets में `SHEET_URL` के रूप में सेट करें।
6. Dak फोटो अपलोड के लिए Google Drive में एक **निजी folder** बनाएं। उस folder को Service Account के `client_email` के साथ Editor access से share करें और folder ID को `DRIVE_FOLDER_ID` में सेट करें। यदि उपयोगकर्ता को फोटो खोलनी है, तो उसी folder को उस अधिकृत Google खाते के साथ भी share करें। फ़ाइलों को सार्वजनिक (Anyone with the link) न करें।

## Streamlit Secrets कॉन्फ़िगरेशन

लोकल विकास के लिए `.streamlit/secrets.toml` फ़ाइल बनाएं। Streamlit Community Cloud पर ऐप के **Settings / Secrets** क्षेत्र में यही सेटिंग्स डालें।

```toml
APP_PASSWORD = "अपना-मजबूत-पासवर्ड"
SHEET_URL = "https://docs.google.com/spreadsheets/d/YOUR_SPREADSHEET_ID/edit"
DRIVE_FOLDER_ID = "YOUR_PRIVATE_DRIVE_FOLDER_ID" # वैकल्पिक, फोटो इसी folder में सेव होंगी
JANPAD = "श्रावस्ती"
THANA = "कोतवाली भिंगा"

GOOGLE_CREDENTIALS = '''
{
  "...": "यहाँ Service Account JSON की पूरी सामग्री रखें"
}
'''
```

ऊपर का JSON केवल उदाहरण है; इसे वास्तविक Service Account JSON से बदलें। `GOOGLE_CREDENTIALS` में JSON की पूरी सामग्री दें और `SHEET_URL` में सही Spreadsheet URL रखें। असली credentials, निजी key या `secrets.toml` को GitHub में commit न करें। यदि credentials कभी सार्वजनिक हो जाएँ, तो उस key को revoke करके नई key बनाएं।

## लोकल रन

Python इंस्टॉल होने के बाद प्रोजेक्ट डायरेक्टरी में चलाएं:

```bash
pip install -r requirements.txt
streamlit run app.py
```

## Google Sheet कनेक्शन की समस्या हो तो

1. Streamlit Cloud में **Manage app → Logs** खोलें और ऐप को दोबारा चलाकर नवीनतम error देखें।
2. `KeyError: 'GOOGLE_CREDENTIALS'` या `KeyError: 'SHEET_URL'` आए तो Secrets के नाम जांचें।
3. `SpreadsheetNotFound` आए तो URL/Spreadsheet ID और Service Account की Share अनुमति जांचें।
4. `APIError 403` आए तो Sheets/Drive API और Service Account की अनुमति जांचें।
5. `WorksheetNotFound` आए तो चारों worksheet tabs के नाम और spelling जांचें।
6. `requirements.txt` में `gspread` और `google-auth` शामिल हैं; deploy के बाद dependency installation पूरा होने दें।

किसी error की जाँच के लिए केवल error message साझा करें। Service Account JSON, private key, password या संवेदनशील मुकदमे का डेटा साझा न करें।

## प्रोजेक्ट संरचना

```
.
├── app.py              # मुख्य Streamlit UI और navigation
├── gsheet.py           # Google Sheets read/write/update functions
├── summon_gen.py       # समन/संबंधित दस्तावेज़ों का HTML
├── karyawahi_gen.py    # कृत कार्यवाही रिपोर्ट का HTML
├── dak_gen.py          # Dak रिपोर्ट का HTML
├── requirements.txt    # Python dependencies
└── .streamlit/
    └── secrets.toml    # लोकल secrets; GitHub पर commit न करें
```

## मौजूदा स्थिति और सीमाएँ

- ऐप Google Sheets पर निर्भर है; कोई अलग स्थानीय Excel डेटाबेस कॉन्फ़िगर नहीं है।
- Dashboard और केस सूची खाली डेटा के साथ UI दिखा सकते हैं, लेकिन वास्तविक रिकॉर्ड पढ़ने/लिखने के लिए वैध Google credentials, सही Spreadsheet URL और अपेक्षित worksheet tabs आवश्यक हैं।
- UI या कोड में बदलाव के बाद Streamlit Cloud Logs में नवीनतम run की जाँच करें। केवल GitHub commit होना, ऐप के सफलतापूर्वक चलने का प्रमाण नहीं है।
