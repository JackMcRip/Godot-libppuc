# =====================================================================
# PPUCYAMLparser.gd - YAML Configuration Parser for PPUC
# =====================================================================
# This parser reads and structures YAML data from elektra.yml configuration files
# for the Pinball Power-Up Controller (PPUC) system in Godot 4.4 format.
# 
# The parser extracts information about game settings, hardware boards,
# switches, LED strips, lamps, PWM outputs, and mechanical components.
# =====================================================================

extends Node

# =====================================================================
# DATA STRUCTURE VARIABLES
# =====================================================================
# Main data categories that store parsed configuration information

# Dictionary containing basic game settings (key-value pairs)
var game = {}

# Array of dictionaries, each representing a hardware board
var boards = []

# Dictionary for DIP switch settings
var dipSwitches = {}

# Array of dictionaries, each representing a switch
var switches = []

# Array of dictionaries, each representing an LED strip
var ledStripes = []

# Combined array of all LEDs (lamps, flashers, and GI)
var leds = []

# Array of dictionaries, each representing a PWM output
var pwmOutput = []

# Dictionary for mechanical components
var mechs = {}

# =====================================================================
# INITIALIZATION
# =====================================================================

# Called when the node enters the scene tree for the first time
func _ready():
	# Node is initially loaded without parsing any files
	pass

# Clears all data structures to prepare for loading a new configuration
func clear_Data():
	game = {}
	boards.clear()
	dipSwitches = {}
	switches.clear()
	ledStripes.clear()
	leds.clear()
	pwmOutput.clear()
	mechs = {}

# =====================================================================
# YAML LOADING AND PARSING
# =====================================================================

# Loads and parses a YAML configuration file
# Parameters:
#   YAML_PATH - Path to the YAML configuration file
func load_yaml(YAML_PATH):
	# Open the file in read mode
	var file = FileAccess.open(YAML_PATH, FileAccess.READ)
	
	# Check if the file was successfully opened
	if file == null:
		# If not, output an error message and exit the function
		print("Error opening file: ", FileAccess.get_open_error())
		return
	
	# Read the entire content of the file
	var content = file.get_as_text()
	
	# Close the file after reading
	file.close()
	
	# Parse the YAML file content
	parse_yamldata(content)

# =====================================================================
# YAML CONTENT PARSING
# =====================================================================

