# =====================================================================
# SetupGUI.gd
# =====================================================================
# This script handles the initial setup of the PPUC (Pinball Power-Up Controller) interface.
# It initializes the PPUC library with necessary parameters, sets up debugging,
# triggers configuration parsing, and initializes hardware components.
# =====================================================================

extends VBoxContainer

# Called when the node enters the scene tree for the first time.
func _ready():
	# Set communication port from UI text field
	libppuc.comport = $"../Steuerung/HBoxContainer/comport".text
	
	# Set path to the YAML configuration file from UI text field
	libppuc.configpath = $"../Steuerung/configpath".text
	
	# Initialize debug console with auto-scrolling enabled
	libppuc.setup_debug($"Log-Console/ScrollContainer/VBoxContainer/Console", true, true)
	
	# Trigger config file parsing by simulating a button press
	$"../Steuerung/ParseConfig".emit_signal("pressed")
	
	# Wait for configuration parsing to complete (3 seconds)
	await get_tree().create_timer(3).timeout
	
	# Initialize hardware components by simulating button presses
	$"../Steuerung/HBoxContainer2/SetLamps".emit_signal("pressed")    # Initialize lamps
	$"../Steuerung/HBoxContainer2/SetCoils".emit_signal("pressed")    # Initialize coils
	$"../Steuerung/HBoxContainer2/SetSwitches".emit_signal("pressed") # Initialize switches

	# Print parsed YAML data to the console for verification
	yamlparser.print_parsed_data()

# Called every frame. 'delta' is the elapsed time since the previous frame.
# Currently not used but kept for potential future frame-by-frame processing
func _process(delta):
	pass
