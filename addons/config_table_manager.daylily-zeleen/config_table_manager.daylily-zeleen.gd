@tool
extends EditorPlugin

var plugin_control


func _enter_tree() -> void:
	var path = _get_main_scene_path()
	plugin_control = ResourceLoader.load(path).instantiate()
	EditorInterface.get_editor_main_screen().add_child(plugin_control)
	EditorInterface.get_editor_main_screen().size_flags_vertical = Control.SIZE_EXPAND_FILL
	plugin_control.hide()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible) -> void:
	plugin_control.visible = visible


func _get_plugin_name() -> String:
	return "Config Table Manger"


func _get_plugin_icon() -> Texture2D:
	return ResourceLoader.load(get_script().resource_path.get_base_dir().path_join("icon.svg"), "", ResourceLoader.CACHE_MODE_IGNORE)


# =====================
func _get_main_scene_path() -> String:
	return get_script().resource_path.get_base_dir().path_join("scenes/main_screen.tscn")
