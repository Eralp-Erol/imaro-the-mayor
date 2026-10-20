class_name InvestorDecision
extends RefCounted
## Yatırımcı karar fonksiyonu (T-013 ölçüt 4, SIM-02): SAF, durumsuz, tamsayı. Girdi bir parsel için "bu projeyi yapar
## mıyım"
## koşullarıdır; çıktı ReasonRecord'a doğrudan verilecek etkenler, eşik, puan ve sonuç kodudur. Formüller ve gerekçeler:
## design/specs/economy-core-v0.md §4. Tüm sayılar `EconomyConfig`'ten gelir.
##
## Girdi sözlüğü (hepsi int, `zone_ok` bool): use, zone_ok, units, land_value, capital, infra_cap, infra_load (mevcut +
## boru hattı), demand_after_pm (proje arzı eklenmiş talep endeksi), rent_mult_pm (bugünkü kira çarpanı), sentiment
## (tohumlu gürültü, -sentiment_range..+sentiment_range), threshold_shift (yatırımcı risk istahı).
## Çıktı: {factors: [{name, value, weight, is_estimate}], threshold, score, positive, code (EconomyState.CODE_*),
## outlay, build_cost}. `score`/`positive` ReasonLog'un hesabıyla BİREBİR aynıdır (test): değişmez
## `olumlu <=> score >= threshold` yapıdan gelir.

const F_DEMAND := &"reason.factor.demand"
const F_RETURN := &"reason.factor.expected_return"
const F_COST := &"reason.factor.construction_cost"
const F_INFRA := &"reason.factor.infrastructure_capacity"
const F_FINANCING := &"reason.factor.financing"
const F_ZONING := &"reason.factor.zoning_fit"
const F_SENTIMENT := &"reason.factor.market_sentiment"
const VETO := -1000


@warning_ignore("integer_division")
static func decide(cfg: EconomyConfig, inp: Dictionary) -> Dictionary:
	var use: int = inp["use"]
	var units: int = inp["units"]
	var build_cost := units * cfg.use_param(use, "cost_per_unit")
	var outlay: int = build_cost + int(inp["land_value"])
	var annual_rent: int = units * cfg.use_param(use, "rent_per_unit_month") * 12 * int(inp["rent_mult_pm"]) / 1000
	var net_yield_pm := EconomyMath.ratio_pm(annual_rent, outlay) - cfg.p("interest_pm")
	var return_value := clampi(net_yield_pm * 1000 / cfg.p("yield_full_scale_pm"), -1000, 1000)
	var cost_value := -mini(1000, EconomyMath.ratio_pm(outlay, cfg.p("project_scale_ref")))
	var headroom: int = int(inp["infra_cap"]) - int(inp["infra_load"]) - units * cfg.use_param(use, "infra_per_unit")
	var infra_value := VETO if headroom < 0 \
		else mini(cfg.p("infra_bonus_max"), EconomyMath.ratio_pm(headroom, int(inp["infra_cap"])))
	var capital: int = inp["capital"]
	var financing_value := VETO if capital < outlay \
		else mini(cfg.p("financing_bonus_max"), EconomyMath.ratio_pm(capital - outlay, outlay))
	var zone_ok: bool = inp["zone_ok"] and units > 0
	var zoning_value := 0 if zone_ok else VETO
	var demand_value := EconomyMath.demand_value(int(inp["demand_after_pm"]))
	var factors: Array = [
		_factor(F_DEMAND, demand_value, cfg.p("w_demand"), false),
		_factor(F_RETURN, return_value, cfg.p("w_expected_return"), true),
		_factor(F_COST, cost_value, cfg.p("w_construction_cost"), true),
		_factor(F_INFRA, infra_value, cfg.p("w_infrastructure"), false),
		_factor(F_FINANCING, financing_value, cfg.p("w_financing"), false),
		_factor(F_ZONING, zoning_value, cfg.p("w_zoning"), false),
		_factor(F_SENTIMENT, int(inp["sentiment"]), cfg.p("w_sentiment"), true),
	]
	var score := 0
	for f: Dictionary in factors:
		score += SimContract.contribution(f["value"], f["weight"])
	var threshold: int = cfg.p("base_threshold") + int(inp["threshold_shift"])
	var positive := score >= threshold
	return {
		"factors": factors, "threshold": threshold, "score": score, "positive": positive,
		"code": _code(positive, zoning_value, infra_value, financing_value, factors),
		"outlay": outlay, "build_cost": build_cost,
	}


static func _factor(name: StringName, value: int, weight: int, is_estimate: bool) -> Dictionary:
	return {"name": name, "value": value, "weight": weight, "is_estimate": is_estimate}


## Olumlu: approved. Olumsuz: önce engel etkenleri (imar > altyapı > finansman); engel yoksa talep/getiri katkısı
## düşük olan (eşitlikte talep).
static func _code(positive: bool, zoning_value: int, infra_value: int, financing_value: int, factors: Array) -> int:
	if positive:
		return EconomyState.CODE_APPROVED
	if zoning_value == VETO:
		return EconomyState.CODE_ZONING
	if infra_value == VETO:
		return EconomyState.CODE_INFRASTRUCTURE
	if financing_value == VETO:
		return EconomyState.CODE_FINANCING
	var demand_part := SimContract.contribution(factors[0]["value"], factors[0]["weight"])
	var return_part := SimContract.contribution(factors[1]["value"], factors[1]["weight"])
	return EconomyState.CODE_DEMAND if demand_part <= return_part else EconomyState.CODE_RETURN
