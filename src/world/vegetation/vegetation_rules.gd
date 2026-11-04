class_name VegetationRules
extends RefCounted
## `data/world/ismeral/vegetation.json` yükleyici + doğrulayıcı (T-062 B0). Yerleşim parametreleri VERİDİR (art-director
## ayarlar); kodda sihirli sayı/tür kimliği yok. Tür anahtarları oyun bitki tablosuna (`VegetationSpecies`) karşı
## doğrulanır: tabloda olmayan (onaysız/bilinmeyen) anahtar kullanan kural geçersizdir ve yerleşim üretmez.

const PATH := "res://data/world/ismeral/vegetation.json"
const SCHEMA_VERSION := 1
const GROUP_FIELD_ROAD := "field_road"
const ROAD_CLASSES: Array[String] = ["arterial", "collector", "local", "field"]

## Ham kontrol verisi (derin kopya).
var cfg: Dictionary = {}
var species: VegetationSpecies = null
## Tür dizini -> ölçek aralığı.
var scale_lo: PackedFloat32Array = PackedFloat32Array()
var scale_hi: PackedFloat32Array = PackedFloat32Array()
## Ad -> PackedFloat32Array (tür dizinine göre ağırlık): street.weights, yard.groups, palm.weights.
var street_weights: Dictionary = {}
var yard_weights: Dictionary = {}
var palm_weights: PackedFloat32Array = PackedFloat32Array()
var coast_weights: PackedFloat32Array = PackedFloat32Array()
var pocket_weights: PackedFloat32Array = PackedFloat32Array()
## rural.classes[k].weights -> PackedFloat32Array.
var rural_weights: Array[PackedFloat32Array] = []
var errors: PackedStringArray = PackedStringArray()


static func load_path(path: String, p_species: VegetationSpecies) -> VegetationRules:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var control: Dictionary = parsed if parsed is Dictionary else {}
	return from_control(control, p_species)


static func from_control(control: Dictionary, p_species: VegetationSpecies) -> VegetationRules:
	var rules := VegetationRules.new()
	rules.cfg = control.duplicate(true)
	rules.species = p_species
	rules.errors = validate(rules.cfg, p_species)
	if rules.errors.is_empty():
		rules._compile()
	return rules


## Hata metinleri (boş = geçerli).
static func validate(control: Dictionary, p_species: VegetationSpecies) -> PackedStringArray:
	var out := PackedStringArray()
	if control.is_empty():
		out.append("vegetation.json okunamadı/boş")
		return out
	if int(control.get("schema_version", 0)) != SCHEMA_VERSION:
		out.append("schema_version != %d" % SCHEMA_VERSION)
	for section in ["budget", "terrain", "clearance", "species", "sidewalk_m", "zone_groups", "palm", "street",
			"yard", "hedge", "grove", "clusters", "coast", "rural"]:
		if not (control.get(section) is Dictionary):
			out.append("bölüm yok: %s" % section)
	if not out.is_empty():
		return out
	if p_species == null or p_species.size() == 0:
		out.append("oyun bitki tablosu boş/kapalı (LibraryGate): yerleşim üretilemez")
		return out
	_validate_budget(control, out)
	_validate_species(control, p_species, out)
	_validate_weights(control, p_species, out)
	_validate_numbers(control, out)
	return out


static func _validate_budget(control: Dictionary, out: PackedStringArray) -> void:
	var budget: Dictionary = control["budget"]
	var order: Array = budget.get("layer_order", [])
	var names: Array = []
	for n in VegetationColumns.LAYER_NAMES:
		names.append(String(n))
	var sorted_order := order.duplicate()
	sorted_order.sort()
	var sorted_names := names.duplicate()
	sorted_names.sort()
	if sorted_order != sorted_names:
		out.append("budget.layer_order katman adlarının bir permütasyonu olmalı: %s" % str(names))
	if int(budget.get("max_instances", 0)) <= 0:
		out.append("budget.max_instances > 0 olmalı")
	var caps: Dictionary = budget.get("layer_caps", {})
	for n: String in names:
		if int(caps.get(n, -1)) < 0:
			out.append("budget.layer_caps.%s eksik/negatif" % n)


static func _validate_species(control: Dictionary, p_species: VegetationSpecies, out: PackedStringArray) -> void:
	var specs: Dictionary = control["species"]
	for key: String in specs:
		if not p_species.has_key(key):
			out.append("species.%s oyun bitki tablosunda yok (onaysız/bilinmeyen)" % key)
			continue
		var sc: Array = (specs[key] as Dictionary).get("scale", [])
		if sc.size() != 2 or float(sc[0]) <= 0.0 or float(sc[0]) > float(sc[1]):
			out.append("species.%s.scale [lo, hi] 0 < lo <= hi olmalı" % key)
	for i in p_species.size():
		if not specs.has(p_species.keys[i]):
			out.append("species.%s için ölçek aralığı yok" % p_species.keys[i])
	for required in ["hedge", "olive_open", "olive_twisted"]:
		if not p_species.has_key(required):
			out.append("tabloda '%s' türü yok" % required)
	if p_species.size() > VegetationColumns.MAX_SPECIES:
		out.append("tür sayısı %d > %d" % [p_species.size(), VegetationColumns.MAX_SPECIES])


