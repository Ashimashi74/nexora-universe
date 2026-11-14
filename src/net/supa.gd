extends Node
## Supa — Supabase client for NEXORA (autoload "Supa").
## GoTrue auth (+ persisted session, auto refresh), PostgREST, RPC, Edge Functions, Storage, Realtime.
## Every network call returns {ok: bool, data: Variant, error: String (fa), status: int, raw: String}
## and never throws: failures become ok=false with a Persian message from err_fa().

const URL := "https://eisstodgncimypdawisy.supabase.co"
const KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVpc3N0b2RnbmNpbXlwZGF3aXN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQyMjkwMTAsImV4cCI6MjEwOTgwNTAxMH0.uEPldAQjJdRyZTGXaz_OpFR7WpFXMiPXlW1S34cR3p8"
const SESSION_FILE := "user://session.json"
## deep-link target used in confirmation / recovery mails (Android intent filter "nexora://auth")
const AUTH_REDIRECT := "nexora://auth"
const DEFAULT_TIMEOUT := 15.0
const POOL_MAX_IDLE := 8

## (event: "INITIAL_SESSION"|"SIGNED_IN"|"SIGNED_OUT"|"TOKEN_REFRESHED"|"USER_UPDATED"|"PASSWORD_RECOVERY", session)
signal auth_changed(event: String, session: Variant)
## the signed-in user's own profiles row (live, kept up to date via realtime)
signal profile_changed(profile: Variant)
## app came back to the foreground after `away` seconds in the background (sockets already woken)
signal app_resumed(away: float)

var session: Variant = null          # Dictionary {access_token, refresh_token, expires_at, expires_in, token_type, user} or null
var profile: Variant = null          # own profiles row (Dictionary) or null
var session_ready := false           # session restored from disk
var recovery := false                # PASSWORD_RECOVERY link opened; UI should ask for a new password
var configured := true
var discs: Node = null               # NxDiscs catalog / inventory cache (src/net/discs.gd)
var socket: RtChannel.Socket = null  # shared realtime socket

var _pool: Array[HTTPRequest] = []
var _busy := 0
var _refresh_timer: Timer
var _refreshing := false
var _refresh_waiter := _Waiter.new()
var _ensuring := false
var _ensure_waiter := _Waiter.new()
var _sockets: Array = []             # all RtChannel.Socket instances polled in _process
var _links := {}                     # room_id -> weakref(RoomLink)
var _profile_ch: RtChannel = null
var _refresh_fail := 0
var _paused_at := -1.0

class _Waiter extends RefCounted:
	signal done(v: Variant)

# ======================================================================== lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_timer = Timer.new()
	_refresh_timer.one_shot = true
	_refresh_timer.timeout.connect(_on_refresh_timer)
	add_child(_refresh_timer)
	socket = new_socket()
	var ds: Script = load("res://src/net/discs.gd")
	if ds:
		discs = ds.new()
		discs.name = "Discs"
		add_child(discs)
	_load_session()

func _process(_dt: float) -> void:
	for s in _sockets:
		s.poll()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		var away := 0.0
		if _paused_at >= 0.0:
			away = maxf(0.0, Time.get_ticks_msec() / 1000.0 - _paused_at)
			_paused_at = -1.0
		_check_refresh_on_resume()
		if what == NOTIFICATION_APPLICATION_RESUMED or away > 0.0:
			app_resumed.emit(away)
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _paused_at < 0.0:
			_paused_at = Time.get_ticks_msec() / 1000.0
		if what == NOTIFICATION_APPLICATION_PAUSED and _refresh_timer:
			_refresh_timer.stop()

func _check_refresh_on_resume() -> void:
	for s in _sockets:
		s.wake()
	if session == null:
		return
	if _expires_in() < 90.0:
		refresh_session()
	else:
		_schedule_refresh()

# ======================================================================== session helpers
func uid() -> String:
	if session is Dictionary and session.get("user") is Dictionary:
		return str(session.user.get("id", ""))
	return ""

func signed_in() -> bool:
	return uid() != ""

func email() -> String:
	if session is Dictionary and session.get("user") is Dictionary:
		var e: Variant = session.user.get("email")
		return str(e) if e else ""
	return ""

