# =====================================================================
# set_switches_button.gd - Script for the Set Switches button
# =====================================================================
# This script handles the behavior of the "Set Switches" button in the PPUC interface.
# When pressed, it logs information about the switches configuration.
# =====================================================================

extends Button

# Called when the node enters the scene tree for the first time
func _ready():
	pass # No initialization needed

# Called every frame. 'delta' is the elapsed time since the previous frame
func _process(delta):
	pass # No per-frame processing needed

# Called when the button is pressed
# Logs the number of switches found in the configuration
func _on_pressed():
	libppuc.debug_log("SWITCHES:" + str(yamlparser.switches.size()), "yellow")
