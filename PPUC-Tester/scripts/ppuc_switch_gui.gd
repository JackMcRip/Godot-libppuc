# =====================================================================
# ppuc_switch_gui.gd - Switch GUI Controller for PPUC
# =====================================================================
# This script manages the graphical user interface for monitoring switches
# in the PPUC (Pinball Power-Up Controller) system. It creates a grid-based
# interface showing switches with color-coding based on their board
# association and activation state, and provides text-to-speech feedback.
# =====================================================================

extends Control

# =====================================================================
# MEMBER VARIABLES
# =====================================================================

# Grid and container references
var switch_grid_containers = []       # Array of containers for each switch in the grid
var switch_ids = []                   # Array of switch IDs in the grid
var switch_grid                       # Reference to the existing SwitchesGrid
var current_switch_info_label         # Reference to the info text display
var local_switches = {}               # Local copy of switches from the YAML configuration

# Timing and state tracking
var last_process_time = 0             # For rate limiting switch polling
var process_interval = 0.01           # Poll every 10ms (100 times per second) for faster updates
var current_hover_switch_id = -1      # Currently hovered switch ID
var connected = false                 # Connection status to PPUC hardware
var last_known_states = {}            # Stores last known states to detect changes

# Text-to-speech variables
var speech_text = ""                  # Text for speech output without formatting tags
var speech_loudness = 90              # Volume level for speech output (0-100)
var speech_exp = false                # Whether to include extended info in speech
var speech = true                     # Whether speech output is enabled

# Array of colors for visually distinguishing different boards (0-15)
@export var board_colors = [
	Color(1.0, 0.0, 0.0, 1.0),      # Red
	Color(0.0, 0.5, 1.0, 1.0),      # Blue
	Color(0.0, 0.8, 0.0, 1.0),      # Green
	Color(1.0, 0.5, 0.0, 1.0),      # Orange
	Color(0.8, 0.0, 0.8, 1.0),      # Purple
	Color(1.0, 1.0, 0.0, 1.0),      # Yellow
	Color(0.0, 0.8, 0.8, 1.0),      # Turquoise
	Color(0.5, 0.3, 0.0, 1.0),      # Brown
	Color(1.0, 0.0, 0.5, 1.0),      # Pink
	Color(0.5, 0.8, 0.0, 1.0),      # Light green
	Color(0.0, 0.3, 0.6, 1.0),      # Dark blue
	Color(0.8, 0.4, 0.6, 1.0),      # Rose
	Color(0.4, 0.2, 0.6, 1.0),      # Indigo
	Color(0.6, 0.6, 0.6, 1.0),      # Gray
	Color(1.0, 0.8, 0.6, 1.0),      # Peach
	Color(0.2, 0.4, 0.2, 1.0)       # Dark green
]

# Color modification factors
var c_saturation = 0.4  # Reduced color saturation for inactive switches
var c_brightness = 0.4  # Reduced brightness for inactive switches

# =====================================================================
# INITIALIZATION
# =====================================================================

