# =====================================================================
# ppuc_lamps_gui.gd - Lamps GUI Controller for PPUC
# =====================================================================
# This script manages the graphical user interface for controlling lamps
# in the PPUC (Pinball Power-Up Controller) system. It provides functionality
# for displaying, filtering, and interacting with lamp elements in the UI.
# =====================================================================

extends Node

# =====================================================================
# CONFIGURATION VARIABLES
# =====================================================================

# Controls whether lamp type filtering is enabled
var set_filter_lamp_type = true

# Filter flags for different lamp types
var lampfilter_gi = false        # General Illumination lamps
var lampfilter_flasher = false   # Flasher lamps
var lampfilter_lamps = true      # Standard lamps

# Flag indicating the blink animation is still active
var blink_wait = false

# When true, hovering over a lamp button will toggle its state
var mouse_set_on = true

# Flag indicating if monitoring is currently running
var monitoring_running

# Flag to enable/disable sound effects
var audio_on = true

# =====================================================================
# SORTING AND FILTERING FUNCTIONS
# =====================================================================

# Sorts and filters an array of LED dictionaries
# Parameters:
#   led_array: Array of LED dictionaries to process
#   number_basis: Field to use for sorting ("ledNumber" or "number")
#   sort_ascending: Whether to sort in ascending order
#   remove_duplicates: Whether to remove duplicate entries
#   filter_board: Board number to filter by (-1 for no filtering)
#   filter_lamp_type: Whether to filter by lamp type
#   show_gi: Whether to include GI lamps
#   show_flasher: Whether to include flasher lamps
#   show_lamps: Whether to include standard lamps
# Returns:
#   Dictionary with two arrays: "numbers" (just the LED numbers) and "items" (complete LED dictionaries)
func sort_led_array(
	led_array: Array,
	number_basis: String = "ledNumber",  # Can be "ledNumber" or "number"
	sort_ascending: bool = true,         # True = ascending, False = descending
	remove_duplicates: bool = false,     # True = removes duplicates
	filter_board: int = -1,              # -1 = no filtering
	filter_lamp_type = true,				 # true = filtering lamp type
	show_gi = true,						 # Whether to show GI lamps
	show_flasher = true,					 # Whether to show flasher lamps
	show_lamps = true,					 # Whether to show standard lamps
) -> Dictionary:
	# Create a copy of the array to avoid modifying the original
	var result_array = led_array.duplicate(true)
	
	# 1. Filter by Board if specified
	if filter_board >= 0:
		var temp_array = []
		for item in result_array:
			if item.has("board") and item["board"] == filter_board:
				temp_array.append(item)
		result_array = temp_array
	
	# 2. Filter by LampType if specified
	if set_filter_lamp_type == true:
		var temp_array = []
		for item in result_array:
			if item.has("lampType") and item["lampType"] == "gi" and show_gi:
				temp_array.append(item)
			elif item.has("lampType") and item["lampType"] == "flasher" and show_flasher:
				temp_array.append(item)
			elif item.has("lampType") and item["lampType"] == "lamps" and show_lamps:
				temp_array.append(item)
		result_array = temp_array
	
	# 3. Sort the array based on the number basis
	if number_basis == "ledNumber" or number_basis == "number":
		result_array.sort_custom(func(a, b):
			if sort_ascending:
				return a[number_basis] < b[number_basis]
			else:
				return a[number_basis] > b[number_basis]
		)
	
	# 4. Remove duplicates if desired
	if remove_duplicates:
		var temp_array = []
		var seen_values = {}
		
		for item in result_array:
			if item.has(number_basis) and not seen_values.has(item[number_basis]):
				seen_values[item[number_basis]] = true
				temp_array.append(item)
		
		result_array = temp_array
	
	# 5. Store the final filtered and sorted array of dictionaries
	var filtered_items = result_array.duplicate()
	
	# 6. Extract only the numbers based on the number basis
	var numbers_array = []
	for item in result_array:
		if item.has(number_basis):
			numbers_array.append(item[number_basis])
	
	# Return both arrays in a dictionary
	return {
		"numbers": numbers_array,
		"items": filtered_items
	}

# =====================================================================
# LAMP BLOCK CREATION FUNCTIONS
# =====================================================================

