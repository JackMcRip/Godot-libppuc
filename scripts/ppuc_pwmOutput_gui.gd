# =====================================================================
# ppuc_pwmOutput_gui.gd - PWM Output GUI Controller for PPUC
# =====================================================================
# This script manages the graphical user interface for controlling PWM outputs
# (coils, motors, etc.) in the PPUC (Pinball Power-Up Controller) system.
# It creates a grid-based interface showing PWM outputs with color-coding
# based on their board association and activation state.
# =====================================================================

extends Control

# =====================================================================
# MEMBER VARIABLES
# =====================================================================

# Grid and container references
var pwmOutput_grid_containers = []    # Array of containers for each PWM output in the grid
var pwmOutput_ids = []                # Array of PWM output IDs in the grid
var pwmOutput_grid                    # Reference to the existing PWMOutputGrid
var current_pwmOutput_info_label      # Reference to the info text display
var local_pwmOutputs = {}             # Local copy of PWM outputs from the YAML configuration

# Timing and state tracking
var last_process_time = 0             # For rate limiting PWM output polling
var process_interval = 0.01           # Poll every 10ms (100 times per second) for faster updates
var current_hover_pwmOutput_id = -1   # Currently hovered PWM output ID
var connected = false                 # Connection status to PPUC hardware
var last_known_states = {}            # Stores last known states to detect changes

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
var c_saturation = 0.4  # Reduced color saturation for inactive PWM outputs
var c_brightness = 0.4  # Reduced brightness for inactive PWM outputs

# =====================================================================
# INITIALIZATION
# =====================================================================

# Called when the node enters the scene tree for the first time
func _ready():
	# Find existing nodes in the scene hierarchy
	find_nodes_in_scene()
	
	# Load PWM outputs from yamlparser if available
	if yamlparser != null and hasattr(yamlparser, "pwmOutput"):
		if typeof(yamlparser.pwmOutput) == TYPE_ARRAY:
			# Convert array to dictionary for faster access
			for pwmOutput_data in yamlparser.pwmOutput:
				if typeof(pwmOutput_data) == TYPE_DICTIONARY and pwmOutput_data.has("number"):
					var pwmOutput_id = pwmOutput_data.get("number")
					if not local_pwmOutputs.has(pwmOutput_id):
						local_pwmOutputs[pwmOutput_id] = []
					local_pwmOutputs[pwmOutput_id].append(pwmOutput_data)
		elif typeof(yamlparser.pwmOutput) == TYPE_DICTIONARY:
			# Copy dictionary
			local_pwmOutputs = yamlparser.pwmOutput.duplicate(true)
		print("PWM outputs loaded from yamlparser")
	
	# Connect to PPUC and listen for PWM output events if available
	if libppuc != null:
		print("libppuc found, attempting signal connection...")
		connected = false
		if libppuc.has_method("connect_to_hardware"):
			connected = true
		
		# Try to connect to the signal
		if libppuc.has_signal("pwmOutput_changed"):
			print("Signal 'pwmOutput_changed' exists")
			var already_connected = false
			if libppuc.is_connected("pwmOutput_changed", Callable(self, "_on_pwmOutput_changed")):
				already_connected = true
				print("Signal already connected")
			
			if not already_connected:
				libppuc.connect("pwmOutput_changed", Callable(self, "_on_pwmOutput_changed"))
				print("Signal 'pwmOutput_changed' connected")
				
		else:
			push_warning("Signal 'pwmOutput_changed' does not exist in libppuc!")
	
	# Wait for all nodes to be initialized
	call_deferred("create_pwmOutput_grid")

	print("#################")
	print("PPUC-PWMOutput-GUI initialized and using existing PWMOutputGrid container")

# =====================================================================
# PROCESSING
# =====================================================================

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

# =====================================================================
# NODE FINDING AND SCENE SETUP
# =====================================================================

