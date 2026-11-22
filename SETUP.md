# הקמת העותק

העותק מנותק מהמקור. הוא לא כותב ל-Firebase של הבעלים ולא מעלה ל-Cloudinary שלו, ואי אפשר לדחוף ממנו למאגר שלו.
עד שממלאים את הפרטים, דף הניהול מציג "Firebase עדיין לא הוגדר" ושום שינוי לא נשמר.

## 1. Firebase (מסד הנתונים)
1. ב-console.firebase.google.com יוצרים פרויקט, ובו Realtime Database. **לא** לבחור Test Mode.
2. מעתיקים את כתובת המסד ואת מזהה הפרויקט.
3. ב-`index.html` ממלאים את הבלוק `firebaseConfig`: `databaseURL`, `projectId`, `authDomain`.
4. מפרסמים את הכללים:
   ```bash
   firebase deploy --only database --project <PROJECT_ID>
   ```

## 2. Cloudinary (וידאו)
יוצרים חשבון ו-upload preset מסוג unsigned, וממלאים ב-`index.html` את `MEDIA_UPLOAD = { cloud, preset }`.
כדאי להגביל ב-preset את סוגי הקבצים ואת הגודל.

## 3. אירוח
יוצרים מאגר GitHub משלך, מפעילים GitHub Pages, ומחליפים את `https://shdydaniel.github.io/luach/` ב-`board-kiosk.bat` וב-`README.txt` בכתובת שתתקבל.
בכל שינוי בלוח מעלים את המספר ב-`var CACHE = "luach-v26"` שב-`sw.js`.

## 4. סיסמת הניהול
ברירת המחדל היא `770`, ומחליפים אותה מדף הניהול.
**הסיסמה נבדקת רק בדפדפן.** כל מי שיודע את כתובת המסד יכול לכתוב אליו ישירות.

## הרצה מקומית
```bash
python3 -m http.server 8766 --bind 127.0.0.1
```
http://localhost:8766 ו-http://localhost:8766/#manage

אחרי 22:00 הלוח מעומעם, וזו התנהגות מכוונת (כיבוי אורות).