# Creates lamp blocks for all LED strips in the configuration
# This is the main function that builds the lamp interface
func create_lamps_blocks():
	# Get reference to the lamps container
	var lampscontainer = get_node("/root/Main-Control/HBoxContainer/Split-Horizontal/TOP-GUI/Spalten/Lampen/Lamps")
	
	# Remove all existing child nodes
	kill_all_childs(lampscontainer)
	
	var result
	libppuc.debug_log("LEDS:"+str(yamlparser.leds.size()), "yellow")

	# Iterate through all LED strips
	for ledstrip in yamlparser.ledStripes:
		# Find the ledStripes index matching the current board
		# Note: multiple board indices can be the same, although the hardware doesn't support this
		var stripe_check = yamlparser.find_dictionaries_with_value(yamlparser.ledStripes, ledstrip["board"])
		var ledstripe_index = stripe_check[0]
		
		print("LED-Strip FOUND: "+str(stripe_check[0])+"  ---  Board:"+str(ledstrip["board"]))
		libppuc.debug_log("LedStripe_Index:"+str(ledstripe_index) + "     Board-Nr:"+str(ledstrip["board"]), "yellow")
		
		# Sort and filter LEDs for this board
		result = lampsgui.sort_led_array(
			yamlparser.leds,
			"ledNumber",
			false,             # Descending order
			false,             # Don't remove duplicates
			ledstrip["board"], # Filter by current board
			true,              # Apply lamp type filtering
			lampfilter_gi,     # Show GI based on filter setting
			lampfilter_flasher, # Show flashers based on filter setting
			lampfilter_lamps   # Show lamps based on filter setting
		)
		
		# Create lamp buttons for this LED strip
		lampsgui.create_lamps_button(
			$"/root/Main-Control/HBoxContainer/Split-Horizontal/TOP-GUI/Spalten/Lampen/Lamps", 
			result.items, 
			ledstripe_index
		)
	
	print("Lamp States:")
	print(str(libppuc.get_lamps()))

# Called when the node enters the scene tree for the first time
func _ready():
	pass

# Creates lamp buttons for a specific LED strip
# Parameters:
#   container: Container node to add buttons to
#   led_array: Array of LED dictionaries to create buttons for
#   stripenr: Index of the LED strip in the yamlparser.ledStripes array
func create_lamps_button(container, led_array, stripenr):
	# Display LED strip information
	show_ledStripeInfos(container, stripenr, led_array.size())

	# Find target container
	var ziel_container = get_node("/root/Main-Control/HBoxContainer/Split-Horizontal/TOP-GUI/Spalten/Lampen/Lamps")
	if ziel_container == null:
		print("Target container not found!")
		return # End function if target container not found
	
	# Create new container
	var neuer_container = GridContainer.new()
	neuer_container.columns = 10
	neuer_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(neuer_container) # Add the new container to the scene
	
	# CREATE BUTTONS
	# For each entry in the LED array, create a button
	for led_info in led_array:		
		# Create new button
		var button = Button.new()
		
		# Set button label to LED number
		button.text = str(led_info["ledNumber"])+"\n"+str(led_info["number"])
		
		# Set button size to exactly 20x20 pixels
		button.custom_minimum_size = Vector2(20, 20)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		# Set font size to 8 pixels
		var font_settings = {}
		font_settings["font_size"] = 8
		button.add_theme_font_size_override("font_size", 8)
		
		# Convert hex color string to Color object
		var original_color = Color("#{0}".format([led_info["color"]]))
		
		# Get HSV components and reduce saturation
		var h = original_color.h
		var s = original_color.s * 0.5  # Reduce saturation by 50%
		var v = original_color.v * 0.5  # Reduce brightness by 50%
		
		# Create new color with reduced saturation
		var desaturated_color = Color.from_hsv(h, s, v, 1.0)
		
		# Create styles for both states
		var normal_style_inactive = StyleBoxFlat.new()
		normal_style_inactive.bg_color = desaturated_color
		
		var normal_style_active = StyleBoxFlat.new()
		normal_style_active.bg_color = original_color
		
		# Set initial button color with reduced saturation
		button.add_theme_stylebox_override("normal", normal_style_inactive)
		
		# Store LED information and styles in the button using metadata
		button.set_meta("led_daten", led_info)
		button.set_meta("normal_style_inactive", normal_style_inactive)
		button.set_meta("normal_style_active", normal_style_active)
		button.set_meta("is_activated", false)
		
		# Connect button signals to handler functions
		button.pressed.connect(_on_led_button_pressed.bind(button))
		button.mouse_entered.connect(_on_led_button_on_mouse_entered.bind(button))
		button.mouse_exited.connect(_on_led_button_on_mouse_exited.bind(button))
		
		# Add button to container
		neuer_container.add_child(button)

# Removes all child nodes from a container
# Parameters:
#   container_node: Container to remove children from
func kill_all_childs(container_node):
	for child in container_node.get_children():
		child.queue_free()

