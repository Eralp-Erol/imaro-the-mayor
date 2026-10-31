class_name ZoningProposeHandler
extends CommandHandler
## `zoning.propose` (ADR-0005 §4, CAN-03 beyaz liste): parsellerin imarını ÖNERİR; yürürlük süresi sonra
## (ParcelZoningSystem) gelir. Yalnız koşul değişir: özel bina oluşmaz, gelişmeyi aktör kararları üretir.
## Doğrulama UYGULAMA anındaki durumla yapılır; ortak şekil denetimi (`SimCommand.validate_shape`) burada da koşar
## ki doğrudan `Commands.submit` ile gelen biçimsiz komut da gerekçeli reddedilsin.

const _SHAPE_PREFIX := "command.reject."

var _parcels: ParcelSource
var _config: FacadeConfig
## T-017: isteğe bağlı öneri kapısı (meclis oylaması). null = doğrudan yürürlük (önceki davranış).
var _gate: ProposalGate


func _init(parcels: ParcelSource, config: FacadeConfig, gate: ProposalGate = null) -> void:
	_parcels = parcels
	_config = config
	_gate = gate


func command_type() -> StringName:
	return SimCommand.KIND_ZONING_PROPOSE


func validate(state: GameState, params: Dictionary) -> StringName:
	return _problem(state, params)["code"]


func reject_args(state: GameState, params: Dictionary) -> Dictionary:
	return _problem(state, params)["args"]


func subjects(params: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if params.get("parcel_ids", null) is PackedInt64Array:
		for id in params["parcel_ids"] as PackedInt64Array:
			out.append(String(SimContract.parcel_ref(id)))
	return out


func apply_with_id(state: GameState, params: Dictionary, command_id: int) -> void:
	if _gate != null and _gate.requires_vote_for(state, command_type(), params):
		_gate.open(state, command_type(), params, command_id, _config.apply_delay_days)
		return
	var due := state.tick + _config.apply_delay_days
	var density: int = params.get("density", ParcelZoningSystem.NO_VALUE)
	var height: int = params.get("max_height_m", ParcelZoningSystem.NO_VALUE)
	for id in params["parcel_ids"] as PackedInt64Array:
		ParcelZoningSystem.set_pending(state, id, params["land_use"], due, command_id, density, height)


## {"code": ret kodu ya da &"", "args": ek argümanlar}.
func _problem(state: GameState, params: Dictionary) -> Dictionary:
	var shape := SimCommand.make(command_type(), params).validate_shape()
	if not shape.is_empty():
		return {"code": StringName(String(shape["reason_key"]).trim_prefix(_SHAPE_PREFIX)), "args": shape["args"]}
	if (params["parcel_ids"] as PackedInt64Array).size() > _config.plan_max_parcels_per_proposal:  # T-043A
		return {"code": &"invalid_value",
			"args": {"param": "parcel_ids", "max": _config.plan_max_parcels_per_proposal}}
	for id in params["parcel_ids"] as PackedInt64Array:
		if not _parcels.has_parcel(id):
			return {"code": &"invalid_target", "args": {"ref": String(SimContract.parcel_ref(id))}}
	if not _config.is_land_use(params["land_use"]):
		return {"code": &"invalid_value", "args": {"param": "land_use"}}
	if _gate != null:
		var gated := _gate.precheck(state, command_type(), params)
		if not gated.is_empty():
			return gated
	return {"code": &"", "args": {}}
