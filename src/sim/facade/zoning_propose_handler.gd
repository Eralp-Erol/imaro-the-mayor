class_name ZoningProposeHandler
extends CommandHandler
## `zoning.propose` (ADR-0005 §4, CAN-03 beyaz liste): parsellerin imarını ÖNERİR; yürürlük süresi sonra
## (ParcelZoningSystem) gelir. Yalnız koşul değişir: özel bina oluşmaz, gelişmeyi aktör kararları üretir.
## Doğrulama UYGULAMA anındaki durumla yapılır; ortak şekil denetimi (`SimCommand.validate_shape`) burada da koşar
## ki doğrudan `Commands.submit` ile gelen biçimsiz komut da gerekçeli reddedilsin.

const _SHAPE_PREFIX := "command.reject."

## D-018: yalnız municipal_reuse:true akışının dünya/sim köprüsü. Eski imar davranışı aynı kalır.
var municipal_context: PublicWorksContext = null

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
	var group := []
	if bool(params.get("municipal_reuse", false)):
		group = MunicipalLandFlow.sorted_ids(params["parcel_ids"] as PackedInt64Array)
	for id in params["parcel_ids"] as PackedInt64Array:
		ParcelZoningSystem.set_pending(state, id, params["land_use"], due, command_id, density, height, group)


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
	return _late_problem(state, params)


## Şekil/hedef denetiminden sonraki kapılar: belediye arazisi yeniden imarı (D-018), sonra öneri kapısı.
func _late_problem(state: GameState, params: Dictionary) -> Dictionary:
	var overlay := ParcelZoningSystem.overlay_ref(state)
	for id in params["parcel_ids"] as PackedInt64Array:  # bekleyen belediye grubu sıradan planla bölünemez
		var held: Variant = overlay.get(id, null)
		if held is Dictionary and bool(held.get("municipal_reuse", false)) and held.get("pending_zone", &"") != &"":
			return {"code": &"precondition", "args": {"why": String(MunicipalLandFlow.PLAN_PENDING),
				"ref": String(SimContract.parcel_ref(id))}}
	if bool(params.get("municipal_reuse", false)):
		var land_problem := MunicipalLandFlow.problem(municipal_context, state, params["parcel_ids"])
		if not land_problem.is_empty():
			return land_problem
	if _gate != null:
		var gated := _gate.precheck(state, command_type(), params)
		if not gated.is_empty():
			return gated
	return {"code": &"", "args": {}}
