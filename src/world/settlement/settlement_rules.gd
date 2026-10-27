class_name SettlementRules
extends RefCounted
## T0 yerleşim kural kümesi (T-005; T-062 A2): `settlement.json` kontrol verisi + oyun bina tablosu
## (`data/library/game_buildings.json`: yalnız onaylı hero; yükleyici `SettlementTable`) -> modül tablosu, zone
## tablosu, bölge bantları, saat kulesi/meydan kuralları. Koordinat gömme yok; saf veri. `validate` bozuk veriyi
## (eksik aile/rol, bilinmeyen palet satırı, koordinat anahtarı, kimliği/katı olmayan modül) hata metniyle bildirir.
## Aile adları ve rolleri koda gömülü değildir: `settlement.json` `family_roles`.

const COORDINATE_KEYS: Array[String] = ["pos_km", "center_km", "anchor_km", "coast_path_km", "outline_km", "pos_m",
		"position"]
## Harita koordinatı sayılan sayı çifti eşiği (her iki bileşen >=).
const COORDINATE_PAIR_MIN := 1000.0
## Oyun tablosundaki kayıt biçimi (`imaro-game-set/1`, tablo "buildings").
const TABLE_FORMAT := "imaro-game-set/1"
## `generator_params.floors` bu değerse kat sayısı katalogda bilinmiyor demektir (A0 sözleşmesi).
const FLOORS_UNKNOWN := "unknown"

var control: Dictionary = {}
var modules: Array[SettlementModule] = []
var module_by_id: Dictionary = {}
var palette_rows: Dictionary = {}
## Aile adı -> rol sözlüğü (settlement.json `family_roles`).
var family_roles: Dictionary = {}
var zones: Dictionary = {}
var placement: Dictionary = {}
var tower: Dictionary = {}
var regions: Dictionary = {}
var overrides: Array = []
var fabric_zones: Dictionary = {}
var farm: Dictionary = {}
var main_street_bonus: Dictionary = {}
var wall_weights: Dictionary = {}
var roof_weights: Dictionary = {}
var house_roof_weights: Dictionary = {}
var shop_accent_rows: PackedInt32Array = PackedInt32Array()
var tile_rows: PackedInt32Array = PackedInt32Array()


static func from_control(settle_control: Dictionary, manifest: Dictionary) -> SettlementRules:
	var rules := SettlementRules.new()
	rules.control = settle_control.duplicate(true)
	rules.palette_rows = (settle_control.get("palette_rows", {}) as Dictionary).duplicate(true)
	rules.placement = (settle_control.get("placement", {}) as Dictionary).duplicate(true)
	rules.tower = (settle_control.get("tower", {}) as Dictionary).duplicate(true)
	rules.family_roles = (settle_control.get("family_roles", {}) as Dictionary).duplicate(true)
	rules.regions = (settle_control.get("regions", {}) as Dictionary).duplicate(true)
	rules.overrides = (settle_control.get("overrides", []) as Array).duplicate(true)
	rules.fabric_zones = (settle_control.get("fabric_zones", {}) as Dictionary).duplicate(true)
	rules.farm = (settle_control.get("farm", {}) as Dictionary).duplicate(true)
	rules.main_street_bonus = (settle_control.get("main_street_floor_bonus", {}) as Dictionary).duplicate(true)
	rules.wall_weights = rules._rows_weights(rules.placement.get("wall_row_weights", {}))
	rules.roof_weights = rules._rows_weights(rules.placement.get("roof_row_weights", {}))
	rules.house_roof_weights = rules._rows_weights(rules.placement.get("house_roof_row_weights", {}))
	var shop := PackedInt32Array()
	for row_name in rules.placement.get("gf_accent_rows", []):
		shop.append(rules.row_of(str(row_name)))
	rules.shop_accent_rows = shop
	var tiles := PackedInt32Array()
	for row_name in rules.placement.get("tile_rows", []):
		tiles.append(rules.row_of(str(row_name)))
	rules.tile_rows = tiles
	rules._build_modules(manifest)
	rules._build_zones(settle_control.get("zones", {}))
	return rules


