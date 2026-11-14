# NEXORA — فینگر سوکر فضایی ⚽✨

[![Android APK + AAB (Godot)](https://github.com/asbiulder/Nexora_godot/actions/workflows/android.yml/badge.svg)](https://github.com/asbiulder/Nexora_godot/actions/workflows/android.yml)

**NEXORA** یک بازی ورزشی آنلاین موبایل است (طراحی اصلی React Native) که با **Godot 4.5.1** و **GDScript** بازنویسی شده. این مخزن شامل کل کد بازی، پلاگین چت صوتی LiveKit برای اندروید و پایپلاین کامل ساخت با GitHub Actions است.

> ✅ خروجیهای نهایی (APK و AAB) هر بار بهصورت خودکار از **GitHub Actions** ساخته و در بخش **Releases** همین مخزن منتشر میشوند.

---

## ✨ امکانات

- 🎮 گیمپلی دیسکی سریع با فیزیک ۲۴۰ هرتز — ضربات سنگین و پرتوان، مهرههای درشت، افکت برخورد، لرزش دوربین و ذرات
- 🏟 بیش از ۳۰ زمین، ۳۶ توپ، صدها دیسک (باشگاهی/ملی/ویژه/متالیک) و ترکیبهای تاکتیکی
- 🌐 بازی آنلاین: اتاقهای ۱v1/۲v2/۳v3، لیگ و ردهبندی، تورنمنت، آرنا، چالش روزانه، باشگاه و چت
- 🎙 چت صوتی با LiveKit (اندروید) و احراز هویت با Supabase
- 🧞 اوراکل (مربی هوشمند داخل بازی) با پیشنهاد ضربه و تحلیل
- 🇮🇷 رابط دوزبانه (فارسی پیشفرض / انگلیسی) با فونت Vazirmatn و Orbitron
- 🎨 HUD سهبعدی شیشهای داخل مسابقه، تم فضایی نئونی، افکت گلو و انیمیشن
- 📱 طراحی عمودی مخصوص موبایل (پایه ۱۰۸۰×۱۹۲۰)

---

## 🚀 اجرا روی کامپیوتر

1. **Godot 4.5.1** (نسخه استاندارد — نه Mono) را نصب کنید: https://godotengine.org/download
2. پوشه پروژه را در Godot باز کنید (`project.godot`).
3. `F5` بزنید (بار اول از خط فرمان: `godot --headless --import`).

> نکته: چت صوتی فقط روی اندروید کار میکند؛ روی دسکتاپ بقیه بازی (آفلاین و آنلاین) کامل قابل استفاده است.

### اجرای تستها

```bash
godot --headless -s res://tests/bot_match.gd      # ۲۰ مسابقه هوش مصنوعی (soak test)
godot --headless -s res://tests/voice_smoke.gd    # رفتار Voice روی غیر-اندروید
godot --headless -s res://tests/ui_walk.gd        # پیمایش خودکار همه صفحهها
```

---

## 📦 ساخت APK اندروید — GitHub Actions (پیشنهادی)

هر `push` روی شاخه `main` (یا اجرای دستی **Run workflow**) پایپلاین `android.yml` را اجرا میکند:

1. ساخت پلاگین چت صوتی (AAR) با Gradle و کپی در `android/plugins/nexora_livekit/`
2. دانلود Godot 4.5.1 + قالبهای خروجی (با کش)
3. ساخت keystore (یا استفاده از Secretها) و اکسپورت:
   - `NEXORA-v<version>-universal.apk` — همه گوشیها (توصیهشده)
   - `NEXORA-v<version>-arm64.apk` — نسخه کوچکتر برای گوشیهای ۶۴ بیتی
   - `NEXORA-v<version>.aab` — برای انتشار در Google Play
4. تست دود روی شبیهساز اندروید (نصب، اجرا، ورود به منو و یک مسابقه سریع)
5. انتشار خودکار در **Releases** با تگ `v<version>`

### امضای انتشار (اختیاری اما پیشنهادی)

پیشفرض: APK با کلید «sideload» داخل مخزن امضا میشود (فقط برای تست دستی؛ روی همان کلید، نسخههای جدید قابل نصب روی قبلی هستند). برای انتشار واقعی در Google Play، Secretهای زیر را در مخزن (Settings → Secrets and variables) تنظیم کنید:

| Secret | توضیح |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | فایل keystore بهصورت base64 |
| `ANDROID_KEYSTORE_USER` | alias کلید |
| `ANDROID_KEYSTORE_PASSWORD` | رمز کلید |

> ⚠️ قبل از انتشار در Google Play، کلید داخلی `android/keys/nexora-release.keystore` را حذف کنید (فقط برای تست است).

### ساخت محلی APK

1. JDK 17، Android SDK (platform 35 + build-tools 35.0.0) و Gradle 8.7+.
2. ساخت پلاگین: `cd plugin_src/livekit && gradle assembleRelease` سپس کپی `build/outputs/aar/nexora-livekit-release.aar` به `android/plugins/nexora_livekit/`.
3. در Godot: Editor Settings → Export → Android (تنظیم مسیر SDK/Java) ← Project → Install Android Build Template ← فعالسازی پلاگین **NexoraLiveKit** در Project Settings → Plugins ← Export → Android.

---

## 🗂 ساختار پروژه

| مسیر | محتوا |
|---|---|
| `project.godot` | تنظیمات پروژه — رزولوشن پایه ۱۰۸۰×۱۹۲۰ عمودی، i18n |
| `SPEC.md` | قرارداد فنی بین ماژولها (reference برای توسعهدهنده) |
| `src/core/` | اتولودها: `Data` (اطلاعات بازی)، `Store` (پروفایل محلی)، `Sfx` (صدا/لرزش)، `Nav` (مسیریاب صفحهها) |
| `src/game/` | `NxEngine` (فیزیک/AI)، `MatchView` (رندر صحنه)، `formation_picker.gd` |
| `src/screens/` | صفحههای آفلاین: خانه، تیم، بازی، فروشگاه، پروفایل، مسابقه، نتیجه |
| `src/online/` | بخش آنلاین: هاب، لابی، لیگها، تورنمنت، آرنا، مسابقه آنلاین |
| `src/social/` | دوستان، باشگاه، چت، پروفایل عمومی |
| `src/oracle/` | دستیار هوشمند داخل بازی |
| `src/net/` | کلاینت Supabase (Auth/REST/Realtime) + RoomLink + Voice (LiveKit) |
| `src/ui/` | کیت رابط (`Kit`)، تم (`NX`)، کروم، اسکرینهای پایه |
| `assets/i18n/` | فایلهای ترجمه (fa/en) — ۷۵۶+ رشته |
| `assets/` | فونتها (Orbitron, Exo2, Vazirmatn) و آرتورک بازی |
| `plugin_src/livekit/` | سورس Kotlin پلاگین چت صوتی اندروید |
| `.github/workflows/android.yml` | پایپلاین CI: AAR ← اکسپورت Godot ← APK/AAB ← تست ← Release |

---

## 🎮 گیمپلی

- **پایش**: روی دیسک خودت ضربه بزن تا انتخاب شود؛ انگشت را در خلاف جهت ضربه بکش (اسلینگشات) و رها کن.
- **حالتها**: مسابقه سریع، جام، تمرین، محلی ۲ نفره، و بخش آنلاین (۱v1 تا ۳v3).
- **تیم**: دیسک، توپ، زمین و ترکیب را از تیم خودت یا فروشگاه انتخاب کن.
- **لیگ**: با بردها امتیاز جمع کن و از برنز تا نکسورا صعود کن.

---

## 🛠 توسعه

- زبان: GDScript (تایپشده)، بدون C#/افزونه غیرضروری.
- فیزیک: `NxEngine` با گام ثابت ۲۴۰ هرتز و interpolation رندر؛ پارامترهای `classic` برای سازگاری بیتبهبیت با نسخه TS.
- تست: `tests/` شامل تستهای headless (بوتمچ، دود رابط، پاریتی، بررسی بافتها).
- قوانین پایه در `SPEC.md` مستند شدهاند.

---