func is_guest() -> bool:
	if not (session is Dictionary and session.get("user") is Dictionary):
		return false
	var u: Dictionary = session.user
	if u.has("is_anonymous") and u.is_anonymous != null:
		return bool(u.is_anonymous)
	return email() == ""

func access_token() -> String:
	if session is Dictionary:
		return str(session.get("access_token", ""))
	return ""

func _now() -> float:
	return Time.get_unix_time_from_system()

func _expires_in() -> float:
	if not (session is Dictionary):
		return 0.0
	return float(session.get("expires_at", 0)) - _now()

func _load_session() -> void:
	if FileAccess.file_exists(SESSION_FILE):
		var f := FileAccess.open(SESSION_FILE, FileAccess.READ)
		if f:
			var v: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if v is Dictionary and v.has("access_token") and v.has("refresh_token"):
				session = v
	session_ready = true
	if session != null:
		if _expires_in() < 60.0:
			# expired while the app was closed; refresh now (keeps the session on network errors)
			await refresh_session()
		else:
			_schedule_refresh()
			_after_sign_in()
	auth_changed.emit("INITIAL_SESSION", session)

func _save_session() -> void:
	if session == null:
		if FileAccess.file_exists(SESSION_FILE):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE))
		return
	var f := FileAccess.open(SESSION_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(session))
		f.close()

func _set_session(s: Variant, event: String) -> void:
	var prev_uid := uid()
	if s is Dictionary:
		# expiry on the LOCAL clock: GoTrue's absolute expires_at is server time, and phones with a wrong
		# clock/timezone would otherwise refresh in a loop (clock ahead) or send expired JWTs (behind).
		if s.get("expires_in") != null and float(s.get("expires_in", 0)) > 0:
			s["expires_at"] = int(_now() + float(s.expires_in))
		elif not s.has("expires_at") or s.get("expires_at") == null:
			s["expires_at"] = int(_now() + 3600.0)
		session = s
	else:
		session = null
	_save_session()
	if session != null:
		_schedule_refresh()
		for sk in _sockets:
			sk.set_auth(access_token())
	else:
		_refresh_timer.stop()
		for sk in _sockets:
			sk.set_auth("")
	if uid() != prev_uid:
		if prev_uid != "":
			_drop_links()   # another account (or signed out): rooms of the old user are gone
		_after_sign_in()
	auth_changed.emit(event, session)

func _schedule_refresh() -> void:
	if session == null:
		return
	# refresh 60 s before expiry (supabase-js uses a similar margin)
	var wait: float = max(2.0, _expires_in() - 60.0)
	_refresh_timer.start(wait)

func _on_refresh_timer() -> void:
	refresh_session()

## Refresh the access token now. Concurrent callers share one request.
func refresh_session() -> Dictionary:
	if session == null:
		return _err("not signed in", 0)
	if _refreshing:
		var r: Variant = await _refresh_waiter.done
		return r
	_refreshing = true
	var rt := str(session.get("refresh_token", ""))
	var res := await _request("POST", URL + "/auth/v1/token?grant_type=refresh_token", {"refresh_token": rt}, [], false)
	_refreshing = false
	if session == null:
		pass   # signed out while the request was in flight
	elif res.ok and res.data is Dictionary and res.data.has("access_token"):
		_refresh_fail = 0
		_set_session(res.data, "TOKEN_REFRESHED")
	elif _refresh_token_dead(res):
		# refresh token revoked / already used / user deleted → local sign out
		_set_session(null, "SIGNED_OUT")
	else:
		# network failure: keep the session and retry with backoff
		_refresh_fail += 1
		_refresh_timer.start(min(60.0, 2.0 * pow(2.0, min(_refresh_fail, 5))))
	_refresh_waiter.done.emit(res)
	return res