# Main parsing function that processes YAML content
# Parameters:
#   content - String containing YAML data to parse
func parse_yamldata(content):
	# Split the content into lines
	var lines = content.split("\n")
	
	# Variables for parsing state management
	var current_section = ""     # Current main group (game, boards, ledStripes, etc.)
	var in_ledstripe = false     # Flag indicating if we're inside an LED strip definition
	var in_subgroup = false      # Flag indicating if we're in a subgroup (lamps, flashers, gi)
	var current_ledstripe = null # Reference to the current LED strip dictionary
	var current_subgroup = ""    # Name of current subgroup in an LED strip
	var current_element = null   # Currently parsed element (board, switch, LED, etc.)
	
	# Process YAML file line by line
	var i = 0
	while i < lines.size():
		var line = lines[i]                 # Current line
		var trimmed_line = line.strip_edges() # Line with whitespace removed
		
		# Skip empty lines
		if trimmed_line.is_empty():
			i += 1
			continue
		
		# Calculate indentation level by counting spaces
		var spaces = 0
		for j in range(line.length()):
			if line[j] == " ":
				spaces += 1
			else:
				break
		
		# Convert spaces to indentation level (2 spaces = 1 level)
		# 0 spaces ÷ 2 = 0 (main group)
		# 2 spaces ÷ 2 = 1 (first indentation level)
		# 4 spaces ÷ 2 = 2 (second indentation level)
		# 6 spaces ÷ 2 = 3 (third indentation level)
		var indentation_level = spaces / 2
		
		# Process lines based on indentation level:
		
		# Main group (no indentation)
		if indentation_level == 0 and ":" in trimmed_line:
			current_section = trimmed_line.split(":")[0].strip_edges()
			in_ledstripe = false
			in_subgroup = false
			current_ledstripe = null
			current_subgroup = ""
			
			# Special handling for empty groups
			if trimmed_line.ends_with("{ }"):
				if current_section == "dipSwitches":
					dipSwitches = {}
				elif current_section == "mechs":
					mechs = {}
			# Handling for game group variables
			elif ":" in trimmed_line and current_section not in ["boards", "switches", "ledStripes", "pwmOutput"]:
				var parts = trimmed_line.split(":", true, 1)
				if parts.size() > 1 and parts[1].strip_edges() != "":
					game[parts[0].strip_edges()] = parse_value(parts[1].strip_edges())
		
		# New element at level 1 (directly under a main group)
		# The "-" character indicates a new element with multiple attributes
		elif trimmed_line == "-" and indentation_level == 1:
			current_element = {}
			
			# Add the element to the appropriate group based on current section
			match current_section:
				"boards":
					boards.append(current_element)
				"switches":
					switches.append(current_element)
				"ledStripes":
					current_ledstripe = {}
					ledStripes.append(current_ledstripe)
					current_element = current_ledstripe
					in_ledstripe = true  # Track that we're inside an LED strip
					in_subgroup = false  # Not in a subgroup yet
				"pwmOutput":
					pwmOutput.append(current_element)
		
		# Subgroup in an LED strip at level 2
		elif ":" in trimmed_line and indentation_level == 2 and in_ledstripe:
			var parts = trimmed_line.split(":", true, 1)
			var key = parts[0].strip_edges()
			var value = parts[1].strip_edges()
			
			# Check if this is a subgroup announcement (lamps, flashers, gi)
			if key in ["lamps", "flashers", "gi"] and (value == "" or value == "{" or value == "{ }"):
				current_subgroup = key
				in_subgroup = true
				
				# Skip empty subgroups
				if value == "{ }":
					in_subgroup = false
			else:
				# If not a subgroup, treat as a normal LED strip attribute
				if value != "" and value != "{" and value != "{ }":
					current_ledstripe[key] = parse_value(value)
		
		# LED element in a subgroup at level 3
		# A "-" at this level indicates a new LED
		elif trimmed_line == "-" and indentation_level == 3 and in_ledstripe and in_subgroup:
			# Create a new LED in the subgroup
			current_element = {}
			
			# Move to next line to start reading LED attributes
			i += 1
			
			# Collect all properties for this LED
			while i < lines.size():
				line = lines[i]
				spaces = 0
				for j in range(line.length()):
					if line[j] == " ":
						spaces += 1
					else:
						break
				
				# Check indentation level
				var next_indentation = spaces / 2
				trimmed_line = line.strip_edges()
				
				# End of LED properties is reached when indentation level is less than 4
				# or when the line is empty
				if next_indentation < 4 or trimmed_line.is_empty():
					break
				
				# Parse LED property
				if ":" in trimmed_line:
					var led_parts = trimmed_line.split(":", true, 1)
					var led_key = led_parts[0].strip_edges()
					var led_value = led_parts[1].strip_edges()
					
					if led_value != "":
						current_element[led_key] = parse_value(led_value)
				
				i += 1
			
			# Add metadata from parent LED strip to the LED
			current_element["board"] = current_ledstripe.get("board", 0)
			current_element["ledType"] = current_ledstripe.get("ledType", "")
			current_element["brightness"] = current_ledstripe.get("brightness", 0)
			current_element["lampType"] = current_subgroup
			
			# Add the LED to the leds list
			leds.append(current_element)
			
			# Go back one line since we incremented in the loop
			i -= 1
		
		# Regular key-value pairs
		elif ":" in trimmed_line and not trimmed_line.begins_with("-"):
			var parts = trimmed_line.split(":", true, 1)
			var key = parts[0].strip_edges()
			var value = parts[1].strip_edges() if parts.size() > 1 else ""
			
			# Process normal properties for an element
			if value != "" and value != "{" and value != "{ }":
				if current_element != null and indentation_level >= 1:
					current_element[key] = parse_value(value)
				elif current_section == "dipSwitches" and indentation_level == 1:
					dipSwitches[key] = parse_value(value)
				elif current_section == "mechs" and indentation_level == 1:
					mechs[key] = parse_value(value)
		
		i += 1  # Move to next line

# =====================================================================
# VALUE PARSING UTILITIES
# =====================================================================

