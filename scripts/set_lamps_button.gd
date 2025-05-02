# =====================================================================
# set_lamps_button.gd - Script for the Set Lamps button
# =====================================================================
# This script handles the behavior of the "Set Lamps" button in the PPUC interface.
# When pressed, it triggers the creation of the lamps GUI blocks.
# =====================================================================

extends Button

# Called when the node enters the scene tree for the first time
func _ready():
	pass # No initialization needed

# Called every frame. 'delta' is the elapsed time since the previous frame
func _process(delta):
	pass # No per-frame processing needed

# Called when the button is pressed
# Creates lamp blocks in the interface
func _on_pressed():
	lampsgui.create_lamps_blocks()

# Called when the mouse control toggle is changed
# Enables/disables automatic lamp state changes on mouse hover
# Parameters:
#   toggled_on: Whether the mouse control is enabled
func _on_mouse_on_toggled(toggled_on):
	lampsgui.mouse_set_on = toggled_on
