# ورودی‌های اصلی و نکات تحویل

فایل‌های اصلی که باید همراه این بسته به تیم داده شوند:
- `nexora-universe-work-fs-v7.zip` — سورس Flutter/Dart.
- `NEXORA_Station_Luxe.zip` — مرجع UI؛ یک نسخه از HTML و دارایی‌هایش در پوشه `reference/NEXORA_Station_Luxe/` موجود است.

سورس اصلی عمداً دوباره داخل این ZIP قرار نگرفته تا دو نسخه متناقض از کد اپ ایجاد نشود. تیم باید مخزن canonical GitHub را Clone کند؛ ZIP سورس پوشه `.git` ندارد.

Static inventory:
- 261 فایل Dart زیر `lib/`
- 16 فایل Game Entry
- 21 فایل در `supabase/migrations/`
- 14 فایل در `supabase/games/migrations/`
- 3 Edge Function entry
- 56 فایل تست زیر `test/`
- GitHub Actions workflows موجود

این بسته نباید شامل Service Role Key، LiveKit Secret، کلید امضای Production یا داده کاربران باشد.
