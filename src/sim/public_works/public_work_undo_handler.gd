class_name PublicWorkUndoHandler
extends CommandHandler
## `public_work.undo_last {}` (T-042 adım 2, ADR-0005 Ek E): son OYUNCU yolunu geri alır (LIFO). Taban yol silinmez.
## Ağ graf
## özeti işlemden önceki ile bit-bit aynı olur, bölgeye verilen kapasite düşer (ekonomi etkin kapasiteyi her kararda
## okuduğundan mevcut durma kuralı kendiliğinden işler). Geri alınacak yol yoksa `public_work.reject.nothing_to_undo`.

const _SHAPE_PREFIX := "command.reject."

var _ctx: PublicWorksContext


func _init(ctx: PublicWorksContext) -> void:
	_ctx = ctx


func command_type() -> StringName:
	return SimCommand.KIND_PUBLIC_WORK_UNDO_LAST


func validate(state: GameState, params: Dictionary) -> StringName:
	var shape := SimCommand.make(command_type(), params).validate_shape()
	if not shape.is_empty():
		return StringName(String(shape["reason_key"]).trim_prefix(_SHAPE_PREFIX))
	if PublicWorksState.work_count(state) == 0 or not _ctx.tracks(state) or not _ctx.net.can_undo():
		return StringName(RoadDraftCheck.key_of(RoadDraftCheck.REASON_NOTHING_TO_UNDO))
	return &""


func preview_args(state: GameState, _params: Dictionary) -> Dictionary:
	var d := PublicWorksState.data(state)
	if d.is_empty() or (d["works"] as Array).is_empty():
		return {}
	var last: Dictionary = (d["works"] as Array)[(d["works"] as Array).size() - 1]
	var units: Dictionary = last["region_units"]
	return {"removed_command_id": last["command_id"], "length_cm": last["length_cm"], "regions": units.duplicate()}


func apply_with_id(state: GameState, _params: Dictionary, command_id: int) -> void:
	var undone := RoadDraftCheck.undo(_ctx.net)
	if not bool(undone["ok"]):
		push_error("PublicWorkUndoHandler: doğrulanan geri alma uygulanamadı; durum değişmedi")
		return
	var work := PublicWorksState.pop_work(state)
	var units: Dictionary = work["region_units"]
	var subjects_out := PackedStringArray([String(SimContract.ref(SimContract.REF_COMMAND, command_id))])
	var args := {"removed_command_id": work["command_id"], "road_class": work["road_class"],
		"length_cm": work["length_cm"], "length_m": roundi(float(work["length_cm"]) * 0.01),
		"units_total": PublicWorksState.total_units(units)}
	for code: String in PublicWorksState.sorted_codes(units):
		subjects_out.append("%s.%s" % [SimContract.REF_REGION, code])
		args["units.%s" % code] = units[code]
	SimEventLog.emit(state, SimEvent.KIND_PUBLIC_WORK_REMOVED, &"event.road.removed", subjects_out, args,
		PackedInt64Array(), command_id)