# Finds and stores references to important nodes in the scene graph
func find_nodes_in_scene():
	# Find the PWMOutputGrid node (container for PWM output elements)
	var pwmOutputs_grid_container = find_node_by_name_recursive(get_tree().root, "PWMOutputGrid")
	if not pwmOutputs_grid_container:
		push_error("PWMOutputGrid node not found!")
		return
	
	# Check if a GridContainer already exists in PWMOutputGrid
	pwmOutput_grid = null
	for child in pwmOutputs_grid_container.get_children():
		if child is GridContainer:
			pwmOutput_grid = child
			break
	
	# If no GridContainer was found, create a new one
	if not pwmOutput_grid:
		pwmOutput_grid = GridContainer.new()
		pwmOutput_grid.name = "PWMOutputGrid"
		pwmOutput_grid.columns = 10  # Always 10 columns
		pwmOutputs_grid_container.add_child(pwmOutput_grid)
	else:
		# If one exists, ensure it has 10 columns
		pwmOutput_grid.columns = 10
	
	# Find the PWMOutputs node
	var pwmOutputs_node = find_node_by_name_recursive(get_tree().root, "PwmOutputs")  # Note spelling in hierarchy
	if not pwmOutputs_node:
		# Try alternative spelling
		pwmOutputs_node = find_node_by_name_recursive(get_tree().root, "PWMOutputs")
	
	# If PWMOutputs node was found, look for its Info child
	if pwmOutputs_node:
		var info_node = null
		for child in pwmOutputs_node.get_children():
			if child.name == "Info":
				info_node = child
				break
				
		# If Info node was found, look for its RichTextLabel
		if info_node:
			for child in info_node.get_children():
				if child is RichTextLabel:
					current_pwmOutput_info_label = child
					print("RichTextLabel for PWM output info found!")
					break
	
	# If no RichTextLabel was found, try to find the Info node directly
	if not current_pwmOutput_info_label:
		var info_node = find_node_by_name_recursive(get_tree().root, "Info")
		if info_node:
			for child in info_node.get_children():
				if child is RichTextLabel:
					current_pwmOutput_info_label = child
					print("RichTextLabel for PWM output info found in Info node!")
					break
	
	# If still no label was found, create a new one
	if not current_pwmOutput_info_label:
		push_warning("Info RichTextLabel not found, creating a new one")
		current_pwmOutput_info_label = RichTextLabel.new()
		current_pwmOutput_info_label.bbcode_enabled = true
		current_pwmOutput_info_label.fit_content = true
		current_pwmOutput_info_label.text = "No PWM output selected"
		
		# Try to place it in the Info node, if available
		var info_node = find_node_by_name_recursive(get_tree().root, "Info")
		if info_node:
			info_node.add_child(current_pwmOutput_info_label)
		else:
			add_child(current_pwmOutput_info_label)

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
# PWM OUTPUT EVENT HANDLING
# =====================================================================

# Checks for PWM output state changes
func check_pwmOutput_events():
	# Check if libppuc is available
	if libppuc == null:
		push_error("libppuc is not available")
		return
		
	# Ensure that pwmOutput_states in libppuc is available
	if not hasattr(libppuc, "pwmOutput_states"):
		push_warning("libppuc.pwmOutput_states is not available")
		return
	
	# Start updates (if needed)
	if libppuc.has_method("start_updates"):
		libppuc.start_updates()
	
	# Check all PWM output states in libppuc.pwmOutput_states dictionary
	if hasattr(libppuc, "pwmOutput_states") and typeof(libppuc.pwmOutput_states) == TYPE_DICTIONARY:
		# For each PWM output in pwmOutput_ids
		for pwmOutput_id in pwmOutput_ids:
			var current_state = get_pwmOutput_state(pwmOutput_id)
			
			# If the state has changed or we're seeing it for the first time
			if not last_known_states.has(pwmOutput_id) or last_known_states[pwmOutput_id] != current_state:
				# Save the new state
				last_known_states[pwmOutput_id] = current_state
				
				# Update the visual representation
				update_pwmOutput_visual(pwmOutput_id, current_state)
				
				# Always show PWM output info, regardless of state
				update_pwmOutput_info(pwmOutput_id)
				
				# Log the state change
				var state_text = "ON" if current_state == 1 else "OFF"
				print("PWM Output #" + str(pwmOutput_id) + " state changed to: " + state_text)
	
	# Use get_next_pwmOutput_state from libppuc for the latest changes (if available)
	if libppuc.has_method("get_next_pwmOutput_state"):
		var pwmOutput_state = libppuc.get_next_pwmOutput_state()
		while pwmOutput_state != null:
			var pwmOutput_number = -1
			var pwmOutput_value = -1
			var success = false
			
			# Try different ways to extract PWM output data
			if typeof(pwmOutput_state) == TYPE_DICTIONARY:
				if pwmOutput_state.has("number") and pwmOutput_state.has("state"):
					pwmOutput_number = int(pwmOutput_state.get("number"))
					pwmOutput_value = int(pwmOutput_state.get("state"))
					success = true
			elif typeof(pwmOutput_state) == TYPE_OBJECT:
				# Try different methods to get the data
				if "number" in pwmOutput_state and "state" in pwmOutput_state:
					pwmOutput_number = int(pwmOutput_state.number)
					pwmOutput_value = int(pwmOutput_state.state)
					success = true
				elif pwmOutput_state.has_method("get_number") and pwmOutput_state.has_method("get_state"):
					pwmOutput_number = int(pwmOutput_state.get_number())
					pwmOutput_value = int(pwmOutput_state.get_state())
					success = true
			
			if success and pwmOutput_number >= 0:
				# Update the display for this PWM output
				update_pwmOutput_visual(pwmOutput_number, pwmOutput_value)
				
				# Save the new state
				last_known_states[pwmOutput_number] = pwmOutput_value
				
				# Always show PWM output info, regardless of state
				update_pwmOutput_info(pwmOutput_number)
				
				print("PWM Output #" + str(pwmOutput_number) + " state changed via get_next_pwmOutput_state!")
			
			# Get the next PWM output state
			pwmOutput_state = libppuc.get_next_pwmOutput_state()
	
	if libppuc.has_method("stop_updates"):
		libppuc.stop_updates()