## Kule durumu (`stats["tower"]`): "disabled" (kural kapalı), "none-approved" (onaylı landmark modülü yok: kule ve
## meydan atlanır; landmark uydurulmaz, T-062 A2 / ADR-0006 §3.2), "pending" (kural açık, modül var; "placed").
func tower_state() -> String:
	if not bool(tower.get("enabled", true)):
		return "disabled"
	if module(str(tower.get("module", ""))) == null:
		return "none-approved"
	return "pending"


## Palet satırı adı -> dizin (bilinmiyorsa -1).
func row_of(row_name: String) -> int:
	return int(palette_rows.get(row_name, -1))


func module(id: String) -> SettlementModule:
	return module_by_id.get(id, null)


func zone(name: StringName) -> SettlementZone:
	return zones.get(name, null)


## Satır adı -> ağırlık sözlüğünü dizin -> ağırlığa çevirir.
func _rows_weights(named: Dictionary) -> Dictionary:
	var out := {}
	for key: String in named:
		var row := row_of(key)
		if row >= 0:
			out[row] = float(named[key])
	return out


## Oyun tablosu `modules[]` -> SettlementModule. `idx` tablo sırasıdır (BuildingColumns.module_idx). Hero
## girdisinde palet
## yoktur (satır dizileri boş); kat `generator_params.floors`, bilinmiyorsa aile rolünün çalışma değeri.
func _build_modules(manifest: Dictionary) -> void:
	var idx := 0
	for entry: Dictionary in manifest.get("modules", []):
		if str(entry.get("kind", "")) in ["building", "landmark"]:
			var m := SettlementModule.new()
			m.idx = idx
			m.id = str(entry["id"])
			m.family = str(entry.get("family", ""))
			var gp: Dictionary = entry.get("generator_params", {})
			var role: Dictionary = family_roles.get(m.family, {})
			var floors_raw: Variant = gp.get("floors", FLOORS_UNKNOWN)
			if floors_raw is int or floors_raw is float:
				m.floors = int(floors_raw)
			else:
				m.floors = int(role.get("floors_unknown", 0))
				m.floors_working_value = true
			var fp: Array = entry.get("footprint_m", [0.0, 0.0])
			m.w = float(fp[0])
			m.d = float(fp[1])
			m.eave_m = float(gp.get("eave_height_m", entry.get("height_m", 0.0)))
			m.total_m = float(entry.get("height_m", m.eave_m))
			m.roof_type = StringName(str(gp.get("roof_type", "")))
			m.gf = bool(role.get("ground_shop", false))
			m.housing = bool(role.get("housing", false))
			m.floor_rule = bool(role.get("floor_rule", false))
			m.house = bool(role.get("house", false))
			m.industry = bool(role.get("industry", false))
			m.civic = bool(role.get("civic", false))
			m.heritage_eligible = bool(role.get("heritage_eligible", false))
			m.wide_allowed = bool(role.get("wide", false))
			m.wide_only = bool(role.get("wide_only", false))
			m.era = SettlementModule.era_code(str(entry.get("era", "")))
			var pal: Dictionary = entry.get("palette", {})
			m.wall_rows = _rows_of(pal.get("wall_rows", []))
			m.roof_rows = _rows_of(pal.get("roof_rows", []))
			m.accent_rows = _rows_of(pal.get("accent_rows", []))
			for row in m.roof_rows:
				m.tile_roof = m.tile_roof or tile_rows.has(row)
			modules.append(m)
			module_by_id[m.id] = m
		idx += 1


