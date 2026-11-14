extends Node
## Voice (autoload) — LiveKit voice chat for online rooms. Port of nxrev src/net/voice.ts.
##
## Android only: talks to the "NexoraLiveKit" Godot v2 Android plugin (plugin_src/livekit, shipped by
## addons/nexora_livekit). Everywhere else (desktop, editor, headless, web) it is a safe no-op:
## supported() == false and join() just reports an error state with a Persian reason.
## Never throws to callers; one session at a time (the RN app made one Voice per room link).
##
## API (SPEC "Voice API"):
##   Voice.supported() -> bool          Voice.support_reason() -> String ("" when supported)
##   Voice.join(room_id)                Voice.set_mic(on)   Voice.set_speaker(on)   Voice.leave()
##   Voice.state : Dictionary {status:"off|connecting|on|error", mic, speaker, can_publish, speaking:[ids], error}
##   Voice.room_id : room of the current/last session ("" when none)
##   signal state_changed(state)        signal active(bool)   (music ducking in Sfx: on while connected or mic on)

signal state_changed(state: Dictionary)
signal active(on: bool)

const PLUGIN_NAME := "NexoraLiveKit"
const PERM_MIC := "android.permission.RECORD_AUDIO"
const CONNECT_TIMEOUT := 25.0
const PERMISSION_TIMEOUT := 90.0

# Persian messages (same text as voice.ts; the unsupported reason per SPEC).
const MSG_UNSUPPORTED := "چت صوتی فقط روی اندروید"
const MSG_NOT_CONFIGURED := "چت صوتی هنوز فعال نشده"
const MSG_NOT_IN_ROOM := "برای چت صوتی باید داخل اتاق باشی"
const MSG_TOKEN_FAILED := "اتصال به سرور صدا ناموفق بود"
const MSG_CONNECT_FAILED := "اتصال صدا ناموفق بود"

var state: Dictionary = {
	"status": "off", "mic": false, "speaker": true, "can_publish": false, "speaking": [], "error": "",
}
var room_id: String = ""

var _plugin: Object = null
var _support_checked := false
var _supported := false
var _reason := ""
var _session := 0              # bumped by join/leave; stale awaits compare against it (voice.ts `alive`)
var _pending_publish := false  # can_publish granted by the token, applied once the room is "on"
var _last_plugin_error := ""
var _active := false
var _watchdog: SceneTreeTimer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Lazy: the NexoraLiveKit plugin, LiveKit and the audio stack are not touched at startup;
	# _check_support() runs on the first supported()/support_reason()/join() call.


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _plugin != null and str(state.status) in ["connecting", "on"]:
			_plugin_call("disconnectRoom")


# ======================================================================= public API

func supported() -> bool:
	_check_support()
	return _supported


## "" when supported, else the Persian reason shown to the user.
func support_reason() -> String:
	_check_support()
	return _reason


func is_active() -> bool:
	return _active


func join(rid: String) -> void:
	rid = str(rid)
	if not supported():
		_patch({"status": "error", "error": _reason})
		return
	var st := str(state.status)
	if st == "connecting" or st == "on":
		if rid == room_id:
			return
		leave()  # singleton: switching rooms ends the old session first
	_session += 1
	var my := _session
	room_id = rid
	_last_plugin_error = ""
	_patch({"status": "connecting", "error": "", "speaking": []})

	var r: Dictionary = await Supa.fn_invoke("livekit-token", {"room_id": rid})
	if my != _session:
		return
	if not bool(r.get("ok", false)):
		var code := int(r.get("status", 0))
		var body: Variant = r.get("data")
		var berr := ""
		if body is Dictionary:
			berr = str((body as Dictionary).get("error", ""))
		if code == 503 or berr == "voice_not_configured":
			_fail(MSG_NOT_CONFIGURED)
		elif code == 403:
			_fail(MSG_NOT_IN_ROOM)
		else:
			_fail(MSG_TOKEN_FAILED)
		return
	var data: Variant = r.get("data")
	if not (data is Dictionary) or str((data as Dictionary).get("url", "")) == "" or str((data as Dictionary).get("token", "")) == "":
		_fail(MSG_TOKEN_FAILED)
		return
	var d: Dictionary = data
	var can_publish := bool(d.get("canPublish", false))
	if can_publish:
		var granted: bool = await _ensure_mic_permission()
		if my != _session:
			return
		if not granted:
			can_publish = false  # listen-only, like voice.ts
	_pending_publish = can_publish
	_arm_watchdog(my)
	if not _plugin_call("connectRoom", [str(d.url), str(d.token), can_publish]):
		_fail(MSG_CONNECT_FAILED)


func set_mic(on: bool) -> void:
	if _plugin == null or str(state.status) != "on" or not bool(state.can_publish):
		return
	if on and not _has_mic_permission():
		var my := _session
		var granted: bool = await _ensure_mic_permission()
		if my != _session or not granted:
			if not granted:
				_patch({"mic": false})
			return
	# Optimistic; the plugin reports "mic:<reason>" on failure and we flip back (voice.ts catch -> mic false).
	if _plugin_call("setMic", [on]):
		_patch({"mic": on})
	else:
		_patch({"mic": false})


func set_speaker(on: bool) -> void:
	_patch({"speaker": on})
	if _plugin != null and str(state.status) in ["connecting", "on"]:
		_plugin_call("setSpeaker", [on])


