# =====================================================================
# set_coils_button.gd - Script for the Set Coils button
# =====================================================================
# This script handles the behavior of the "Set Coils" button in the PPUC interface.
# When pressed, it triggers a test of all PWM outputs in sequence.
# =====================================================================

extends Button

# Called when the node enters the scene tree for the first time
func _ready():
	pass # No initialization needed

# Called every frame. 'delta' is the elapsed time since the previous frame
func _process(delta):
	pass # No per-frame processing needed

# Called when the button is pressed - empty because the actual functionality
# is in pwmOutput_test which is called from elsewhere
func _on_pressed():
	pass

# Tests all PWM outputs by activating them one by one
# This is a sequence test that activates each coil briefly and then deactivates it
func pwmOutput_test():
	libppuc.debug_log("Loading coils", "green")
	for pwm in yamlparser.pwmOutput:
		print("#######################")
		print("Voltage on Output Number:" + str(pwm["number"]))
		print("Board: " + str(pwm["board"]) + "   Port: " + str(pwm["port"]))
		libppuc.debug_log("Voltage on Output Number:" + str(pwm["number"]), "orange")
		libppuc.debug_log("Board: " + str(pwm["board"]) + "   Port: " + str(pwm["port"]), "orange")
		
		# Activate the solenoid
		libppuc.set_solenoid_state(pwm["number"], 1)
		
		# Wait 1 second
		await get_tree().create_timer(1).timeout
		
		# Deactivate the solenoid
		libppuc.set_solenoid_state(pwm["number"], 0)
		libppuc.debug_log("Voltage Off:" + str(pwm["number"]), "green")
