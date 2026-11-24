# 05 — مشخصات پیاده‌سازی UI/UX

## جهت هنری
مرجع Station Luxe:
- Base نزدیک `#07080C`
- Gold نزدیک `#D9B872`
- Gold highlight نزدیک `#F6E7BD`
- Gold shadow نزدیک `#8A6A2C`
- Glass surface با سفید بسیار کم‌شفاف و Blur محدود
- Vazirmatn برای فارسی/متن؛ Cormorant Garamond فقط برای تیتر لاتین تزئینی. فونت‌ها باید داخل اپ باشند و به CDN وابسته نباشند.

## Design Tokens
- Color: background، surface، elevated، border، textPrimary، textMuted، accentGold، success، warning، danger.
- Radius: 12 / 18 / 24 / 30.
- Spacing: 4 / 8 / 12 / 16 / 24 / 32.
- Elevation کم و کنترل‌شده؛ Glow دائمی ممنوع.
- Motion: 180–320ms برای تعامل؛ 500–800ms فقط برای انتقال نمایشی.
- Touch target حداقل 44–48dp.
- RTL واقعی، safe area و number formatting تست شوند.

## صفحات
### Hub
Carousel جهان‌ها، ادامه فعالیت، دوستان آنلاین، روم‌های قابل پیوستن، رویداد/چالش منتخب، Header پروفایل و Wallet زنده، Bottom nav، Loading skeleton، Empty و Offline.

### Play / Arcade
جست‌وجو و دسته‌بندی؛ کارت بازی با ظرفیت، مدت، Online/Solo، رنک و وضعیت؛ Game detail با قوانین/مود/ظرفیت؛ Quick Match و Friend Invite. آیتم Feature Flag خاموش نباید مثل قابلیت فعال نمایش داده شود.

### Social
Feed، Stories، Following/Discover، DM، گروه، کانال، Room discovery و Voice stage؛ Report، Block و Mute.

### Compete
Tournament cards، لیگ، رنک، فصل، Bracket قابل زوم/اسکرول، Match detail و تاریخچه.

### Profile / Personal Orbit
هویت، سطح، XP، آمار، دستاورد، کلکسیون، Edit profile، privacy، blocked users، Avatar wardrobe و room customization.

### Exchange
Catalog، item detail، preview، confirm purchase، موجودی، transaction history، gift flow و redemption؛ success/failure/refund.

### ORACLE
Chat/assistant، suggested prompts، game help، indicator پاسخ AI، خطای سرویس و کنترل سابقه/حریم خصوصی.

## Componentهای مشترک
NxGlassCard، NxGoldButton، NxWorldCarousel، NxBottomNav، NxAvatar، NxCurrencyChip، NxSectionHeader، NxEmptyState و NxErrorState. همه از Theme و Design tokens مرکزی استفاده کنند.

## HTML Prototype به Flutter
- HTML فقط Reference بصری و Asset map است.
- DOM مستقیماً به WebView منتقل نشود.
- از Flutter Theme و Riverpod/Router موجود استفاده شود.
- داده UI از Repository/Provider بیاید؛ نام Ashkan، موجودی‌های نمونه، سطح 24 و تعداد 4 روم هرگز برای کاربر واقعی hardcode نشوند.
- تمام دکمه‌ها به Route/Use Case واقعی متصل شوند.
- Assetهای غایب با manifest رسمی و fallback مدیریت شوند.
- ذرات و parallax lifecycle-aware باشند و در Reduce Motion خاموش شوند.

## فارسی/انگلیسی و Accessibility
- تمام متن‌ها از localization resources.
- تاریخ/زمان/عدد/واحد پول بر اساس locale.
- تست RTL روی متن‌های ترکیبی فارسی/انگلیسی.
- عرض 320dp تا تبلت.
- Contrast مناسب، TalkBack label، Focus order، Reduce Motion، فونت قابل افزایش.
- وضعیت فقط با رنگ منتقل نشود.