# Updates the visual representation of a specific PWM output
# Parameters:
#   pwmOutput_id: ID of the PWM output to update
#   state: New state of the PWM output (0 or 1)
func update_pwmOutput_visual(pwmOutput_id, state):
	# Look for the PWM output in the grid
	var container_found = false
	
	for i in range(pwmOutput_ids.size()):
		if pwmOutput_ids[i] == pwmOutput_id and i < pwmOutput_grid_containers.size():
			var container = pwmOutput_grid_containers[i]
			if is_instance_valid(container):
				var style_box = container.get_theme_stylebox("panel")
				if style_box != null:
					container_found = true
					
					if state == 1:
						# Use full color for active state
						style_box.bg_color = board_colors[yamlparser.pwmOutput[pwmOutput_id]["board"]]
					else:
						# Use desaturated color for inactive state
						style_box.bg_color = reduce_saturation(board_colors[yamlparser.pwmOutput[pwmOutput_id]["board"]], c_saturation, c_brightness)
					
					# Maintain hover border if present
					if current_hover_pwmOutput_id == pwmOutput_id:
						style_box.border_width_bottom = 2
						style_box.border_width_top = 2
						style_box.border_width_left = 2
						style_box.border_width_right = 2
						style_box.border_color = Color(1, 1, 1)  # White border
					break
	
	if not container_found and pwmOutput_id in pwmOutput_ids:
		print("WARNING: Container for PWM Output #" + str(pwmOutput_id) + " not found!")

# Gets the state of a PWM output
# Parameters:
#   pwmOutput_id: ID of the PWM output
# Returns:
#   int: State of the PWM output (0 or 1)
func get_pwmOutput_state(pwmOutput_id):
	# If pwmOutput_id is an array index, convert it to the actual PWM output number
	var actual_pwmOutput_number = pwmOutput_id
	if pwmOutput_id < yamlparser.pwmOutput.size():
		if typeof(yamlparser.pwmOutput[pwmOutput_id]) == TYPE_DICTIONARY:
			actual_pwmOutput_number = yamlparser.pwmOutput[pwmOutput_id].get("number")
	
	# Rest of the function remains the same, but searches for actual_pwmOutput_number
	if libppuc == null or not hasattr(libppuc, "pwmOutput_states"):
		return 0
		
	if typeof(libppuc.pwmOutput_states) != TYPE_DICTIONARY:
		return 0
		
	if libppuc.pwmOutput_states.has(actual_pwmOutput_number):
		return libppuc.pwmOutput_states[actual_pwmOutput_number]
	elif libppuc.pwmOutput_states.has(str(actual_pwmOutput_number)):
		return libppuc.pwmOutput_states[str(actual_pwmOutput_number)]
	
	return 0

# =====================================================================
# PWM OUTPUT GRID CREATION
# =====================================================================

