@tool
extends EditorPlugin
## Registers the NexoraLiveKit Android export plugin (see export_plugin.gd).

const ExportPluginScript := preload("res://addons/nexora_livekit/export_plugin.gd")

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_export_plugin = ExportPluginScript.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin:
		remove_export_plugin(_export_plugin)
	_export_plugin = null
