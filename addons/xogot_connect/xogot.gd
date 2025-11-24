@tool
extends Control

const XogotDebug = preload("res://addons/xogot_connect/xogot_debug.gd")
const PairingDialog = preload("res://addons/xogot_connect/pairing_dialog.tscn")

# Plugin version
const PLUGIN_VERSION = "1.0.3"

var FILE_NAME: String:
	get:
		return EditorInterface.get_editor_paths().get_data_dir().path_join("Xogot").path_join("xogot_user.tres")

var user = User.new()
@onready var devices_vbox: VBoxContainer = %DevicesItemList
@onready var file_server_warning: Label = %FileServerWarning
@onready var remote_host_warning: Label = %RemoteHostWarning
@onready var export_preset_warning: Label = %ExportPresetWarning
@onready var remote_debug_warning: Label = %RemoteDebugWarning if has_node("%RemoteDebugWarning") else null
@onready var tcp_server_error: Label = %TcpServerError if has_node("%TcpServerError") else null
@onready var login_panel: MarginContainer = %LoginPanel
@onready var scan_panel: MarginContainer = %ScanPanel
@onready var email_login_panel: VBoxContainer = %EmailLoginPanel
@onready var apple_login_panel: VBoxContainer = %AppleLoginPanel
@onready var profile_panel: VBoxContainer = %ProfilePanel
@onready var email_input: LineEdit = %EmailInput
@onready var send_code_button: Button = %SendCodeButton
@onready var verification_panel: VBoxContainer = %VerificationPanel
@onready var code_input: LineEdit = %CodeInput
@onready var verify_code_button: Button = %VerifyCodeButton
@onready var resend_code_button: Button = %ResendCodeButton
@onready var apple_api_key_input: LineEdit = %AppleApiKeyInput
@onready var submit_apple_api_key_button: Button = %SubmitAppleApiKeyButton
@onready var user_name_value: Label = %UserNameValue
@onready var manual_add_container: VBoxContainer = %ManualAddContainer
@onready var add_manual_device_button: Button = %AddManualDeviceButton
@onready var ip_input: LineEdit = %IPInput
@onready var port_input: LineEdit = %PortInput
@onready var name_input: LineEdit = %NameInput
@onready var add_device_button: Button = %AddDeviceButton
@onready var no_devices_help: MarginContainer = %NoDevicesHelp
@onready var remote_debug_help: MarginContainer = %RemoteDebugHelp
@onready var native_library_warning: PanelContainer = %NativeLibraryWarning
@onready var native_library_list: Label = %LibraryList

# Update notification UI (created programmatically)
var update_notification_panel: PanelContainer = null
var update_notification_label: Label = null
var update_download_button: Button = null

var is_logged_in := false
const APPLE_LOGIN_URL = "https://share.xogot.com/login-apple"
const API_BASE_URL = "https://xogotapi.azurewebsites.net/api/"
const REQUEST_CODE_ENDPOINT = "LoginPin"
const VERIFY_CODE_ENDPOINT = "LoginPin"

var http_request: HTTPRequest = null
var pending_email: String = ""

# Version check
var version_check_request: HTTPRequest = null
var update_available := false
var required_update := false
var latest_version := ""
var download_url := ""
var update_description := ""

var export_platform: XogotExportPlatform = null
var plugin: EditorPlugin = null
# Store discovered devices by deviceId (or address+port as fallback)
var discovered_devices := {}
# Store device states (deviceId -> state)
var device_states := {}

# Timer for removing stale devices
var stale_device_timer: Timer
const STALE_DEVICE_TIMEOUT := 8  # Remove devices not seen for 8 seconds

# TCP server integration
var tcp_server: TCPServer = null
var tcp_clients := []
const TCP_PORT := 9998
var tcp_server_running := false

# Store pending devices awaiting version confirmation during discovery
var pending_devices := {}  # {device_id: device_data}
var version_dialog: ConfirmationDialog = null

# Track approved version mismatches (versions the user has approved connecting to)
var approved_versions := {}  # {version_string: bool}

# Track rejected version mismatches (versions the user has rejected)
var rejected_versions := {}  # {version_string: bool}

# Current device being prompted for version confirmation
var current_version_prompt_device_id: String = ""

# Pairing system
var pairing_manager: PairingManager = null
signal pairing_succeeded(device_id: String)
signal pairing_failed(device_id: String, reason: String)

# Native library warning tracking
var native_library_files: Array = []
var show_native_library_warnings: bool = true

func debug_print(message: String):
	if XogotDebug.ENABLED:
		print(message)

func saveUser():
	if user.device_id == "":
		user.device_id = generate_guid()
	debug_print("Saving user with API key: " + user.api_key)
	# Ensure the Xogot directory exists
	var xogot_dir = EditorInterface.get_editor_paths().get_data_dir().path_join("Xogot")
	var dir = DirAccess.open(EditorInterface.get_editor_paths().get_data_dir())
	if dir and not dir.dir_exists("Xogot"):
		dir.make_dir("Xogot")
	var result = ResourceSaver.save(user, FILE_NAME)
	debug_print("Save result: " + str(result))
	if result != OK:
		printerr("Failed to save user data: ", result)
func loadUser():
	var hasUser := false
	debug_print("Attempting to load user from: " + FILE_NAME)
	if ResourceLoader.exists(FILE_NAME):
		debug_print("File exists, loading...")
		var loaded_user = ResourceLoader.load(FILE_NAME)
		debug_print("Loaded resource type: " + type_string(typeof(loaded_user)))
		if loaded_user is User:
			user = loaded_user
			hasUser = true
			debug_print("Successfully loaded user with API key: " + user.api_key)
			if user.device_id == "":
				user.device_id = generate_guid()
			#IF there is an apikey, we are logged in.
			is_logged_in = user.api_key != ""
		else:
			printerr("Invalid data type in file! Expected User, got: ", type_string(typeof(loaded_user)))
	else:
		debug_print("No saved data file found at: " + FILE_NAME)
	if !hasUser:
		debug_print("Creating new user")
		user = User.new()
		user.device_id = generate_guid()

	# Load native library warning preference
	show_native_library_warnings = EditorInterface.get_editor_settings().get_project_metadata("xogot", "show_native_library_warnings", true)

func _ready() -> void:
	print("Xogot Remote Debugger Plugin Ready")
	loadUser()
	# start_scanning()
	set_process(true)

	# Initialize pairing manager
	pairing_manager = PairingManager.new()
	pairing_succeeded.connect(_on_pairing_succeeded)
	pairing_failed.connect(_on_pairing_failed)

	# Check for native libraries and update warning panel
	_check_and_update_native_library_warning()

	# Initialize HTTP request node
	http_request = HTTPRequest.new()
	add_child(http_request)

	# Initialize version check HTTP request
	version_check_request = HTTPRequest.new()
	add_child(version_check_request)

	# Initialize version confirmation dialog
	version_dialog = ConfirmationDialog.new()
	version_dialog.title = "Godot Version Mismatch"
	version_dialog.ok_button_text = "Connect Anyway"
	version_dialog.cancel_button_text = "Cancel"
	add_child(version_dialog)

	# Create update notification UI
	_create_update_notification_ui()

	# Check for plugin updates
	check_plugin_version()

	# Check login status and show appropriate panel
	check_login_status()
	
	# Update remote host if it's localhost
	update_remote_host_if_needed()
	
	# Setup stale device removal timer
	stale_device_timer = Timer.new()
	stale_device_timer.wait_time = 1.0  # Check every second
	stale_device_timer.timeout.connect(_remove_stale_devices)
	stale_device_timer.autostart = true
	add_child(stale_device_timer)
	
	# Set reference to this instance in the export platform
	if export_platform:
		export_platform.xogot_instance = self

func _exit_tree():
	# Clean up when the plugin is removed
	if isScanning:
		stop_scanning()
		stop_tcp_server()
		stop_udp_listener()

	debug_print("Xogot Remote Debugger Plugin cleaned up")

func check_login_status():
	# Login is optional - pairing via PIN codes works without an account
	# If user has an API key, verify it for "Same Account" pairing benefit
	if user.api_key != "" and user.api_key != null:
		# Verify the API key is still valid
		verifyUserData(user.api_key)
	else:
		is_logged_in = false
		# Go directly to scan panel - login not required for PIN pairing
		show_scan_panel()

func show_login_panel():
	login_panel.visible = true
	scan_panel.visible = false
	# Show main login options, hide sub-panels
	login_panel.get_node("VBoxContainer").visible = true
	email_login_panel.visible = false
	apple_login_panel.visible = false
	profile_panel.visible = false

func show_scan_panel():
	login_panel.visible = false
	scan_panel.visible = true

	# Show manual add button if already scanning, otherwise hide it
	if add_manual_device_button:
		add_manual_device_button.visible = isScanning
	if manual_add_container:
		manual_add_container.visible = false
	# Hide help text initially
	if no_devices_help:
		no_devices_help.visible = false
	if remote_debug_help:
		remote_debug_help.visible = false