# =====================================================================
# BUTTON EVENT HANDLING
# =====================================================================

# Called when mouse enters an LED button
# Parameters:
#   button: The button that was entered
func _on_led_button_on_mouse_entered(button):
	# Get LED information from the button and display in info area
	var led_info = button.get_meta("led_daten")
	var is_activated = button.get_meta("is_activated")
	var infotext = button.get_meta("led_daten")
	
	var led_info_text = "LED-ID: "+str(infotext["ledNumber"])+" ("+str(infotext["number"])+") - "+str(infotext["description"])+"\n"
	led_info_text += 'Color: #'+str(infotext["color"])+" ("+str(infotext["ledType"])+" / "+str(infotext["brightness"])+") - "+str(infotext["description"])+"\n"
	led_info_text += 'Lamp Type: '+str(infotext["lampType"]+"\n")
	led_info_text += 'Board: '+str(infotext["board"])
	
	$"/root/Main-Control/HBoxContainer/Split-Horizontal/TOP-GUI/Spalten/Lampen/Info/RichTextLabel".text = led_info_text

	print("LED-Button Status: "+str(is_activated))
	var activestate  # activestate is the current lamp state only for the blink cycle
	if is_activated:  # is_activated is the button variable indicating if it's pressed
		activestate = 1
	else:
		activestate = 0
		
	$"/root/Main-Control/HBoxContainer/Split-Horizontal/TOP-GUI/Spalten/Lampen/Info/RichTextLabel".text = led_info_text
	
	if libppuc.connected:
		# Loop the blinking sequence
		for i in range(6):  # Number of blinks can be adjusted as needed
			blink_wait = true
			
			# Change Lamp State
			if activestate == 0:
				activestate = 1
			else:
				activestate = 0
				
			# Turn the lamp to opposite state
			if activestate == 0: 
				libppuc.set_lamp_state(infotext["number"], 0)
			else: 
				libppuc.set_lamp_state(infotext["number"], 1)
				
			await get_tree().create_timer(0.05).timeout

			# Check activation state again
			if activestate == 0:
				activestate = 1
			else:
				activestate = 0  # Return to original state

			if activestate == 0: 
				libppuc.set_lamp_state(infotext["number"], 0)
			else: 
				libppuc.set_lamp_state(infotext["number"], 1)
				
			await get_tree().create_timer(0.05).timeout
			
	blink_wait = false
	
	# Restore original state
	if is_activated: 
		libppuc.set_lamp_state(infotext["number"], 1)
	else: 
		libppuc.set_lamp_state(infotext["number"], 0)

# Called when mouse exits an LED button
# Parameters:
#   button: The button that was exited
func _on_led_button_on_mouse_exited(button):
	# Get LED information from the button
	var led_info = button.get_meta("led_daten")  # LED data retrieved from button
	var infotext = led_info

	var is_activated = button.get_meta("is_activated")
	print("LED-Button Status: "+str(is_activated))

# Called when an LED button is pressed
# Parameters:
#   button: The button that was pressed
func _on_led_button_pressed(button):
	if blink_wait:                                # If blinking is still active
		await get_tree().create_timer(0.4).timeout  # Wait a moment
		if blink_wait: return                       # If still blinking, don't execute the function

	# Get LED information from the button
	var led_info = button.get_meta("led_daten")
	var is_activated = button.get_meta("is_activated")
	var infotext = button.get_meta("led_daten")
	print(infotext["ledNumber"])

	# Toggle activation state
	is_activated = !is_activated
	button.set_meta("is_activated", is_activated)
	
	# Get appropriate style based on activation state
	var style = button.get_meta("normal_style_active") if is_activated else button.get_meta("normal_style_inactive")
	
	# Update button style
	button.add_theme_stylebox_override("normal", style)
	
	# Turn lamp on/off if connected to hardware
	if libppuc.connected: 
		if is_activated: 
			libppuc.set_lamp_state(infotext["number"], 1)
		else: 
			libppuc.set_lamp_state(infotext["number"], 0)

# =====================================================================
# LED STRIP INFO DISPLAY FUNCTIONS
# =====================================================================

# Formats a value for display in LED strip info
# Parameters:
#   value: Value to format
# Returns:
#   Formatted string representation of the value
func format_value(value):
	# Format value based on type
	if value is String:
		return "\"" + value + "\""
	elif value is Dictionary:
		return "{ ... }"  # Abbreviate nested dictionaries
	elif value is Array:
		return "[ ... ]"  # Abbreviate arrays
	else:
		return str(value)

