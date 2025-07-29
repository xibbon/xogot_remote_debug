
extends EditorExportPlatformExtension
class_name XogotExportPlatform

# Holds the list of discovered devices (should be updated externally)
var discovered_devices: Array = []
var new_devices: Array = []
var devicesUpdated: bool = false
var iosLogo: ImageTexture

# Reference to the xogot instance for sending sync requests
var xogot_instance = null
# var iosLogo = ImageLoaderSVG.load_from_string(iosLogoString)
# --- EditorExportPlatformExtension required overrides (stubs) ---
func loadImages() -> void:
	if iosLogo:
		return # Already loaded
	var iosImage = Image.load_from_file("res://addons/xogot_remote_debugger/resources/iosLogo.svg")
	iosLogo = ImageTexture.create_from_image(iosImage)

func _get_name() -> String:
	# print("XogotExportPlatform: _get_name called")
	return "Xogot"

func _get_logo() -> Texture2D:
	loadImages()
	return iosLogo

func _get_supported_features() -> PackedStringArray:
	print("XogotExportPlatform: _get_supported_features called")
	return ["remote"]

func _get_export_file_extension(preset: EditorExportPreset) -> String:
	print("XogotExportPlatform: _get_export_file_extension called")
	return "zip"

func _get_binary_extensions(preset: EditorExportPreset) -> PackedStringArray:
	print("XogotExportPlatform: _get_binary_extensions called")
	return ["zip"]

func _has_valid_export_configuration(preset: EditorExportPreset, debug: bool) -> bool:
	print("XogotExportPlatform: _has_valid_export_configuration called")
	return true

func _get_platform_features() -> PackedStringArray:
	print("XogotExportPlatform: _get_platform_features called")
	return ["xogot", "remote"]

func _get_preset_features(preset: EditorExportPreset) -> PackedStringArray:
	print("XogotExportPlatform: _get_preset_features called")
	return ["remote"]

func _get_options_count() -> int:
	# print("XogotExportPlatform: _get_options_count called")
	return discovered_devices.size()

func _get_option_label(deviceIndex: int) -> String:
	# print("XogotExportPlatform: _get_option_label called for deviceIndex: ", deviceIndex)
	if not discovered_devices:
		return "No devices found"
	var device = discovered_devices[deviceIndex]
	return "  %s (%s)" % [device.get("deviceName", "?"), device.get("address", "?")]

func _get_option_tooltip(deviceIndex: int) -> String:
	# print("XogotExportPlatform: _get_option_tooltip called for deviceIndex: ", deviceIndex)
	return "Run on remote device"

func _get_option_icon(deviceIndex: int) -> ImageTexture:
	loadImages()
	return iosLogo;

