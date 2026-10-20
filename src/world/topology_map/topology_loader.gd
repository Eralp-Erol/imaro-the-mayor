class_name TopologyLoader
extends RefCounted
## Dünya + ağ + T0 yerleşimi + topoloji modeli üretimi (T-028). Tek yer: sahne, CLI ve testler aynı yolu kullanır.
## Üretilmiş hiçbir şey diske yazılmaz (Q-015: koordinat verisi commit'lenmez); her çalıştırmada tohumdan hesaplanır.

const DATA_DIR := "res://data/world/ismeral"
const MANIFEST_PATH := "res://assets/models/buildings/kit_manifest.json"
## T0 yerleşim tohumu (T-005 varsayılanı); dünya tohumundan ayrı bir akıştır.
const SETTLEMENT_SEED := 20261020


## {"model": TopologyModel, "world", "net", "result", "errors": PackedStringArray, "timings_ms": Dictionary}.
## `with_settlement = false` yoğunluk katmanını boş bırakır (hızlı önizleme).
static func load_all(world_seed: int = -1, with_settlement: bool = true, cell_size_m: float = -1.0) -> Dictionary:
	var timings := {}
	var control := WorldControlData.load_dir(DATA_DIR)
	var errors := WorldControlData.validate(control)
	if not errors.is_empty():
		return {"model": null, "errors": errors, "timings_ms": timings}
	var the_seed := world_seed if world_seed >= 0 else int(control["world"]["default_seed"])
	var overrides := {}
	if cell_size_m > 0.0:
		overrides["cell_size_m"] = cell_size_m
	var t0 := Time.get_ticks_msec()
	var world := WorldGenerator.generate(control, the_seed, overrides)
	timings["world"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var net := NetworkGenerator.generate(world, _read_json("%s/network.json" % DATA_DIR), the_seed)
	timings["network"] = Time.get_ticks_msec() - t0
	var result: SettlementResult = null
	if with_settlement:
		t0 = Time.get_ticks_msec()
		result = T0Settlement.generate_detailed(world, net, _read_json(MANIFEST_PATH), SETTLEMENT_SEED,
				_read_json("%s/settlement.json" % DATA_DIR))
		timings["settlement"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var model := TopologyModel.build(world, net, result)
	timings["model"] = Time.get_ticks_msec() - t0
	return {"model": model, "world": world, "net": net, "result": result, "errors": errors, "timings_ms": timings}


static func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