# Called when the node enters the scene tree for the first time
func _ready():
	# Increase volume for all possible TTS factors
	# 1. Set TTS volume to maximum
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		# Choose the voice as before
		var voices = DisplayServer.tts_get_voices_for_language("en")
		var voice_id = voices[0]
	
	# TTS debugging - Adapted for your Godot version
	print("TTS Debug: Trying to find voices...")
	var voices = DisplayServer.tts_get_voices()
	print("TTS voices found: ", voices.size())
	if voices.size() > 0:
		print("First voice: ", voices[0])
	else:
		print("NO TTS voices found!")

	# Find existing nodes in the scene hierarchy
	find_nodes_in_scene()
	
	# Load switches from yamlparser if available
	if yamlparser != null and hasattr(yamlparser, "switches"):
		if typeof(yamlparser.switches) == TYPE_ARRAY:
			# Convert array to dictionary for faster access
			for switch_data in yamlparser.switches:
				if typeof(switch_data) == TYPE_DICTIONARY and switch_data.has("number"):
					var switch_id = switch_data.get("number")
					if not local_switches.has(switch_id):
						local_switches[switch_id] = []
					local_switches[switch_id].append(switch_data)
		elif typeof(yamlparser.switches) == TYPE_DICTIONARY:
			# Copy dictionary
			local_switches = yamlparser.switches.duplicate(true)
		print("Switches loaded from yamlparser")
	
	# Connect to PPUC and listen for switch events if available
	if libppuc != null:
		print("libppuc found, attempting signal connection...")
		connected = false
		if libppuc.has_method("connect_to_hardware"):
			connected = true
		
		# Try to connect to the signal
		if libppuc.has_signal("switch_changed"):
			print("Signal 'switch_changed' exists")
			var already_connected = false
			if libppuc.is_connected("switch_changed", Callable(self, "_on_switch_changed")):
				already_connected = true
				print("Signal already connected")
			
			if not already_connected:
				libppuc.connect("switch_changed", Callable(self, "_on_switch_changed"))
				print("Signal 'switch_changed' connected")
				
		else:
			push_warning("Signal 'switch_changed' does not exist in libppuc!")
	
	# Wait for all nodes to be initialized
	call_deferred("create_switch_grid")

	print("#################")
	print("PPUC-Switch-GUI initialized and using existing SwitchesGrid container")

# =====================================================================
# PROCESSING
# =====================================================================

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	# Rate limiting for switch polling
	last_process_time += delta
	if last_process_time >= process_interval:
		last_process_time = 0  # Reset timer
		
		if libppuc != null:
			# Always check status
			check_switch_events()
			
			# Check if the signal is connected
			if libppuc.has_signal("switch_changed") and not libppuc.is_connected("switch_changed", Callable(self, "_on_switch_changed")):
				print("Signal 'switch_changed' was disconnected, reconnecting...")
				libppuc.connect("switch_changed", Callable(self, "_on_switch_changed"))

# =====================================================================
# NODE FINDING AND SCENE SETUP
# =====================================================================

# Finds and stores references to important nodes in the scene graph
func find_nodes_in_scene():
	# Find the SwitchesGrid node (container for switch elements)
	var switches_grid_container = find_node_by_name_recursive(get_tree().root, "SwitchesGrid")
	if not switches_grid_container:
		push_error("SwitchesGrid node not found!")
		return
	
	# Check if a GridContainer already exists in SwitchesGrid
	switch_grid = null
	for child in switches_grid_container.get_children():
		if child is GridContainer:
			switch_grid = child
			break
	
	# If no GridContainer was found, create a new one
	if not switch_grid:
		switch_grid = GridContainer.new()
		switch_grid.name = "SwitchGrid"
		switch_grid.columns = 10  # Always 10 columns
		switches_grid_container.add_child(switch_grid)
	else:
		# If one exists, ensure it has 10 columns
		switch_grid.columns = 10
	
	# Find the Switches node
	var switches_node = find_node_by_name_recursive(get_tree().root, "Swicthes")  # Note spelling in hierarchy
	if not switches_node:
		# Try alternative spelling
		switches_node = find_node_by_name_recursive(get_tree().root, "Switches")
	
	# If Switches node was found, look for its Info child
	if switches_node:
		var info_node = null
		for child in switches_node.get_children():
			if child.name == "Info":
				info_node = child
				break
				
		# If Info node was found, look for its RichTextLabel
		if info_node:
			for child in info_node.get_children():
				if child is RichTextLabel:
					current_switch_info_label = child
					print("RichTextLabel for switch info found!")
					break
	
	# If no RichTextLabel was found, try to find the Info node directly
	if not current_switch_info_label:
		var info_node = find_node_by_name_recursive(get_tree().root, "Info")
		if info_node:
			for child in info_node.get_children():
				if child is RichTextLabel:
					current_switch_info_label = child
					print("RichTextLabel for switch info found in Info node!")
					break
	
	# If still no label was found, create a new one
	if not current_switch_info_label:
		push_warning("Info RichTextLabel not found, creating a new one")
		current_switch_info_label = RichTextLabel.new()
		current_switch_info_label.bbcode_enabled = true
		current_switch_info_label.fit_content = true
		current_switch_info_label.text = "No switch selected"
		
		# Try to place it in the Info node, if available
		var info_node = find_node_by_name_recursive(get_tree().root, "Info")
		if info_node:
			info_node.add_child(current_switch_info_label)
		else:
			add_child(current_switch_info_label)

