# 02 — نقشه بازی‌ها و ۱۵ بازی جدید

## بازی‌های موجود در سورس
1. Finger Soccer
2. Carrom
3. Billiards
4. Backgammon
5. Ludo
6. Snakes & Ladders
7. UNO
8. Quiz
9. Mafia
10. Kart Racing
11. Obstacle Race
12. Bomb Arena
13. Pool8
14. Mini Golf
15. Basketball Battle
16. Spy Mafia

وجود `supportsOnline: true` به‌تنهایی اثبات نمی‌کند بازی آنلاین Production-ready است؛ هر بازی باید جداگانه تست شود. Billiards و Pool8 از نظر دامنه نام هم‌پوشان دارند و تفاوت قوانین/UX آن‌ها باید بررسی شود.

## پانزده بازی پیشنهادی جدید
این‌ها پیشنهاد محصولی هستند و هنوز در سورس به‌عنوان بازی کامل تأیید نشده‌اند.

| # | بازی | حالت | ظرفیت | دلیل انتخاب |
|---:|---|---|---:|---|
| 1 | Chess Blitz | رقابتی | 1v1 | عمق و رقابت بلندمدت |
| 2 | Checkers Arena | رقابتی | 1v1 | یادگیری ساده |
| 3 | Connect Four | رقابتی | 1v1 | راند کوتاه |
| 4 | Tic-Tac-Toe Royale | رقابتی/مینی | 1v1 | ورود سریع |
| 5 | Domino Clash | رقابتی/مهمانی | 2–4 | بازی گروهی |
| 6 | Word Duel | رقابتی | 1v1/2v2 | زبان و سرعت فکر |
| 7 | Draw & Guess | Party | 3–8 | تعامل و اشتراک‌گذاری |
| 8 | Memory Match | Solo/دوئل | 1/1v1 | تجربه کوتاه و رکوردی |
| 9 | Battleship | رقابتی | 1v1 | استراتژی |
| 10 | Air Hockey | رقابتی | 1v1 | فیزیک آرکیدی |
| 11 | Table Tennis Duel | رقابتی | 1v1 | ورزشی و مهارتی |
| 12 | Dodgeball Arena | تیمی | 2v2–3v3 | هیجان و تاکتیک |
| 13 | Rhythm Clash | Solo/دوئل | 1/1v1 | ریتم و رکورد |
| 14 | Tower Defense Co-op | Co-op | 2–4 | همکاری و پیشرفت |
| 15 | Daily Puzzle Lab | Solo/تیمی | 1/گروهی | محتوای تازه روزانه |

### موج‌های انتشار
- **Wave A:** Connect Four، Domino Clash، Draw & Guess، Word Duel، Memory Match.
- **Wave B:** Chess Blitz، Checkers، Battleship، Air Hockey، Table Tennis.
- **Wave C:** Dodgeball، Rhythm Clash، Tower Defense Co-op، Daily Puzzle Lab، Tic-Tac-Toe Royale.

بازی‌های Real-time و فیزیکی پس از اثبات معماری Realtime و Anti-cheat ساخته شوند.

## قرارداد مشترک Game Engine
هر بازی باید داشته باشد:
- `game_id` ثابت و نسخه‌دار، `rules_version` و `protocol_version`.
- GameConfig برای ظرفیت، تیم، زمان و قوانین.
- State قابل Serialize و Actionهای محدود و اعتبارسنجی‌پذیر.
- State transition مستقل از UI.
- Bot با سطح دشواری مشخص.
- Lifecycle: created → waiting → ready → playing → completed/aborted.
- Reconnect، snapshot، event replay و idempotency.
- Result معتبرشده توسط سرور.
- Unit tests برای قوانین و Widget/Render tests برای UI.

## Matchmaking
- Queue جدا برای game، region، mode، skill band و party size.
- ELO/MMR فقط از نتیجه معتبر سرور تغییر کند.
- جلوگیری از Match دوباره و Reservation صندلی با TTL.
- Grace period برای reconnect.
- انصراف و penalty متناسب با مرحله مسابقه.
- Party lock برای 2v2/3v3 و تعیین تیم پیش از Match.

## تورنمنت و لیگ
- Single Elimination، Double Elimination و Round Robin.
- Check-in، Seed، Bracket و مدیریت No-show.
- نتیجه با تأیید سرور یا داوری/اعتراض.
- Disconnect، Disqualification و آرشیو برندگان.
- جایزه شفاف و غیرقمارگونه.

## ضدتقلب
- کلاینت Intent/Action می‌فرستد، نه نتیجه نهایی.
- زمان، نوبت، امتیاز و پاداش در سرور اعتبارسنجی شود.
- Rate limit، توالی نوبت و idempotency.
- Event log برای بررسی اختلاف.
- برای بازی Real-time مدل authority و reconciliation جداگانه طراحی شود.
