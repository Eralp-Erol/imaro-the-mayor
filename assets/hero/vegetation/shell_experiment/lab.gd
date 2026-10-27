extends "res://assets/hero/vegetation/vegetation_lab.gd"
## Candidate material is supplied by its real GLB import, never a lab override.


func _plant(asset: String, level: String, pos: Vector3) -> void:
	if asset != "plane" or level != "proxy":
		super._plant(asset, level, pos)
		return
	var scene := (
		load("res://assets/hero/vegetation/shell_experiment/plane_shell.glb") as PackedScene
	)
	var candidate := scene.instantiate() as Node3D
	candidate.position = pos
	add_child(candidate)


func _environment() -> void:
	super._environment()
	for child in get_children():
		if child is DirectionalLight3D:
			child.rotation_degrees.y += float(_args.get("sun_yaw_offset", "0"))
