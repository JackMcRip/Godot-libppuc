# =====================================================================
# PPUC WRAPPER FOR GODOT
# =====================================================================
# This script provides a convenient wrapper around the libppuc native 
# extension for communicating with PPUC (Pinball Power-Up Controller) 
# hardware via RS485 serial interface. It offers simplified access to 
# all native functions while adding enhanced debugging, state tracking,
# and signal-based notification of state changes.
#
# Author: Claude AI
# Version: 1.0
# =====================================================================

extends Node

# =====================================================================
# EVENT CONSTANTS
# =====================================================================
# These constants define the event types used in PPUC communication

const EVENT_NULL = 0         # Null event (no operation)
const EVENT_PING = 1         # Ping request to check board presence
const EVENT_PONG = 2         # Pong response from a board
const EVENT_RESET = 3        # Reset all boards
const EVENT_POLL_EVENTS = 4  # Request events from a board
const EVENT_RUN = 5          # Start/stop updates on boards
const EVENT_READ_SWITCHES = 8 # Read initial switch states

# Component type constants
const EVENT_SOURCE_SWITCH = 7   # Switch event source
const EVENT_SOURCE_SOLENOID = 6 # Solenoid event source
const EVENT_SOURCE_LIGHT = 5    # Light event source
const EVENT_SOURCE_GI = 4       # General Illumination event source

# PWM Type constants (for coils)
const PWM_TYPE_SOLENOID = 0  # Solenoid type PWM output
const PWM_TYPE_FLASHER = 1   # Flasher type PWM output
const PWM_TYPE_LAMP = 2      # Lamp type PWM output
const PWM_TYPE_MOTOR = 3     # Motor type PWM output

# LED Type constants
const LED_TYPE_LAMP = 0      # Lamp type LED
const LED_TYPE_FLASHER = 1   # Flasher type LED
const LED_TYPE_GI = 2        # General Illumination type LED

# =====================================================================
# MEMBER VARIABLES
# =====================================================================

# Core variables
var ppuc = null                  # Reference to PPUCGD native instance
var debug_enabled = false        # Flag to enable/disable debug output
var debug_output = null          # RichTextLabel for debug output
var polling_enabled = false      # Flag to enable/disable continuous polling
var polling_timer = null         # Timer for polling hardware
var configpath = null            # Path to the YAML configuration file
var comport = null               # Serial port for RS485 communication

# State tracking dictionaries
var switch_states = {}           # Current switch states {number: state}
var lamp_states = {}             # Current lamp states {number: state}
var coil_states = {}             # Current coil states {number: state}

# =====================================================================
# SIGNALS
# =====================================================================
# Signals for state changes and connection events

# Emitted when a switch changes state
signal switch_changed(number, state)

# Emitted when a lamp changes state
signal lamp_changed(number, state)

# Emitted when a coil changes state
signal coil_changed(number, state)

# Emitted on successful connection
signal connected

# Emitted on disconnect
signal disconnected

# Emitted when connection fails
signal connection_failed

# Emitted with dictionary of changed switches and their states
signal switches_changed(changed_switches)

# =====================================================================
# INITIALIZATION FUNCTIONS
# =====================================================================

# Sets up debug output capabilities
# Parameters:
#   rich_text_label: The RichTextLabel node to use for debug output
#   enabled: Whether debug output is enabled (default: true)
#   auto_scroll: Whether to automatically scroll to the bottom (default: true)
func setup_debug(rich_text_label, enabled = true, auto_scroll = true):
	debug_output = rich_text_label
	debug_enabled = enabled
	
	# Configure auto-scrolling
	if debug_output != null and auto_scroll:
		debug_output.scroll_following = true
		
	debug_log("Debug output configured and " + ("enabled" if enabled else "disabled"), "green")

# Logs a debug message with optional color
# Parameters:
#   message: The message to log
#   color: The color of the message (default: white)
func debug_log(message, color = "white"):
	if debug_enabled and debug_output != null:
		var timestamp = Time.get_datetime_string_from_system()
		debug_output.append_text("[color=%s][%s] %s[/color]\n" % [color, timestamp, message])
		#print("[PPUC] ", message)  # Also print to console for convenience

# Logs a debug message with color and waits for specified seconds
# Parameters:
#   message: The message to log
#   wait_time: Time to wait in seconds after logging
#   color: The color of the message (default: white)
# Note: This is a coroutine and must be called with await
func debug_log_wait(message, wait_time = 1.0, color = "white"):
	debug_log(message, color)
	await get_tree().create_timer(wait_time).timeout

# Manually scrolls debug output to the bottom
# Useful if automatic scrolling is disabled or not working properly
func scroll_debug_to_bottom():
	if debug_output != null:
		# Get the total number of lines
		var line_count = debug_output.get_line_count()
		# Scroll to the last line
		if line_count > 0:
			debug_output.scroll_to_line(line_count - 1)