# Recursive function to find a node by name
# Parameters:
#   node: The node to start searching from
#   name: The name of the node to find
# Returns:
#   The found node, or null if not found
func find_node_by_name_recursive(node, name):
	if node.name == name:
		return node
	
	for child in node.get_children():
		var result = find_node_by_name_recursive(child, name)
		if result:
			return result
	
	return null

# =====================================================================
# SWITCH EVENT HANDLING
# =====================================================================

# Checks for switch state changes
func check_switch_events():
	# Check if libppuc is available
	if libppuc == null:
		push_error("libppuc is not available")
		return
		
	# Ensure that switch_states in libppuc is available
	if not hasattr(libppuc, "switch_states"):
		push_warning("libppuc.switch_states is not available")
		return
	
	# Start updates (if needed)
	if libppuc.has_method("start_updates"):
		libppuc.start_updates()
	
	# Check all switch states in libppuc.switch_states dictionary
	if hasattr(libppuc, "switch_states") and typeof(libppuc.switch_states) == TYPE_DICTIONARY:
		# For each switch in switch_ids
		for switch_id in switch_ids:
			var current_state = get_switch_state(switch_id)
			
			# If the state has changed or we're seeing it for the first time
			if not last_known_states.has(switch_id) or last_known_states[switch_id] != current_state:
				# Save the new state
				last_known_states[switch_id] = current_state
				
				# Update the visual representation
				update_switch_visual(switch_id, current_state)
				
				# Always show switch info, regardless of state
				update_switch_info(switch_id)
				
				# Log the state change
				var state_text = "ON" if current_state == 1 else "OFF"
				print("Switch #" + str(switch_id) + " state changed to: " + state_text)
	
	# Use get_next_switch_state from libppuc for the latest changes (if available)
	if libppuc.has_method("get_next_switch_state"):
		var switch_state = libppuc.get_next_switch_state()
		while switch_state != null:
			var switch_number = -1
			var switch_value = -1
			var success = false
			
			# Try different ways to extract switch data
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
			
			if success and switch_number >= 0:
				# Update the display for this switch
				update_switch_visual(switch_number, switch_value)
				
				# Save the new state
				last_known_states[switch_number] = switch_value
				
				# Always show switch info, regardless of state
				update_switch_info(switch_number)
				
				print("Switch #" + str(switch_number) + " state changed via get_next_switch_state!")
			
			# Get the next switch state
			switch_state = libppuc.get_next_switch_state()
	
	if libppuc.has_method("stop_updates"):
		libppuc.stop_updates()

# Updates the visual representation of a specific switch
# Parameters:
#   switch_id: ID of the switch to update
#   state: New state of the switch (0 or 1)
func update_switch_visual(switch_id, state):
	# Look for the switch in the grid
	var container_found = false
	
	for i in range(switch_ids.size()):
		if switch_ids[i] == switch_id and i < switch_grid_containers.size():
			var container = switch_grid_containers[i]
			if is_instance_valid(container):
				var style_box = container.get_theme_stylebox("panel")
				if style_box != null:
					container_found = true
					
					if state == 1:
						# Use full color for active state
						style_box.bg_color = board_colors[yamlparser.switches[switch_id]["board"]]
					else:
						# Use desaturated color for inactive state
						style_box.bg_color = reduce_saturation(board_colors[yamlparser.switches[switch_id]["board"]], c_saturation, c_brightness)
					
					# Maintain hover border if present
					if current_hover_switch_id == switch_id:
						style_box.border_width_bottom = 2
						style_box.border_width_top = 2
						style_box.border_width_left = 2
						style_box.border_width_right = 2
						style_box.border_color = Color(1, 1, 1)  # White border
					break
	
	if not container_found and switch_id in switch_ids:
		print("WARNING: Container for Switch #" + str(switch_id) + " not found!")

