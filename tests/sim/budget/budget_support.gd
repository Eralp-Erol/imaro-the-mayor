class_name BudgetSupport
extends RefCounted
## T-043C gösterge bütçe test yardımcıları (test paketi değildir). İki yapı: (1) yollu iki bölgeli dünya
## (`PublicWorksSupport`), (2) yolsuz fixture dünyası (`EconomyWorld`, gelir testleri). Beklenen değerler testte
## BAĞIMSIZ hesaplanır (yapılandırmadan okunan sayılarla), üretim koduna çağrı yapılmaz.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const W := preload("res://tests/sim/economy/economy_world.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
const CONFIG_PATH := "res://data/sim/budget/budget_config.json"
## Fixture dünyasında tek parsel imarlanınca konut/ticaret inşaatı (periyodik tarama kapalı; ekonomi testleriyle aynı).
const PATCH := {
	"decision": {"review_enabled": 0},
	"regions": {"overrides": {"F1": {"initial_households": 400, "infra_capacity_units": 2000}}},
}


static func raw_config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))


static func config(patch: Dictionary = {}) -> BudgetConfig:
	var cfg := BudgetConfig.from_dict(S.merge(raw_config(), patch))
	assert(cfg.is_valid(), "bütçe test yapılandırması geçersiz: %s" % cfg.error)
	return cfg


## Yollu dünya + gösterge bütçe. `attach=false`: bütçesiz karşılaştırma koşusu.
static func road_run(world_seed: int = P.SEED, budget_patch: Dictionary = {}, attach: bool = true) -> Dictionary:
	var run := P.setup(world_seed)
	if attach:
		assert((run["facade"] as SimFacadeImpl).attach_budget(config(budget_patch)), "attach_budget başarısız")
	return run


## Yolsuz fixture dünyası + gösterge bütçe.
static func fixture_handle(budget_patch: Dictionary = {}, attach: bool = true, world_seed: int = S.SEED) \
		-> EconomyHandle:
	var h := W.handle(PATCH, world_seed)
	if attach:
		assert(h.facade.attach_budget(config(budget_patch)), "attach_budget başarısız")
	return h


static func economy_cfg() -> EconomyConfig:
	return S.config()


## Beklenen yol gideri: birim x cost_per_unit(kullanım) x pay / 1000 (sıfıra doğru kesme).
@warning_ignore("integer_division")
static func expected_road_cost(units_total: int, cfg: BudgetConfig) -> int:
	var unit_cost := economy_cfg().use_param(EconomyState.use_id(cfg.road_cost_use), "cost_per_unit")
	return units_total * unit_cost * cfg.public_cost_share_pm / 1000


## Beklenen aylık gelir: Σ(biten birim x kira) x oran / 1000, ekonomi sonuç özetinden.
@warning_ignore("integer_division")
static func expected_revenue(f: SimFacadeImpl, cfg: BudgetConfig) -> int:
	var o := f.economy_outcome()
	var ec := economy_cfg()
	var base := 0
	for r in o.regions:
		base += r.residential_units * ec.use_param(EconomyConfig.USE_RESIDENTIAL, "rent_per_unit_month")
		base += r.commercial_units * ec.use_param(EconomyConfig.USE_COMMERCIAL, "rent_per_unit_month")
	return base * cfg.tax_rate_pm / 1000


static func road_units(f: SimFacadeImpl, index: int = -1) -> int:
	var works := f.public_works()
	var work: PublicWorkView = works[index if index >= 0 else works.size() - 1]
	var total := 0
	for code: Variant in work.region_units:
		total += int(work.region_units[code])
	return total


static func line_amount(f: SimFacade, key: StringName = &"budget.line.roads") -> int:
	var l := f.snapshot().budget.line(key)
	return -999999 if l == null else l.amount
