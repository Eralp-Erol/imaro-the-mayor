class_name CitySave
extends RefCounted

static func save_game(sim: CitySimulation, path: String = "user://ilgin.save") -> Error:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_var(sim.snapshot(), false)
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path)

static func load_game(path: String = "user://ilgin.save") -> CitySimulation:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	var data: Variant = file.get_var(false)
	file.close()
	if not data is Dictionary: return null
	return CitySimulation.from_snapshot(data)