## Only a definitive GoTrue answer about the refresh token signs the user out. 408/429/5xx, timeouts,
## captive portals (HTML 4xx) and proxies keep the session and retry.
func _refresh_token_dead(res: Dictionary) -> bool:
	var st := int(res.get("status", 0))
	if st != 400 and st != 401 and st != 403 and st != 404:
		return false
	var d: Variant = res.get("data")
	if not (d is Dictionary):
		return false
	var code := str(d.get("error_code", d.get("code", ""))).to_lower()
	var msg := (str(d.get("error", "")) + " " + str(d.get("error_description", "")) + " " + str(d.get("msg", "")) + " " + str(d.get("message", ""))).to_lower()
	if code in ["refresh_token_not_found", "refresh_token_already_used", "session_not_found", "session_expired", "user_not_found", "user_banned", "bad_jwt"]:
		return true
	return msg.contains("refresh token") or msg.contains("invalid_grant") or msg.contains("user not found")

## Make sure the access token is fresh before a request (called by every authed request).
func _fresh_token() -> void:
	if session != null and _expires_in() < 15.0:
		await refresh_session()

# ======================================================================== auth
## Guests are signed in anonymously on demand. Returns the uid ("" on failure).
func ensure() -> String:
	if signed_in():
		return uid()
	if _ensuring:
		var v: Variant = await _ensure_waiter.done
		return str(v)
	_ensuring = true
	var r := await sign_in_anon()
	_ensuring = false
	var id := uid() if r.ok else ""
	_ensure_waiter.done.emit(id)
	return id

func sign_in_anon() -> Dictionary:
	var res := await _request("POST", URL + "/auth/v1/signup", {"data": {}}, [], false)
	if res.ok and res.data is Dictionary and res.data.has("access_token"):
		_set_session(res.data, "SIGNED_IN")
		return _ok(res.data.get("user"))
	if res.ok:
		return _err("Anonymous sign-ins are disabled", res.status)
	return res

## data.info = "confirm" when e-mail confirmation is required (no session until the link is opened)
func sign_up_email(email_: String, password: String, username: String = "") -> Dictionary:
	var body := {"email": email_.strip_edges(), "password": password, "data": {}}
	if username.strip_edges() != "":
		body.data["username"] = username.strip_edges()
	var res := await _request("POST", URL + "/auth/v1/signup?redirect_to=" + AUTH_REDIRECT.uri_encode(), body, [], false)
	if not res.ok:
		return res
	if res.data is Dictionary and res.data.has("access_token"):
		_set_session(res.data, "SIGNED_IN")
		return _ok({"info": ""})
	return _ok({"info": "confirm"})

func sign_in_email(email_: String, password: String) -> Dictionary:
	var res := await _request("POST", URL + "/auth/v1/token?grant_type=password", {"email": email_.strip_edges(), "password": password}, [], false)
	if res.ok and res.data is Dictionary and res.data.has("access_token"):
		_set_session(res.data, "SIGNED_IN")
		return _ok(res.data.get("user"))
	return res if not res.ok else _err("unknown", res.status)

## guest → e-mail upgrade keeping the same user id (auth.updateUser)
func upgrade(email_: String, password: String) -> Dictionary:
	var res := await update_user({"email": email_.strip_edges(), "password": password})
	if res.ok:
		res.data = {"info": "confirm"}
	return res

func set_new_password(password: String) -> Dictionary:
	var res := await update_user({"password": password})
	if res.ok:
		recovery = false
	return res

func update_user(attrs: Dictionary) -> Dictionary:
	if not signed_in():
		return _err("not signed in", 0)
	await _fresh_token()
	var res := await _request("PUT", URL + "/auth/v1/user?redirect_to=" + AUTH_REDIRECT.uri_encode(), attrs, _auth_headers(), false)
	if res.ok and res.data is Dictionary and session is Dictionary:
		session["user"] = res.data
		_save_session()
		auth_changed.emit("USER_UPDATED", session)
	return res

func reset_password(email_: String) -> Dictionary:
	return await _request("POST", URL + "/auth/v1/recover?redirect_to=" + AUTH_REDIRECT.uri_encode(), {"email": email_.strip_edges()}, [], false)

func resend(email_: String) -> Dictionary:
	return await _request("POST", URL + "/auth/v1/resend?redirect_to=" + AUTH_REDIRECT.uri_encode(), {"type": "signup", "email": email_.strip_edges()}, [], false)