func show_email_login_panel():
	# Hide main login options, show email panel
	login_panel.get_node("VBoxContainer").visible = false
	email_login_panel.visible = true
	apple_login_panel.visible = false
	profile_panel.visible = false

func show_apple_login_panel():
	# Hide main login options, show apple panel
	login_panel.get_node("VBoxContainer").visible = false
	apple_login_panel.visible = true
	email_login_panel.visible = false
	profile_panel.visible = false

func show_profile_panel():
	# Show profile panel instead of login options
	login_panel.visible = true
	scan_panel.visible = false
	login_panel.get_node("VBoxContainer").visible = false
	email_login_panel.visible = false
	apple_login_panel.visible = false
	profile_panel.visible = true

func update_profile_display():
	# Update the profile panel with user information
	if user.user_name != "" and user.user_name != null:
		user_name_value.text = user.user_name
	else:
		user_name_value.text = "Not set"


var hasExportPlatform := false

func isFileServerEnabled() -> bool :
	return EditorInterface.get_editor_settings().get_project_metadata("debug_options", "run_file_server",false);

func isRemoteDebugEnabled() -> bool:
	return EditorInterface.get_editor_settings().get_project_metadata("debug_options", "run_deploy_remote_debug",true)

func isRemoteHostLocalhost() -> bool:
	var remote_host = EditorInterface.get_editor_settings().get_setting("network/debug/remote_host")
	return remote_host == "127.0.0.1" or remote_host == "localhost"

func hasXogotExportPreset() -> bool:
	# Check if export_presets.cfg exists and contains Xogot preset
	if not FileAccess.file_exists("res://export_presets.cfg"):
		return false
	
	var file = FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	if not file:
		return false
	
	var content = file.get_as_text()
	file.close()
	
	# Check if content contains Xogot preset
	return content.contains('name="Xogot"') and content.contains('platform="Xogot"')

func createXogotExportPreset() -> bool:
	# First, read existing content if file exists
	var existing_content = ""
	var highest_preset_index = -1
	
	if FileAccess.file_exists("res://export_presets.cfg"):
		var read_file = FileAccess.open("res://export_presets.cfg", FileAccess.READ)
		if read_file:
			existing_content = read_file.get_as_text()
			read_file.close()
			
			# Find the highest preset index
			var lines = existing_content.split("\n")
			for line in lines:
				if line.begins_with("[preset."):
					# Extract the number from [preset.N] or [preset.N.options]
					var parts = line.split(".")
					if parts.size() >= 2:
						var index_str = parts[1].split("]")[0]
						if index_str.is_valid_int():
							var index = index_str.to_int()
							if index > highest_preset_index:
								highest_preset_index = index
	
	# Next preset index is highest + 1
	var next_preset_index = highest_preset_index + 1
	
	# Create or append to export_presets.cfg
	var file = FileAccess.open("res://export_presets.cfg", FileAccess.WRITE)
	if not file:
		printerr("Could not create/open export_presets.cfg")
		return false
	
	# Write existing content first
	if existing_content != "":
		file.store_string(existing_content)
		if not existing_content.ends_with("\n"):
			file.store_string("\n")
	
	# Append new Xogot preset with correct index
	var preset_content = """[preset.%d]

name="Xogot"
platform="Xogot"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.%d.options]

custom_template/debug=""
custom_template/release=""
""" % [next_preset_index, next_preset_index]
	
	file.store_string(preset_content)
	file.close()
	debug_print("Created Xogot export preset at index %d in export_presets.cfg" % next_preset_index)
	return true

func ensureXogotExportPreset():
	if not hasXogotExportPreset():
		if createXogotExportPreset():
			# Try to refresh the export system
			# Note: This is a workaround since Godot doesn't expose proper APIs
			_try_refresh_export_presets()

func _try_refresh_export_presets():
	# Method 1: Try to access EditorExport through EditorInterface
	var editor_interface = EditorInterface
	
	# Method 2: Force a project settings save which might trigger a reload
	ProjectSettings.save()
	
	# Method 3: Try to emit a fake file system change
	if editor_interface.get_resource_filesystem():
		# Scan specifically for the export_presets.cfg file
		editor_interface.get_resource_filesystem().scan()
	
	# Method 4: Try to force the export system to reload by triggering related settings
	var editor_settings = EditorInterface.get_editor_settings()
	if editor_settings:
		# Emit a fake settings change to potentially trigger export system refresh
		editor_settings.emit_signal("settings_changed")
	
	# Method 5: Remove and re-add the export platform to force a refresh
	if export_platform and plugin:
		plugin.remove_export_platform(export_platform)
		# Small delay to ensure removal is processed
		await get_tree().create_timer(0.1).timeout
		plugin.add_export_platform(export_platform)
	
	# Method 6: Force update the UI
	_update_file_server_warning()

	debug_print("Attempted to refresh export presets")

func removeXogotExportPreset():
	if not hasXogotExportPreset():
		return
	
	# Read the current export_presets.cfg
	var file = FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	if not file:
		return
	
	var content = file.get_as_text()
	file.close()
	
	# Find and remove the Xogot preset section
	var lines = content.split("\n")
	var new_lines = []
	var skip_section = false
	var preset_count = 0
	var i = 0
	
	while i < lines.size():
		var line = lines[i]
		
		# Check if we're at a preset header
		if line.begins_with("[preset."):
			# Look ahead to see if this is the Xogot preset
			var is_xogot = false
			for j in range(i + 1, min(i + 5, lines.size())):
				if lines[j].contains('name="Xogot"') or lines[j].contains('platform="Xogot"'):
					is_xogot = true
					break
			
			if is_xogot:
				# Skip this entire preset section
				skip_section = true
				i += 1
				continue
			else:
				# This is a different preset, renumber it
				skip_section = false
				new_lines.append("[preset.%d]" % preset_count)
				preset_count += 1
				i += 1
				continue
		
		# If we're not skipping, add the line
		if not skip_section:
			new_lines.append(line)
		
		i += 1
	
	# Write the updated content back
	file = FileAccess.open("res://export_presets.cfg", FileAccess.WRITE)
	if file:
		file.store_string("\n".join(new_lines))
		file.close()
		debug_print("Removed Xogot export preset")
		_update_file_server_warning()  # Update UI to reflect the change

func _update_file_server_warning():
	if file_server_warning:
		file_server_warning.visible = not isFileServerEnabled()
	if remote_host_warning:
		remote_host_warning.visible = isRemoteHostLocalhost()
	if export_preset_warning:
		export_preset_warning.visible = not hasXogotExportPreset()
	if remote_debug_warning:
		remote_debug_warning.visible = not isRemoteDebugEnabled()

func _show_tcp_error(message: String):
	if tcp_server_error:
		tcp_server_error.text = message
		tcp_server_error.visible = true
		tcp_server_error.add_theme_color_override("font_color", Color(1, 0.3, 0.3))

func _hide_tcp_error():
	if tcp_server_error:
		tcp_server_error.visible = false

const MDNS_PORT := 9987
var udp_client: PacketPeerUDP
var isScanning := false
func start_scanning():
	isScanning = true
	udp_client = PacketPeerUDP.new()
	udp_client.set_broadcast_enabled(true)
	var err = udp_client.bind(MDNS_PORT)
	if err != OK:
		debug_print("Error binding to port: " + str(err))
		return
	debug_print("listening")

func stop_scanning():
	isScanning = false
	if udp_client and udp_client.is_bound():
		udp_client.close()
		udp_client = null
	debug_print("Stopped scanning")

	
	

var udp_listener: PacketPeerUDP
const UDP_LISTENER_PORT := 9877

func start_udp_listener():
	udp_listener = PacketPeerUDP.new()
	udp_listener.set_broadcast_enabled(true)
	var err = udp_listener.bind(UDP_LISTENER_PORT)
	if err != OK:
		printerr("Failed to bind UDP listener on port ", UDP_LISTENER_PORT, ": ", err)
		return
	debug_print("Started UDP listener on port " + str(UDP_LISTENER_PORT))

func stop_udp_listener():
	if udp_listener and udp_listener.is_bound():
		udp_listener.close()
		udp_listener = null
	debug_print("Stopped UDP listener")

func _process(_delta):
	processUdpListener()
	processTcpListener()
	process_udp_listener()	
	_update_file_server_warning()

func processUdpListener():
	if udp_client and udp_client.is_bound():
		while udp_client.get_available_packet_count() > 0:
			var packet = udp_client.get_packet()
			var message = packet.get_string_from_utf8()
			# print("UDP Message: ", message)

			# Parse JSON message
			var json_parser = JSON.new()
			var json = json_parser.parse(message)
			if json == OK:
				var data: Dictionary = json_parser.get_data()
				# Check for Swift UDPMessage format
				if data.has("messageType") and data.has("deviceName") and data.has("address") and data.has("dataPort"):
					add_device_to_ui(data)
				else:
					printerr("Received JSON, but missing required fields: ", message)
			else:
				printerr("Invalid JSON message received: ", message)

