# =====================================================================
# Parse_Config_Button.gd - Script for the Parse Config button
# =====================================================================
# This script handles the behavior of the "Parse Config" button in the PPUC interface.
# When pressed, it loads and parses the YAML configuration file and logs the results.
# =====================================================================

extends Button

# Called when the node enters the scene tree for the first time
func _ready():
	pass # No initialization needed

# Called every frame. 'delta' is the elapsed time since the previous frame
func _process(delta):
	pass # No per-frame processing needed

# Called when the button is pressed
# Parses the YAML configuration file and logs the results
func _on_pressed():
	# Clear existing data
	yamlparser.clear_Data()
	
	libppuc.debug_log("Parsing... YAML", "yellow")
	
	# Load YAML file and parse information
	yamlparser.load_yaml(libppuc.configpath)
	libppuc.debug_log("Parsing finished", "green")

	# Log the parsed data
	libppuc.debug_log("Results:", "green")
	
	# Log game information
	libppuc.debug_log("Game:", "yellow")
	for element in yamlparser.game.keys():
		libppuc.debug_log(element + ": " + str(yamlparser.game[element]), "white")
	
	# Log boards information
	libppuc.debug_log("Boards:" + str(yamlparser.boards.size()), "yellow")
	for element in yamlparser.boards:
		for element_boards in element.keys():
			libppuc.debug_log(str(element_boards) + ": " + str(element[element_boards]), "white")
	
	# Log LED strips information
	libppuc.debug_log("LED-Stripes:" + str(yamlparser.ledStripes.size()), "yellow")
	for element in yamlparser.ledStripes:
		for element_stripes in element.keys():
			libppuc.debug_log(str(element_stripes) + ": " + str(element[element_stripes]), "white")

	# Log LEDs information
	libppuc.debug_log("LEDS:" + str(yamlparser.leds.size()), "yellow")
	for element in yamlparser.leds:
		for element_leds in element.keys():
			libppuc.debug_log(str(element_leds) + ": " + str(element[element_leds]), "white")

	# Log coils information
	libppuc.debug_log("COILS:" + str(yamlparser.pwmOutput.size()), "yellow")
	for element in yamlparser.pwmOutput:
		for element_pwmoutput in element.keys():
			libppuc.debug_log(str(element_pwmoutput) + ": " + str(element[element_pwmoutput]), "white")

	# Log switches information
	libppuc.debug_log("SWITCHES:" + str(yamlparser.switches.size()), "yellow")
	for element in yamlparser.switches:
		for element_switches in element.keys():
			libppuc.debug_log(str(element_switches) + ": " + str(element[element_switches]), "white")