## from a deep link (#access_token=..&refresh_token=..&type=recovery)
func set_session_tokens(access: String, refresh: String, type: String = "") -> Dictionary:
	var res := await _request("GET", URL + "/auth/v1/user", null, ["Authorization: Bearer " + access], false)
	if not res.ok:
		return res
	var exp := int(_now() + 3600)
	var parts := access.split(".")
	if parts.size() == 3:
		var pl: Variant = JSON.parse_string(_b64url_decode(parts[1]))
		if pl is Dictionary and pl.has("exp"):
			# lifetime from the token itself (exp - iat) so a wrong phone clock does not matter
			var life := float(pl.exp) - float(pl.get("iat", float(pl.exp) - 3600.0))
			exp = int(_now() + clampf(life, 60.0, 86400.0))
	_set_session({"access_token": access, "refresh_token": refresh, "token_type": "bearer", "expires_at": exp, "expires_in": exp - int(_now()), "user": res.data}, "SIGNED_IN")
	if type == "recovery":
		recovery = true
		auth_changed.emit("PASSWORD_RECOVERY", session)
	return _ok(res.data)

## Parse an auth deep link (nexora://auth#access_token=..). Returns {ok, data:{type}, error}.
func handle_auth_url(url: String) -> Dictionary:
	var i := url.find("#")
	var q := url.find("?")
	var raw := url.substr(i + 1) if i >= 0 else (url.substr(q + 1) if q >= 0 else "")
	var p := {}
	for kv in raw.split("&", false):
		var a := kv.split("=", true, 1)
		p[a[0].uri_decode()] = (a[1] if a.size() > 1 else "").replace("+", " ").uri_decode()
	if p.has("error_description") or p.has("error"):
		if str(p.get("error_code", "")) == "otp_expired":
			return {"ok": false, "data": null, "error": "لینک ایمیل منقضی شده؛ دوباره درخواست بده", "status": 0, "raw": "otp_expired"}
		return _err(str(p.get("error_description", p.get("error", ""))), 0)
	if p.has("access_token") and p.has("refresh_token"):
		var r := await set_session_tokens(p.access_token, p.refresh_token, str(p.get("type", "")))
		if r.ok:
			r.data = {"type": str(p.get("type", ""))}
		return r
	return _err("bad link", 0)

func sign_out() -> Dictionary:
	if signed_in():
		await call_rpc("leave_all_rooms")
		await _request("POST", URL + "/auth/v1/logout?scope=global", null, _auth_headers(), false)
	_set_session(null, "SIGNED_OUT")
	return _ok(null)

## Port of auth.tsx setUsername (validation + profiles update)
func set_username(name_: String) -> Dictionary:
	var n := name_.strip_edges()
	if n.length() < 3 or n.length() > 20:
		return {"ok": false, "data": null, "error": "نام کاربری باید ۳ تا ۲۰ کاراکتر باشد", "status": 0, "raw": ""}
	var re := RegEx.create_from_string("^[A-Za-z0-9_.\\- \\x{0600}-\\x{06FF}\\x{200c}]+$")
	if re.search(n) == null:
		return {"ok": false, "data": null, "error": "فقط حروف، عدد، فاصله و _ . - مجاز است", "status": 0, "raw": ""}
	if not signed_in():
		return _err("not signed in", 0)
	var r := await update("profiles", "id=eq." + uid(), {"username": n})
	if r.ok and profile is Dictionary:
		profile["username"] = n
		profile_changed.emit(profile)
	return r

# ======================================================================== own profile (live)
func refresh_profile() -> Variant:
	if not signed_in():
		return null
	var r := await select("profiles", "select=*&id=eq." + uid(), true)
	if r.ok:
		profile = r.data
		profile_changed.emit(profile)
		return profile
	return null

func _after_sign_in() -> void:
	if _profile_ch:
		remove_channel(_profile_ch)
		_profile_ch = null
	if not signed_in():
		profile = null
		profile_changed.emit(null)
		return
	var me := uid()
	refresh_profile()
	update("profiles", "id=eq." + me, {"online_at": Time.get_datetime_string_from_system(true) + "Z"})
	_profile_ch = channel("profile:" + me)
	_profile_ch.on_postgres("UPDATE", "public", "profiles", "id=eq." + me, func(p: Dictionary) -> void:
		if p.get("new") is Dictionary:
			if not (profile is Dictionary):
				profile = {}
			profile.merge(p.new, true)
			profile_changed.emit(profile))
	_profile_ch.subscribe()

