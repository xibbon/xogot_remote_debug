@tool
extends EditorPlugin

var dock

var xogot_export_platform

func _enter_tree():
	if OS.has_feature("mobile"):
		return

	xogot_export_platform = preload("res://addons/xogot_remote_debugger/xogot_export_platform.gd").new()
	add_export_platform(xogot_export_platform)
	Engine.register_singleton("XogotExportPlatform", xogot_export_platform)
	# EditorExport.singleton.add_platform(xogot_export_platform)
	# Initialization of the plugin goes here.
	# Load the dock scene and instantiate it.
	dock = preload("res://addons/xogot_remote_debugger/xogot.tscn").instantiate()
	dock.export_platform = xogot_export_platform
	dock.plugin = self

	# Add the loaded scene to the docks.
	# DOCK_SLOT_RIGHT_UL tabs with Inspector panel
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _exit_tree():
	if OS.has_feature("mobile"):
		return

	remove_export_platform(xogot_export_platform)
	# Clean-up of the plugin goes here.
	# Remove the dock.
	remove_control_from_docks(dock)
	# Erase the control from the memory.
	dock.free()

func _notification(what):
	# print("Notification: ", what)
	pass
