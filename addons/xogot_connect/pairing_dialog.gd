@tool
class_name PairingDialog
extends ConfirmationDialog

## PairingDialog provides a UI for entering a 4-digit pairing code
##
## This dialog is shown when the user attempts to connect to an unpaired device.
## It prompts the user to enter the pairing code displayed on the remote device.

signal code_entered(code: String)
signal cancelled()

var device_name: String = "":
	set(value):
		device_name = value
		if is_inside_tree():
			_update_dialog_text()

@onready var code_input: LineEdit = $VBoxContainer/CodeInput

func _ready():
	title = "Pair with Device"
	_update_dialog_text()

	# Configure dialog buttons
	get_ok_button().text = "Pair"
	get_ok_button().disabled = true

	# Setup code input
	if code_input:
		code_input.placeholder_text = "1234"
		code_input.max_length = 4
		code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER

		# Only allow numbers
		code_input.text_changed.connect(_on_code_input_text_changed)

		# Enable OK button when 4 digits entered, and auto-submit
		code_input.text_changed.connect(func(text):
			get_ok_button().disabled = text.length() != 4
			# Auto-submit when 4 digits are entered
			if text.length() == 4:
				_submit_code.call_deferred()
		)

		# Allow Enter key to submit
		code_input.text_submitted.connect(func(_text):
			if code_input.text.length() == 4:
				_submit_code()
		)

		# Auto-focus input
		code_input.call_deferred("grab_focus")

	# Connect signals
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)

func _update_dialog_text():
	if device_name != "":
		dialog_text = "Enter the 4-digit pairing code displayed on:\n%s" % device_name
	else:
		dialog_text = "Enter the 4-digit pairing code displayed on the device"

func _submit_code() -> void:
	if code_input and code_input.text.length() == 4:
		emit_signal("code_entered", code_input.text)
		hide()

func _on_code_input_text_changed(text: String) -> void:
	# Filter to only allow numeric input
	var filtered = ""
	for c in text:
		if c.is_valid_int():
			filtered += c
	if filtered != text:
		code_input.text = filtered
		code_input.caret_column = filtered.length()

func _on_confirmed() -> void:
	if code_input and code_input.text.length() == 4:
		emit_signal("code_entered", code_input.text)

func _on_canceled() -> void:
	emit_signal("cancelled")
