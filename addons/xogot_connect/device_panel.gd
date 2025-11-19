@tool
extends Panel

const XogotDebug = preload("res://addons/xogot_connect/xogot_debug.gd")

# Device data
var device_id: String
var currentText: String
var current_state: String = "Idle"
var is_manual: bool = false
var pending_device_data: Dictionary = {}
var is_version_rejected: bool = false
var device_godot_version: String = ""
var can_connect: bool = true
var badge_text: String = ""

# Node references
@onready var device_label: Label = $HBoxContainer/DeviceLabel
@onready var state_indicator: ColorRect = $HBoxContainer/IndicatorContainer/StateIndicator
@onready var remove_button: Button = %RemoveButton

signal device_removed(device_id: String)
signal device_clicked(device_id: String, godot_version: String)

func _ready():
	# Connect to label's resized signal to adjust panel height
	if device_label:
		device_label.resized.connect(_on_label_resized)
	
	# Connect the remove button signal
	if remove_button and not remove_button.pressed.is_connected(_on_remove_pressed):
		remove_button.pressed.connect(_on_remove_pressed)
	
	# Update UI with any data that was set before ready
	_update_ui()

func _update_ui():
	# Update the label text
	if device_label and currentText != "":
		device_label.text = currentText
		# Trigger height adjustment after text change
		call_deferred("_on_label_resized")
	
	# Update remove button visibility
	if remove_button:
		remove_button.visible = is_manual
	
	# Update state indicator
	if state_indicator:
		update_state(current_state)

func set_device_data(device_data: Dictionary):
	device_id = device_data["deviceId"]
	is_manual = device_data.get("isManual", false)
	device_godot_version = device_data.get("godotVersion", "")

	# Check pairing status
	can_connect = device_data.get("canConnect", true)
	badge_text = device_data.get("badgeText", "")

	# Check if this device's version was rejected
	is_version_rejected = device_data.has("versionApproved") and not device_data["versionApproved"]

	if XogotDebug.ENABLED:
		print("Setting device data for: ", device_id, ", isManual: ", is_manual, ", rejected: ", is_version_rejected, ", canConnect: ", can_connect, ", badge: ", badge_text)

	var device_text = "%s (%s)" % [
		device_data.get("deviceName", "Unknown Device"),
		device_data.get("address", "?")
	]

	# Add pairing badge to text
	if badge_text != "":
		match badge_text:
			"Same Account":
				device_text += " [✓ Same Account]"
			"Paired":
				device_text += " [✓ Paired]"
			"Pairing Required":
				device_text += " [⚠ Pairing Required]"

	# Add rejection indicator to text (overrides pairing badge if rejected)
	if is_version_rejected:
		device_text += " [Version Rejected]"

	currentText = device_text

	# Set tooltip text
	if device_label:
		var tooltip = "Type: %s, Version: %s" % [
			device_data.get("serviceType", "?"),
			device_data.get("appVersion", "?")
		]
		if badge_text == "Pairing Required":
			tooltip += "\n⚠️ Click to enter pairing code"
		elif is_version_rejected:
			tooltip += "\n⚠️ Click to re-enable this version"
		device_label.tooltip_text = tooltip

	# Update the UI
	_update_ui()

func update_state(state: String):
	current_state = state

	# If version is rejected, override state with rejected color
	if is_version_rejected:
		state_indicator.color = Color.ORANGE_RED
		return

	# Update visual indicators based on state
	match state:
		"Idle":
			state_indicator.color = Color.GRAY
		"Connecting":
			state_indicator.color = Color.YELLOW
		"Connected":
			state_indicator.color = Color.GREEN
		"Debugging":
			state_indicator.color = Color.CYAN
		"Error":
			state_indicator.color = Color.RED
		"Awaiting Confirmation...":
			state_indicator.color = Color.YELLOW

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# Emit click signal if device is rejected OR needs pairing
			if is_version_rejected or badge_text == "Pairing Required":
				device_clicked.emit(device_id, device_godot_version)
				accept_event()

func _on_remove_pressed():
	device_removed.emit(device_id)

func _on_label_resized():
	if not device_label:
		return
	
	# Wait for the next frame to ensure the label has calculated its size
	await get_tree().process_frame
	
	# Get the label's preferred height with wrapping
	var label_height = device_label.get_theme_font("font").get_multiline_string_size(
		device_label.text, 
		HORIZONTAL_ALIGNMENT_LEFT, 
		device_label.size.x, 
		device_label.get_theme_font_size("font_size")
	).y
	
	# Add padding (top and bottom margins)
	var total_height = label_height + 32  # 16px padding on each side
	
	# Ensure minimum height
	total_height = max(total_height, 60)
	
	# Update panel's minimum size
	custom_minimum_size.y = total_height