static func _validate_weights(control: Dictionary, p_species: VegetationSpecies, out: PackedStringArray) -> void:
	var groups: Dictionary = (control["street"] as Dictionary).get("weights", {})
	var lists: Array[Array] = []
	for g: String in groups:
		lists.append(["street.weights.%s" % g, groups[g]])
	var yard_groups: Dictionary = (control["yard"] as Dictionary).get("groups", {})
	for g: String in yard_groups:
		lists.append(["yard.groups.%s" % g, yard_groups[g]])
	lists.append(["palm.weights", (control["palm"] as Dictionary).get("weights", {})])
	lists.append(["coast.weights", (control["coast"] as Dictionary).get("weights", {})])
	lists.append(["rural.olive_pocket.weights",
			((control["rural"] as Dictionary).get("olive_pocket", {}) as Dictionary).get("weights", {})])
	for k in ((control["rural"] as Dictionary).get("classes", []) as Array).size():
		var cls: Dictionary = (control["rural"] as Dictionary)["classes"][k]
		lists.append(["rural.classes[%d].weights" % k, cls.get("weights", {})])
	for item in lists:
		var w: Dictionary = item[1] if item[1] is Dictionary else {}
		var total := 0.0
		for key: String in w:
			if not p_species.has_key(key):
				out.append("%s: tür '%s' oyun bitki tablosunda yok" % [item[0], key])
			elif float(w[key]) < 0.0:
				out.append("%s.%s negatif" % [item[0], key])
			else:
				total += float(w[key])
		if total <= 0.0:
			out.append("%s: ağırlık toplamı 0" % item[0])
	for zone: String in (control["zone_groups"] as Dictionary):
		var g := str((control["zone_groups"] as Dictionary)[zone])
		if not groups.has(g):
			out.append("zone_groups.%s -> '%s' street.weights'te yok" % [zone, g])
	if not groups.has(GROUP_FIELD_ROAD) or not groups.has("rural"):
		out.append("street.weights 'rural' ve 'field_road' gruplarını içermeli")
	for zone: String in ((control["yard"] as Dictionary).get("zones", {}) as Dictionary):
		var yz: Dictionary = control["yard"]["zones"][zone]
		if not yard_groups.has(str(yz.get("group", ""))):
			out.append("yard.zones.%s.group '%s' yard.groups'ta yok" % [zone, str(yz.get("group", ""))])
		if not (yz.has("per_ha") or yz.has("per_building")):
			out.append("yard.zones.%s: per_ha ya da per_building gerekli" % zone)


static func _validate_numbers(control: Dictionary, out: PackedStringArray) -> void:
	var terrain: Dictionary = control["terrain"]
	var cliff := float(terrain.get("cliff_deg", 0.0))
	for layer_name: String in (terrain.get("max_slope_deg", {}) as Dictionary):
		if float(terrain["max_slope_deg"][layer_name]) > cliff:
			out.append("terrain.max_slope_deg.%s > cliff_deg" % layer_name)
	for layer_name in VegetationColumns.LAYER_NAMES:
		if not (terrain.get("max_slope_deg", {}) as Dictionary).has(String(layer_name)):
			out.append("terrain.max_slope_deg.%s eksik" % String(layer_name))
	var cl: Dictionary = control["clusters"]
	if float(cl.get("lo", 1.0)) >= float(cl.get("hi", 0.0)):
		out.append("clusters.lo < hi olmalı")
	for cls: String in ROAD_CLASSES:
		if not ((control["street"] as Dictionary).get("classes", {}) as Dictionary).has(cls):
			out.append("street.classes.%s eksik" % cls)
		if not (control["sidewalk_m"] as Dictionary).has(cls):
			out.append("sidewalk_m.%s eksik" % cls)
	if float(control["clearance"].get("sep_frac", -1.0)) < 0.0:
		out.append("clearance.sep_frac eksik")
	var max_sep_cell := float(control["clearance"].get("room_cap_m", 0.0))
	if max_sep_cell <= 0.0:
		out.append("clearance.room_cap_m > 0 olmalı")
	if float(control["grove"].get("max_per_grove", 0)) <= 0.0:
		out.append("grove.max_per_grove > 0 olmalı")


func _compile() -> void:
	var n := species.size()
	scale_lo.resize(n)
	scale_hi.resize(n)
	for i in n:
		var sc: Array = cfg["species"][species.keys[i]]["scale"]
		scale_lo[i] = float(sc[0])
		scale_hi[i] = float(sc[1])
	for g: String in (cfg["street"]["weights"] as Dictionary):
		street_weights[g] = weights_of(cfg["street"]["weights"][g])
	for g: String in (cfg["yard"]["groups"] as Dictionary):
		yard_weights[g] = weights_of(cfg["yard"]["groups"][g])
	palm_weights = weights_of(cfg["palm"]["weights"])
	coast_weights = weights_of(cfg["coast"]["weights"])
	pocket_weights = weights_of(cfg["rural"]["olive_pocket"]["weights"])
	rural_weights.clear()
	for cls: Dictionary in cfg["rural"]["classes"]:
		rural_weights.append(weights_of(cls["weights"]))


## {tür anahtarı: ağırlık} -> tür dizinine göre PackedFloat32Array.
func weights_of(w: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(species.size())
	for key: String in w:
		var idx := species.index_of(key)
		if idx >= 0:
			out[idx] = float(w[key])
	return out


func is_valid() -> bool:
	return errors.is_empty()
