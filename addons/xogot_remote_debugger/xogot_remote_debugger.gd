@tool
extends EditorPlugin

var dock

var xogot_export_platform

func _enter_tree():

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
	add_control_to_dock(DOCK_SLOT_RIGHT_UR, dock)
	# Note that LEFT_UL means the left of the editor, upper-left dock.


func _exit_tree():

	remove_export_platform(xogot_export_platform)
	# Clean-up of the plugin goes here.
	# Remove the dock.
	remove_control_from_docks(dock)
	# Erase the control from the memory.
	dock.free()

func _notification(what):
	# print("Notification: ", what)
	pass
