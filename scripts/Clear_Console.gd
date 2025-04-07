# =====================================================================
# Clear_Console.gd - Script for the Clear Console button
# =====================================================================
# This script handles the behavior of the "Clear Console" button in the PPUC interface.
# When pressed, it clears the debug console output.
# =====================================================================

extends Button

# Called when the node enters the scene tree for the first time
func _ready():
	pass # No initialization needed

# Called every frame. 'delta' is the elapsed time since the previous frame
func _process(delta):
	pass # No per-frame processing needed

# Called when the button is pressed
# Clears the debug console output
func _on_pressed():
	libppuc.clear_debug_output()
