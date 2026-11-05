extends SceneTree
## B-028 olcum probu: --demo kare-60 kayit/yukleme smoke kancasinin parcalarini (hash/export/import/resync) zamanlar.
## Kullanim:
## tools/godot.sh --path . --resolution 1600x900 --script res://tools/godot/b028_smoke_probe.gd --
##   --demo --no-smoke-save-load

var _scene: Node = null


func _initialize() -> void:
	run.call_deferred()


func _ms(t0: int) -> float:
	return snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)


func run() -> void:
	var packed: PackedScene = load("res://scenes/game/playable.tscn")
	_scene = packed.instantiate()
	root.add_child(_scene)
	for i in 70:
		await process_frame
	var impl := _scene._facade as SimFacadeImpl
	var t := Time.get_ticks_usec()
	var h0 := impl.state_hash()
	print("B028 state_hash_ms=", _ms(t))
	t = Time.get_ticks_usec()
	var bytes := impl.export_save()
	print("B028 export_ms=", _ms(t), " bytes=", bytes.size())
	t = Time.get_ticks_usec()
	var res := SimSave.decode(bytes)
	print("B028 decode_ms=", _ms(t), " ok=", res.ok)
	t = Time.get_ticks_usec()
	var loaded := impl.import_save(bytes)
	print("B028 import_total_ms=", _ms(t), " ok=", loaded.ok)
	t = Time.get_ticks_usec()
	_scene.resync_sim_buildings_after_load()
	print("B028 resync_ms=", _ms(t))
	t = Time.get_ticks_usec()
	var h1 := impl.state_hash()
	print("B028 state_hash2_ms=", _ms(t), " eq=", h0 == h1)
	quit(0)