# Gets the state of a switch
# Parameters:
#   switch_id: ID of the switch
# Returns:
#   int: State of the switch (0 or 1)
func get_switch_state(switch_id):
	# If switch_id is an array index, convert it to the actual switch number
	var actual_switch_number = switch_id
	if switch_id < yamlparser.switches.size():
		if typeof(yamlparser.switches[switch_id]) == TYPE_DICTIONARY:
			actual_switch_number = yamlparser.switches[switch_id].get("number")
	
	# Rest of the function remains the same, but searches for actual_switch_number
	if libppuc == null or not hasattr(libppuc, "switch_states"):
		return 0
		
	if typeof(libppuc.switch_states) != TYPE_DICTIONARY:
		return 0
		
	if libppuc.switch_states.has(actual_switch_number):
		return libppuc.switch_states[actual_switch_number]
	elif libppuc.switch_states.has(str(actual_switch_number)):
		return libppuc.switch_states[str(actual_switch_number)]
	
	return 0

# =====================================================================
# SWITCH GRID CREATION
# =====================================================================

# Creates the grid for switches
func create_switch_grid():
	# Ensure switch_grid exists
	if not is_instance_valid(switch_grid):
		push_error("Switch grid not initialized")
		return
	
	var gridcontainer_parent = switch_grid.get_parent()
	
	# Remove old elements
	for child in switch_grid.get_children():
		switch_grid.remove_child(child)
		child.queue_free()
	
	switch_grid_containers.clear()
	switch_ids.clear()
	
	# Extract switch IDs directly from yamlparser.switches
	if yamlparser != null and hasattr(yamlparser, "switches"):
		if typeof(yamlparser.switches) == TYPE_ARRAY:
			# Use array position as ID instead of collecting unique IDs
			print(str(yamlparser.switches.size()) + " Switches to read:")
			for i in range(yamlparser.switches.size()):
				switch_ids.append(i)  # Use array index as ID
		
		elif typeof(yamlparser.switches) == TYPE_DICTIONARY:
			# Extract switch IDs from the dictionary
			for switch_id_str in yamlparser.switches.keys():
				var switch_data = yamlparser.switches[switch_id_str]
				if typeof(switch_data) == TYPE_DICTIONARY and switch_data.has("number"):
					var switch_id = switch_data.get("number")
					if not switch_id in switch_ids:
						switch_ids.append(switch_id)
	
	# Sort the IDs numerically
	switch_ids.sort()

	# Create grid elements
	for switch_id in switch_ids:
		# Check if the switch is already active
		var initial_color = board_colors[yamlparser.switches[switch_id]["board"]]
		if get_switch_state(switch_id) == 1:
			initial_color = board_colors[yamlparser.switches[switch_id]["board"]]
			# Save the initial state
			last_known_states[switch_id] = 1
		else:
			# Use desaturated color for inactive state
			initial_color = reduce_saturation(initial_color, c_saturation, c_brightness)
			last_known_states[switch_id] = 0
			
		var container = create_grid_item(switch_id, initial_color)
		switch_grid.add_child(container)
		switch_grid_containers.append(container)
		
		# Set up mouse events for the switch
		container.mouse_entered.connect(_on_switch_grid_item_mouse_entered.bind(switch_id, container))
		container.mouse_exited.connect(_on_switch_grid_item_mouse_exited.bind(switch_id, container))
		container.gui_input.connect(_on_switch_grid_item_clicked.bind(switch_id, container))
	
	print("Switch grid created with " + str(switch_grid_containers.size()) + " elements")
	print("#################")
	
	# Create board color legend
	gridcontainer_parent.add_child(create_board_legend())