# ======================================================================== REST / RPC / functions / storage
## PostgREST: path like "rooms?select=*&id=eq.<id>". prefer e.g. "return=representation".
func rest(method: String, path: String, body: Variant = null, prefer: String = "", extra_headers: Array = []) -> Dictionary:
	await _fresh_token()
	var res := await _request(method, URL + "/rest/v1/" + path, body, _rest_headers(prefer, extra_headers), false)
	# JWT expired server-side (clock skew / slept through the refresh timer): refresh once and retry
	if res.status == 401 and session != null and _jwt_expired(res):
		var rr := await refresh_session()
		if rr.ok:
			res = await _request(method, URL + "/rest/v1/" + path, body, _rest_headers(prefer, extra_headers), false)
	return res

func _rest_headers(prefer: String, extra: Array) -> PackedStringArray:
	var h := _auth_headers()
	if prefer != "":
		h.append("Prefer: " + prefer)
	h.append_array(extra)
	return h

func _jwt_expired(res: Dictionary) -> bool:
	var t := (str(res.get("raw", "")) + " " + (JSON.stringify(res.data) if res.get("data") != null else "")).to_lower()
	return t.contains("jwt expired") or t.contains("pgrst301") or t.contains("pgrst303") or t.contains("invalid jwt")

## select("room_players", "select=*,profiles(username,avatar)&room_id=eq.X&order=joined_at")
## single=true → data is the first row or null (maybeSingle)
func select(table: String, query: String = "select=*", single: bool = false) -> Dictionary:
	var q := query if query.contains("select=") else ("select=*&" + query if query != "" else "select=*")
	if single:
		q += "&limit=1"
	var r := await rest("GET", table + "?" + q)
	if r.ok and single:
		r.data = r.data[0] if (r.data is Array and r.data.size() > 0) else null
	return r

func insert(table: String, rows: Variant, returning: bool = true) -> Dictionary:
	return await rest("POST", table, rows, "return=representation" if returning else "return=minimal")

## upsert with on_conflict columns ("user_id,disc_id"); ignore_duplicates → resolution=ignore-duplicates
func upsert(table: String, rows: Variant, on_conflict: String = "", ignore_duplicates: bool = false, returning: bool = true) -> Dictionary:
	var p := "resolution=" + ("ignore-duplicates" if ignore_duplicates else "merge-duplicates")
	p += ",return=" + ("representation" if returning else "minimal")
	var path := table + ("?on_conflict=" + on_conflict if on_conflict != "" else "")
	return await rest("POST", path, rows, p)

## update("profiles", "id=eq.X", {username:"n"})
func update(table: String, filter: String, patch: Dictionary, returning: bool = false) -> Dictionary:
	return await rest("PATCH", table + "?" + filter, patch, "return=representation" if returning else "return=minimal")

func delete(table: String, filter: String, returning: bool = false) -> Dictionary:
	return await rest("DELETE", table + "?" + filter, null, "return=representation" if returning else "return=minimal")

## exact count via HEAD-less GET with Prefer count=exact; data = int
func count(table: String, filter: String = "") -> Dictionary:
	var r := await rest("GET", table + "?select=*&limit=0" + ("&" + filter if filter != "" else ""), null, "count=exact")
	if r.ok:
		var cr := str(r.get("content_range", ""))
		r.data = int(cr.get_slice("/", 1)) if cr.contains("/") else 0
	return r

## Supa.rpc("fn", {p_x: 1}) → {ok,data,error}. (Variadic so it can shadow Node.rpc; only args[0] is used.)
@warning_ignore("native_method_override")
func rpc(fn: StringName, ...args: Array):
	var a: Variant = args[0] if args.size() > 0 else {}
	return await call_rpc(String(fn), a if a is Dictionary else {})

## Same as rpc() with a typed signature.
func call_rpc(fn: String, args: Dictionary = {}) -> Dictionary:
	return await rest("POST", "rpc/" + fn, args)

