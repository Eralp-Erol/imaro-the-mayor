class_name PoliticsGate
extends ProposalGate
## Öneri kapısı (T-017, Q-014): `requires_council` verisi doğruysa oyuncunun imar/bütçe önerisi doğrudan yürürlüğe
## girmez, meclis oylamasına gider; kabul edilirse koşul (pending_zone) yazılır, reddedilirse hiçbir şey olmaz. Veri
## yanlışsa kapı hiçbir şey yapmaz (öneri doğrudan yürürlüğe girer). Her iki yol da testlidir.

var _ctx: PoliticsContext


func _init(ctx: PoliticsContext) -> void:
	_ctx = ctx


func requires_vote(_state: GameState, command_kind: StringName) -> bool:
	return _ctx.politics.requires_council(String(command_kind))


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
		CouncilEngine.open_vote(state, _ctx, CouncilEngine.zoning_spec(_ctx, params, command_id, delay_days))
	elif command_kind == SimCommand.KIND_BUDGET_PROPOSE:
		CouncilEngine.open_vote(state, _ctx, CouncilEngine.budget_spec(command_id, params.get("lines", {})))