# Creates the grid for PWM outputs
func create_pwmOutput_grid():
	# Ensure pwmOutput_grid exists
	if not is_instance_valid(pwmOutput_grid):
		push_error("PWM Output grid not initialized")
		return
	
	var gridcontainer_parent = pwmOutput_grid.get_parent()
	
	# Remove old elements
	for child in pwmOutput_grid.get_children():
		pwmOutput_grid.remove_child(child)
		child.queue_free()
	
	pwmOutput_grid_containers.clear()
	pwmOutput_ids.clear()
	
	# Extract PWM output IDs directly from yamlparser.pwmOutput
	if yamlparser != null and hasattr(yamlparser, "pwmOutput"):
		if typeof(yamlparser.pwmOutput) == TYPE_ARRAY:
			# Use array position as ID instead of collecting unique IDs
			print(str(yamlparser.pwmOutput.size()) + " PWM Outputs to read:")
			for i in range(yamlparser.pwmOutput.size()):
				pwmOutput_ids.append(i)  # Use array index as ID
		
		elif typeof(yamlparser.pwmOutput) == TYPE_DICTIONARY:
			# Extract PWM output IDs from the dictionary
			for pwmOutput_id_str in yamlparser.pwmOutput.keys():
				var pwmOutput_data = yamlparser.pwmOutput[pwmOutput_id_str]
				if typeof(pwmOutput_data) == TYPE_DICTIONARY and pwmOutput_data.has("number"):
					var pwmOutput_id = pwmOutput_data.get("number")
					if not pwmOutput_id in pwmOutput_ids:
						pwmOutput_ids.append(pwmOutput_id)
	
	# Sort the IDs numerically
	pwmOutput_ids.sort()

	# Create grid elements
	for pwmOutput_id in pwmOutput_ids:
		# Check if the PWM output is already active
		var initial_color = board_colors[yamlparser.pwmOutput[pwmOutput_id]["board"]]
		if get_pwmOutput_state(pwmOutput_id) == 1:
			initial_color = board_colors[yamlparser.pwmOutput[pwmOutput_id]["board"]]
			# Save the initial state
			last_known_states[pwmOutput_id] = 1
		else:
			# Use desaturated color for inactive state
			initial_color = reduce_saturation(initial_color, c_saturation, c_brightness)
			last_known_states[pwmOutput_id] = 0
			
		var container = create_grid_item(pwmOutput_id, initial_color)
		pwmOutput_grid.add_child(container)
		pwmOutput_grid_containers.append(container)
		
		# Set up mouse events for the PWM output
		container.mouse_entered.connect(_on_pwmOutput_grid_item_mouse_entered.bind(pwmOutput_id, container))
		container.mouse_exited.connect(_on_pwmOutput_grid_item_mouse_exited.bind(pwmOutput_id, container))
		container.gui_input.connect(_on_pwmOutput_grid_item_clicked.bind(pwmOutput_id, container))
	
	print("PWM Output grid created with " + str(pwmOutput_grid_containers.size()) + " elements")
	print("#################")
	
	# Create board color legend
	gridcontainer_parent.add_child(create_board_legend())

# Helper function to create a grid item
# Parameters:
#   id: ID of the PWM output
#   base_color: Base color for the PWM output
# Returns:
#   PanelContainer: Created grid item container
func create_grid_item(id: int, base_color: Color) -> PanelContainer:
	var container = PanelContainer.new()
	container.custom_minimum_size = Vector2(35, 35)  # Good size for clickability
	
	# IMPORTANT: Set mouse_filter value to detect mouse events
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Set default values
	var pwmOutput_number = id  # Fallback: Use the provided ID
	var board_number = 0       # Default board number
	
	# Get data from the YAML parser if available
	if yamlparser != null and hasattr(yamlparser, "pwmOutput"):
		if typeof(yamlparser.pwmOutput) == TYPE_ARRAY and id < yamlparser.pwmOutput.size():
			var pwmOutput_data = yamlparser.pwmOutput[id]
			if typeof(pwmOutput_data) == TYPE_DICTIONARY:
				# Get PWM output number from the data
				if pwmOutput_data.has("number"):
					pwmOutput_number = pwmOutput_data.get("number")
				
				# Get board number from the data
				if pwmOutput_data.has("board"):
					board_number = pwmOutput_data.get("board")
	
	# Restrict board number to valid range (0-15)
	board_number = clamp(board_number, 0, 15)
	
	# Display the PWM output number
	var label = Label.new()
	label.text = str(pwmOutput_number)
	
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
# PWM OUTPUT INFO DISPLAY
# =====================================================================

