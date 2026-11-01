class_name PublicWorkUndoHandler
extends CommandHandler
## `public_work.undo_last {}` (T-042 adım 2, ADR-0005 Ek E; T-042c D-014 §1): KLASİK GERİ AL. Başka bir yol parçası
## (ya da yıkım) yapılana kadar EN SON yapılan yol geri alınır ve eylem HİÇ YAPILMAMIŞ gibi olur: yol ağdan kalkar,
## bölgeye verilen kapasite düşer, alınan parseller/binalar geri gelir ve o yola bağlı halk tepkisi (tepki defteri)
## silinir. Taban yol silinmez. Geri alma YIĞILMAZ: son yol gidince bir önceki yol yeni bir yol yapılana dek geri
## alınamaz (kalıcı olanı kaldırmanın yolu yıkımdır, `public_work.demolish`). Pencere `UndoWindow`dadır; kapalıysa
## `public_work.reject.undo_window_closed` (+ `cause`), hiç yol yoksa `public_work.reject.nothing_to_undo`.
## Ağ graf özeti işlemden önceki ile bit-bit aynı olur (kayıt/yükleme aynı özeti doğrular).

const _SHAPE_PREFIX := "command.reject."
const CODE_WINDOW_CLOSED := &"public_work.reject.undo_window_closed"

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
	var window := UndoWindow.status(_ctx, state)
	if not bool(window["open"]):
		if window["cause"] == UndoWindow.CAUSE_NOTHING:
			return StringName(RoadDraftCheck.key_of(RoadDraftCheck.REASON_NOTHING_TO_UNDO))
		return CODE_WINDOW_CLOSED
	if _last_work(state).has("expropriation") and (_ctx.expropriation == null or not _ctx.expropriation.available()):
		return ExpropriationFlow.CODE_DISABLED  # alınan parselleri geri verecek dünya köprüsü yok
	return &""


func reject_args(state: GameState, _params: Dictionary) -> Dictionary:
	var window := UndoWindow.status(_ctx, state)
	if bool(window["open"]) or window["cause"] == UndoWindow.CAUSE_NOTHING:
		return {}
	return {"cause": String(window["cause"])}


func preview_args(state: GameState, _params: Dictionary) -> Dictionary:
	var d := PublicWorksState.data(state)
	if d.is_empty() or (d["works"] as Array).is_empty():
		return {}
	var last := _last_work(state)
	var units: Dictionary = last["region_units"]
	var args := {"removed_command_id": last["command_id"], "length_cm": last["length_cm"], "regions": units.duplicate()}
	if last.has("expropriation"):  # geri alınca binalar geri gelir VE o yolun halk tepkisi silinir (D-014)
		var record: Dictionary = last["expropriation"]
		args["restored_parcels"] = (record["parcel_ids"] as Array).size()
		args["restored_built_parcels"] = record["built_parcels"]
		args["restored_res_units"] = record["res_units"]
		args["restored_com_units"] = record["com_units"]
	return args


static func _last_work(state: GameState) -> Dictionary:
	var d := PublicWorksState.data(state)
	if d.is_empty() or (d["works"] as Array).is_empty():
		return {}
	return (d["works"] as Array)[(d["works"] as Array).size() - 1]


func apply_with_id(state: GameState, _params: Dictionary, command_id: int) -> void:
	var undone := _ctx.undo_live_op()  # kamulaştırmalı op'u dünya köprüsü geri alır (parselleri geri koyar)
	if not bool(undone["ok"]):
		push_error("PublicWorkUndoHandler: doğrulanan geri alma uygulanamadı; durum değişmedi")
		return
	var work := PublicWorksState.pop_work(state)  # pencere de kapanır
	var removed_command := int(work["command_id"])
	if work.has("expropriation"):  # iş kaydındaki alt kayıtlar (snapshots, ileride yeniden iskân) burada geri sarılır
		ExpropriationFlow.revert(_ctx, state, work, command_id)  # restored olayı removed'dan ÖNCE
	var reactions := PublicWorksState.remove_reactions(state, removed_command)  # halk tepkisi hiç olmamış gibi
	if _ctx.reaction_revoke.is_valid():
		_ctx.reaction_revoke.call(state, removed_command)
	var units: Dictionary = work["region_units"]
	var subjects_out := PackedStringArray([String(SimContract.ref(SimContract.REF_COMMAND, command_id))])
	var args := {"removed_command_id": removed_command, "road_class": work["road_class"],
		"length_cm": work["length_cm"], "length_m": roundi(float(work["length_cm"]) * 0.01),
		"units_total": PublicWorksState.total_units(units)}
	if reactions > 0:
		args["reaction_rows_removed"] = reactions
	for code: String in PublicWorksState.sorted_codes(units):
		subjects_out.append("%s.%s" % [SimContract.REF_REGION, code])
		args["units.%s" % code] = units[code]
	SimEventLog.emit(state, SimEvent.KIND_PUBLIC_WORK_REMOVED, &"event.road.removed", subjects_out, args,
		PackedInt64Array(), command_id)
