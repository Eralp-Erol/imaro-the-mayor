extends SceneTree
## Dev aracı: dünya üretir, süreyi ölçer, maske/rölyef PNG'lerini yazar (T-001 ölçüt 2-3 kendi kendine doğrulama).
## Kullanım:
##   tools/godot.sh --headless --path . -s res://src/world/world_preview_cli.gd -- [seed] [cell_size_m] [out_dir]
## Çıktı: <out_dir>/ismeral-mask.png, ismeral-relief.png
## (varsayılan: artifacts/screenshots/captures/world-preview, git ignore altında).
## Süre ölçümü Time kullanır; bu bir araçtır, üreteç saf kalır.

const DATA_DIR := "res://data/world/ismeral"
const DEFAULT_OUT_DIR := "artifacts/screenshots/captures/world-preview"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var control := WorldControlData.load_dir(DATA_DIR)
	var errors := WorldControlData.validate(control)
	if not errors.is_empty():
		push_error("kontrol verisi geçersiz: %s" % ", ".join(errors))
		quit(1)
		return
	var world_seed := int(args[0]) if args.size() > 0 else int(control["world"]["default_seed"])
	var overrides := {}
	if args.size() > 1:
		overrides["cell_size_m"] = float(args[1])
	var out_dir := ProjectSettings.globalize_path("res://%s" % DEFAULT_OUT_DIR)
	if args.size() > 2:
		out_dir = args[2]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var t0 := Time.get_ticks_msec()
	var world := WorldGenerator.generate(control, world_seed, overrides)
	var t1 := Time.get_ticks_msec()
	var hash := world.state_hash()
	var t2 := Time.get_ticks_msec()
	print("generate: %d ms (%dx%d samples, cell %.0f m) · state_hash: %d ms · %s" % [
		t1 - t0, world.width, world.height, world.cell_size, t2 - t1, hash])
	var violations := WorldInvariants.check_all(world)
	print("invariant violations: %d" % violations.size())
	for v in violations:
		print("  - %s" % v)

	var scale := maxi(1, int(round(1000.0 / maxf(world.width, 1.0))))
	WorldPreview.render(world, WorldPreview.Mode.MASK, scale).save_png("%s/ismeral-mask.png" % out_dir)
	WorldPreview.render(world, WorldPreview.Mode.RELIEF, scale).save_png("%s/ismeral-relief.png" % out_dir)
	print("png: %s" % out_dir)
	quit(0)