# Enables or disables debug mode for both the wrapper and native extension
# Parameters:
#   enabled: True to enable debug mode, false to disable
func set_debug(enabled):
	debug_enabled = enabled
	if ppuc != null:
		ppuc.set_debug(enabled)
	
	debug_log("Debug mode set: " + str(enabled), "white")

# Clears all text from the debug output RichTextLabel
func clear_debug_output():
	if debug_output != null:
		debug_output.clear()
		debug_log("Debug output cleared", "green")

# Initializes the PPUC instance. Must be called before any other functions.
# Returns:
#   bool: True if setup was successful, false otherwise
func setup_ppuc():
	debug_log("Setting up PPUC library wrapper...", "yellow")
	
	# Create PPUC instance if not already created
	if ppuc == null:
		ppuc = PPUCGD.new()
		add_child(ppuc)
		
		# Create polling timer with a slower interval to prevent overloading
		polling_timer = Timer.new()
		polling_timer.wait_time = 0.05  # 50ms interval (20Hz) - slower but still responsive
		polling_timer.one_shot = false
		polling_timer.autostart = false
		polling_timer.timeout.connect(_on_polling_timer_timeout)
		add_child(polling_timer)
		
		debug_log("PPUC setup complete", "green")
		return true
	else:
		debug_log("PPUC already set up", "yellow")
		return false

# =====================================================================
# CONNECTION MANAGEMENT
# =====================================================================

# Loads PPUC configuration from a YAML file
# Parameters:
#   config_file: Path to the YAML configuration file
# Returns:
#   bool: True if configuration loaded successfully
func load_configuration(config_file):
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return false
	
	# Ensure path is global
	var global_path = config_file
	global_path = ProjectSettings.globalize_path(config_file)
	
	debug_log("Loading configuration from: " + global_path, "yellow")
	# Load configuration
	ppuc.load_configuration(global_path)
	debug_log("Configuration loaded successfully", "green")
	return true

# Connects to PPUC hardware via RS485
# Parameters:
#   com_port: The serial port to use (e.g., "COM3")
#   config_file: Path to the YAML configuration file
# Returns:
#   bool: True if connection was successful, false otherwise
func connect_to_hardware(com_port, config_file):
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return false
	
	# Set debug mode
	ppuc.set_debug(debug_enabled)
	debug_log("Debug mode set: " + str(debug_enabled), "white")
	
	# Set serial port
	ppuc.set_serial(com_port)
	debug_log("Serial port set: " + com_port, "white")
	
	# Load configuration
	if not load_configuration(config_file):
		debug_log("Failed to load configuration", "red")
		emit_signal("connection_failed")
		return false
	
	debug_log("Trying to connect to hardware", "yellow")
	# Connect to hardware
	if ppuc.connect_to_hardware():
		debug_log("Connected to hardware successfully", "green")
		
		# Always enable polling when connected
		polling_enabled = true
		start_polling()
		
		# Start updates
		ppuc.start_updates()
		debug_log("Updates started", "green")
		
		emit_signal("connected")
		return true
	else:
		debug_log("Failed to connect to hardware", "red")
		emit_signal("connection_failed")
		return false

# Disconnects from PPUC hardware
func disconnect_from_hardware():
	if ppuc == null:
		debug_log("PPUC not initialized", "yellow")
		return
	
	debug_log("Disconnecting from hardware...", "yellow")
	
	# Stop polling
	stop_polling()
	
	# Stop updates
	ppuc.stop_updates()
	
	# Disconnect
	ppuc.disconnect()
	
	debug_log("Disconnected from hardware", "green")
	emit_signal("disconnected")

# =====================================================================
# POLLING CONTROL
# =====================================================================

# Starts polling for switch, lamp, and coil state changes
func start_polling():
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return
	
	debug_log("Start monitoring for switch changes", "green")
	
	# Initialize empty switch states dictionary
	switch_states.clear()
	
	polling_enabled = true
	if polling_timer != null:
		polling_timer.start()
		debug_log("Polling started", "green")

# Stops polling for switch, lamp, and coil state changes
func stop_polling():
	polling_enabled = false
	if polling_timer != null:
		polling_timer.stop()
		debug_log("Polling stopped", "yellow")

