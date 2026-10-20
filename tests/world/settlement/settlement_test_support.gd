class_name SettlementTestSupport
extends RefCounted
## tests/world/settlement ortak yardımcıları (test paketi değildir). Gerçek Ismeral ağı + yerleşim bir kez üretilir ve
## salt okunur paylaşılır (`full`); olumsuz/determinizm testleri küçültülmüş (`light`) ağ üzerinde çalışır.

const CONTROL_PATH := "res://data/world/ismeral/settlement.json"
const MANIFEST_PATH := "res://assets/models/buildings/kit_manifest.json"
const PALETTE_PATH := "res://assets/kit/kit_palette.json"
const SEED := 20261020

static var _full: SettlementResult = null
static var _light: SettlementResult = null


static func control() -> Dictionary:
	return _read(CONTROL_PATH)


static func manifest() -> Dictionary:
	return _read(MANIFEST_PATH)


static func palette() -> Dictionary:
	return _read(PALETTE_PATH)


static func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func rules(settle_control: Dictionary = {}) -> SettlementRules:
	return SettlementRules.from_control(settle_control if not settle_control.is_empty() else control(), manifest())


## Tam Ismeral ağı (100 m dünya) üzerinde varsayılan yerleşim; süreç başına bir kez. SALT OKUNUR.
static func full() -> SettlementResult:
	if _full == null:
		_full = T0Settlement.generate_detailed(WorldTestSupport.default_world(), NetworkTestSupport.default_network(),
				manifest(), SEED, control())
	return _full


## Küçültülmüş ağ üzerinde yerleşim (varsayılan kontrol); süreç başına bir kez. SALT OKUNUR.
static func light() -> SettlementResult:
	if _light == null:
		_light = light_with(SEED, control())
	return _light


static func light_with(settle_seed: int, settle_control: Dictionary) -> SettlementResult:
	return T0Settlement.generate_detailed(WorldTestSupport.default_world(), NetworkTestSupport.light_network(),
			manifest(), settle_seed, settle_control)


## Verilen ağ üzerinde (kendi WorldData'sıyla) yerleşim.
static func generate_on(net: WorldNetwork, settle_seed: int, settle_control: Dictionary) -> SettlementResult:
	return T0Settlement.generate_detailed(net.world, net, manifest(), settle_seed, settle_control)


static func net_full() -> WorldNetwork:
	return NetworkTestSupport.default_network()


static func net_light() -> WorldNetwork:
	return NetworkTestSupport.light_network()
