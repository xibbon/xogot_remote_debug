class_name PairingManager
extends RefCounted

## PairingManager handles device pairing logic and persistence
##
## This class manages the pairing system for remote debugging, allowing iOS/macOS
## devices to connect without requiring user authentication. It handles:
## - Persistent storage of paired devices
## - Pairing status validation
## - Device pairing and unpairing operations

const XogotDebug = preload("res://addons/xogot_connect/xogot_debug.gd")
const PAIRED_DEVICES_KEY = "xogot.paired_devices"

## Dictionary of paired devices: device_id -> PairedDevice
var paired_devices: Dictionary = {}

## PairedDevice represents a device that has been paired with this Godot Editor
class PairedDevice:
	var device_id: String       ## Unique device identifier
	var device_name: String     ## Human-readable name
	var paired_at: int          ## Unix timestamp when paired

	func to_dict() -> Dictionary:
		return {
			"device_id": device_id,
			"device_name": device_name,
			"paired_at": paired_at
		}

	func from_dict(data: Dictionary) -> void:
		device_id = data.get("device_id", "")
		device_name = data.get("device_name", "")
		paired_at = data.get("paired_at", 0)

func _init():
	load_paired_devices()

func debug_print(message: String) -> void:
	if XogotDebug.ENABLED:
		print(message)

## Load paired devices from persistent storage
func load_paired_devices() -> void:
	var config = ConfigFile.new()
	var err = config.load("user://paired_devices.cfg")
	if err == OK:
		paired_devices.clear()
		for device_id in config.get_sections():
			var device = PairedDevice.new()
			device.device_id = device_id
			device.device_name = config.get_value(device_id, "device_name", "")
			device.paired_at = config.get_value(device_id, "paired_at", 0)
			paired_devices[device_id] = device
		debug_print("[PairingManager] Loaded %d paired devices" % paired_devices.size())
	else:
		debug_print("[PairingManager] No paired devices found")

## Save paired devices to persistent storage
func save_paired_devices() -> void:
	var config = ConfigFile.new()
	for device_id in paired_devices.keys():
		var device = paired_devices[device_id]
		config.set_value(device_id, "device_name", device.device_name)
		config.set_value(device_id, "paired_at", device.paired_at)
	config.save("user://paired_devices.cfg")
	debug_print("[PairingManager] Saved %d paired devices" % paired_devices.size())

## Check if a device is already paired
func is_paired(device_id: String) -> bool:
	return paired_devices.has(device_id)

## Add a device as paired
func add_paired_device(device_id: String, device_name: String) -> void:
	var device = PairedDevice.new()
	device.device_id = device_id
	device.device_name = device_name
	device.paired_at = Time.get_unix_time_from_system()
	paired_devices[device_id] = device
	save_paired_devices()
	debug_print("[PairingManager] Added paired device: %s (%s)" % [device_name, device_id])

## Remove a paired device
func unpair_device(device_id: String) -> void:
	if paired_devices.erase(device_id):
		save_paired_devices()
		debug_print("[PairingManager] Unpaired device: %s" % device_id)

## Get all paired devices
func get_paired_devices() -> Array:
	return paired_devices.values()
