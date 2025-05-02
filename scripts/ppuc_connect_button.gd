# =====================================================================
# ppuc_connect_button.gd - Script for the PPUC Connect button
# =====================================================================
# This script handles the behavior of the PPUC Connect toggle button.
# When toggled on, it establishes a connection to the PPUC hardware.
# When toggled off, it disconnects from the hardware.
# =====================================================================

extends CheckButton

# Called when the node enters the scene tree for the first time
func _ready():
	# Create an empty style to remove focus visual
	var empty_style = StyleBoxEmpty.new()
	add_theme_stylebox_override("focus", empty_style)
	
	# Connect to libppuc signals for connection status
	libppuc.connected.connect(connected)
	libppuc.disconnected.connect(disconnected)
	
	# Set initial color to red (disconnected)
	self.modulate = Color.RED

# Called when the connection is successful
# Changes the button color to green to indicate connection
func connected():
	self.modulate = Color.GREEN

# Called when disconnected from the hardware
# Changes the button color to red to indicate disconnection
func disconnected():
	self.modulate = Color.RED

# Called every frame. 'delta' is the elapsed time since the previous frame
func _process(delta):
	pass # No per-frame processing needed

# Called when the button is toggled
# Connects to or disconnects from the PPUC hardware
# Parameters:
#   toggled_on: Whether the button is toggled on (connect) or off (disconnect)
func _on_toggled(toggled_on):
	print("- BEGIN CONNECTING -")
	
	# Change color to yellow to indicate operation in progress
	self.modulate = Color.YELLOW
	
	if toggled_on:
		# Setup PPUC and connect to hardware
		libppuc.setup_ppuc()
		await get_tree().create_timer(0.5).timeout
		libppuc.connect_to_hardware(libppuc.comport, libppuc.configpath)
	else:
		# Disconnect from hardware
		libppuc.disconnect_from_hardware()