## Edge function. On HTTP errors data still carries the parsed body and status the HTTP code.
func fn_invoke(name_: String, body: Variant = {}) -> Dictionary:
	await _fresh_token()
	var res := await _request("POST", URL + "/functions/v1/" + name_, body, _auth_headers(), false)
	if res.status == 401 and session != null and _jwt_expired(res):
		var rr := await refresh_session()
		if rr.ok:
			res = await _request("POST", URL + "/functions/v1/" + name_, body, _auth_headers(), false)
	return res

## Upload bytes to Storage. Returns data = public URL.
func upload(bucket: String, path: String, bytes: PackedByteArray, mime: String = "image/jpeg", upsert_: bool = false) -> Dictionary:
	await _fresh_token()
	var h := _auth_headers()
	h.append("Content-Type: " + mime)
	h.append("x-upsert: " + ("true" if upsert_ else "false"))
	h.append("cache-control: max-age=3600")
	var r := await _request("POST", URL + "/storage/v1/object/" + bucket + "/" + path, bytes, h, true)
	if r.ok:
		r.data = public_url(bucket, path)
	return r

func public_url(bucket: String, path: String) -> String:
	return URL + "/storage/v1/object/public/" + bucket + "/" + path

## Run several coroutine callables in parallel; returns their results in order.
func parallel(calls: Array) -> Array:
	var st := {"left": calls.size(), "res": []}
	st.res.resize(calls.size())
	if calls.is_empty():
		return []
	var w := _Waiter.new()
	for i in calls.size():
		_run_one(calls[i], i, st, w)
	if st.left > 0:
		await w.done
	return st.res

func _run_one(c: Callable, i: int, st: Dictionary, w: _Waiter) -> void:
	var r: Variant = await c.call()
	st.res[i] = r
	st.left -= 1
	if st.left == 0:
		w.done.emit(null)

# ======================================================================== realtime
## New independent websocket (most code uses the shared `socket`).
func new_socket() -> RtChannel.Socket:
	var s := RtChannel.Socket.new(URL, KEY)
	s.set_auth(access_token())
	_sockets.append(s)
	return s

func close_socket(s: RtChannel.Socket) -> void:
	s.disconnect_socket()
	_sockets.erase(s)

## Supa.channel("room:<id>", {broadcast:{self:false, ack:false}, presence:{key:uid}})
func channel(name_: String, opts: Dictionary = {}, sock: RtChannel.Socket = null) -> RtChannel:
	var s := sock if sock else socket
	return s.channel(name_, opts)

func remove_channel(ch: RtChannel) -> void:
	if ch:
		ch.unsubscribe()

func register_link(room_id: String, link: Object) -> void:
	_links[room_id] = weakref(link)

func unregister_link(room_id: String, link: Object) -> void:
	if _links.has(room_id) and _links[room_id].get_ref() == link:
		_links.erase(room_id)

## every live RoomLink is destroyed (sign-out / account switch)
func _drop_links() -> void:
	for k in _links.keys():
		var o: Object = _links[k].get_ref()
		if o and is_instance_valid(o) and not o.get("dead") and o.has_method("destroy"):
			o.destroy()
	_links.clear()

func live_links() -> Array:
	var out: Array = []
	for k in _links:
		var o: Object = _links[k].get_ref()
		if o and is_instance_valid(o) and not o.get("dead"):
			out.append(o)
	return out

## RoomLink for a room created earlier (lobby → match → result share it)
func link_for(room_id: String) -> Object:
	if _links.has(room_id):
		var o: Object = _links[room_id].get_ref()
		if o and is_instance_valid(o) and not o.get("dead"):
			return o
	return null

# ======================================================================== HTTP core
func _auth_headers() -> PackedStringArray:
	var t := access_token()
	return PackedStringArray(["Authorization: Bearer " + (t if t != "" else KEY)])

func _take_req() -> HTTPRequest:
	var h: HTTPRequest
	if _pool.size() > 0:
		h = _pool.pop_back()
	else:
		h = HTTPRequest.new()
		h.use_threads = OS.get_name() != "Web"
		h.accept_gzip = true
		h.body_size_limit = 16 * 1024 * 1024
		add_child(h)
	_busy += 1
	return h

func _give_req(h: HTTPRequest) -> void:
	_busy -= 1
	if _pool.size() < POOL_MAX_IDLE:
		_pool.append(h)
	else:
		h.queue_free()