# Formats a dictionary as BBCode for display
# Parameters:
#   dict: Dictionary to format
# Returns:
#   BBCode formatted string representation of the dictionary
func format_dict_as_bbcode(dict):
	# Format dictionary
	var text = "[code]{\n"
	for key in dict:
		text += "  \"" + str(key) + "\": " + format_value(dict[key]) + ",\n"
		print("*"+str(key))
	text += "}[/code]\n\n"
	return text

# Displays information about an LED strip
# Parameters:
#   parent_container: Container to add the info display to
#   stripenr: Index of the LED strip
#   size: Number of LEDs in the strip
func show_ledStripeInfos(parent_container, stripenr, size):
	# Create heading for LED strip
	var board_label = Label.new()
	var strip_text
	strip_text = "Board: " + str(stripenr) + str("\n")
	strip_text += yamlparser.ledStripes[stripenr]["description"] + str("\n")
	strip_text += "LEDs:"+ str(size) + str("\n")
	board_label.text = strip_text
	board_label.add_theme_font_size_override("font_size", 14)
	parent_container.add_child(board_label)
	
	# Create RichTextLabel for this board
	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.custom_minimum_size = Vector2(400, 0)  # Fixed width, adaptable height
	parent_container.add_child(rtl)

	# Generate dictionary text
	var text = ""
	rtl.text = ""
	
	# Check if yamlparser.ledStripes[stripenr] exists and is a dictionary
	# Note: Board number != LED strip number - CHANGE THIS???
	if yamlparser.ledStripes[stripenr]:
		var board_data = yamlparser.ledStripes[stripenr]
		# Text output is currently disabled
		# text = format_dict_as_bbcode(board_data)
		rtl.text = text
	else:
		rtl.text = "no ledStripe found..."

# =====================================================================
# ALL LAMPS CONTROL FUNCTIONS
# =====================================================================

# Turns on all lamps when the "All On" button is pressed
func _on_all_on_button_pressed():
	var lampenguicontainer = get_node("/root/Main-Control/HBoxContainer/Split-Horizontal/TOP-GUI/Spalten/Lampen/Lamps")
	var lampscontainerparent = lampenguicontainer.get_children()
	
	# Iterate through all lamp containers
	for lampscontainer in lampscontainerparent:
		if lampscontainer is GridContainer:
			var lamps = lampscontainer.get_children()
			# Iterate through all lamp buttons
			for lampbutton in lamps:
				var lamp = lampbutton.get_meta("led_daten")
				if lamp["number"]:
					# Turn on each lamp
					libppuc.set_lamp_state(lamp["number"], 1)
					await get_tree().create_timer(0.05).timeout

# Turns off all lamps when the "All Off" button is pressed
func _on_all_off_button_pressed():
	print("ALL_LAMPS_OFF:")
	var lampenguicontainer = get_node("/root/Main-Control/HBoxContainer/Split-Horizontal/TOP-GUI/Spalten/Lampen/Lamps")
	var lampscontainerparent = lampenguicontainer.get_children()
	
	# Iterate through all lamp containers
	for lampscontainer in lampscontainerparent:
		if lampscontainer is GridContainer:
			var lamps = lampscontainer.get_children()
			# Iterate through all lamp buttons
			for lampbutton in lamps:
				var lamp = lampbutton.get_meta("led_daten")
				if lamp["number"]:
					# Turn off each lamp
					libppuc.set_lamp_state(lamp["number"], 0)
					await get_tree().create_timer(0.05).timeout

# =====================================================================
# FILTER TOGGLE FUNCTIONS
# =====================================================================

# Toggles GI lamps visibility
# Parameters:
#   toggled_on: Whether the GI toggle is turned on
func _on_gi_onoff_toggled(toggled_on):
	if toggled_on:
		lampfilter_gi = true
	else:
		lampfilter_gi = false
	create_lamps_blocks()

# Toggles flasher lamps visibility
# Parameters:
#   toggled_on: Whether the flasher toggle is turned on
func _on_flashonoff_toggled(toggled_on):
	if toggled_on:
		lampfilter_flasher = true
	else:
		lampfilter_flasher = false
	create_lamps_blocks()

# Toggles standard lamps visibility
# Parameters:
#   toggled_on: Whether the lamps toggle is turned on
func _on_lampsonoff_toggled(toggled_on):
	if toggled_on:
		lampfilter_lamps = true
	else:
		lampfilter_lamps = false
	create_lamps_blocks()

# =====================================================================
#  PPUC TEST FUNCTIONS
# =====================================================================

# Start the libppuc lamps test feature
func _on_lamp_test_pressed():
	libppuc.lamp_test()