func _run(preset: EditorExportPreset, device: int, debug_flags: int) -> Error:
	# print("XogotExportPlatform: _run_on_target called for target: ", device)
	
	# Find the device from the target string
	var device_data = discovered_devices[device]
	if not device_data:
		printerr("Device not found for target: ", device)
		return ERR_INVALID_PARAMETER
	
	# Get project information from EditorInterface
	var project_name = ProjectSettings.get_setting("application/config/name", "UnnamedProject")
	var project_path = ProjectSettings.globalize_path("res://")
	var user_id = "editor_user"  # Could be made configurable
	
	var settings = EditorInterface.get_editor_settings()
	var host: String = settings.get_setting("network/debug/remote_host")
	var remotePort: int = settings.get_setting("network/debug/remote_port")
	var protocol = "tcp://" #_get_debug_protocol()
	# var p2 = _get_debug_protocol()
	var fsPort = settings.get_setting("filesystem/file_server/port")
	print("XogotExportPlatform: _run_on_target called with host: %s, port: %d, protocol: %s" % [host, remotePort, protocol])
	print("XogotExportPlatform: fsPort: ", fsPort)
	# Get game arguments from preset or debug flags
	var game_args = []
	var dumbDeploy = debug_flags & EditorExportPlatform.DEBUG_FLAG_DUMB_CLIENT
	print("Dumb Deploy: ", dumbDeploy)

	# Always enable remote debugging for Xogot deployments
	# if debug_flags & EditorExportPlatform.DEBUG_FLAG_REMOTE_DEBUG:
	# Get the first available IP address for remote debugging
	game_args.append("--remote-debug")
	game_args.append("%s%s:%d" % [protocol, host, remotePort])
	# if dumbDeploy:
	game_args.append("--remote-fs")
	game_args.append("%s:%d" % [host, fsPort])

	var breakPoints = EditorInterface.get_script_editor().get_breakpoints();
	if !breakPoints.is_empty():
		game_args.append("--breakpoints")
		var bpoints = ""
		for i in range(breakPoints.size()):
			bpoints += breakPoints[i].replace(" ", "%20")
			if i < breakPoints.size() - 1:
				bpoints += ","
		game_args.append(bpoints)
		
	# Send sync request through xogot instance
	if xogot_instance:
		var target_address = device_data["address"]
		var target_port = device_data["dataPort"]
		var public_ips = xogot_instance.get_public_ip_addresses()
		var sender_port = xogot_instance.TCP_PORT
		var sync_type = "remotefs"

		print("XogotExportPlatform: Sending sync request to %s:%d with args: %s" % [target_address, target_port, game_args])
		xogot_instance.sendSyncRequest(target_address, target_port, project_name, project_path, user_id, public_ips, sender_port, game_args, sync_type)
		print("Sync request sent to device: ", device_data["deviceName"])
	else:
		printerr("Xogot instance not available")
		return ERR_UNAVAILABLE
	
	return OK

func _get_run_icon() -> Texture2D:
	
	# print("XogotExportPlatform: _get_run_icon called")
	return null

func _get_custom_export_options(preset: EditorExportPreset) -> Array:
	print("XogotExportPlatform: _get_custom_export_options called")
	return []

func _get_os_name() -> String:
	print("XogotExportPlatform: _get_os_name called")
	return "Xogot"

func _is_platform_supported() -> bool:
	print("XogotExportPlatform: _is_platform_supported called")
	return true

func _export_project( preset: EditorExportPreset, debug: bool, path: String, flags: int )-> int:
	print("XogotExportPlatform: _export_project called")
	# Stub: implement export logic if needed
	return OK

func _poll_export() -> bool:
	# print("XogotExportPlatform: _poll_export called")
	# Stub: implement polling logic if needed
	if devicesUpdated:
		# print("XogotExportPlatform: _poll_export - devices updated")
		# print("Discovered devices 1: ", new_devices)
		# We need to copy the array to avoid modifying it while iterating
		discovered_devices = new_devices.duplicate()
		new_devices.clear()
		# print("Discovered devices 2: ", discovered_devices)
		devicesUpdated = false
		return true
	return false

func _get_export_option_visibility(preset: EditorExportPreset, option: String) -> bool:
	print("XogotExportPlatform: _get_export_option_visibility called for option: ", option)
	return true

func _has_valid_project_configuration(preset: EditorExportPreset) -> bool:
	print("XogotExportPlatform: _has_valid_project_configuration called")
	return true

func _get_run_targets(preset: EditorExportPreset) -> Array:
	print("XogotExportPlatform: _get_run_targets called")
	var targets = []
	for device in discovered_devices:
		if device.has("deviceName"):
			targets.append(device["deviceName"])
		elif device.has("deviceId"):
			targets.append(device["deviceId"])
	return targets

func _get_run_target_label(preset: EditorExportPreset, target: String) -> String:
	print("XogotExportPlatform: _get_run_target_label called for target: ", target)
	return target

# func _run_on_target(preset: EditorExportPreset, target: String, debug_flags: int) -> int:
# 	print("XogotExportPlatform: _run_on_target called for target: ", target)
	