func _rows_of(names: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for n in names:
		out.append(row_of(str(n)))
	return out


func _build_zones(zone_control: Dictionary) -> void:
	for zname: String in zone_control:
		var zc: Dictionary = zone_control[zname]
		var z := SettlementZone.new()
		z.name = StringName(zname)
		z.floors_shift = float(zc.get("floors_shift", 0.0))
		z.floors_sigma = maxf(float(zc.get("floors_sigma", 1.3)), 0.1)
		z.gf_main = float(zc.get("gf_main", 1.0))
		z.gf_local = float(zc.get("gf_local", 1.0))
		var sb: Array = zc.get("setback_m", [0.3, 1.0])
		z.setback_min = float(sb[0])
		z.setback_max = float(sb[1])
		var gp: Array = zc.get("gap_m", [0.0, 0.4])
		z.gap_min = float(gp[0])
		z.gap_max = float(gp[1])
		z.adjacent = bool(zc.get("adjacent", true))
		z.units_max = maxi(1, int(zc.get("units_max", 2)))
		z.rows = maxi(1, int(zc.get("rows", 1)))
		z.second_row_p = float(zc.get("second_row_p", 0.7))
		var rg: Array = zc.get("row_gap_m", [3.0, 6.0])
		z.row_gap_min = float(rg[0])
		z.row_gap_max = float(rg[1])
		z.wide_p = float(zc.get("wide_p", 0.0))
		z.heritage_p = float(zc.get("heritage_p", 0.0))
		z.fill_p = float(zc.get("fill", -1.0))
		z.tile_cap = float(zc.get("tile_cap", 1.0))
		z.unique_combo = bool(zc.get("unique_combo", true))
		z.min_meshes = int(zc.get("min_window_meshes", 0))
		z.min_walls = int(zc.get("min_window_walls", 0))
		var id_weights: Dictionary = zc.get("id_weights", {})
		var fam_weights: Dictionary = zc.get("family_weights", {})
		var fam_names: Array = fam_weights.keys()
		fam_names.sort()
		for fam: String in fam_names:
			var members: Array[SettlementModule] = []
			for m in modules:
				if m.family == fam:
					members.append(m)
			for m in members:
				z.candidates.append(m)
				z.base_weights.append(float(fam_weights[fam]) / float(members.size()) * float(id_weights.get(m.id, 1.0)))
		var wide: Dictionary = zc.get("wide_weights", {})
		var wide_names: Array = wide.keys()
		wide_names.sort()
		for fam: String in wide_names:
			var members: Array[SettlementModule] = []
			for m in modules:
				if m.family == fam:
					members.append(m)
			for m in members:
				z.wide_modules.append(m)
				z.wide_weights.append(float(wide[fam]) / float(members.size()))
		zones[z.name] = z


## Veri sağlığı: hata metinleri (boş = geçerli). Üretimden önce çağrılır; testler de kullanır.
static func validate(settle_control: Dictionary, manifest: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key in ["palette_rows", "placement", "tower", "regions", "zones", "fabric_zones"]:
		if not settle_control.has(key):
			errors.append("eksik anahtar: %s" % key)
	if not errors.is_empty():
		return errors
	errors.append_array(scan_coordinates(settle_control))
	var rules := from_control(settle_control, manifest)
	if str(manifest.get("format", "")) != TABLE_FORMAT:
		errors.append("modül tablosu biçimi '%s' != '%s'" % [str(manifest.get("format", "")), TABLE_FORMAT])
	var families := {}
	for m in rules.modules:
		families[m.family] = true
		errors.append_array(_validate_module(m, rules.family_roles))
	for fam: String in families:
		if not rules.family_roles.has(fam):
			errors.append("family_roles: tablodaki aile '%s' için rol yok" % fam)
	for fam: String in rules.family_roles:
		if not families.has(fam):
			errors.append("family_roles: tabloda olmayan aile '%s'" % fam)
	var zone_control: Dictionary = settle_control["zones"]
	for zname: String in zone_control:
		_validate_zone(zname, zone_control[zname], families, rules.family_roles, errors)
	for code: String in settle_control["regions"]:
		_validate_region(code, settle_control["regions"][code], zone_control, errors)
	for fab: String in settle_control["fabric_zones"]:
		var target := str(settle_control["fabric_zones"][fab])
		if not zone_control.has(target) and target != "farm":
			errors.append("fabric_zones[%s]: bilinmeyen zone" % fab)
	for ov: Dictionary in settle_control.get("overrides", []):
		if not zone_control.has(str(ov.get("zone", ""))):
			errors.append("overrides: bilinmeyen zone '%s'" % str(ov.get("zone", "")))
	errors.append_array(_validate_palette_names(settle_control, rules))
	var tw: Dictionary = settle_control["tower"]
	# Boş modül = onaylı landmark yok ('none-approved'): kule atlanır. Dolu ama tabloda olmayan kimlik yazım
	# hatasıdır.
	if bool(tw.get("enabled", true)) and not str(tw.get("module", "")).is_empty() \
			and rules.module(str(tw.get("module", ""))) == null:
		errors.append("tower.module tabloda yok: %s" % str(tw.get("module", "")))
	for m in rules.modules:
		for rows in [m.wall_rows, m.roof_rows, m.accent_rows]:
			if (rows as PackedInt32Array).has(-1):
				errors.append("%s: palet satırı palette_rows içinde yok" % m.id)
	return errors


## Veri tarafındaki palet satırı adları (tile_rows, gf_accent_rows, satır ağırlıkları, kule duvar/çatı/vurgu)
## palette_rows'ta
## tanımlı olmalı: hero modüllerde palet yok, bu adlar yine de kural verisidir (palet taşıyan tablo dönerse çalışır).
static func _validate_palette_names(settle_control: Dictionary, rules: SettlementRules) -> PackedStringArray:
	var errors := PackedStringArray()
	var pl: Dictionary = settle_control["placement"]
	var names: Array = []
	for key in ["tile_rows", "gf_accent_rows"]:
		names.append_array(pl.get(key, []))
	for key in ["wall_row_weights", "roof_row_weights", "house_roof_row_weights"]:
		names.append_array((pl.get(key, {}) as Dictionary).keys())
	for key in ["wall", "roof", "accent"]:
		var tower_row := str((settle_control["tower"] as Dictionary).get(key, ""))
		if not tower_row.is_empty():
			names.append(tower_row)
	for n in names:
		if rules.row_of(str(n)) < 0:
			errors.append("palet satırı adı palette_rows içinde yok: %s" % str(n))
	return errors


## Modül başına şema denetimi: kimlik, aile, ayak izi, kat (sayı ya da rol çalışma değeri), saçak, çatı tipi, dönem.
static func _validate_module(m: SettlementModule, roles: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if m.family.is_empty():
		errors.append("%s: aile yok" % m.id)
	if m.w <= 0.0 or m.d <= 0.0:
		errors.append("%s: ayak izi geçersiz" % m.id)
	if m.floors < 1:
		errors.append("%s: kat sayısı yok (katalog '%s' ve family_roles.floors_unknown tanımsız)" % [m.id, FLOORS_UNKNOWN])
	if m.floors_working_value and not (roles.get(m.family, {}) as Dictionary).has("floors_unknown"):
		errors.append("%s: kat bilinmiyor ve aile rolünde floors_unknown yok" % m.id)
	if m.eave_m <= 0.0 or m.total_m <= 0.0:
		errors.append("%s: yükseklik alanları yok" % m.id)
	if m.roof_type == &"":
		errors.append("%s: çatı tipi yok" % m.id)
	if m.era == BuildingColumns.ERA_NONE:
		errors.append("%s: dönem yok" % m.id)
	return errors


static func _validate_zone(zname: String, zc: Dictionary, families: Dictionary, roles: Dictionary,
		errors: PackedStringArray) -> void:
	var fam_weights: Dictionary = zc.get("family_weights", {})
	if fam_weights.is_empty():
		errors.append("zone %s: family_weights boş" % zname)
	for fam: String in fam_weights:
		if not families.has(fam):
			errors.append("zone %s: manifestte olmayan aile '%s'" % [zname, fam])
		if bool((roles.get(fam, {}) as Dictionary).get("wide_only", false)):
			errors.append("zone %s: '%s' family_weights'te olamaz (wide_weights kullanın)" % [zname, fam])
		if float(fam_weights[fam]) < 0.0:
			errors.append("zone %s: negatif ağırlık (%s)" % [zname, fam])
	for key in ["setback_m", "gap_m"]:
		var rng: Array = zc.get(key, [0.0, 0.0])
		if rng.size() != 2 or float(rng[0]) > float(rng[1]) or float(rng[0]) < 0.0:
			errors.append("zone %s: %s [min,max] sıralı ve >= 0 olmalı" % [zname, key])
	var wide_p := float(zc.get("wide_p", 0.0))
	if wide_p < 0.0 or wide_p > 1.0:
		errors.append("zone %s: wide_p [0,1] dışında" % zname)
	var wide: Dictionary = zc.get("wide_weights", {})
	if wide_p > 0.0 and wide.is_empty():
		errors.append("zone %s: wide_p > 0 ama wide_weights boş" % zname)
	for fam: String in wide:
		if not families.has(fam) or not bool((roles.get(fam, {}) as Dictionary).get("wide", false)):
			errors.append("zone %s: wide_weights'te geçersiz aile '%s'" % [zname, fam])


static func _validate_region(code: String, rc: Dictionary, zone_control: Dictionary, errors: PackedStringArray) -> void:
	var last := -1.0
	var bands: Array = rc.get("bands", [])
	if bands.is_empty():
		errors.append("regions[%s]: bands boş" % code)
	for band: Dictionary in bands:
		var max_t := float(band.get("max_t", -1.0))
		if max_t <= last:
			errors.append("regions[%s]: bantlar max_t artan olmalı" % code)
		last = max_t
		if not zone_control.has(str(band.get("zone", ""))):
			errors.append("regions[%s]: bilinmeyen zone '%s'" % [code, str(band.get("zone", ""))])
	if last < 1.0:
		errors.append("regions[%s]: son bant t >= 1'i kapsamalı" % code)
	for key in ["floors", "fill"]:
		var f: Dictionary = rc.get(key, {})
		if not f.has("center") or not f.has("edge"):
			errors.append("regions[%s].%s: center/edge gerekli" % [code, key])
	var fill: Dictionary = rc.get("fill", {})
	for key in ["center", "edge"]:
		if float(fill.get(key, 0.0)) < 0.0 or float(fill.get(key, 0.0)) > 1.0:
			errors.append("regions[%s].fill.%s [0,1] dışında" % [code, key])


## Gömülü koordinat taraması (Q-015): koordinat anahtarları, harita-koordinatı gibi görünen sayı çiftleri (her iki
## bileşen >= 1000) ve konum anahtarları. Dönüş: hata metinleri (boş = temiz). Kural verisi koordinat içermez.
static func scan_coordinates(node: Variant, path: String = "") -> PackedStringArray:
	var errors := PackedStringArray()
	_scan_coordinates(node, path, errors)
	return errors


static func _scan_coordinates(node: Variant, path: String, errors: PackedStringArray) -> void:
	if node is Dictionary:
		for key: String in node:
			if COORDINATE_KEYS.has(key) or key == "x" or key == "z" or key == "lat" or key == "lon":
				errors.append("koordinat anahtarı gömülü: %s/%s" % [path, key])
			_scan_coordinates(node[key], "%s/%s" % [path, key], errors)
	elif node is Array:
		var arr: Array = node
		if arr.size() == 2 and _is_number(arr[0]) and _is_number(arr[1]) \
				and absf(float(arr[0])) >= COORDINATE_PAIR_MIN and absf(float(arr[1])) >= COORDINATE_PAIR_MIN:
			errors.append("koordinat çifti gibi sayı çifti: %s %s" % [path, str(arr)])
		for item in arr:
			_scan_coordinates(item, path, errors)


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