func processTcpListener():
	if tcp_server_running and tcp_server:
		# Accept new TCP clients
		if tcp_server.is_connection_available():
			var client = tcp_server.take_connection()
			var client_ip = client.get_connected_host()
			debug_print("TCP connection from: " + client_ip)

			# Version check was already done during discovery
			# If device is connecting, it means it was approved
			tcp_clients.append(client)
			_update_device_state_by_ip(client_ip, "Debugging")
		
		# Handle data from TCP clients and remove disconnected ones
		var clients_to_remove = []
		for i in range(tcp_clients.size()):
			var client = tcp_clients[i]
			var status = client.get_status()

			# Check if client is disconnected or has errors
			if status != StreamPeerTCP.STATUS_CONNECTED:
				clients_to_remove.append(i)
				if status == StreamPeerTCP.STATUS_ERROR:
					debug_print("TCP client error detected")
				elif status == StreamPeerTCP.STATUS_NONE:
					debug_print("TCP client disconnected")
				continue

			# Try to poll the connection to detect if it's still alive
			client.poll()

			# Check for available data
			if client.get_available_bytes() > 0:
				var available_bytes = client.get_available_bytes()
				debug_print("[TCP] Available bytes: %d" % available_bytes)

				# Read raw bytes first
				var raw_bytes = client.get_data(available_bytes)
				if raw_bytes[0] != OK:
					printerr("[TCP] Failed to read data: %d" % raw_bytes[0])
					clients_to_remove.append(i)
					continue

				var packet_data = raw_bytes[1]
				debug_print("[TCP] Raw packet size: %d bytes" % packet_data.size())

				# Check if data is length-prefixed (first 4 bytes = UInt32 length)
				var data: String = ""
				if packet_data.size() >= 4:
					# Try to read length prefix (big-endian UInt32)
					var length_prefix = (packet_data[0] << 24) | (packet_data[1] << 16) | (packet_data[2] << 8) | packet_data[3]
					debug_print("[TCP] Potential length prefix (big-endian): %d" % length_prefix)

					# Check if this looks like a length prefix
					if length_prefix > 0 and length_prefix < 1000000 and packet_data.size() >= (4 + length_prefix):
						# Data appears to be length-prefixed
						debug_print("[TCP] Data appears to be length-prefixed, extracting JSON...")
						var json_bytes = packet_data.slice(4, 4 + length_prefix)
						data = json_bytes.get_string_from_utf8()
						debug_print("[TCP] Extracted data length: %d" % data.length())
					else:
						# Try little-endian
						var length_prefix_le = packet_data[0] | (packet_data[1] << 8) | (packet_data[2] << 16) | (packet_data[3] << 24)
						debug_print("[TCP] Potential length prefix (little-endian): %d" % length_prefix_le)

						if length_prefix_le > 0 and length_prefix_le < 1000000 and packet_data.size() >= (4 + length_prefix_le):
							debug_print("[TCP] Data appears to be length-prefixed (little-endian), extracting JSON...")
							var json_bytes = packet_data.slice(4, 4 + length_prefix_le)
							data = json_bytes.get_string_from_utf8()
							debug_print("[TCP] Extracted data length: %d" % data.length())
						else:
							# Not length-prefixed, read as raw string
							debug_print("[TCP] No valid length prefix found, reading as raw UTF-8...")
							data = packet_data.get_string_from_utf8()
				else:
					# Packet too small for length prefix
					debug_print("[TCP] Packet too small for length prefix, reading as raw UTF-8...")
					data = packet_data.get_string_from_utf8()

				debug_print("[TCP] Final data: %s" % data)

				if data == "":  # Empty data might indicate disconnection
					printerr("[TCP] Empty data received (could not decode UTF-8), marking client for removal")
					debug_print("[TCP] Raw bytes (first 32): %s" % packet_data.slice(0, min(32, packet_data.size())))
					clients_to_remove.append(i)
					continue

				debug_print("Received from TCP client: " + data)

				# Parse JSON message
				var json_parser = JSON.new()
				var parse_result = json_parser.parse(data)
				debug_print("[TCP] JSON parse result: %d" % parse_result)

				if parse_result == OK:
					var msg = json_parser.get_data()
					debug_print("[TCP] Parsed message: %s" % str(msg))

					# Handle message types
					var message_type = msg.get("messageType", "")
					debug_print("[TCP] Message type: %s" % message_type)

					match message_type:
						"request":
							debug_print("[TCP] Received sync request from client")

						"cancel":
							var client_ip = client.get_connected_host()
							var cancel_id = msg.get("id", "")
							var reason = msg.get("reason", "User cancelled")
							debug_print("Sync cancelled: %s (ID: %s)" % [reason, cancel_id])
							_update_device_state_by_ip(client_ip, "Idle")

						"failed":
							var client_ip = client.get_connected_host()
							var fail_reason = msg.get("reason", "Unknown error")
							printerr("Sync failed: %s" % fail_reason)
							_update_device_state_by_ip(client_ip, "Error")

						"game_started":
							var client_ip = client.get_connected_host()
							debug_print("Game started on client")
							_update_device_state_by_ip(client_ip, "Debugging")

						"game_stopped":
							var client_ip = client.get_connected_host()
							debug_print("Received stop game request. Stopping TCP server.")
							_update_device_state_by_ip(client_ip, "Idle")
							stop_tcp_server()

						"syncing":
							var client_ip = client.get_connected_host()
							debug_print("Client is syncing files")
							_update_device_state_by_ip(client_ip, "Connecting")

						"sync_complete":
							var client_ip = client.get_connected_host()
							debug_print("Sync completed successfully")
							_update_device_state_by_ip(client_ip, "Connected")

						"pairing_request":
							debug_print("Received pairing request (unexpected on server)")

						"pairing_response":
							debug_print("[TCP] Handling pairing response")
							var client_ip = client.get_connected_host()
							handle_pairing_response(msg, client_ip)

						"pairing_accepted", "pairing_rejected":
							debug_print("Received pairing status: %s" % message_type)

						_:
							debug_print("[TCP] Unknown message type: %s" % message_type)
				else:
					printerr("[TCP] JSON parse error: %d" % parse_result)
					printerr("[TCP] Failed to parse: %s" % data)
		
		# Remove disconnected clients (iterate backwards to avoid index issues)
		for i in range(clients_to_remove.size() - 1, -1, -1):
			var idx = clients_to_remove[i]
			var client = tcp_clients[idx]
			var client_ip = client.get_connected_host()
			debug_print("Removing disconnected TCP client at index " + str(idx) + " (IP: " + client_ip + ")")
			# Update device state when client disconnects
			_update_device_state_by_ip(client_ip, "Idle")
			tcp_clients.remove_at(idx)

func process_udp_listener():
	if udp_listener and udp_listener.is_bound():
		while udp_listener.get_available_packet_count() > 0:
			var packet = udp_listener.get_packet()
			var sender = udp_listener.get_packet_ip()
			var sender_port = udp_listener.get_packet_port()
			var message = packet.get_string_from_utf8()
			debug_print("Received from " + sender + ":" + str(sender_port) + " - " + message)
			if message == "ping":
				var response = "pong".to_utf8_buffer()
				udp_listener.set_dest_address(sender, sender_port)
				udp_listener.put_packet(response)
				debug_print("Sent pong to " + sender + ":" + str(sender_port))

