# 04 — طرح بک‌اند، داده و امنیت

## قواعد دیتابیس
- UUID برای شناسه اصلی.
- `created_at`, `updated_at`, `deleted_at` در دامنه مناسب.
- Foreign key و Unique/Check constraint واقعی.
- Index مطابق query و EXPLAIN.
- Migration نسخه‌دار و قابل بازبینی.
- RLS برای تمام جدول‌های قابل دسترسی از Client.
- تراکنش برای wallet، purchase، reward و match result.
- هر تغییر اقتصادی Ledger تغییرناپذیر داشته باشد.

## مدل داده پیشنهادی
این طرح هدف است؛ پیش از افزودن، با جدول‌های موجود مقایسه شود تا Duplicate ساخته نشود.

### Identity / Social
- `profiles`: user_id، username، display_name، avatar_path، bio، privacy، locale، status.
- `user_settings`: notification/privacy/audio/accessibility preferences.
- `user_blocks`: blocker_id، blocked_id.
- `follows`: follower_id، following_id، status.
- `friendships`: user_a، user_b، status، requested_by.
- `user_presence`: user_id، last_seen، presence_state، expires_at.

### Messaging / Rooms
- `conversations`: id، type، created_by.
- `conversation_members`: conversation_id، user_id، role، joined_at، muted_until.
- `messages`: conversation_id، sender_id، body، media_id، reply_to، created_at، edited_at.
- `message_receipts`: message_id، user_id، delivered_at، read_at.
- `media_objects`: owner_id، storage_path، mime، size، moderation_status.
- `rooms`: owner_id، title، visibility، capacity، status، game_id.
- `room_members`: room_id، user_id، role، joined_at.
- `room_events`: room_id، actor_id، event_type، payload، created_at.

### Game / Competition
- `game_catalog`: game_id، rules_version، enabled، modes، min/max players.
- `matchmaking_tickets`: user_id، game_id، mode، party_id، rating_band، status، expires_at.
- `matches`: game_id، mode، status، rules_version، started_at، ended_at.
- `match_players`: match_id، user_id، team_id، seat، result.
- `match_events`: match_id، seq، actor_id، action_type، payload، idempotency_key.
- `match_snapshots`: match_id، seq، state_json، created_at.
- `game_ratings`: user_id، game_id، season_id، rating، games_played.
- `tournaments`: owner_id، game_id، format، status، starts_at، rules.
- `tournament_entries`: tournament_id، user_id/team_id، seed، status.
- `tournament_matches`: tournament_id، round، slot، match_id، winner_id.
- `seasons`: code، starts_at، ends_at، status.

### Economy / Progress
- `wallet_accounts`: user_id، currency، balance_cache.
- `wallet_ledger`: user_id، currency، delta، reason، reference_id، idempotency_key، created_at.
- `catalog_items`: sku، type، price، currency، availability، metadata.
- `inventory_items`: user_id، sku، quantity، acquired_at.
- `purchases`: user_id، provider، provider_txn_id، status، amount، currency.
- `gift_codes`: code_hash، reward_payload، max_uses، used_count، expires_at.
- `gift_redemptions`: code_id، user_id، redeemed_at.
- `missions`: mission_id، season_id، objective، reward.
- `mission_progress`: user_id، mission_id، progress، completed_at.
- `achievements`: achievement_id، criteria، reward.
- `user_achievements`: user_id، achievement_id، unlocked_at.

### Safety / Operations
- `reports`: reporter_id، target_type، target_id، reason، status.
- `moderation_actions`: moderator_id، target_id، action، reason، expires_at.
- `admin_audit_log`: actor_id، action، target، metadata، created_at.
- `notification_preferences`: user_id، category، enabled.
- `notification_jobs`: user_id، template_id، payload، scheduled_at، status.
- `feature_flags`: key، enabled، audience، config.

## RPC/APIهای ضروری
نام‌ها قراردادی‌اند و باید با کد فعلی تطبیق داده شوند:
`profile_update`, `follow_request_create`, `follow_request_accept`, `user_block`, `conversation_create`, `message_send`, `message_mark_read`, `room_create`, `room_join`, `room_leave`, `room_moderate`, `matchmaking_enqueue`, `matchmaking_cancel`, `match_reserve`, `match_action_submit`, `match_reconnect`, `match_forfeit`, `tournament_register`, `tournament_check_in`, `tournament_report_result`, `wallet_grant`, `wallet_spend`, `gift_code_redeem`, `mission_claim`, `achievement_claim`, `report_submit`, `moderation_apply`, `oracle_request`.

هر RPC باید Auth check، ورودی validate، rate limit، idempotency و خروجی ساخت‌یافته داشته باشد.

## RLS و دسترسی
- کاربر فقط داده خصوصی خودش را ویرایش کند.
- پروفایل عمومی فقط فیلدهای مجاز را expose کند.
- DM فقط برای اعضای همان Conversation خوانده شود.
- Storage path user-scoped و policyدار باشد.
- Room خصوصی فقط با دعوت/مجوز.
- نتیجه Match و Wallet از Client مستقیم Update نشود.
- Moderator فقط در محدوده نقش خود عمل کند.
- Admin actionها Audit شوند.
- SECURITY DEFINER فقط با `search_path` امن، حداقل privilege و تست سوءاستفاده.

## Wallet و خرید
- هر تغییر موجودی یک Ledger row دارد.
- `idempotency_key` برای هر پرداخت/Claim یکتا است.
- قیمت از Catalog سرور خوانده شود؛ مبلغ Client قابل اعتماد نیست.
- خرید واقعی با Google Play Billing و Server-side verification.
- Refund/chargeback، pending، failed و duplicate transaction مدیریت شود.
- Gift Code با hash ذخیره شود.
- Coin/Gem برای شرط‌بندی یا تبدیل نقدی خارج از قوانین استفاده نشود.
- موجودی Cache با Ledger Reconcile شود.

## احراز هویت دو Supabase
1. مشخص شود کدام پروژه مرجع Auth است.
2. Games project باید JWT کاربر را امن verify کند؛ user_id ارسالی کلاینت کافی نیست.
3. issuer، audience، expiry و key rotation مستند شود.
4. انتقال/حذف کاربر در هر دو دامنه هماهنگ شود.
5. اطلاعات حساس و Wallet بین پروژه‌ها mirror نشود.
6. تصمیم حفظ دو پروژه یا ادغام با ADR ثبت شود.

## LiveKit و تماس
- Client فقط Token کوتاه‌عمر از Edge Function بگیرد.
- سرور عضویت و نقش را بررسی کند.
- Token محدود به Room و identity باشد.
- پایان تماس، خروج و expiry تست شود.
- Secret فقط سمت سرور.
- Consent و Permission دوربین/میکروفون شفاف.
- Report و block/mute در تماس.

## ORACLE
- درخواست AI از سرور عبور کند؛ Provider key در APK نباشد.
- ورودی محدود و Rate limit شود.
- داده خصوصی فقط با رضایت و نیاز واقعی ارسال شود.
- AI اختیار مستقیم خرید/پرداخت/مدیریت حساب نداشته باشد.
- محتوای نامناسب و گزارش‌ها سیاست مشخص داشته باشند.
- سقف مصرف رایگان/Pro شفاف باشد.

## عملیات
Backup زمان‌بندی‌شده و Restore واقعی، Migration plan، Staging بدون PII، Runbook قطعی سرویس، خطای پرداخت و صف Match، و Alert برای خطا، queue stuck و ledger mismatch.
