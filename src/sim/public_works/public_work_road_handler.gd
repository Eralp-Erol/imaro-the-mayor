class_name PublicWorkRoadHandler
extends CommandHandler
## `public_work.road {points_cm, road_class}` (T-042 adım 2, CAN-04, D-009, ADR-0005 Ek E). Belediye yolu çizer: ağa
## delta
## olarak eklenir ve çizilen yolun değdiği bölgelerin altyapı kapasitesi artar (veri güdümlü formül). Özel bina DOĞURMAZ
## (CAN-03): yalnız koşulu değiştirir, gelişmeyi yatırımcı kararları üretir.
##
## Doğrulama saf `RoadDraftCheck`tir (önizleme ve sim AYNI kod); ret kodları `public_work.reject.*` anahtarlarının
## kendisidir (`CommandReject.is_passthrough`). Gönderimde ek olarak "dünya meşgul" sorulur; tick sınırında doğrulama
## çalışma zamanına bağlı değildir. Uygulama aynı tick sınırında yeniden doğrular (arada başka yol gelmiş olabilir).

const _SHAPE_PREFIX := "command.reject."

var _ctx: PublicWorksContext


func _init(ctx: PublicWorksContext) -> void:
	_ctx = ctx


func command_type() -> StringName:
	return SimCommand.KIND_PUBLIC_WORK_ROAD


func validate(state: GameState, params: Dictionary) -> StringName:
	return _problem(state, params, false)["code"]


func validate_submit(state: GameState, params: Dictionary) -> StringName:
	return _problem(state, params, true)["code"]


## Ret ek bilgisi çalışma zamanına (meşgul) bağlı değildir: tick sınırındaki ret olayı da aynı argümanları taşır.
func reject_args(state: GameState, params: Dictionary) -> Dictionary:
	return _problem(state, params, false)["args"]


func preview_args(state: GameState, params: Dictionary) -> Dictionary:
	var problem := _problem(state, params, false)
	if problem["code"] != &"":
		return {}
	return _args_of(problem["draft"])


func subjects(_params: Dictionary) -> PackedStringArray:
	return PackedStringArray()


func apply_with_id(state: GameState, params: Dictionary, command_id: int) -> void:
	var road_class: StringName = params["road_class"]
	var plan := _ctx.draft(params["points_cm"], road_class)  # aynı ağ sürümünde doğrulamayla tek denetim (önbellek)
	var result := RoadDraftCheck.apply_checked(_ctx.net, plan, road_class, _ctx.rules)
	if not bool(result["applied"]):
		push_error("PublicWorkRoadHandler: doğrulanan yol uygulanamadı (%s); durum değişmedi" % str(result["reason"]))
		return
	var units: Dictionary = plan["region_units"]
	var work := {"command_id": command_id, "tick": state.tick, "road_class": String(road_class),
		"length_cm": plan["length_cm"], "region_units": units}
	PublicWorksState.append_work(state, _ctx.net.base_hash, _ctx.net.peek_last_op(), _ctx.net.graph_hash(), work)
	var subjects_out := PackedStringArray([String(SimContract.ref(SimContract.REF_COMMAND, command_id))])
	var args := {"road_class": String(road_class), "length_cm": plan["length_cm"],
		"length_m": roundi(float(plan["length_cm"]) * 0.01), "units_total": PublicWorksState.total_units(units),
		"work_id": PublicWorksState.work_count(state)}
	for code: String in PublicWorksState.sorted_codes(units):
		subjects_out.append("%s.%s" % [SimContract.REF_REGION, code])
		args["units.%s" % code] = units[code]
	SimEventLog.emit(state, SimEvent.KIND_PUBLIC_WORK_BUILT, &"event.road.built", subjects_out, args,
		PackedInt64Array(), command_id)


## {"code": ret kodu ya da &"", "args": ret argümanları, "draft": denetim sonucu}.
func _problem(state: GameState, params: Dictionary, at_submit: bool) -> Dictionary:
	var shape := SimCommand.make(command_type(), params).validate_shape()
	if not shape.is_empty():
		return {"code": StringName(String(shape["reason_key"]).trim_prefix(_SHAPE_PREFIX)), "args": shape["args"],
			"draft": {}}
	if not _ctx.tracks(state):  # ağa bu bağlam dışında delta yazılmış: yol listesi ağla tutarsız, çizim güvenli değil
		return {"code": StringName(RoadDraftCheck.key_of(RoadDraftCheck.REASON_BUSY)), "args": {}, "draft": {}}
	var busy := at_submit and _ctx.is_busy()
	var draft := _ctx.draft(params["points_cm"], params["road_class"], busy)
	if bool(draft["ok"]):
		return {"code": &"", "args": {}, "draft": draft}
	return {"code": StringName(draft["key"]), "args": _reject_args(draft), "draft": draft}


## UI için ret ek bilgisi: uzunluk sınırları ve (varsa) reddin konumu (cm; harita işareti).
func _reject_args(draft: Dictionary) -> Dictionary:
	var args := {"length_m": roundi(float(draft["length_m"])), "min_m": roundi(float(draft["min_length_m"])),
		"max_m": roundi(float(draft["max_length_m"]))}
	if bool(draft["has_at"]):
		var at: Vector2 = draft["at"]
		args["at_x_cm"] = roundi(at.x * 100.0)
		args["at_z_cm"] = roundi(at.y * 100.0)
	return args


## Geçerli taslağın ön izlemesi: sim'in kendi hesabı. Maliyet "henüz kurulmadı" (T-014, Q-003): para yok.
func _args_of(draft: Dictionary) -> Dictionary:
	var units: Dictionary = draft["region_units"]
	return {"length_cm": draft["length_cm"], "length_m": roundi(float(draft["length_cm"]) * 0.01),
		"regions": units.duplicate(), "units_total": PublicWorksState.total_units(units),
		"cost_available": _ctx.config.cost_available, "cost_reason_key": String(_ctx.config.cost_reason_key)}