func add_device_to_ui(device_data: Dictionary):
	var key = device_data["deviceId"]
	# Add timestamp to device data for stale device removal
	device_data["last_seen"] = Time.get_unix_time_from_system()

	# Track pairing mode and session token
	if not device_data.has("isPairingMode"):
		device_data["isPairingMode"] = device_data.get("pairingMode", "false") == "true"
	if not device_data.has("sessionToken"):
		device_data["sessionToken"] = device_data.get("sessionToken", "")

	# Check pairing status
	device_data["isPaired"] = pairing_manager.is_paired(key)
	device_data["canConnect"] = _can_device_connect(device_data)
	device_data["badgeText"] = _get_device_badge_text(device_data)
	device_data["priority"] = _get_device_priority(device_data)

	# Check if this is a new device or an update
	var is_new_device = not discovered_devices.has(key)

	# Preserve existing approval status if device already exists
	if not is_new_device and discovered_devices.has(key):
		var existing_device = discovered_devices[key]
		if existing_device.has("versionApproved"):
			device_data["versionApproved"] = existing_device["versionApproved"]

	# Check Godot version compatibility
	if device_data.has("godotVersion"):
		var device_version = device_data["godotVersion"]
		var editor_version = get_current_godot_version()
		device_data["versionMatch"] = versions_match(device_version, editor_version)

		# For new devices with version mismatch, check if we need to prompt
		if is_new_device and not device_data["versionMatch"]:
			# Check if this version was already approved or rejected
			if approved_versions.has(device_version):
				# Already approved - mark as approved
				device_data["versionApproved"] = true
				debug_print("✓ Device version %s already approved: %s" % [device_version, device_data.get("deviceName", key)])
			elif rejected_versions.has(device_version):
				# Already rejected - mark as rejected
				device_data["versionApproved"] = false
				debug_print("✗ Device version %s already rejected: %s" % [device_version, device_data.get("deviceName", key)])
			else:
				# First time seeing this version - show dialog
				debug_print("⚠️ Version mismatch detected for device: " + device_data.get("deviceName", key))
				debug_print("   Editor: " + editor_version + ", Device: " + device_version)

				# Add to discovered devices immediately so it shows in UI
				discovered_devices[key] = device_data
				_refresh_device_list()

				# Show dialog and store device ID for callback
				current_version_prompt_device_id = key
				var device_name = device_data.get("deviceName", "Unknown Device")
				_show_version_mismatch_dialog(device_version, editor_version, device_name)
				return  # Early return - don't sync to export platform yet
		# For existing devices with version mismatch, ensure approval status is set from global lists
		elif not is_new_device and not device_data["versionMatch"]:
			if not device_data.has("versionApproved"):
				# Check global approval/rejection lists
				if approved_versions.has(device_version):
					device_data["versionApproved"] = true
				elif rejected_versions.has(device_version):
					device_data["versionApproved"] = false

	discovered_devices[key] = device_data

	if is_new_device:
		debug_print("Added device to UI: " + device_data.get("deviceName", key) + ", isManual: " + str(device_data.get("isManual", false)))

	# Sync with export platform singleton (only approved or matching devices)
	_sync_devices_to_export_platform()

	_refresh_device_list()

func _sync_devices_to_export_platform():
	# Only sync devices that can connect (paired or same account) and have approved versions
	if export_platform:
		var approved_devices = []
		for device in discovered_devices.values():
			var device_name = device.get("deviceName", "Unknown")
			var can_connect = device.get("canConnect", false)
			var has_version_match = device.get("versionMatch", true)
			var has_version_approved = device.has("versionApproved") and device["versionApproved"]

			# MUST be able to connect (paired/same account)
			if not can_connect:
				debug_print("  ✗ Excluding %s (pairing required)" % device_name)
				continue

			# MUST have matching or approved version
			var include_device = false
			if has_version_match:
				# Version matches or no version info
				include_device = true
				debug_print("  ✓ Including %s (version matches, can connect)" % device_name)
			elif has_version_approved:
				# Version mismatch but user approved it
				include_device = true
				debug_print("  ✓ Including %s (version approved: %s, can connect)" % [device_name, device.get("godotVersion", "?")])
			else:
				debug_print("  ✗ Excluding %s (version rejected or pending)" % device_name)

			if include_device:
				approved_devices.append(device)

		debug_print("Syncing %d devices to export platform" % approved_devices.size())
		export_platform.new_devices = approved_devices
		export_platform.devicesUpdated = true

const DevicePanel = preload("res://addons/xogot_connect/device_panel.tscn")

func _refresh_device_list():
	if devices_vbox:
		var children = devices_vbox.get_children()
		for child in children:
			child.queue_free()

		# Sort devices by priority (lower priority value = higher in list)
		var sorted_devices = discovered_devices.values()
		sorted_devices.sort_custom(func(a, b):
			var priority_a = a.get("priority", 999)
			var priority_b = b.get("priority", 999)
			if priority_a != priority_b:
				return priority_a < priority_b
			# If same priority, sort alphabetically by name
			return a.get("deviceName", "") < b.get("deviceName", "")
		)

		for device_data in sorted_devices:
			var device_panel = DevicePanel.instantiate()
			device_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			device_panel.set_device_data(device_data)
			devices_vbox.add_child(device_panel)

			# Connect the device_removed signal for manual devices
			if device_data.get("isManual", false):
				device_panel.device_removed.connect(_on_manual_device_removed)

			# Connect the device_clicked signal for rejected devices and unpaired devices
			device_panel.device_clicked.connect(_on_device_clicked)

			# Apply current state if exists
			var device_id = device_data["deviceId"]
			if device_states.has(device_id):
				device_panel.update_state(device_states[device_id])
			else:
				device_panel.update_state("Idle")

		# Update help text visibility
		_update_no_devices_help()
	else:
		printerr("devices_vbox is not initialized.")

func _update_no_devices_help():
	if no_devices_help:
		# Show help text only when scanning and no devices found
		no_devices_help.visible = isScanning and discovered_devices.is_empty()
	
	if remote_debug_help:
		# Show remote debug instructions when we have devices
		remote_debug_help.visible = isScanning and not discovered_devices.is_empty()

func _get_device_by_ip(ip: String) -> Dictionary:
	# Find and return device data by IP address
	for device_id in discovered_devices.keys():
		var device = discovered_devices[device_id]
		if device.has("address") and device["address"] == ip:
			return device
	return {}

func _update_device_state_by_ip(ip: String, state: String):
	# Find device by IP address and update its state
	for device_id in discovered_devices.keys():
		var device = discovered_devices[device_id]
		if device.has("address") and device["address"] == ip:
			device_states[device_id] = state
			_refresh_device_list()
			debug_print("Updated device state: " + device_id + " -> " + state)
			return
	debug_print("Could not find device with IP: " + ip)

func _has_active_tcp_connection(device_ip: String) -> bool:
	# Check if any TCP client is connected from this device IP
	for client in tcp_clients:
		if client:
			var status = client.get_status()
			if status == StreamPeerTCP.STATUS_CONNECTED:
				# Poll to ensure connection is still alive
				client.poll()
				# Re-check status after polling
				if client.get_status() == StreamPeerTCP.STATUS_CONNECTED and client.get_connected_host() == device_ip:
					return true
	return false

func _remove_stale_devices():
	var current_time = Time.get_unix_time_from_system()
	var devices_to_remove = []
	
	for device_id in discovered_devices.keys():
		var device_data = discovered_devices[device_id]
		
		# Skip manually added devices - they should only be removed manually
		if device_data.has("isManual") and device_data["isManual"]:
			continue
		
		if device_data.has("last_seen"):
			var time_since_last_seen = current_time - device_data["last_seen"]
			if time_since_last_seen > STALE_DEVICE_TIMEOUT:
				# Check if device has an active TCP connection
				var device_ip = device_data.get("address", "")
				if device_ip != "" and _has_active_tcp_connection(device_ip):
					# Only keep if we've seen the device recently (within 30 seconds)
					if time_since_last_seen < 30:
						debug_print("Keeping device with active TCP connection: " + device_id + " (IP: " + device_ip + ")")
						continue
					else:
						debug_print("Removing device despite TCP connection - not seen for " + str(time_since_last_seen) + " seconds")
				devices_to_remove.append(device_id)
				debug_print("Removing stale device: " + device_id + " (last seen " + str(time_since_last_seen) + " seconds ago)")
	
	# Remove stale devices
	for device_id in devices_to_remove:
		discovered_devices.erase(device_id)
		device_states.erase(device_id)
	
	# Update UI and export platform if devices were removed
	if devices_to_remove.size() > 0:
		if export_platform:
			# Make sure to preserve all device data including isManual flag
			var devices_array = []
			for device in discovered_devices.values():
				devices_array.append(device)
			export_platform.new_devices = devices_array
			export_platform.devicesUpdated = true
		_refresh_device_list()

func get_public_ip_addresses() -> Array:
	var ip_addresses = []
	var local_addresses = IP.get_local_addresses()
	for ip in local_addresses:
		# Filter for IPv4 addresses (contains dots, not colons)
		if "." in ip and ":" not in ip and "169.254." not in ip and ip != "127.0.0.1":
			ip_addresses.append(ip)
	return ip_addresses



func update_remote_host_if_needed():
	var settings = EditorInterface.get_editor_settings()
	var current_host = settings.get_setting("network/debug/remote_host")
	if current_host == "127.0.0.1" or current_host == "localhost":
		var best_ip = "0.0.0.0"
		settings.set_setting("network/debug/remote_host", best_ip)
		# settings.save()
		debug_print("Updated remote host from " + current_host + " to " + best_ip)

# Removed button functionality - devices are display only now
# func _on_device_panel_button_pressed(device_id: String, action: String):
# 	... (removed)

func get_current_godot_version() -> String:
	var version_info = Engine.get_version_info()
	return "%d.%d.%d" % [version_info.major, version_info.minor, version_info.patch]

func versions_match(version1: String, version2: String) -> bool:
	# Compare major.minor.patch versions
	return version1 == version2

