# App Store Connect — כל הפרטים להגשה

כל שדה למטה מוכן להעתקה כמו שהוא. הערה: השדות באנגלית נדרשים רק אם בוחרים גם לוקליזציה
באנגלית; אפשר להגיש בעברית בלבד (Primary language: Hebrew).

## 1. App Information

| שדה | ערך |
|---|---|
| Name (עד 30 תווים) | `הלכות הבן איש חי` |
| Subtitle (עד 30) | `הלכה יומית לפי פרשת השבוע` |
| Bundle ID | **להחליף** את ה־placeholder `com.benishchai.halachayomit` למזהה של החשבון שלך (Xcode → Signing) |
| SKU | `benishchai-halacha-001` (כל מחרוזת ייחודית) |
| Primary language | Hebrew |
| Primary category | Reference |
| Secondary category | Education |
| Content rights | לסמן **No** לשאלה על תוכן צד־שלישי מוגן: הספר עצמו נחלת הכלל (המחבר נפטר 1909), הביאור, העיצוב והאפליקציה — יצירה מקורית שלנו, © Ilay Janashvili. |
| Age rating | כל התשובות "None/No" → **4+** |
| Price | Free |
| Availability | כל המדינות |

## 2. Version Information (1.0)

**Promotional text (עד 170 תווים)**
```
הלכה אחת ביום, לפי הסדר של הבן איש חי. פרשת השבוע, הלכות החג, ביאור פשוט. עובד גם בלי אינטרנט.
```

**Description (עד 4,000 תווים)**
```
הלכה אחת ביום. בדיוק לפי הסדר של הבן איש חי.

כל ההלכות של רבינו יוסף חיים זצוק"ל מספר הבן איש חי, לפי פרשת השבוע, עם ביאור בעברית פשוטה לכל נפש.

• פרשת השבוע נבחרת לבד, כל שבוע
• לפני כל חג: הלכות החג, מחולקות לימים
• לימוד לפי נושא: תפילה, ברכות, שבת, כשרות ועוד
• חיפוש בכל הספר
• סימון "למדתי", התקדמות ומועדפים
• תזכורת יומית
• עובד גם בלי אינטרנט. בלי חשבון, בלי פרסומות.

פותחים, קוראים, ממשיכים ביום.
```

**Keywords (עד 100 תווים, מופרדים בפסיק, בלי רווחים)**
```
בן איש חי,הלכה,הלכה יומית,פרשת השבוע,יוסף חיים,הלכות,תורה,יהדות,ספרדי,שבת,ברכות,תפילה
```

**Support URL** — `https://halacha-yomit-app.surge.sh/support.html` (עמוד תמיכה חי, עם מייל)
**Marketing URL** (אופציונלי) — `https://halacha-yomit-app.surge.sh/`
**Privacy Policy URL** — `https://halacha-yomit-app.surge.sh/privacy.html` (חי)
**Copyright** — `© 2026 Ilay Janashvili`
**Version** — `1.0`. **Build** — מוגדר ב־Xcode (`CURRENT_PROJECT_VERSION = 1`).

**What's New (גרסה 1.0)**
```
הגרסה הראשונה: כל הלכות הבן איש חי לפי פרשת השבוע, הלכות החגים, לימוד לפי נושא, חיפוש, מעקב התקדמות ותזכורת יומית.
```

## 3. App Review Information

| שדה | ערך |
|---|---|
| Sign-in required | **No** (אין חשבון בכלל) |
| Contact | שם + טלפון + מייל של המפרסם |
| Notes for the reviewer | ראו למטה |

**Notes** (אנגלית, לבודק של אפל)
```
The app is a study companion for the Hebrew halachic work "Ben Ish Chai" (public domain, author d. 1909) with an original plain-Hebrew commentary. All content is bundled; no account, no login, no purchases, no ads.

Native features beyond the web view: a daily local notification (Local Notifications only, no push server), offline storage of the full text, share-as-image.

The home screen shows this week's Torah portion (computed from the device's Hebrew calendar) and, on the weekdays before a Jewish festival, a gold "festival halachot" card. Content is Hebrew only, right-to-left.

Privacy: the app does not collect personal data. It only increments an anonymous "devices" counter and an anonymous "currently online" presence flag in a Firebase Realtime Database (random key, no identifiers) — described in the privacy policy.
```

## 4. App Privacy (שאלון הפרטיות)

- "Do you or your third-party partners collect data from this app?" → **No** (Data Not Collected).
  הנימוק: לא נשלח שום מזהה מכשיר, שם, מיקום, כתובת או תוכן. המונה האנונימי אינו "data linked to the
  user" ואינו "tracking" לפי ההגדרות של אפל. מדיניות הפרטיות מתארת אותו במפורש, כך שההצהרה עקבית.
- אם מעדיפים להיות שמרניים: "Yes" → קטגוריה **Other Usage Data** → Not linked to you → Not used for tracking → purpose: App Functionality.

## 5. Export Compliance

- `ITSAppUsesNonExemptEncryption = false` כבר ב־Info.plist → App Store Connect לא ישאל. אם ישאל:
  "Does your app use encryption?" → **No** (רק HTTPS סטנדרטי).

## 6. Screenshots

- **iPhone 6.9"** (חובה, 1320×2868): 7 תמונות מוכנות ב־`appstore/screenshots_6.9/` — מסך השבוע עם
  כרטיס החג, קורא הלכה, ביאור, לפי נושא, כל הפרשיות, חיפוש, מצב כהה. מומלץ להעלות 5–7.
- iPhone 6.5" — לא חובה (App Store Connect משתמש ב־6.9" גם ל־6.5").
- iPad — **לא נדרש**: האפליקציה מוגדרת iPhone בלבד (`TARGETED_DEVICE_FAMILY = 1`), Portrait בלבד.
  (iPad עדיין יכול להריץ אותה במצב תאימות.)
- App icon 1024×1024 ללא אלפא — ב־`Assets.xcassets` (נכנס אוטומטית ל־build).
- App Preview (וידאו) — לא חובה.

## 7. תהליך ההגשה (סדר פעולות)

1. Xcode → App target → Signing & Capabilities → Team + Bundle ID חדש.
2. Product → Archive → Distribute App → App Store Connect → Upload.
3. App Store Connect → My Apps → + New App (שם, Bundle ID, SKU, שפה Hebrew).
4. למלא את סעיפים 1–5 מהקובץ הזה, להעלות את הצילומים, לבחור את ה־build.
5. TestFlight על מכשיר אמיתי (מומלץ, לא חובה) → Submit for Review.

## 8. סיכונים אפשריים בבדיקה (Review) ואיך עונים

- **4.2 Minimum functionality / "web wrapper"** — האפליקציה כוללת התראה מקומית, תוכן מלא אופליין
  ושיתוף כתמונה; התוכן וההיגיון (לוח עברי, חלוקת הלכות החג) הם ייחודיים לה. הערות הבודק למעלה מסבירות.
- **5.1.1 Privacy** — יש מדיניות פרטיות חיה ומתוארת. אין בקשת הרשאה מלבד התראות (בקשה בהפעלה
  הראשונה, עם הסבר המערכת).
- **2.1 Crash** — נבדק על סימולטור iPhone 17 Pro/Pro Max, iOS 26.5; מומלץ להריץ פעם אחת על מכשיר אמיתי.
