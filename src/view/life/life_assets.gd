class_name LifeAssets
extends RefCounted
## Yaşam görünümünün varlıkları (T-050). Kimlikler YALNIZ `LibraryGate` (araç + insan oyun tabloları) üzerinden alınır:
## araç `veh_car` (D-012), insan `hum_hero_block_neutral_a` / `hum_hero_block_broad_a` (D-013, B blok figür). Başka kimlik
## istenirse kapı reddeder (`gate.unapproved_ids`); mesh/materyal yüklenmez. Piyon/faset ve eski kit insanı (`prop_human`)
## oyuna girmez.

const CAR_ID := "veh_car"
const HUMAN_IDS: Array[String] = ["hum_hero_block_neutral_a", "hum_hero_block_broad_a"]
const CAR_SHADER := "res://assets/shaders/mat_life_car.gdshader"
const HUMAN_SHADER := "res://assets/shaders/mat_life_human.gdshader"
## Palet satırı adı -> yerleşimin kullanacağı kit satırı dizini listesi; tablo `palette.wall_rows`ten gelir.
var car_rows: PackedInt32Array = PackedInt32Array()
var car_mesh: ArrayMesh = null
## [gövde (0 nötr, 1 geniş)][LOD (0/1)] -> mesh.
var human_mesh: Array = [[null, null], [null, null]]
var atlas: Texture2D = null
var gate: LibraryGate = null
var errors: PackedStringArray = PackedStringArray()
var loaded_ids: PackedStringArray = PackedStringArray()
var _car_roof_row: int = 0
var _car_accent_row: int = 0


## Kapıdan yükler. Kapı kapalı/kimlik reddedilirse `errors` dolu ve `ok()` false (çağıran görünümü kurmaz).
static func load_default(p_gate: LibraryGate = null) -> LifeAssets:
	var a := LifeAssets.new()
	a.gate = p_gate if p_gate != null else LibraryGate.load_life()
	a._load_car()
	a._load_humans()
	return a


func ok() -> bool:
	return errors.is_empty() and car_mesh != null and atlas != null and human_mesh[0][0] != null \
			and human_mesh[0][1] != null and human_mesh[1][0] != null and human_mesh[1][1] != null


func _load_car() -> void:
	var rec := gate.request(CAR_ID)
	if rec.is_empty():
		errors.append("%s kapıdan geçmedi" % CAR_ID)
		return
	var lod0 := (rec["lods"] as Dictionary)["LOD0"] as Dictionary
	car_mesh = HeroMeshLoader.load_mesh(str(lod0["glb"]), Vector3.ZERO)
	if car_mesh == null:
		errors.append("%s mesh yüklenemedi" % CAR_ID)
		return
	loaded_ids.append(CAR_ID)
	var pal := rec.get("palette", {}) as Dictionary
	for row_name in pal.get("wall_rows", []):
		var idx := KitMaterial.row_index(str(row_name))
		if idx >= 0:
			car_rows.append(idx)
	_car_roof_row = _first_row(pal.get("roof_rows", []))
	_car_accent_row = _first_row(pal.get("accent_rows", []))
	if car_rows.is_empty():
		errors.append("%s paletinde duvar satırı yok" % CAR_ID)


func _first_row(names: Array) -> int:
	for n in names:
		var idx := KitMaterial.row_index(str(n))
		if idx >= 0:
			return idx
	return 0


func _load_humans() -> void:
	for body in HUMAN_IDS.size():
		var rec := gate.request(HUMAN_IDS[body])
		if rec.is_empty():
			errors.append("%s kapıdan geçmedi" % HUMAN_IDS[body])
			continue
		var lods := rec["lods"] as Dictionary
		for lod in 2:
			var node := lods["LOD%d" % lod] as Dictionary
			var mesh := HeroMeshLoader.load_mesh(str(node["glb"]), Vector3.ZERO)
			if mesh == null:
				errors.append("%s LOD%d mesh yüklenemedi" % [HUMAN_IDS[body], lod])
			else:
				(human_mesh[body] as Array)[lod] = mesh
		loaded_ids.append(HUMAN_IDS[body])
		if atlas == null:
			var tex: Variant = load(str((rec["atlas"] as Dictionary)["path"]))
			atlas = tex as Texture2D
			if atlas == null:
				errors.append("insan atlası yüklenemedi")


## Araç materyali (kit paleti + hareket). Menzil/zaman uniform'ları görünüm tarafından güncellenir.
func make_car_material(movement: Dictionary) -> ShaderMaterial:
	var base := KitMaterial.create()
	var mat := ShaderMaterial.new()
	mat.resource_name = "mat_life_car"
	mat.shader = load(CAR_SHADER)
	for key in ["palette", "part_row", "part_mul"]:
		mat.set_shader_parameter(key, base.get_shader_parameter(key))
	mat.set_shader_parameter("roof_row", float(_car_roof_row))
	mat.set_shader_parameter("accent_row", float(_car_accent_row))
	_apply_movement(mat, float(movement["car_speed_mps"]), movement)
	return mat


func make_human_material(movement: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.resource_name = "mat_life_human"
	mat.shader = load(HUMAN_SHADER)
	mat.set_shader_parameter("atlas", atlas)
	_apply_movement(mat, float(movement["person_speed_mps"]), movement)
	return mat


func _apply_movement(mat: ShaderMaterial, speed: float, movement: Dictionary) -> void:
	mat.set_shader_parameter("life_speed", speed)
	mat.set_shader_parameter("life_spread", float(movement["speed_spread"]))
	mat.set_shader_parameter("life_end_fade", float(movement["end_fade_m"]))
