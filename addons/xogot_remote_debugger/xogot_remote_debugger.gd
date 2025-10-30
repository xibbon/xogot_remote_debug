@tool
extends EditorPlugin

var dock

var xogot_export_platform

func _enter_tree():
	if OS.has_feature("mobile"):
		return

	# Configure iOS virtual controller settings
	_configure_ios_virtual_controller()

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

func _configure_ios_virtual_controller():
	# Set iOS virtual controller default settings only if they don't exist
	var settings_added = false

	if not ProjectSettings.has_setting("input_devices/virtual_controller/ios/enable_controller"):
		ProjectSettings.set_setting("input_devices/virtual_controller/ios/enable_controller", false)
		settings_added = true

	if not ProjectSettings.has_setting("input_devices/virtual_controller/ios/enable_left_thumbstick"):
		ProjectSettings.set_setting("input_devices/virtual_controller/ios/enable_left_thumbstick", true)
		settings_added = true

	if not ProjectSettings.has_setting("input_devices/virtual_controller/ios/enable_right_thumbstick"):
		ProjectSettings.set_setting("input_devices/virtual_controller/ios/enable_right_thumbstick", true)
		settings_added = true

	if not ProjectSettings.has_setting("input_devices/virtual_controller/ios/enable_button_a"):
		ProjectSettings.set_setting("input_devices/virtual_controller/ios/enable_button_a", true)
		settings_added = true

	if not ProjectSettings.has_setting("input_devices/virtual_controller/ios/enable_button_b"):
		ProjectSettings.set_setting("input_devices/virtual_controller/ios/enable_button_b", true)
		settings_added = true

	if not ProjectSettings.has_setting("input_devices/virtual_controller/ios/enable_button_x"):
		ProjectSettings.set_setting("input_devices/virtual_controller/ios/enable_button_x", true)
		settings_added = true

	if not ProjectSettings.has_setting("input_devices/virtual_controller/ios/enable_button_y"):
		ProjectSettings.set_setting("input_devices/virtual_controller/ios/enable_button_y", true)
		settings_added = true

	# Only save if we actually added new settings
	if settings_added:
		ProjectSettings.save()
		print("Xogot: Configured iOS virtual controller settings")

func _notification(what):
	# print("Notification: ", what)
	pass