# Called when the polling timer times out
# Checks for changes in switch states using an efficient polling approach
func _on_polling_timer_timeout():
	if ppuc == null or not polling_enabled:
		return
	
	# Get next switch state
	var switch_state = ppuc.get_next_switch_state()
	
	# Debug output for monitoring
	if debug_enabled:
		if switch_state != { }:
			debug_log("NextSwitchState: " + str(switch_state), "white")
	
	# If no switch state is available, just return
	if switch_state == null:
		return
	
	# Extract number and state from the switch data
	var switch_number = -1
	var switch_value = -1
	var success = false
	
	# Try different ways to extract the switch data (exactly like RS485-Test.gd)
	if typeof(switch_state) == TYPE_DICTIONARY:
		if switch_state.has("number") and switch_state.has("state"):
			switch_number = int(switch_state.get("number"))
			switch_value = int(switch_state.get("state"))
			success = true
	elif typeof(switch_state) == TYPE_OBJECT:
		# Try different methods to get the data
		if "number" in switch_state and "state" in switch_state:
			switch_number = int(switch_state.number)
			switch_value = int(switch_state.state)
			success = true
		elif switch_state.has_method("get_number") and switch_state.has_method("get_state"):
			switch_number = int(switch_state.get_number())
			switch_value = int(switch_state.get_state())
			success = true
	
	# If we successfully extracted the data
	if success and switch_number >= 0:
		# Check if there's a change
		if not switch_states.has(switch_number) or switch_states[switch_number] != switch_value:
			var change_type = "New Switch" if not switch_states.has(switch_number) else "Change"
			var state_text = "ON" if switch_value == 1 else "OFF"
			
			if debug_enabled:
				debug_log("Switch #%d: %s -> %s" % [switch_number, change_type, state_text], "aqua")
			
			# Save the new state
			switch_states[switch_number] = switch_value
			
			# Emit signal for state change
			emit_signal("switch_changed", switch_number, switch_value)
	else:
		# If we still have issues with extraction, add debugging
		if not has_meta("extraction_error_logged"):
			set_meta("extraction_error_logged", true)
			debug_log("Debug: Switch-State Type = " + str(typeof(switch_state)), "yellow")
			debug_log("Debug: Switch-State = " + str(switch_state), "yellow")
			
			if typeof(switch_state) == TYPE_OBJECT:
				var properties = []
				for prop in switch_state.get_property_list():
					properties.append(prop.name)
				debug_log("Debug: Available Properties = " + str(properties), "yellow")

# =====================================================================
# HARDWARE CONTROL
# =====================================================================

# Sets the state of a solenoid (coil)
# Parameters:
#   number: The solenoid number
#   state: 1 to activate, 0 to deactivate
func set_solenoid_state(number, state):
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return
	
	ppuc.set_solenoid_state(number, state)
	
	# Update state
	coil_states[number] = state
	
	# Debug log
	var state_text = "ON" if state == 1 else "OFF"
	debug_log("Coil #%d: %s" % [number, state_text], "yellow")
	
	# Emit signal
	emit_signal("coil_changed", number, state)

# Sets the state of a lamp
# Parameters:
#   number: The lamp number
#   state: 1 to turn on, 0 to turn off
func set_lamp_state(number, state):
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return
	
	ppuc.set_lamp_state(number, state)
	
	# Update state
	lamp_states[number] = state
	
	# Debug log
	var state_text = "ON" if state == 1 else "OFF"
	debug_log("Lamp #%d: %s" % [number, str(state_text)], "green")
	
	# Emit signal
	emit_signal("lamp_changed", number, state)

# Starts sending updates to hardware
func start_updates():
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return
	
	ppuc.start_updates()

# Stops sending updates to hardware
func stop_updates():
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return
	
	ppuc.stop_updates()

# =====================================================================
# CONFIGURATION FUNCTIONS
# =====================================================================

# Sets the ROM name/identifier
# Parameters:
#   rom_name: The ROM name/identifier
func set_rom(rom_name):
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return
	
	ppuc.set_rom(rom_name)
	debug_log("ROM name set: " + rom_name, "white")

# Gets the current ROM name/identifier
# Returns:
#   String: The ROM name
func get_rom():
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return ""
	
	return ppuc.get_rom()

# Gets the switch number for the coin door closed switch
# Returns:
#   int: The switch number
func get_coin_door_closed_switch():
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return -1
	
	return ppuc.get_coin_door_closed_switch()

# Gets the solenoid number for the game on solenoid
# Returns:
#   int: The solenoid number
func get_game_on_solenoid():
	if ppuc == null:
		pass
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return -1
	
	return ppuc.get_game_on_solenoid()

# =====================================================================
# DATA RETRIEVAL FUNCTIONS
# =====================================================================

