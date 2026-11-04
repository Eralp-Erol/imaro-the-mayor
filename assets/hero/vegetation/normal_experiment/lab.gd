extends "res://assets/hero/vegetation/vegetation_lab.gd"
## Experimental imported asset; no lab material/normal replacement.


func _plant(asset: String, level: String, pos: Vector3) -> void:
	if asset != "plane" or level != "proxy":
		super._plant(asset, level, pos)
		return
	var scene := (
		load("res://assets/hero/vegetation/normal_experiment/plane_proxy.glb") as PackedScene
	)
	var plant := scene.instantiate() as Node3D
	plant.position = pos
	add_child(plant)


func _environment() -> void:
	super._environment()
	for child in get_children():
		if child is DirectionalLight3D:
			child.rotation_degrees.y += float(_args.get("sun_yaw_offset", "0"))