# Converts string values to their appropriate types (int, float, bool, etc.)
# Parameters:
#   value_str - String value to convert
# Returns:
#   Parsed value in appropriate type (int, float, bool, string, etc.)
func parse_value(value_str: String):
	# Remove leading and trailing whitespace
	value_str = value_str.strip_edges()
	
	# Empty string
	if value_str.is_empty():
		return ""
	
	# Empty dictionary or array
	if value_str == "{ }" or value_str == "[]":
		return {}
	
	# Boolean values
	if value_str.to_lower() == "true":
		return true
	elif value_str.to_lower() == "false":
		return false
	
	# Numbers (integers and floats)
	if value_str.is_valid_int():
		return value_str.to_int()
	elif value_str.is_valid_float():
		return value_str.to_float()
	
	# Default: return as string
	return value_str

# =====================================================================
# DATA DISPLAY AND DEBUGGING
# =====================================================================

# Prints all parsed data to the console for debugging and verification
func print_parsed_data():
	# Divider for better readability
	print("\n=== Parsed YAML Data ===\n")
	
	# Print game group
	print("=== GAME ===")
	for key in game:
		print("%s: %s" % [key, str(game[key])])
	
	# Print boards group
	print("\n=== BOARDS ===")
	for i in range(boards.size()):
		print("Board %d:" % i)
		for key in boards[i]:
			print("  %s: %s" % [key, str(boards[i][key])])
	
	# Print dipSwitches group
	print("\n=== DIP SWITCHES ===")
	if dipSwitches.is_empty():
		print("  No DIP Switches defined")
	else:
		for key in dipSwitches:
			print("%s: %s" % [key, str(dipSwitches[key])])
	
	# Print switches group
	print("\n=== SWITCHES ===")
	for i in range(switches.size()):
		print("Switch %d:" % i)
		for key in switches[i]:
			print("  %s: %s" % [key, str(switches[i][key])])
	
	# Print leds group (contains lamps, flashers and gi)
	print("\n=== LEDS ===")
	for i in range(leds.size()):
		print("LED %d (%s):" % [i, leds[i].get("lampType", "unknown")])
		for key in leds[i]:
			print("  %s: %s" % [key, str(leds[i][key])])
	
	# Print ledStripes group
	print("\n=== LED STRIPES ===")
	for i in range(ledStripes.size()):
		print("LED Stripe %d:" % i)
		for key in ledStripes[i]:
			if key not in ["lamps", "flashers", "gi"]:  # Skip subgroups
				print("  %s: %s" % [key, str(ledStripes[i][key])])
	
	# Print pwmOutput group
	print("\n=== PWM OUTPUT ===")
	for i in range(pwmOutput.size()):
		print("PWM Output %d:" % i)
		for key in pwmOutput[i]:
			print("  %s: %s" % [key, str(pwmOutput[i][key])])
	
	# Print mechs group
	print("\n=== MECHS ===")
	if mechs.is_empty():
		print("  No mechanical components defined")
	else:
		for key in mechs:
			print("%s: %s" % [key, str(mechs[key])])

# =====================================================================
# UTILITY FUNCTIONS
# =====================================================================

# Finds dictionaries with a specific value in an array of dictionaries
# Parameters:
#   array_of_dictionaries - Array to search in
#   search_value - Value to search for
# Returns:
#   Array of indices of found dictionaries
func find_dictionaries_with_value(array_of_dictionaries, search_value):
	# Array to store the indices of found dictionaries
	var result_indices = []
	
	# Counter for the number of found dictionaries
	var count_found = 0

	# Iterate through each dictionary in the array
	for i in array_of_dictionaries.size():
		var current_dictionary = array_of_dictionaries[i]
		
		# Check if the dictionary has the key "board" and if its value matches the search value
		if current_dictionary.has("board") and current_dictionary["board"] == search_value:
			# Add the index to the result array
			result_indices.append(i)
			
			# Increment the counter
			count_found += 1

	# Output message based on the number of found dictionaries
	if count_found == 0:
		libppuc.debug_log("No dictionaries found with the value:" + str(search_value), "yellow")
	elif count_found == 1:
		libppuc.debug_log("Dictionary found with the value" + str(search_value) + "at index:" + str(result_indices[0]), "yellow")		
	else:
		libppuc.debug_log("Multiple dictionaries found with the value" + str(search_value) + "at indices:" + str(result_indices), "yellow")		

	# Return the indices of the found dictionaries
	return result_indices