func _show_version_mismatch_dialog(client_version: String, editor_version: String, device_name: String):
	if not version_dialog:
		return

	var message = "Godot version mismatch detected!\n\n"
	message += "Device: %s\n" % device_name
	message += "Editor Version: %s\n" % editor_version
	message += "Device Version: %s\n\n" % client_version
	message += "Connecting with different versions may cause unexpected behavior.\n"
	message += "Do you want to allow devices with this version?"

	version_dialog.dialog_text = message

	# Disconnect previous signals
	if version_dialog.confirmed.is_connected(_on_version_mismatch_confirmed):
		version_dialog.confirmed.disconnect(_on_version_mismatch_confirmed)
	if version_dialog.canceled.is_connected(_on_version_mismatch_canceled):
		version_dialog.canceled.disconnect(_on_version_mismatch_canceled)

	# Connect signals
	version_dialog.confirmed.connect(_on_version_mismatch_confirmed.bind(client_version))
	version_dialog.canceled.connect(_on_version_mismatch_canceled.bind(client_version))

	version_dialog.popup_centered()

func _on_version_mismatch_confirmed(device_version: String):
	debug_print("User approved version: " + device_version)

	# Add this version to approved list so we don't ask again
	approved_versions[device_version] = true

	# Remove from rejected list if it was there
	if rejected_versions.has(device_version):
		rejected_versions.erase(device_version)
		debug_print("Removed version %s from rejected list" % device_version)

	# Update the device that triggered this prompt
	if current_version_prompt_device_id != "" and discovered_devices.has(current_version_prompt_device_id):
		discovered_devices[current_version_prompt_device_id]["versionApproved"] = true
		debug_print("Device %s marked as approved" % current_version_prompt_device_id)

	# Update any other devices with the same version
	var devices_updated = 0
	for device_id in discovered_devices.keys():
		var device = discovered_devices[device_id]
		if device.has("godotVersion") and device["godotVersion"] == device_version:
			device["versionApproved"] = true
			devices_updated += 1

	debug_print("Updated %d devices with version %s" % [devices_updated, device_version])

	# Sync to export platform now that devices are approved
	_sync_devices_to_export_platform()
	_refresh_device_list()

	current_version_prompt_device_id = ""

	# Disconnect signals
	if version_dialog.confirmed.is_connected(_on_version_mismatch_confirmed):
		version_dialog.confirmed.disconnect(_on_version_mismatch_confirmed)
	if version_dialog.canceled.is_connected(_on_version_mismatch_canceled):
		version_dialog.canceled.disconnect(_on_version_mismatch_canceled)

func _on_version_mismatch_canceled(device_version: String):
	debug_print("User rejected version: " + device_version)

	# Add this version to rejected list
	rejected_versions[device_version] = true

	# Update the device that triggered this prompt
	if current_version_prompt_device_id != "" and discovered_devices.has(current_version_prompt_device_id):
		discovered_devices[current_version_prompt_device_id]["versionApproved"] = false
		debug_print("Device %s marked as rejected" % current_version_prompt_device_id)

	# Update any other devices with the same version
	for device_id in discovered_devices.keys():
		var device = discovered_devices[device_id]
		if device.has("godotVersion") and device["godotVersion"] == device_version:
			device["versionApproved"] = false

	# Refresh UI to show rejected state
	_refresh_device_list()

	current_version_prompt_device_id = ""

	# Disconnect signals
	if version_dialog.confirmed.is_connected(_on_version_mismatch_confirmed):
		version_dialog.confirmed.disconnect(_on_version_mismatch_confirmed)
	if version_dialog.canceled.is_connected(_on_version_mismatch_canceled):
		version_dialog.canceled.disconnect(_on_version_mismatch_canceled)

# --- Pairing System Helper Functions ---

## Check if a device can connect without pairing
func _can_device_connect(device_data: Dictionary) -> bool:
	var device_id = device_data.get("deviceId", "")
	var device_user_id = device_data.get("userId", "")

	# Priority 1: Same user ID
	if device_user_id != "" and user.user_id != "" and device_user_id == user.user_id:
		return true

	# Priority 2: Previously paired
	if pairing_manager.is_paired(device_id):
		return true

	# Priority 3: Has active session token (currently paired in this session)
	var is_pairing_mode = device_data.get("isPairingMode", false)
	var session_token = device_data.get("sessionToken", "")
	if is_pairing_mode and session_token != "":
		return true

	return false

## Get badge text for UI display
func _get_device_badge_text(device_data: Dictionary) -> String:
	var device_id = device_data.get("deviceId", "")
	var device_user_id = device_data.get("userId", "")

	if device_user_id != "" and user.user_id != "" and device_user_id == user.user_id:
		return "Same Account"
	if pairing_manager.is_paired(device_id):
		return "Paired"
	return "Pairing Required"

## Get device priority for sorting (lower = higher priority)
func _get_device_priority(device_data: Dictionary) -> int:
	var device_id = device_data.get("deviceId", "")
	var device_user_id = device_data.get("userId", "")

	if device_user_id != "" and user.user_id != "" and device_user_id == user.user_id:
		return 0  # Highest priority
	if pairing_manager.is_paired(device_id):
		return 1  # Second priority
	return 2  # Lowest priority

## Get device name for server identification
func get_device_name() -> String:
	# Return a user-friendly device name
	var hostname = OS.get_environment("HOSTNAME")
	if hostname == "":
		hostname = OS.get_environment("COMPUTERNAME")
	if hostname == "":
		hostname = "Godot Editor"
	return hostname

# --- Add a simple GUID generator ---
func generate_guid() -> String:
	var hex = "0123456789abcdef"
	var r = RandomNumberGenerator.new()
	r.randomize()
	var template = [8, 4, 4, 4, 12]
	var parts = []
	for len in template:
		var part = ""
		for i in range(len):
			part += hex[r.randi_range(0, 15)]
		parts.append(part)
	return "%s-%s-%s-%s-%s" % parts

func start_tcp_server():
	if tcp_server_running:
		return true  # Server already running, this is OK
	tcp_server = TCPServer.new()
	var err = tcp_server.listen(TCP_PORT)
	if err != OK:
		printerr("Failed to start TCP server: ", err)
		tcp_server = null
		tcp_server_running = false
		_show_tcp_error("Port %d is already in use. Another instance of Xogot Remote Debugger may be running." % TCP_PORT)
		return false
	else:
		debug_print("TCP server listening on port " + str(TCP_PORT))
		tcp_server_running = true
		tcp_clients.clear()
		_hide_tcp_error()
		return true

func stop_tcp_server():
	if not tcp_server_running:
		return
	debug_print("Stopping TCP server")
	# Send end game response to all clients
	var end_game_msg = {"messageType": "game_stopped"}
	var json = JSON.stringify(end_game_msg)
	var packet = json.to_utf8_buffer()
	for client in tcp_clients:
		client.put_data(packet)
		client.disconnect_from_host()
	tcp_clients.clear()
	if tcp_server:
		tcp_server.stop()
		tcp_server = null
	tcp_server_running = false

func sendSyncRequest(target_address: String, target_port: int, project_name: String, project_path: String, user_id: String, sender_ips: Array, sender_port: int, game_args: Array, sync_type: String = "rsync"):
	# Start TCP server for remote session
	if not start_tcp_server():
		# TCP server failed to start, update device state to show error
		for device_id in discovered_devices.keys():
			var device = discovered_devices[device_id]
			if device.has("address") and device["address"] == target_address:
				device_states[device_id] = "Error"
				_refresh_device_list()
				break
		return

	start_udp_listener()
	# Build sync request dictionary (matches Swift's SyncRequestMessage)
	var sync_request = {
		"messageType": "request",
		"id": generate_guid(),
		"userId": user_id,
		"deviceId": user.device_id,  # Add Godot server's device ID
		"projectName": project_name,
		"projectPath": project_path,
		"senderIPs": sender_ips,
		"senderPort": sender_port,
		"gameArgs": game_args,
		"timestamp": Time.get_unix_time_from_system(),
		"syncType": sync_type
	}
	debug_print("Sync request includes deviceId: %s" % user.device_id)
	var json = JSON.stringify(sync_request)
	var packet = json.to_utf8_buffer()
	var udp = PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	var err = udp.connect_to_host(target_address, target_port)
	if err != OK:
		printerr("Failed to connect to host for sync request: ", err)
		return
	var sent = udp.put_packet(packet)
	if sent != OK:
		printerr("Failed to send sync request packet: ", sent)
	else:
		debug_print("Sync request sent to %s:%s" % [target_address, str(target_port)])
	udp.close()

# Optionally, expose a manual stop function for UI or script
func stop_remote_session():
	stop_tcp_server()
	stop_udp_listener()
	_hide_tcp_error()

