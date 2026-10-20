class_name ZoningProposeHandler
extends CommandHandler
## `zoning.propose` (ADR-0005 §4, CAN-03 beyaz liste): parsellerin imarını ÖNERİR; yürürlük süresi sonra
## (ParcelZoningSystem) gelir. Yalnız koşul değişir: özel bina oluşmaz, gelişmeyi aktör kararları üretir.
## Doğrulama UYGULAMA anındaki durumla yapılır; ortak şekil denetimi (`SimCommand.validate_shape`) burada da koşar
## ki doğrudan `Commands.submit` ile gelen biçimsiz komut da gerekçeli reddedilsin.

const _SHAPE_PREFIX := "command.reject."

var _parcels: ParcelSource
var _config: FacadeConfig


func _init(parcels: ParcelSource, config: FacadeConfig) -> void:
	_parcels = parcels
	_config = config


func command_type() -> StringName:
	return SimCommand.KIND_ZONING_PROPOSE


func validate(_state: GameState, params: Dictionary) -> StringName:
	return _problem(params)["code"]


func reject_args(_state: GameState, params: Dictionary) -> Dictionary:
	return _problem(params)["args"]


func subjects(params: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if params.get("parcel_ids", null) is PackedInt64Array:
		for id in params["parcel_ids"] as PackedInt64Array:
			out.append(String(SimContract.parcel_ref(id)))
	return out


func apply_with_id(state: GameState, params: Dictionary, command_id: int) -> void:
	var due := state.tick + _config.apply_delay_days
	var density: int = params.get("density", ParcelZoningSystem.NO_VALUE)
	var height: int = params.get("max_height_m", ParcelZoningSystem.NO_VALUE)
	for id in params["parcel_ids"] as PackedInt64Array:
		ParcelZoningSystem.set_pending(state, id, params["land_use"], due, command_id, density, height)


## {"code": ret kodu ya da &"", "args": ek argümanlar}.
func _problem(params: Dictionary) -> Dictionary:
	var shape := SimCommand.make(command_type(), params).validate_shape()
	if not shape.is_empty():
		return {"code": StringName(String(shape["reason_key"]).trim_prefix(_SHAPE_PREFIX)), "args": shape["args"]}
	for id in params["parcel_ids"] as PackedInt64Array:
		if not _parcels.has_parcel(id):
			return {"code": &"invalid_target", "args": {"ref": String(SimContract.parcel_ref(id))}}
	if not _config.is_land_use(params["land_use"]):
		return {"code": &"invalid_value", "args": {"param": "land_use"}}
	return {"code": &"", "args": {}}