# Helper function to create a grid item
# Parameters:
#   id: ID of the switch
#   base_color: Base color for the switch
# Returns:
#   PanelContainer: Created grid item container
func create_grid_item(id: int, base_color: Color) -> PanelContainer:
	var container = PanelContainer.new()
	container.custom_minimum_size = Vector2(35, 35)  # Good size for clickability
	
	# IMPORTANT: Set mouse_filter value to detect mouse events
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Set default values
	var switch_number = id  # Fallback: Use the provided ID
	var board_number = 0    # Default board number
	
	# Get data from the YAML parser if available
	if yamlparser != null and hasattr(yamlparser, "switches"):
		if typeof(yamlparser.switches) == TYPE_ARRAY and id < yamlparser.switches.size():
			var switch_data = yamlparser.switches[id]
			if typeof(switch_data) == TYPE_DICTIONARY:
				# Get switch number from the data
				if switch_data.has("number"):
					switch_number = switch_data.get("number")
				
				# Get board number from the data
				if switch_data.has("board"):
					board_number = switch_data.get("board")
	
	# Restrict board number to valid range (0-15)
	board_number = clamp(board_number, 0, 15)
	
	# Display the switch number
	var label = Label.new()
	label.text = str(switch_number)
	
	# Set proper horizontal and vertical alignment
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Ensure the label uses the available space
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.size_flags_vertical = SIZE_EXPAND_FILL
	
	# Set mouse filter for the label so clicks pass through to the container
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	container.add_child(label)
	
	# Set background style with the color corresponding to the board
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = base_color
	style_box.corner_radius_top_left = 3
	style_box.corner_radius_top_right = 3
	style_box.corner_radius_bottom_left = 3
	style_box.corner_radius_bottom_right = 3
	container.add_theme_stylebox_override("panel", style_box)
	
	return container

# Helper function to adjust saturation and brightness of a color
# Parameters:
#   color: Original color
#   saturation_factor: Factor to adjust saturation (0-1)
#   brightness_factor: Factor to adjust brightness (0-1)
# Returns:
#   Color: Adjusted color
func reduce_saturation(color: Color, saturation_factor: float = 0.5, brightness_factor: float = 0.5) -> Color:
	# Create a gray with the same brightness as the original color for saturation adjustment
	var gray_value = (color.r + color.g + color.b) / 3.0
	var gray = Color(gray_value, gray_value, gray_value, color.a)
	
	# Interpolate between original and gray based on saturation factor
	var desaturated = color.lerp(gray, 1.0 - saturation_factor)
	
	# Adjust brightness by multiplying each RGB component
	var result = Color(
		desaturated.r * brightness_factor,
		desaturated.g * brightness_factor,
		desaturated.b * brightness_factor,
		desaturated.a
	)
	
	return result

# Creates the board color legend
# Returns:
#   HBoxContainer: Created legend container
func create_board_legend() -> HBoxContainer:
	var outer_container = HBoxContainer.new()
	
	# Create container for vertical arrangement
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	outer_container.add_child(vbox)
	
	# Add top spacer - before the board labels
	var top_spacer_label = Label.new()
	top_spacer_label.text = " "  # A space
	top_spacer_label.custom_minimum_size = Vector2(0, 20)  # 20 pixels height
	vbox.add_child(top_spacer_label)
	
	# Create original legend
	var legend_container = HBoxContainer.new()
	legend_container.add_theme_constant_override("separation", 2)  # Space between labels
	vbox.add_child(legend_container)
	
	# Create legend entries for the boards
	for i in range(4):
		var board_number = i
		
		# PanelContainer for each board label
		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(100, 30)  # Size for the label
		
		# Create label with board text
		var label = Label.new()
		label.text = "Board: " + str(board_number)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		label.size_flags_vertical = SIZE_EXPAND_FILL
		
		# Use the color for this board
		var style_box = StyleBoxFlat.new()
		style_box.bg_color = reduce_saturation(board_colors[board_number], c_saturation, c_brightness)
		panel.add_theme_stylebox_override("panel", style_box)
		
		# Add label to panel
		panel.add_child(label)
		
		# Add panel to container
		legend_container.add_child(panel)
	
	return outer_container