## Send a pairing request to a device
func send_pairing_request(device_data: Dictionary, pairing_code: String) -> void:
	var device_id = device_data.get("deviceId", "")
	var device_name = device_data.get("deviceName", "Unknown Device")
	var target_address = device_data.get("address", "")
	var target_port = device_data.get("dataPort", 9986)

	debug_print("[Pairing] Sending pairing request to %s with code: %s" % [device_name, pairing_code])
	debug_print("[Pairing] Target: %s:%s, Server ID: %s" % [target_address, target_port, user.device_id])

	# Ensure TCP server is running to receive pairing response
	if not tcp_server_running:
		debug_print("[Pairing] Starting TCP server to receive pairing response...")
		if not start_tcp_server():
			printerr("[Pairing] Failed to start TCP server")
			emit_signal("pairing_failed", device_id, "Failed to start TCP server")
			return
		debug_print("[Pairing] TCP server started on port %d" % TCP_PORT)

	# Create request message
	var request = {
		"id": generate_guid(),
		"messageType": "pairing_request",
		"pairingCode": pairing_code,
		"deviceId": user.device_id,
		"deviceName": get_device_name()
	}

	debug_print("[Pairing] Request: %s" % str(request))

	# Serialize to JSON
	var json_data = JSON.stringify(request)
	var data = json_data.to_utf8_buffer()

	# Send via UDP
	var udp = PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	var err = udp.connect_to_host(target_address, target_port)
	if err != OK:
		printerr("[Pairing] Failed to connect for pairing request: %d" % err)
		emit_signal("pairing_failed", device_id, "Network error")
		return

	var sent = udp.put_packet(data)
	if sent != OK:
		printerr("[Pairing] Failed to send pairing request: %d" % sent)
		emit_signal("pairing_failed", device_id, "Failed to send request")
	else:
		debug_print("[Pairing] Request sent to %s:%s" % [target_address, target_port])

	udp.close()

## Handle pairing response from device
func handle_pairing_response(data: Dictionary, client_ip: String) -> void:
	var response_id = data.get("id", "")
	var accepted = data.get("accepted", false)
	var session_token = data.get("sessionToken", "")
	var reason = data.get("reason", "Unknown error")

	debug_print("[Pairing] Response from %s: accepted=%s, token=%s" % [client_ip, str(accepted), session_token])

	# Find device by IP
	var device_data = _get_device_by_ip(client_ip)
	if device_data.is_empty():
		printerr("[Pairing] Could not find device for IP: %s" % client_ip)
		return

	var device_id = device_data.get("deviceId", "")
	var device_name = device_data.get("deviceName", "Unknown Device")

	if accepted and session_token != "":
		debug_print("[Pairing] Pairing accepted for %s" % device_name)

		# Save device as permanently paired
		pairing_manager.add_paired_device(device_id, device_name)

		# Update device in discovered devices list
		discovered_devices[device_id]["sessionToken"] = session_token
		discovered_devices[device_id]["isPairingMode"] = true
		discovered_devices[device_id]["isPaired"] = true
		discovered_devices[device_id]["canConnect"] = true
		discovered_devices[device_id]["badgeText"] = "Paired"
		discovered_devices[device_id]["priority"] = 1

		# Refresh UI
		_refresh_device_list()

		# Emit success signal
		emit_signal("pairing_succeeded", device_id)

		print("[Pairing] Successfully paired with %s" % device_name)
	else:
		printerr("[Pairing] Pairing rejected: %s" % reason)
		emit_signal("pairing_failed", device_id, reason)

## Called when pairing succeeds - auto-launch game
func _on_pairing_succeeded(device_id: String) -> void:
	debug_print("[Pairing] Pairing succeeded for device: %s" % device_id)

	# Update UI to show paired status
	_refresh_device_list()
	_sync_devices_to_export_platform()

	# Auto-launch game on paired device
	if discovered_devices.has(device_id):
		if export_platform:
			export_platform.selected_device_id = device_id
			debug_print("[Pairing] Export platform updated to use device: %s" % device_id)
		else:
			printerr("[Pairing] Export platform is null")
	else:
		printerr("[Pairing] Device %s not found in discovered_devices" % device_id)

## Called when pairing fails
func _on_pairing_failed(device_id: String, reason: String) -> void:
	printerr("[Pairing] Pairing failed for device %s: %s" % [device_id, reason])

	# Show error dialog
	var dialog = AcceptDialog.new()
	dialog.title = "Pairing Failed"

	match reason:
		"Invalid pairing code":
			dialog.dialog_text = "Incorrect pairing code. Please check the code and try again."
		"Pairing mode is not active":
			dialog.dialog_text = "Device is not in pairing mode. Please restart advertising on the device."
		"Session expired":
			dialog.dialog_text = "Pairing session expired. Please try again."
		_:
			dialog.dialog_text = "Pairing failed: %s" % reason

	add_child(dialog)
	dialog.popup_centered()
	# Auto-cleanup dialog when closed
	dialog.confirmed.connect(func(): dialog.queue_free())

## Show warning dialog about native iOS libraries
func show_native_library_warning(warning_msg: String) -> void:
	# Only show popup dialog if warnings are enabled
	if not show_native_library_warnings:
		return

	var dialog = ConfirmationDialog.new()
	dialog.title = "iOS Native Libraries Detected"
	dialog.dialog_text = warning_msg + "\n\nYou can continue debugging, but these libraries will not be loaded."
	dialog.ok_button_text = "Continue"
	dialog.cancel_button_text = "Don't Show This Again"

	add_child(dialog)
	dialog.popup_centered()

	# Handle "Continue" button - just close the dialog
	dialog.confirmed.connect(func(): dialog.queue_free())

	# Handle "Don't Show This Again" button
	dialog.canceled.connect(func():
		show_native_library_warnings = false
		# Don't hide the panel - only suppress popup dialogs
		EditorInterface.get_editor_settings().set_project_metadata("xogot", "show_native_library_warnings", false)
		print("[Xogot] Native library popup warnings disabled (panel will still show)")
		dialog.queue_free()
	)

## Check for native libraries and update the warning panel
func _check_and_update_native_library_warning() -> void:
	if not export_platform:
		return

	# Get native library files from export platform
	var project_path = ProjectSettings.globalize_path("res://")
	native_library_files.clear()

	# Check for .a (static libraries)
	native_library_files.append_array(_find_files_by_extension(project_path, ".a"))

	# Check for .dylib (dynamic libraries)
	native_library_files.append_array(_find_files_by_extension(project_path, ".dylib"))

	# Check for .xcframework
	native_library_files.append_array(_find_directories_by_name(project_path, ".xcframework"))

	# Check for .framework (iOS frameworks)
	native_library_files.append_array(_find_directories_by_name(project_path, ".framework"))

	# Update the warning panel - always show if libraries are detected
	if native_library_files.size() > 0:
		var library_list_text = ""
		for file in native_library_files:
			var relative_path = file.replace(project_path, "res://")
			library_list_text += "  • %s\n" % relative_path

		native_library_list.text = library_list_text
		native_library_warning.visible = true
	else:
		native_library_warning.visible = false

# Recursively find files with a specific extension
func _find_files_by_extension(path: String, extension: String) -> Array:
	var files = []
	var dir = DirAccess.open(path)

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()

		while file_name != "":
			var full_path = path.path_join(file_name)

			if dir.current_is_dir():
				# Skip hidden directories and common build/cache directories
				if not file_name.begins_with(".") and file_name != "build" and file_name != ".godot":
					files.append_array(_find_files_by_extension(full_path, extension))
			else:
				if file_name.ends_with(extension):
					files.append(full_path)

			file_name = dir.get_next()

		dir.list_dir_end()

	return files

# Recursively find directories with a specific name pattern
func _find_directories_by_name(path: String, pattern: String) -> Array:
	var directories = []
	var dir = DirAccess.open(path)

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()

		while file_name != "":
			var full_path = path.path_join(file_name)

			if dir.current_is_dir():
				# Skip hidden directories and common build/cache directories
				if not file_name.begins_with(".") and file_name != "build" and file_name != ".godot":
					if file_name.ends_with(pattern):
						directories.append(full_path)
					else:
						directories.append_array(_find_directories_by_name(full_path, pattern))

			file_name = dir.get_next()

		dir.list_dir_end()

	return directories

func _on_scan_button_pressed() -> void:
	debug_print("Scan button pressed")
	
	_update_file_server_warning()
	
	if isScanning:
		stop_scanning()
		stop_tcp_server()
		stop_udp_listener()
		%ScanButton.text = "Search Peer Devices"
		isScanning = false
		_hide_tcp_error()

		# Clear only the remote debug device list (not discovered_devices)
		# This removes approved devices from remote debugging but keeps them stored
		# so manual devices will reappear when scanning is re-enabled
		if export_platform:
			export_platform.new_devices = []
			export_platform.devicesUpdated = true

		# Hide manual add button when scanning is disabled
		if add_manual_device_button:
			add_manual_device_button.visible = false
		# Also hide the manual add container if it's visible
		if manual_add_container:
			manual_add_container.visible = false

		# Update help text visibility
		_update_no_devices_help()
		
		# Remove Xogot export preset when stopping scan
		# removeXogotExportPreset()
	else:
		# Ensure Xogot export preset exists when starting scan
		ensureXogotExportPreset()
		
		start_scanning()
		if start_tcp_server():
			isScanning = true
			%ScanButton.text = "Stop Search"
			
			# Show manual add button when scanning is enabled
			if add_manual_device_button:
				add_manual_device_button.visible = true
			
			# Update help text visibility
			_update_no_devices_help()
		else:
			# TCP server failed, scanning not started
			stop_scanning()
			isScanning = false