func leave(keep_error: bool = false) -> void:
	_session += 1
	_watchdog = null
	_pending_publish = false
	if _plugin != null and str(state.status) in ["connecting", "on"]:
		_plugin_call("disconnectRoom")
	if not keep_error:
		room_id = ""
		_patch({"status": "off", "mic": false, "speaking": [], "error": ""})
	else:
		_patch({"mic": false, "speaking": []})


# ======================================================================= plugin bridge

func _check_support() -> void:
	if _support_checked:
		return
	_support_checked = true
	_supported = false
	_reason = MSG_UNSUPPORTED
	if OS.get_name() != "Android" or not Engine.has_singleton(PLUGIN_NAME):
		return
	var p: Object = Engine.get_singleton(PLUGIN_NAME)
	if p == null:
		return
	_plugin = p
	# Signal(...).connect goes straight to Object::connect. Never call `_plugin.connect(...)`:
	# JNISingleton routes calls whose arity matches a Java method (connect(url,token,publish)) to Java.
	# Plugin signals are emitted from the Android UI thread, so always defer onto the main loop.
	for pair in [["state", _on_plugin_state], ["speakers", _on_plugin_speakers], ["error", _on_plugin_error]]:
		var sig := Signal(_plugin, StringName(pair[0]))
		if not sig.is_connected(pair[1]):
			sig.connect(pair[1], CONNECT_DEFERRED)
	_supported = true
	_reason = ""


func _plugin_call(method: String, args: Array = []) -> bool:
	if _plugin == null:
		return false
	_plugin.callv(method, args)
	return true


func _on_plugin_state(s: String) -> void:
	var st := str(state.status)
	match s:
		"connecting":
			pass
		"on":
			if st != "connecting":
				return  # stale (left meanwhile)
			_watchdog = null
			_patch({"status": "on", "can_publish": _pending_publish, "mic": false, "error": ""})
			if not bool(state.speaker):
				_plugin_call("setSpeaker", [false])
			if _pending_publish:
				set_mic(true)
		"off":
			if st == "on" or st == "connecting":
				_watchdog = null
				_session += 1
				_patch({"status": "off", "mic": false, "speaking": []})
		"error":
			if st == "on" or st == "connecting":
				_fail(_fa_or(_last_plugin_error, MSG_CONNECT_FAILED))


func _on_plugin_speakers(json: String) -> void:
	var v: Variant = JSON.parse_string(json)
	var ids: Array = []
	if v is Array:
		for x in v:
			ids.append(str(x))
	if ids != state.speaking:
		_patch({"speaking": ids})


func _on_plugin_error(msg: String) -> void:
	if msg.begins_with("mic:"):
		if bool(state.mic):
			_patch({"mic": false})
		return
	_last_plugin_error = msg
	push_warning("Voice: " + msg)


# ======================================================================= permissions

func _has_mic_permission() -> bool:
	if OS.get_name() != "Android":
		return true
	return PERM_MIC in OS.get_granted_permissions()


## Requests RECORD_AUDIO and waits for SceneTree.on_request_permissions_result (bounded wait).
func _ensure_mic_permission() -> bool:
	if _has_mic_permission():
		return true
	var tree := get_tree()
	if tree == null:
		return false
	var w := _PermWaiter.new(PERM_MIC)
	tree.on_request_permissions_result.connect(w.on_result)
	var already := OS.request_permission(PERM_MIC)
	if already:
		tree.on_request_permissions_result.disconnect(w.on_result)
		return true
	tree.create_timer(PERMISSION_TIMEOUT, true).timeout.connect(w.on_timeout)
	var granted: bool = await w.done
	if tree.on_request_permissions_result.is_connected(w.on_result):
		tree.on_request_permissions_result.disconnect(w.on_result)
	return granted or _has_mic_permission()


class _PermWaiter extends RefCounted:
	signal done(granted: bool)
	var perm := ""
	var finished := false

	func _init(p: String) -> void:
		perm = p

	func on_result(permission: String, granted: bool) -> void:
		if finished or permission != perm:
			return
		finished = true
		done.emit(granted)

	func on_timeout() -> void:
		if finished:
			return
		finished = true
		done.emit(false)


# ======================================================================= helpers

func _arm_watchdog(my: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var t := tree.create_timer(CONNECT_TIMEOUT, true)
	_watchdog = t
	t.timeout.connect(func() -> void:
		if _watchdog == t and my == _session and str(state.status) == "connecting":
			_fail(MSG_CONNECT_FAILED))


func _fail(msg: String) -> void:
	_watchdog = null
	_patch({"status": "error", "error": _fa_or(msg, MSG_CONNECT_FAILED), "mic": false, "speaking": []})
	leave(true)


## voice.ts: keep the message only when it is already Persian, else the generic one.
static func _fa_or(msg: String, fallback: String) -> String:
	for i in msg.length():
		var c := msg.unicode_at(i)
		if c >= 0x0600 and c <= 0x06FF:
			return msg
	return fallback


func _patch(patch: Dictionary) -> void:
	for k in patch:
		state[k] = patch[k]
	var on := str(state.status) == "on" or bool(state.mic)
	if on != _active:
		_active = on
		active.emit(on)
	state_changed.emit(state)