# Updates the PWM output info display
# Parameters:
#   pwmOutput_id: ID of the PWM output to display info for
func update_pwmOutput_info(pwmOutput_id: int):
	if not is_instance_valid(current_pwmOutput_info_label):
		push_error("current_pwmOutput_info_label not valid")
		return
		
	# Safety check for libppuc and yamlparser
	if libppuc == null:
		push_error("libppuc is not available")
		return
		
	var pwmOutput_info = ""
	
	# Use the array index to get the actual PWM output
	var actual_pwmOutput_data = null
	var actual_pwmOutput_number = pwmOutput_id
	
	if yamlparser != null and hasattr(yamlparser, "pwmOutput"):
		if typeof(yamlparser.pwmOutput) == TYPE_ARRAY and pwmOutput_id < yamlparser.pwmOutput.size():
			actual_pwmOutput_data = yamlparser.pwmOutput[pwmOutput_id]
			if typeof(actual_pwmOutput_data) == TYPE_DICTIONARY and actual_pwmOutput_data.has("number"):
				actual_pwmOutput_number = actual_pwmOutput_data.get("number")
	
	# Display PWM output information
	if actual_pwmOutput_data != null:
		pwmOutput_info += "[b]PWM Output #%d (ID: %d)[/b]\n" % [actual_pwmOutput_number, pwmOutput_id]
		
		# Show details of the PWM output
		pwmOutput_info += "Description: %s\n" % actual_pwmOutput_data.get("description", "")
		pwmOutput_info += "Board: %d, Port: %d\n" % [actual_pwmOutput_data.get("board", 0), actual_pwmOutput_data.get("port", 0)]
		
		# Add current state
		var state = get_pwmOutput_state(pwmOutput_id)
		pwmOutput_info += "\nCurrent state: " + ("[color=green]ON[/color]" if state == 1 else "[color=red]OFF[/color]")
	else:
		# Fallback if no PWM output data is available
		pwmOutput_info += "[b]PWM Output #%d[/b]\n" % pwmOutput_id
		pwmOutput_info += "No detailed info available\n"
		
		var state = get_pwmOutput_state(pwmOutput_id)
		pwmOutput_info += "Current state: " + ("[color=green]ON[/color]" if state == 1 else "[color=red]OFF[/color]")
	
	# Special handling for RichTextLabel
	if current_pwmOutput_info_label is RichTextLabel:
		current_pwmOutput_info_label.clear()
		current_pwmOutput_info_label.append_text(pwmOutput_info)
	else:
		current_pwmOutput_info_label.text = pwmOutput_info
		
	print("PWM Output info updated for PWM Output #" + str(pwmOutput_id))

# Displays the result of an event method call
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

# Called when mouse enters a PWM output grid item
# Parameters:
#   pwmOutput_id: ID of the PWM output being hovered
#   container: Container being hovered
func _on_pwmOutput_grid_item_mouse_entered(pwmOutput_id, container):
	current_hover_pwmOutput_id = pwmOutput_id
	update_pwmOutput_info(pwmOutput_id)
	print("Mouse entered PWM Output #" + str(pwmOutput_id))
	
	# Visual feedback - add border
	var style_box = container.get_theme_stylebox("panel")
	style_box.border_width_bottom = 2
	style_box.border_width_top = 2
	style_box.border_width_left = 2
	style_box.border_width_right = 2
	style_box.border_color = Color(1, 1, 1)  # White border

# Called when mouse exits a PWM output grid item
# Parameters:
#   pwmOutput_id: ID of the PWM output being exited
#   container: Container being exited
func _on_pwmOutput_grid_item_mouse_exited(pwmOutput_id, container):
	current_hover_pwmOutput_id = -1
	print("Mouse exited PWM Output #" + str(pwmOutput_id))
	
	# Remove border
	var style_box = container.get_theme_stylebox("panel")
	style_box.border_width_bottom = 0
	style_box.border_width_top = 0
	style_box.border_width_left = 0
	style_box.border_width_right = 0

# Called when a PWM output grid item is clicked
# Parameters:
#   event: Input event
#   pwmOutput_id: ID of the PWM output being clicked
#   container: Container being clicked
func _on_pwmOutput_grid_item_clicked(event, pwmOutput_id, container):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Show PWM output info
		print("PWM Output #" + str(pwmOutput_id) + " was clicked")
		update_pwmOutput_info(pwmOutput_id)

# =====================================================================
# PWM OUTPUT STATE CHANGE HANDLING
# =====================================================================

# Event handler for PWM output state changes
# Parameters:
#   pwmOutput_id: ID of the PWM output that changed
#   state: New state of the PWM output
func _on_pwmOutput_changed(pwmOutput_id, state):
	print("SIGNAL RECEIVED: PWM Output #" + str(pwmOutput_id) + " has state " + str(state))
	
	# Save the new state
	last_known_states[pwmOutput_id] = state
	
	# Update the visual representation
	update_pwmOutput_visual(pwmOutput_id, state)
	
	# Update the PWM output info display for all state changes
	update_pwmOutput_info(pwmOutput_id)
	
	# Log the state change
	var state_text = "ON" if state == 1 else "OFF"
	print("PWM Output #" + str(pwmOutput_id) + " state changed to: " + state_text)

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


# =====================================================================
# PPUC TEST FUNCTIONS
# =====================================================================

# Start the libppuc coil test feature
func _on_coil_test_pressed():
	libppuc.coil_test()