# Removed - no longer using device buttons
# func _on_remote_debug_button_pressed(deviceId: String):
# 	print("Remote Debugging for device: ", deviceId)

# Login-related button handlers
func _on_login_back_button_pressed():
	debug_print("Login back button pressed")
	show_scan_panel()

func _on_email_login_button_pressed():
	debug_print("Email login button pressed")
	show_email_login_panel()

func _on_apple_login_button_pressed():
	debug_print("Apple login button pressed")
	show_apple_login_panel()

func _on_email_back_button_pressed():
	debug_print("Email back button pressed")
	show_login_panel()

func _on_apple_back_button_pressed():
	debug_print("Apple back button pressed")
	show_login_panel()

func _on_email_input_text_changed(new_text: String):
	send_code_button.disabled = new_text.strip_edges().length() == 0

func _on_send_code_button_pressed():
	var email = email_input.text.strip_edges()
	if email.length() > 0:
		debug_print("Sending verification code to: " + email)
		pending_email = email
		_request_verification_code(email)

func _on_code_input_text_changed(new_text: String):
	verify_code_button.disabled = new_text.strip_edges().length() == 0

func _on_verify_code_button_pressed():
	var code = code_input.text.strip_edges()
	if code.length() > 0:
		debug_print("Verifying code: " + code)
		_verify_code(pending_email, code)

func _on_resend_code_button_pressed():
	debug_print("Resending verification code")
	send_code_button.text = "Send Verification Code"
	send_code_button.disabled = false
	_on_send_code_button_pressed()

func _on_launch_apple_browser_button_pressed():
	debug_print("Launching browser for Apple login")
	OS.shell_open(APPLE_LOGIN_URL)

func _on_apple_api_key_input_text_changed(new_text: String):
	submit_apple_api_key_button.disabled = new_text.strip_edges().length() == 0

func _on_submit_apple_api_key_button_pressed():
	var api_key = apple_api_key_input.text.strip_edges()
	if api_key.length() > 0:
		debug_print("Submitting Apple API key: " + api_key)
		authenticate_with_api_key(api_key)
func verifyUserData(api_key: String):
	# Make an API call to /api/GetUser with the api key in the header
	
	# Disconnect any existing connections
	if http_request.request_completed.is_connected(_on_get_user_completed):
		http_request.request_completed.disconnect(_on_get_user_completed)
	
	# Prepare request
	var url = API_BASE_URL + "GetUser"
	var headers = [
		"Content-Type: application/json",
		"apiKey: " + api_key
	]
	
	# Connect signal for response
	http_request.request_completed.connect(_on_get_user_completed)
	
	# Make request
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		debug_print("Failed to make GetUser request: " + str(error))
		# Revert to not logged in state
		is_logged_in = false
		show_login_panel()

func _on_get_user_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	# Disconnect signal
	http_request.request_completed.disconnect(_on_get_user_completed)
	
	if response_code == 200:
		var json = JSON.new()
		var jsonString = body.get_string_from_utf8()
		debug_print("GetUser response: " + jsonString)
		var parse_result = json.parse(jsonString)

		if parse_result == OK:
			var user_data = json.data
			# Update user data based on API response
			# Expected fields: id, username, displayName, email, dateCreated
			if user_data.has("id"):
				user.user_id = user_data["id"]
			if user_data.has("username"):
				user.user_name = user_data["username"]
			if user_data.has("email"):
				user.email = user_data["email"]

			# Save updated user data
			saveUser()

			# User is verified, proceed to scan panel
			is_logged_in = true
			show_scan_panel()
			debug_print("User verified successfully")
		else:
			debug_print("Failed to parse GetUser response")
			is_logged_in = false
			show_login_panel()
	else:
		debug_print("GetUser request failed with status code: " + str(response_code))
		# Invalid API key or other error
		user.api_key = ""
		saveUser()
		is_logged_in = false
		show_login_panel()

func authenticate_with_api_key(api_key: String):
	# Store the API key
	user.api_key = api_key
	saveUser()
	
	# Validate API key with server and get user data
	verifyUserData(api_key)
	
	# Clear all input fields
	apple_api_key_input.text = ""
	email_input.text = ""
	code_input.text = ""
	pending_email = ""
	
	# Reset email verification UI
	verification_panel.visible = false
	send_code_button.text = "Send Verification Code"
	send_code_button.disabled = false
	verify_code_button.text = "Verify Code"
	
	# Show scan panel
	show_scan_panel()

	debug_print("Login successful with API key")


func logout():
	user.api_key = ""
	user.user_id = ""
	user.email = ""
	user.user_name = ""
	saveUser()
	is_logged_in = false
	show_login_panel()
	debug_print("Logged out")

func _on_continue_button_pressed():
	debug_print("Continue to devices")
	show_scan_panel()

func _on_logout_button_pressed():
	debug_print("Logout button pressed")
	logout()

func _on_profile_button_pressed():
	debug_print("Profile button pressed")
	if is_logged_in:
		show_profile_panel()
		update_profile_display()
	else:
		show_login_panel()

# API Request Functions
func get_api_key() -> String:
	if user.api_key != "" and user.api_key != null:
		return user.api_key
	else:
		return ""

func _request_verification_code(email: String):
	# Disconnect any existing connections
	if http_request.request_completed.is_connected(_on_request_code_completed):
		http_request.request_completed.disconnect(_on_request_code_completed)
	
	# Show loading state
	send_code_button.text = "Sending..."
	send_code_button.disabled = true
	
	# Prepare request
	var url = API_BASE_URL + REQUEST_CODE_ENDPOINT
	var headers = [
		"Content-Type: application/json"
	]
	# Only add apiKey header if we have one
	var api_key = get_api_key()
	if api_key != "":
		headers.append("apiKey: " + api_key)
	var body = JSON.stringify({
		"email": email,
		"device": user.device_id
	})
	
	# Connect signal for response
	http_request.request_completed.connect(_on_request_code_completed)
	
	# Make request
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		debug_print("Failed to make request: " + str(error))
		_handle_request_code_error("Network error")

func _on_request_code_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	# Disconnect signal
	http_request.request_completed.disconnect(_on_request_code_completed)
	
	if response_code == 200:
		var response_text = body.get_string_from_utf8()
		if response_text == "Pin Sent":
			debug_print("Verification code sent successfully")
			# Show verification panel
			verification_panel.visible = true
			send_code_button.text = "Code Sent"
			send_code_button.disabled = true
		else:
			_handle_request_code_error("Unexpected response: " + response_text)
	else:
		_handle_request_code_error("Failed to send code (HTTP " + str(response_code) + ")")

func _handle_request_code_error(error_msg: String):
	debug_print("Error requesting verification code: " + error_msg)
	send_code_button.text = "Send Verification Code"
	send_code_button.disabled = false
	# TODO: Show error message to user

func _verify_code(email: String, code: String):
	# Disconnect any existing connections
	if http_request.request_completed.is_connected(_on_verify_code_completed):
		http_request.request_completed.disconnect(_on_verify_code_completed)
	
	# Show loading state
	verify_code_button.text = "Verifying..."
	verify_code_button.disabled = true
	
	# Prepare request
	var url = API_BASE_URL + VERIFY_CODE_ENDPOINT
	var headers = [
		"Content-Type: application/json"
	]
	# Only add apiKey header if we have one
	var api_key = get_api_key()
	if api_key != "":
		headers.append("apiKey: " + api_key)
	var body = JSON.stringify({
		"email": email,
		"device": user.device_id,
		"pin": code
	})
	
	# Connect signal for response
	http_request.request_completed.connect(_on_verify_code_completed)
	
	# Make request
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		debug_print("Failed to make request: " + str(error))
		_handle_verify_code_error("Network error")

func _on_verify_code_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	# Disconnect signal
	http_request.request_completed.disconnect(_on_verify_code_completed)
	
	if response_code == 200:
		var json = JSON.new()
		var jsonString = body.get_string_from_utf8()
		debug_print(jsonString)
		var parse_result = json.parse(jsonString)

		if parse_result == OK:
			var response = json.data
			if response.has("apiKey") and response.has("user"):
				debug_print("Code verified successfully")
				# Store user information
				var user_data = response["user"]
				user.user_id = user_data["id"]
				user.user_name = user_data["username"]
				# Authenticate with the returned API key
				authenticate_with_api_key(response["apiKey"])
			else:
				_handle_verify_code_error("No API key or user data in response")
		else:
			_handle_verify_code_error("Invalid response")
	elif response_code == 401:
		_handle_verify_code_error("Invalid verification code")
	else:
		_handle_verify_code_error("Failed to verify code (HTTP " + str(response_code) + ")")

