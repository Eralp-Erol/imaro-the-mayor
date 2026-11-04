class_name PolicySetHandler
extends CommandHandler
## `policy.set {policy_id, enabled}` (T-065 Aşama 1, D-016 §1, ADR-0009 A): belediyenin KALICI politikasını açar/kapatır
## (şimdilik `resettlement`: kamulaştırmada yeniden iskân yükümlülüğü). Politika bir SEÇİMDİR (CAN-10, SIM-10): açmak da
## kapatmak da meşrudur. Yalnız KOŞULU değiştirir; özel bina doğurmaz (CAN-03). Durum `PolicyState`tedir.
##
## Ret kodları (sözleşme 1.7): bilinmeyen politika `invalid_value` (+ `param = policy_id`); yapılandırmada yok
## `precondition` + `why = system.not_built`; zaten bu değerde `precondition` + `why = policy.unchanged` (günlüğe boş
## kayıt düşmez). Her değişimin gerekçesi (SIM-12) ve `policy.changed` olayı vardır.

const _SHAPE_PREFIX := "command.reject."
const DECISION := &"decision.municipal.policy_set"
const FACTOR_ENABLED := &"reason.factor.policy_enabled"

var _ctx: PublicWorksContext


func _init(ctx: PublicWorksContext) -> void:
	_ctx = ctx


func command_type() -> StringName:
	return SimCommand.KIND_POLICY_SET


func validate(state: GameState, params: Dictionary) -> StringName:
	return _problem(state, params)["code"]


func reject_args(state: GameState, params: Dictionary) -> Dictionary:
	return _problem(state, params)["args"]


func preview_args(_state: GameState, params: Dictionary) -> Dictionary:
	return {"policy_id": params["policy_id"], "enabled": params["enabled"]}


func subjects(_params: Dictionary) -> PackedStringArray:
	return PackedStringArray()


func apply_with_id(state: GameState, params: Dictionary, command_id: int) -> void:
	var id := StringName(params["policy_id"])
	var value := bool(params["enabled"])
	var previous := PolicyState.enabled(state, id)
	PolicyState.set_enabled(state, id, value, command_id)
	var ref := String(SimContract.ref(SimContract.REF_COMMAND, command_id))
	var rid := state.record_reason(ExpropriationFlow.ACTOR, DECISION,
		[{"name": FACTOR_ENABLED, "value": 1 if value else 0, "source_ref": ref}], 0, &"policy_set",
		PackedStringArray([ref]))
	SimEventLog.emit(state, SimEvent.KIND_POLICY_CHANGED, &"event.policy.changed", PackedStringArray([ref]),
		{"policy_id": String(id), "enabled": value, "previous": previous},
		PackedInt64Array([rid]) if rid > 0 else PackedInt64Array(), command_id)


## Politika bu yapılandırmada kurulu mu? (Şimdilik: yeniden iskân sayıları veride var mı.)
func _built(policy_id: StringName) -> bool:
	return policy_id == PolicyView.ID_RESETTLEMENT and _ctx.config.resettlement.available


## {"code": ret kodu ya da &"", "args": ret argümanları}.
func _problem(state: GameState, params: Dictionary) -> Dictionary:
	var shape := SimCommand.make(command_type(), params).validate_shape()
	if not shape.is_empty():
		return {"code": StringName(String(shape["reason_key"]).trim_prefix(_SHAPE_PREFIX)), "args": shape["args"]}
	var id := StringName(params["policy_id"])
	if not PolicyState.IDS.has(id):
		return {"code": &"invalid_value", "args": {"param": "policy_id"}}
	if not _built(id):
		return {"code": &"precondition", "args": {"why": PolicyView.WHY_NOT_BUILT}}
	if PolicyState.enabled(state, id) == bool(params["enabled"]):
		return {"code": &"precondition", "args": {"why": PolicyView.WHY_UNCHANGED}}
	return {"code": &"", "args": {}}