# =====================================================================
# SWITCH INFO DISPLAY
# =====================================================================

# Updates the switch info display
# Parameters:
#   switch_id: ID of the switch to display info for
func update_switch_info(switch_id: int):
	if not is_instance_valid(current_switch_info_label):
		push_error("current_switch_info_label not valid")
		return
		
	# Safety check for libppuc and yamlparser
	if libppuc == null:
		push_error("libppuc is not available")
		return
		
	var switch_info = ""
	speech_text = ""  # Reset text for speech output without formatting tags
	
	# Use the array index to get the actual switch
	var actual_switch_data = null
	var actual_switch_number = switch_id
	
	if yamlparser != null and hasattr(yamlparser, "switches"):
		if typeof(yamlparser.switches) == TYPE_ARRAY and switch_id < yamlparser.switches.size():
			actual_switch_data = yamlparser.switches[switch_id]
			if typeof(actual_switch_data) == TYPE_DICTIONARY and actual_switch_data.has("number"):
				actual_switch_number = actual_switch_data.get("number")
	
	# Display switch information
	if actual_switch_data != null:
		switch_info += "[b]Switch #%d (ID: %d)[/b]\n" % [actual_switch_number, switch_id]
		speech_text += "Number %d. " % actual_switch_number
		
		# Show details of the switch
		switch_info += "Description: %s\n" % actual_switch_data.get("description", "")
		speech_text += "%s. " % actual_switch_data.get("description", "")
		
		switch_info += "Board: %d, Port: %d\n" % [actual_switch_data.get("board", 0), actual_switch_data.get("port", 0)]
		if speech_exp: 
			speech_text += "Board: %d, Port: %d. " % [actual_switch_data.get("board", 0), actual_switch_data.get("port", 0)]
		
		# Add current state
		var state = get_switch_state(switch_id)
		switch_info += "\nCurrent state: " + ("[color=green]ON[/color]" if state == 1 else "[color=red]OFF[/color]")
		speech_text += "is : " + ("ON" if state == 1 else "OFF")
	else:
		# Fallback if no switch data is available
		switch_info += "[b]Switch #%d[/b]\n" % switch_id
		speech_text += "Switch %d. " % switch_id
		
		switch_info += "No detailed info available\n"
		speech_text += "No Info. "
		
		var state = get_switch_state(switch_id)
		switch_info += "Current state: " + ("[color=green]ON[/color]" if state == 1 else "[color=red]OFF[/color]")
		speech_text += "State: " + ("ON" if state == 1 else "OFF")
	
	# Special handling for RichTextLabel
	if current_switch_info_label is RichTextLabel:
		current_switch_info_label.clear()
		current_switch_info_label.append_text(switch_info)
	else:
		current_switch_info_label.text = switch_info
	
	var audio_on = true
	# TTS speech output, if audio_on is enabled
	if audio_on == true:
		# Stop previous speech if active
		if DisplayServer.tts_is_speaking():
			DisplayServer.tts_stop()
		
	# Try to get English voices instead of German
	var voices = DisplayServer.tts_get_voices_for_language("en")

	# If no English voices are available, use all available voices
	if voices.size() == 0:
		voices = DisplayServer.tts_get_voices()
		print("No English voices found, using all available voices")

	if voices.size() > 0:
		# Verbose debugging to see what's in voices[0]
		print("First voice: ", voices[0])
		print("Type of first voice: ", typeof(voices[0]))
		
		# Speak the text with high priority if possible
		# Use the loudest Master Bus value to ensure TTS is loud enough
		var master_idx = AudioServer.get_bus_index("Master")
		var current_volume = AudioServer.get_bus_volume_db(master_idx)
		AudioServer.set_bus_volume_db(master_idx, 6.0)  # Temporarily increase to +6dB
		
		# For smoother speech output, place the information directly one after another
		speech_text = speech_text.replace("\n", " ").replace("..", ".").replace(".", ",").replace("  ", " ")
		# Speak the text in English
		if speech: 
			DisplayServer.tts_speak(speech_text, voices[0], speech_loudness)
		print("Speak:   '"+speech_text+"'")
		
		# Optional trick: Call tts_speak multiple times to increase priority
		# Wait a short moment and stop all speech outputs except the last one
		await get_tree().create_timer(0.1).timeout
		DisplayServer.tts_stop()

		# For smoother speech output, place the information directly one after another
		speech_text = speech_text.replace("\n", " ").replace("..", ".").replace(".", ",").replace("  ", " ")
		if speech: 
			DisplayServer.tts_speak(speech_text, voices[0], speech_loudness)
		print("Speak:   '"+speech_text+"'")
		
		print("English TTS speech output with maximum volume started")
	else:
		print("No TTS voices found!")
		
	print("Switch info updated for Switch #" + str(switch_id))