# Checks for switch state changes and emits signals for any changes
# Similar to implementation in RS485-Test.gd but with signal emission
# Returns:
#   Dictionary: Dictionary of changed switches and their states
func check_switch_events():
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return {}
	
	var changed_switches = {}
	
	# Get next switch state
	var switch_state = ppuc.get_next_switch_state()
	
	# Debug output if enabled
	if debug_enabled:
		pass
		#debug_log("Check switch events: " + str(switch_state), "white")
	
	# If no switch state is available, return empty dictionary
	if switch_state == null:
		return {}
	
	# Extract number and state, if possible
	var switch_number = -1
	var switch_value = -1
	var success = false
	
	# Try different ways to extract the switch data (from RS485-Test.gd)
	if typeof(switch_state) == TYPE_DICTIONARY:
		if switch_state.has("number") and switch_state.has("state"):
			switch_number = int(switch_state.get("number"))
			switch_value = int(switch_state.get("state"))
			success = true
	elif typeof(switch_state) == TYPE_OBJECT:
		# Try different methods to get the data
		if "number" in switch_state and "state" in switch_state:
			switch_number = int(switch_state.number)
			switch_value = int(switch_state.state)
			success = true
		elif switch_state.has_method("get_number") and switch_state.has_method("get_state"):
			switch_number = int(switch_state.get_number())
			switch_value = int(switch_state.get_state())
			success = true
	
	# If we successfully extracted the data
	if success and switch_number >= 0:
		# Check if there's a change
		if not switch_states.has(switch_number) or switch_states[switch_number] != switch_value:
			var change_type = "New Switch" if not switch_states.has(switch_number) else "Change"
			var state_text = "ON" if switch_value == 1 else "OFF"
			
			if debug_enabled:
				debug_log("Switch #%d: %s -> %s" % [switch_number, change_type, state_text], "aqua")
			
			# Save the new state
			switch_states[switch_number] = switch_value
			
			# Add to changed switches dictionary
			changed_switches[switch_number] = switch_value
			
			# Emit signal for individual switch change
			emit_signal("switch_changed", switch_number, switch_value)
	else:
		# If we still have issues with extraction, add debugging
		if not has_meta("extraction_error_logged"):
			set_meta("extraction_error_logged", true)
			debug_log("Debug: Switch-State Type = " + str(typeof(switch_state)), "yellow")
			debug_log("Debug: Switch-State = " + str(switch_state), "yellow")
			
			if typeof(switch_state) == TYPE_OBJECT:
				var properties = []
				for prop in switch_state.get_property_list():
					properties.append(prop.name)
				debug_log("Debug: Available Properties = " + str(properties), "yellow")
	
	# If any switches changed, emit the collective signal
	if changed_switches.size() > 0:
		emit_signal("switches_changed", changed_switches)
	
	return changed_switches

# Gets all coils from the configuration
# Returns:
#   Array: Array of coil data objects
func get_coils():
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return []
	
	return ppuc.get_coils()

# Gets all lamps from the configuration
# Returns:
#   Array: Array of lamp data objects
func get_lamps():
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return []
	
	return ppuc.get_lamps()

# Gets all switches from the configuration
# Returns:
#   Array: Array of switch data objects
func get_switches():
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return []
	
	var switches = ppuc.get_switches()
	if debug_enabled:
		debug_log("Get switches from config: " + str(switches), "white")
	return switches

# Gets the current known switch states
# Returns:
#   Dictionary: Dictionary of switch states {number: state}
func get_switch_states():
	return switch_states.duplicate()

# =====================================================================
# TESTING FUNCTIONS
# =====================================================================

# Runs a test of all coils
func coil_test():
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return
	
	debug_log("Running coil test...", "yellow")
	ppuc.coil_test()
	debug_log("Coil test complete", "green")

# Runs a test of all lamps
func lamp_test():
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return
	
	debug_log("Running lamp test...", "yellow")
	ppuc.lamp_test()
	debug_log("Lamp test complete", "green")

# Runs a test monitoring switch activations
func switch_test():
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return
	
	debug_log("Running switch test...", "yellow")
	ppuc.switch_test()
	debug_log("Switch test complete", "green")

# =====================================================================
# ADVANCED FUNCTIONS
# =====================================================================

# Sends a custom event to the PPUC system
# Parameters:
#   source_id: Source ID of the event
#   event_id: Event ID
#   value: Event value
func send_event(source_id, event_id, value):
	if ppuc == null:
		#debug_log("PPUC not initialized. Call setup_ppuc() first.", "red")
		return
	
	# Create event object
	var event = PPUCEvent.new(source_id, event_id, value)
	
	# Send event
	ppuc.send_event(event)
	debug_log("Event sent: source=%d, event=%d, value=%d" % [source_id, event_id, value], "white")

# Process function called every frame
# Checks for switch events when connection is active
func _process(delta):
	if ppuc != null and polling_enabled:
		# Check for switch events (identical approach to RS485-Test.gd)
		check_switch_events()

# PPUCEvent class for creating events to be sent to the PPUC system
class PPUCEvent:
	# Event class for internal PPUC message passing
	var source_id = 0  # Source identifier
	var event_id = 0   # Event type identifier
	var value = 0      # Event value
	
	# Constructor for creating a new event
	func _init(p_source_id = 0, p_event_id = 0, p_value = 0):
		source_id = p_source_id
		event_id = p_event_id
		value = p_value