const _METHODS := {"GET": HTTPClient.METHOD_GET, "POST": HTTPClient.METHOD_POST, "PUT": HTTPClient.METHOD_PUT, "PATCH": HTTPClient.METHOD_PATCH, "DELETE": HTTPClient.METHOD_DELETE, "HEAD": HTTPClient.METHOD_HEAD}

func _request(method: String, url: String, body: Variant, headers: Array, raw: bool, timeout: float = DEFAULT_TIMEOUT) -> Dictionary:
	if not is_inside_tree():
		return _err("Network request failed", 0)
	var h := _take_req()
	h.timeout = timeout
	var hs := PackedStringArray(["apikey: " + KEY, "X-Client-Info: nexora-godot/2.0", "Accept: application/json"])
	var has_ct := false
	var has_auth := false
	for x in headers:
		var s := str(x)
		if s.to_lower().begins_with("content-type:"):
			has_ct = true
		if s.to_lower().begins_with("authorization:"):
			has_auth = true
		hs.append(s)
	if not has_auth:
		hs.append("Authorization: Bearer " + KEY)
	var m: int = _METHODS.get(method, HTTPClient.METHOD_GET)
	var err: int
	if raw:
		var bytes: PackedByteArray = body if body is PackedByteArray else PackedByteArray()
		err = h.request_raw(url, hs, m, bytes)
	else:
		var txt := ""
		if body != null:
			txt = JSON.stringify(body)
			if not has_ct:
				hs.append("Content-Type: application/json")
		err = h.request(url, hs, m, txt)
	if err != OK:
		_give_req(h)
		return _err("Network request failed", 0)
	var out: Array = await h.request_completed
	_give_req(h)
	var result: int = out[0]
	var code: int = out[1]
	var rh: PackedStringArray = out[2]
	var rb: PackedByteArray = out[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return _err("timeout" if result == HTTPRequest.RESULT_TIMEOUT else "Network request failed", 0)
	var text := rb.get_string_from_utf8()
	var data: Variant = null
	if text.strip_edges() != "":
		var j := JSON.new()
		data = j.data if j.parse(text) == OK else text
	var cr := ""
	for line in rh:
		if line.to_lower().begins_with("content-range:"):
			cr = line.substr(14).strip_edges()
	if code >= 200 and code < 300:
		return {"ok": true, "data": data, "error": "", "status": code, "raw": "", "content_range": cr}
	var msg := _msg_of(data)
	if msg == "":
		msg = "HTTP %d" % code
	var r := _err(msg, code)
	r.data = data
	return r

func _msg_of(d: Variant) -> String:
	if d is Dictionary:
		for k in ["message", "error_description", "msg", "error", "code"]:
			var v: Variant = d.get(k)
			if v is String and v != "":
				var extra := ""
				var ec: Variant = d.get("error_code")
				if ec is String and k != "code":
					extra = " " + ec
				return v + extra
		return JSON.stringify(d)
	if d is String:
		return d
	return ""

func _ok(data: Variant) -> Dictionary:
	return {"ok": true, "data": data, "error": "", "status": 200, "raw": ""}

func _err(msg: String, status: int) -> Dictionary:
	return {"ok": false, "data": null, "error": err_fa(msg), "status": status, "raw": msg}

func _b64url_decode(s: String) -> String:
	var t := s.replace("-", "+").replace("_", "/")
	while t.length() % 4 != 0:
		t += "="
	return Marshalls.base64_to_raw(t).get_string_from_utf8()

# ======================================================================== errors (exact port of errFa)
const _ERR_MAP := [
	["not enough gems", "الماس کافی نداری"],
	["already owned", "این دیسک را قبلاً داری"],
	["not owned", "این دیسک را نداری"],
	["already in club", "تو الان عضو یک باشگاه هستی"],
	["club full", "ظرفیت باشگاه پر است"],
	["invite only", "این باشگاه فقط با دعوت عضو می‌گیرد"],
	["level too low", "سطحت برای این کار کافی نیست"],
	["officer only", "فقط افسران باشگاه"],
	["leader only", "فقط رهبر باشگاه"],
	["admin only", "فقط مدیران"],
	["already claimed", "قبلاً دریافت کردی"],
	["not completed", "هنوز کامل نشده"],
	["bad size", "اندازه‌ی نامعتبر"],
	["already joined", "قبلاً ثبت‌نام کردی"],
	["\\bblocked\\b", "این کاربر تو را مسدود کرده"],
	["title required", "عنوان لازم است"],
	["season running", "فصل هنوز تمام نشده"],
	["cannot dm yourself", "نمی‌توانی به خودت پیام بدهی"],
	["not public", "این گفتگو عمومی نیست"],
	["club not found", "باشگاه پیدا نشد"],
	["request not found", "درخواست پیدا نشد"],
	["not allowed|bad action", "اجازه‌ی این کار را نداری"],
	["clubs_name_key|duplicate key.*clubs.*name", "این نام باشگاه گرفته شده"],
	["clubs_tag_key|duplicate key.*tag", "این تگ گرفته شده"],
	["tag.*check|clubs_tag_check", "تگ باید ۲ تا ۵ حرف/عدد انگلیسی بزرگ باشد"],
	["room not found", "اتاق پیدا نشد"],
	["room closed", "این اتاق بسته شده"],
	["teams not full", "هنوز همه‌ی جایگاه‌ها پر نشده"],
	["not all ready", "همه‌ی بازیکن‌ها آماده نیستند"],
	["seat taken", "این جایگاه گرفته شده"],
	["host only", "فقط میزبان می‌تونه این کار رو بکنه"],
	["organizer only", "فقط برگزارکننده می‌تونه این کار رو بکنه"],
	["registration closed", "ثبت‌نام این تورنمنت بسته شده"],
	["\\bfull\\b", "ظرفیت تکمیل است"],
	["already started", "از قبل شروع شده"],
	["match running", "بازی در جریان است"],
	["match not live", "این مسابقه دیگر فعال نیست"],
	["match not ready|not playable", "این مسابقه هنوز آماده نیست"],
	["not in this match", "تو در این مسابقه نیستی"],
	["need at least 2", "حداقل ۲ شرکت‌کننده لازم است"],
	["bad slot", "جایگاه نامعتبر"],
	["not signed in|JWT|unauthorized", "اول وارد حساب شو"],
	["duplicate key.*username|profiles_username_key", "این نام کاربری قبلاً گرفته شده"],
	["duplicate key.*tournament_entries|tournament_id, captain", "قبلاً در این تورنمنت ثبت‌نام کردی"],
	["username.*check|char_length", "نام کاربری باید ۳ تا ۲۰ کاراکتر باشد"],
	["Invalid login credentials", "ایمیل یا رمز عبور اشتباه است"],
	["Email not confirmed", "ایمیلت هنوز تأیید نشده؛ صندوق ایمیل را ببین"],
	["User already registered|already been registered|email_exists", "با این ایمیل قبلاً حساب ساخته شده"],
	["Password should be at least|weak_password", "رمز عبور باید حداقل ۶ کاراکتر باشد"],
	["rate limit|too many|over_email_send_rate_limit", "درخواست زیاد بود؛ کمی بعد دوباره امتحان کن"],
	["invalid.*email|validate email|email_address_invalid", "ایمیل معتبر نیست"],
	["Anonymous sign-ins are disabled", "ورود مهمان غیرفعال است"],
	["Network request failed|Failed to fetch|fetch failed|timeout|NetworkError", "اتصال اینترنت برقرار نیست"],
]
var _err_re: Array = []

## Persian message for an error (String or Dictionary with message/error_description/msg)
func err_fa(e: Variant) -> String:
	var m := ""
	if e is String:
		m = e
	elif e is Dictionary:
		if e.has("ok"):
			return str(e.get("error", "")) if str(e.get("error", "")) != "" else "خطای ناشناخته؛ دوباره امتحان کن"
		m = _msg_of(e)
	if _err_re.is_empty():
		for pair in _ERR_MAP:
			_err_re.append([RegEx.create_from_string("(?i)" + pair[0]), pair[1]])
	for pr in _err_re:
		if pr[0].search(m) != null:
			return pr[1]
	return ("خطا: " + m.substr(0, 80)) if m != "" else "خطای ناشناخته؛ دوباره امتحان کن"