# 	# Find the device from the target string
# 	var device_data = _get_device_from_target(target)
# 	if not device_data:
# 		printerr("Device not found for target: ", target)
# 		return ERR_INVALID_PARAMETER
	
# 	# Get project information from EditorInterface
# 	var project_name = ProjectSettings.get_setting("application/config/name", "UnnamedProject")
# 	var project_path = ProjectSettings.globalize_path("res://")
# 	var user_id = "editor_user"  # Could be made configurable
	
# 	# Get game arguments from preset or debug flags
# 	var game_args = []
# 	if debug_flags & EditorExportPlatform.DEBUG_FLAG_DUMB_CLIENT:
# 		game_args.append("--debug")
# 	if debug_flags & EditorExportPlatform.DEBUG_FLAG_REMOTE_DEBUG:
# 		game_args.append("--remote-debug")
	
# 	# Send sync request through xogot instance
# 	if xogot_instance:
# 		var target_address = device_data["address"]
# 		var target_port = device_data["dataPort"]
# 		var public_ips = xogot_instance.get_public_ip_addresses()
# 		var sender_port = xogot_instance.TCP_PORT
# 		var sync_type = "remotefs"
		
# 		xogot_instance.sendSyncRequest(target_address, target_port, project_name, project_path, user_id, public_ips, sender_port, game_args, sync_type)
# 		print("Sync request sent to device: ", device_data["deviceName"])
# 	else:
# 		printerr("Xogot instance not available")
# 		return ERR_UNAVAILABLE
	
# 	return OK

func _get_device_from_target(target: String) -> Dictionary:
	# The target string should match the device name or identifier
	# Search through discovered devices to find the matching one
	for device in discovered_devices:
		if device.has("deviceName") and device["deviceName"] == target:
			return device
		# Also check by deviceId if available
		if device.has("deviceId") and device["deviceId"] == target:
			return device
	return {}


# func _get_name() -> String:
# 	return "Xogot"

# func _get_logo() -> Texture2D:
# 	# Optional: add your logo
# 	return null

# func _get_supported_features() -> PackedStringArray:
# 	return ["remote"] # this is a remote-only platform

# func _get_export_file_extension(preset: EditorExportPreset) -> String:
# 	return "zip"

# func _get_binary_extensions(preset: EditorExportPreset) -> PackedStringArray:
# 	# Return the file extensions this platform exports (e.g., zip)
# 	return ["zip"]

# func _has_valid_export_configuration(preset: EditorExportPreset, debug: bool) -> bool:
# 	# Always return true for now; add checks if needed
# 	return true

# # func _has_valid_export_configuration(preset: EditorExportPreset) -> bool:
# # 	# Always return true for now; add checks if needed
# # 	return true

# func _get_platform_features() -> PackedStringArray:
# 	# Return platform features (for export filtering)
# 	return ["xogot", "remote"]

# func _get_preset_features(preset: EditorExportPreset) -> PackedStringArray:
# 	# Return preset-specific features (for export filtering)
# 	return ["remote"]
# func _get_options_count() -> int:
# 	# Return the number of devices discovered
# 	return discovered_devices.size()

# func _get_option_label(deviceIndex: int) -> String:
# 	# Return a user-friendly label for the device
# 	if not discovered_devices:
# 		return "No devices found"
# 	var device = discovered_devices[deviceIndex]
# 	return "%s (%s:%s)" % [device.get("deviceName", "?"), device.get("address", "?"), device.get("dataPort", "?")]
# func _run(preset: EditorExportPreset, device: int, debug_flags: int) -> Error:
# 	# Implement logic to run the project on the selected device
# 	print("Running on device: ", device)
# 	# You can call your sync/send logic here, e.g. via a singleton or signal
# 	# Example: XogotRemoteDebugger.send_run_to_device(target, ...)
# 	return OK

# func _get_run_icon() -> Texture2D:
# 	# Optional: add a custom run icon
# 	return null