# =====================================================================
# TTS TESTING AND INPUT HANDLING
# =====================================================================

# TTS test function - triggered by pressing T key
func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:  # T key
		# Try to get English voices
		var voices = DisplayServer.tts_get_voices_for_language("en")

		# If no English voices are available, use all available voices
		if voices.size() == 0:
			voices = DisplayServer.tts_get_voices()
			print("No English voices found, using all available voices")

		if voices.size() > 0:
			# Verbose debugging to see what's in voices[0]
			print("First voice: ", voices[0])
			print("Type of first voice: ", typeof(voices[0]))
				
			# For smoother speech output, place the information directly one after another
			speech_text = speech_text.replace("\n", " ").replace("..", ".").replace(".", ",").replace("  ", " ")
			# Direct use of voice as ID - from your example
			if speech: 
				DisplayServer.tts_speak(speech_text, voices[0], speech_loudness)
			print("Speak:   '"+speech_text+"'")

		else:
			print("No TTS voices found!")

# Shows the result of an event method call
# Parameters:
#   method_call: Name of the method that was called
#   result: Result of the method call
func show_event_result(method_call, result):
	var result_text = str(result)
	var timestamp = Time.get_datetime_string_from_system()
	libppuc.log_message("Event method '" + method_call + "' returned: " + result_text, "yellow")

# =====================================================================
# MOUSE EVENT HANDLING
# =====================================================================

# Called when mouse enters a switch grid item
# Parameters:
#   switch_id: ID of the switch being hovered
#   container: Container being hovered
func _on_switch_grid_item_mouse_entered(switch_id, container):
	current_hover_switch_id = switch_id
	update_switch_info(switch_id)
	print("Mouse entered Switch #" + str(switch_id))
	
	# Visual feedback - add border
	var style_box = container.get_theme_stylebox("panel")
	style_box.border_width_bottom = 2
	style_box.border_width_top = 2
	style_box.border_width_left = 2
	style_box.border_width_right = 2
	style_box.border_color = Color(1, 1, 1)  # White border
	
	# Check current state and update color accordingly
	var current_state = get_switch_state(switch_id)
	if current_state == 1:
		style_box.bg_color = board_colors[yamlparser.switches[switch_id]["board"]]   # Full color
	else:
		style_box.bg_color = reduce_saturation(board_colors[yamlparser.switches[switch_id]["board"]], c_saturation, c_brightness)

