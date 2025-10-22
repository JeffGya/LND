extends Node

## Entry point of Echoes of the Sankofa MVP
## Headless-friendly: allows passing /seed_info via command line argument
## Example:
##   godot --headless --main-pack echoes-mvp.pck --seed_info

func _ready() -> void:
	print("Echoes of the Sankofa — Main initialized.")

	# Detect CLI arguments for headless mode
	var args: Array = OS.get_cmdline_args()
	if args.has("--seed_info"):
		_run_headless_seed_info()
	else:
		# In normal mode, initialize systems or load main menu scene here
		print("No CLI flags detected. Starting standard runtime...")

func _run_headless_seed_info() -> void:
	print("[HEADLESS] Running /seed_info debug command...")
	var DebugConsole = preload("res://core/ui/debug/debug_console.gd").new()
	add_child(DebugConsole)
	DebugConsole.run_command("/seed_info")
	print("[HEADLESS] Seed info printed successfully.")
	get_tree().quit()  # terminate after printing
