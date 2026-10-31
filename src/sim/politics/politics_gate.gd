class_name PoliticsGate
extends ProposalGate
## Öneri kapısı (T-017, Q-014): `requires_council` verisi doğruysa oyuncunun imar/bütçe önerisi doğrudan yürürlüğe
## girmez, meclis oylamasına gider; kabul edilirse koşul (pending_zone) yazılır, reddedilirse hiçbir şey olmaz. Veri
## yanlışsa kapı hiçbir şey yapmaz (öneri doğrudan yürürlüğe girer). Her iki yol da testlidir.
##
## D-011 Soru 4 ("İkisi de, seçenek": küçük plan doğrudan, BÜYÜK plan meclise): `council.plan_council_min_parcels` /
## `plan_council_min_units` (CALISMA DEGERI; 0 = ölçüt kapalı) > 0 ise imar planı yalnız BÜYÜKSE meclise gider
## (parsel sayısı >= min_parcels YA DA önizleme toplam birimi >= min_units). İkisi de 0 iken bayrak tek başına karar
## verir (eski davranış bit-bit). `requires_council.zoning.propose=false` iken hiçbir plan meclise gitmez.

const ROUTE_LARGE := "plan.council_large"

var _ctx: PoliticsContext
## Toplam birim ölçütü için önizleme formülü (yatırımcınınkiyle aynı); null ise birim 0 sayılır (yalnız parsel eşiği).
var _economy: EconomySystem


func _init(ctx: PoliticsContext, economy: EconomySystem = null) -> void:
	_ctx = ctx
	_economy = economy


## Komut TÜRÜ için meclis yolu var mı (bayrak). Plan başına karar: `requires_vote_for`.
func requires_vote(_state: GameState, command_kind: StringName) -> bool:
	return _ctx.politics.requires_council(String(command_kind))


func requires_vote_for(state: GameState, command_kind: StringName, params: Dictionary) -> bool:
	if not requires_vote(state, command_kind):
		return false
	if command_kind != SimCommand.KIND_ZONING_PROPOSE or not _ctx.politics.plan_council_thresholds_active():
		return true
	return bool(_plan_route(state, params)["large"])


## {large, parcels, units}: bu plan eşiklere göre büyük mü? Birim yalnız min_units > 0 iken hesaplanır.
func _plan_route(state: GameState, params: Dictionary) -> Dictionary:
	var council: Dictionary = _ctx.politics.council
	var min_parcels := int(council.get("plan_council_min_parcels", 0))
	var min_units := int(council.get("plan_council_min_units", 0))
	var ids: PackedInt64Array = params.get("parcel_ids", PackedInt64Array()) as PackedInt64Array
	var units := 0
	if min_units > 0 and _economy != null and not ids.is_empty():
		var preview := _economy.plan_preview(state, ids, StringName(params.get("land_use", &"")),
			int(params.get("density", ParcelZoningSystem.NO_VALUE)),
			int(params.get("max_height_m", ParcelZoningSystem.NO_VALUE)))
		units = int(preview["total_units"]) if preview["ok"] else 0
	var large := (min_parcels > 0 and ids.size() >= min_parcels) or (min_units > 0 and units >= min_units)
	return {"large": large, "parcels": ids.size(), "units": units}


func plan_thresholds() -> Dictionary:
	if not _ctx.politics.plan_council_thresholds_active():
		return {}
	return {"min_parcels": int(_ctx.politics.council.get("plan_council_min_parcels", 0)),
		"min_units": int(_ctx.politics.council.get("plan_council_min_units", 0))}


func pending_vote_for_parcel(state: GameState, parcel_id: int) -> int:
	return CouncilEngine.pending_vote_for_parcel(state, parcel_id)


## Aynı parsel için bekleyen oylama varken yeni imar önerisi reddedilir (`precondition`, vote.pending).
func precheck(state: GameState, command_kind: StringName, params: Dictionary) -> Dictionary:
	if not requires_vote(state, command_kind) or not params.get("parcel_ids", null) is PackedInt64Array:
		return {}
	for id in params["parcel_ids"] as PackedInt64Array:
		var pending := CouncilEngine.pending_vote_for_parcel(state, id)
		if pending > 0:
			return {"code": &"precondition", "args": {"why": "vote.pending", "ref": "vote.%d" % pending}}
	return {}


func open(state: GameState, command_kind: StringName, params: Dictionary, command_id: int, delay_days: int) -> void:
	if not PoliticsState.ensure_initialized(state, _ctx):
		return
	if command_kind == SimCommand.KIND_ZONING_PROPOSE:
		var spec := CouncilEngine.zoning_spec(_ctx, params, command_id, delay_days)
		if _ctx.politics.plan_council_thresholds_active():  # SIM-12: meclise NEDEN gittiği (yalnız eşik etkinse yazılır)
			var route := _plan_route(state, params)
			(spec["proposal"] as Dictionary)["route"] = {"reason": ROUTE_LARGE, "parcels": route["parcels"],
				"units": route["units"], "min_parcels": int(_ctx.politics.council["plan_council_min_parcels"]),
				"min_units": int(_ctx.politics.council["plan_council_min_units"])}
		CouncilEngine.open_vote(state, _ctx, spec)
	elif command_kind == SimCommand.KIND_BUDGET_PROPOSE:
		CouncilEngine.open_vote(state, _ctx, CouncilEngine.budget_spec(command_id, params.get("lines", {})))