func _handle_verify_code_error(error_msg: String):
	debug_print("Error verifying code: " + error_msg)
	verify_code_button.text = "Verify Code"
	verify_code_button.disabled = false
	# TODO: Show error message to user

func _validate_manual_add_inputs():
	if ip_input and port_input and name_input and add_device_button:
		var ip_valid = ip_input.text.strip_edges() != "" and _is_valid_ip(ip_input.text)
		var port_valid = port_input.text.strip_edges() != "" and port_input.text.is_valid_int()
		var name_valid = name_input.text.strip_edges() != ""
		
		add_device_button.disabled = not (ip_valid and port_valid and name_valid)

func _is_valid_ip(ip: String) -> bool:
	var parts = ip.split(".")
	if parts.size() != 4:
		return false
	
	for part in parts:
		if not part.is_valid_int():
			return false
		var num = part.to_int()
		if num < 0 or num > 255:
			return false
	
	return true

func _on_manual_ip_input_text_changed(new_text: String):
	_validate_manual_add_inputs()

func _on_manual_port_input_text_changed(new_text: String):
	_validate_manual_add_inputs()

func _on_manual_name_input_text_changed(new_text: String):
	_validate_manual_add_inputs()

func _on_add_device_button_pressed():
	if not ip_input or not port_input or not name_input:
		return
	
	var ip_address = ip_input.text.strip_edges()
	var port = port_input.text.strip_edges().to_int()
	var device_name = name_input.text.strip_edges()
	
	# Generate a unique device ID for manually added devices
	var device_id = "manual_%s_%d" % [ip_address.replace(".", "_"), port]
	
	# Create device data matching the structure of discovered devices
	var device_data = {
		"deviceId": device_id,
		"deviceName": device_name + " (Manual)",
		"address": ip_address,
		"dataPort": port,
		"serviceType": "manual",
		"appVersion": "Unknown",
		"isManual": true,
		"messageType": "mDNS"
	}
	
	# Add the device using the existing add_device_to_ui function
	add_device_to_ui(device_data)

	# Clear the input fields after adding
	ip_input.text = ""
	port_input.text = "9986"
	name_input.text = ""
	_validate_manual_add_inputs()

	debug_print("Manually added device: %s at %s:%d" % [device_name, ip_address, port])

func _on_device_clicked(device_id: String, godot_version: String):
	# Get device data
	if not discovered_devices.has(device_id):
		return

	var device_data = discovered_devices[device_id]
	var device_name = device_data.get("deviceName", "Unknown Device")
	var can_connect = device_data.get("canConnect", false)

	# Check if device can connect without pairing
	if can_connect:
		# Device is already paired or same account - this click is for version mismatch
		debug_print("Clicked on rejected device: " + device_id + ", version: " + godot_version)
		var editor_version = get_current_godot_version()

		# Remove from rejected list so we can re-prompt
		rejected_versions.erase(godot_version)

		# Store current device for callback
		current_version_prompt_device_id = device_id

		# Show the dialog again
		_show_version_mismatch_dialog(godot_version, editor_version, device_name)
	else:
		# Device needs pairing - show pairing dialog
		debug_print("Clicked on unpaired device: " + device_id)
		_show_pairing_dialog(device_data)

## Show pairing dialog for code entry
func _show_pairing_dialog(device_data: Dictionary) -> void:
	var device_name = device_data.get("deviceName", "Unknown Device")

	var dialog = PairingDialog.instantiate()
	dialog.device_name = device_name

	# Connect signals
	dialog.code_entered.connect(func(code):
		send_pairing_request(device_data, code)
		dialog.queue_free()
	)

	dialog.cancelled.connect(func():
		dialog.queue_free()
	)

	add_child(dialog)
	dialog.popup_centered()

func _on_manual_device_removed(device_id: String):
	if discovered_devices.has(device_id):
		discovered_devices.erase(device_id)
		if device_states.has(device_id):
			device_states.erase(device_id)
		_refresh_device_list()
		debug_print("Removed manual device: " + device_id)

func _on_add_manual_device_button_pressed():
	if manual_add_container:
		manual_add_container.visible = not manual_add_container.visible
		# Update button text based on visibility
		if add_manual_device_button:
			if manual_add_container.visible:
				add_manual_device_button.text = "− Hide Manual Connection"
			else:
				add_manual_device_button.text = "+ Add Device Manually"

func _create_update_notification_ui():
	# Create a panel container for the update notification
	update_notification_panel = PanelContainer.new()
	update_notification_panel.visible = false
	update_notification_panel.custom_minimum_size = Vector2(0, 44)

	# Add some styling
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.5, 0.8, 0.9)  # Blue background
	style.set_corner_radius_all(5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	update_notification_panel.add_theme_stylebox_override("panel", style)

	# Create an HBoxContainer to hold label and button
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	update_notification_panel.add_child(hbox)

	# Create label
	update_notification_label = Label.new()
	update_notification_label.text = "Update available!"
	update_notification_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	update_notification_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	update_notification_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hbox.add_child(update_notification_label)

	# Create download button
	update_download_button = Button.new()
	update_download_button.text = "Download"
	update_download_button.custom_minimum_size = Vector2(100, 0)
	update_download_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	update_download_button.pressed.connect(_on_update_download_pressed)
	hbox.add_child(update_download_button)

	# Add to the VBoxContainer inside scan_panel, not to scan_panel itself
	# scan_panel is a MarginContainer which can only have one child (the VBoxContainer)
	if scan_panel:
		var vbox = scan_panel.get_child(0)  # Get the VBoxContainer inside MarginContainer
		if vbox:
			vbox.add_child(update_notification_panel)
			vbox.move_child(update_notification_panel, 0)  # Move to top

		# Add a spacer after the update notification
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(0, 10)
		spacer.name = "UpdateNotificationSpacer"
		spacer.visible = false  # Hidden by default
		if vbox:
			vbox.add_child(spacer)
			vbox.move_child(spacer, 1)  # Right after the update panel

func _show_update_notification():
	if update_notification_panel and update_available:
		update_notification_label.text = "Update available: v%s - %s" % [latest_version, update_description]
		update_notification_panel.visible = true

		# Also show the spacer if it exists
		if scan_panel:
			var vbox = scan_panel.get_child(0)
			if vbox:
				var spacer = vbox.get_node_or_null("UpdateNotificationSpacer")
				if spacer:
					spacer.visible = true

func _on_update_download_pressed():
	if download_url != "":
		OS.shell_open(download_url)
		debug_print("Opening download URL: " + download_url)

# Version check functions
func check_plugin_version():
	var url = API_BASE_URL + "CheckExtensionVersion?version=" + PLUGIN_VERSION
	debug_print("Checking for plugin updates: " + url)

	# Disconnect any existing connections
	if version_check_request.request_completed.is_connected(_on_version_check_completed):
		version_check_request.request_completed.disconnect(_on_version_check_completed)

	# Connect signal for response
	version_check_request.request_completed.connect(_on_version_check_completed)

	# Make request
	var error = version_check_request.request(url, [], HTTPClient.METHOD_GET)
	if error != OK:
		printerr("Failed to check for updates: ", error)

func _on_version_check_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	# Disconnect signal
	version_check_request.request_completed.disconnect(_on_version_check_completed)

	if response_code == 200:
		var json = JSON.new()
		var json_string = body.get_string_from_utf8()
		var parse_result = json.parse(json_string)

		if parse_result == OK:
			var data = json.data
			debug_print("Version check response: " + json_string)

			update_available = not data.get("isUpToDate", true)
			required_update = data.get("isRequiredUpdate", false)
			latest_version = data.get("latestVersion", "")
			download_url = data.get("downloadUrl", "")
			update_description = data.get("description", "")

			if required_update:
				# Show required update popup immediately
				_show_required_update_dialog()
			elif update_available:
				# Show update notification in UI
				debug_print("Update available: " + latest_version)
				_show_update_notification()
		else:
			printerr("Failed to parse version check response")
	else:
		printerr("Version check failed with status code: ", response_code)

func _show_required_update_dialog():
	var dialog = AcceptDialog.new()
	dialog.title = "Required Update"
	dialog.dialog_text = "A required update is available!\n\n"
	dialog.dialog_text += "Current Version: " + PLUGIN_VERSION + "\n"
	dialog.dialog_text += "Latest Version: " + latest_version + "\n\n"
	dialog.dialog_text += update_description + "\n\n"
	dialog.dialog_text += "Please update to continue using Xogot Remote Debugger."

	# Add a button to open download URL
	dialog.add_button("Download Update", true, "download")
	dialog.custom_action.connect(_on_update_dialog_action)

	add_child(dialog)
	dialog.popup_centered()

func _on_update_dialog_action(action: String):
	if action == "download" and download_url != "":
		OS.shell_open(download_url)
		debug_print("Opening download URL: " + download_url)