# Called when mouse exits a switch grid item
# Parameters:
#   switch_id: ID of the switch being exited
#   container: Container being exited
func _on_switch_grid_item_mouse_exited(switch_id, container):
	current_hover_switch_id = -1
	print("Mouse exited Switch #" + str(switch_id))
	
	# Remove border
	var style_box = container.get_theme_stylebox("panel")
	style_box.border_width_bottom = 0
	style_box.border_width_top = 0
	style_box.border_width_left = 0
	style_box.border_width_right = 0
	
	# Maintain current state
	var current_state = get_switch_state(switch_id)
	if current_state == 1:
		style_box.bg_color = board_colors[yamlparser.switches[switch_id]["board"]]  # Full color
	else:
		style_box.bg_color = reduce_saturation(board_colors[yamlparser.switches[switch_id]["board"]], c_saturation, c_brightness)

# Called when a switch grid item is clicked
# Parameters:
#   event: Input event
#   switch_id: ID of the switch being clicked
#   container: Container being clicked
func _on_switch_grid_item_clicked(event, switch_id, container):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Show switch info
		print("Switch #" + str(switch_id) + " was clicked")
		update_switch_info(switch_id)

# =====================================================================
# SWITCH STATE CHANGE HANDLING
# =====================================================================

# Event handler for switch state changes
# Parameters:
#   switch_id: ID of the switch that changed
#   state: New state of the switch
func _on_switch_changed(switch_id, state):
	print("SIGNAL RECEIVED: Switch #" + str(switch_id) + " has state " + str(state))
	
	# Save the new state
	last_known_states[switch_id] = state
	
	# Update the visual representation
	update_switch_visual(switch_id, state)
	
	# Update the switch info display for all state changes
	update_switch_info(switch_id)
	
	# Log the state change
	var state_text = "ON" if state == 1 else "OFF"
	print("Switch #" + str(switch_id) + " state changed to: " + state_text)

# =====================================================================
# UTILITY FUNCTIONS
# =====================================================================

# Helper function to check if an object has an attribute
# Parameters:
#   obj: Object to check
#   attr_name: Name of the attribute to check for
# Returns:
#   bool: True if the object has the attribute, false otherwise
func hasattr(obj, attr_name):
	if obj == null:
		return false
	
	if typeof(obj) == TYPE_DICTIONARY:
		return obj.has(attr_name)
	elif typeof(obj) == TYPE_OBJECT:
		return attr_name in obj
	
	return false

# Tests the audio system by playing a simple tone
func test_audio_system():
	# Creates a simple tone to test if audio generally works
	var audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	
	# Create a simple tone
	var audio_stream = AudioStreamGenerator.new()
	audio_stream.mix_rate = 44100
	audio_stream.buffer_length = 0.5  # 0.5 seconds
	
	audio_player.stream = audio_stream
	audio_player.play()
	
	# Fill generator
	var playback = audio_player.get_stream_playback()
	var buffer = PackedVector2Array()
	buffer.resize(audio_stream.buffer_length * audio_stream.mix_rate)
	
	# Generate simple sine tone
	for i in range(buffer.size()):
		var value = sin(i * 0.1) * 0.5  # Simple tone
		buffer[i] = Vector2(value, value)
	
	playback.push_buffer(buffer)
	print("Test tone is playing...")

# =====================================================================
# UI TOGGLE CALLBACKS
# =====================================================================

# Toggle speech output on/off
# Parameters:
#   toggled_on: Whether the speech checkbox is turned on
func _on_speech_check_button_toggled(toggled_on):
	if toggled_on:
		speech = true
		print("Speech ON")
	else:
		speech = false
		print("Speech OFF")

# Toggle extended speech info on/off
# Parameters:
#   toggled_on: Whether the extended speech checkbox is turned on
func _on_speech_exp_check_button_2_toggled(toggled_on):
	if toggled_on:
		speech_exp = true
		print("Speech enhanced info ON")
	else:
		speech_exp = false
		print("Speech enhanced info OFF")


# =====================================================================
#  PPUC TEST FUNCTIONS
# =====================================================================

# Start the libppuc switch test feature

func _on_switch_test_pressed():
	libppuc.switch_test()
