class_name PublicWorkDemolishHandler
extends CommandHandler
## `public_work.demolish {command_id}` (T-042c, D-014 §1): duran bir oyuncu yolunu YIKAR. Her zaman mümkündür
## (klasik geri al penceresi kapandıktan sonra da), bir MALİYETİ vardır (gösterge; bütçe kısıtı yok, değer
## `data/sim/budget/budget_config.json road.demolish_cost_per_m`) ve geri alma DEĞİLDİR: kamulaştırmayla alınan
## parseller ve yıkılan binalar GERİ GELMEZ, halk tepkisi silinmez (yıkım yeni bir eylemdir). Yalnız koşulu değiştirir:
## yolun bölgeye verdiği altyapı kapasitesi düşer; özel bina doğurmaz (CAN-03). Yıkılan yol `public_works()`
## listesinden çıkar ve klasik geri al penceresi kapanır.
##
## Ret kodları: `no_such_road` (yok/zaten yıkılmış), `demolition_unavailable` (ağda kenarı bulunamadı ya da tam
## silinemedi), `demolition_changes_parcels` (dünya parselleri yeniden üretirdi; sim parsel kümesi sabit; güvenlik
## ağı: keep_parcels açık dünyada kamulaştırmalı yol da yıkılır, parsel kimlikleri korunur), `busy`
## (yalnız gönderimde: dünya meşgul). Hesap `DemolitionPlan`dadır (kuru koşu = önizleme ile uygulama aynı kod).

const _SHAPE_PREFIX := "command.reject."
const CODE_NO_SUCH_ROAD := &"public_work.reject.no_such_road"
const CODE_UNAVAILABLE := &"public_work.reject.demolition_unavailable"
const CODE_CHANGES_PARCELS := &"public_work.reject.demolition_changes_parcels"
const DECISION := &"decision.municipal.demolish_road"
const FACTOR_UNITS := &"reason.factor.removed_capacity_units"

var _ctx: PublicWorksContext


func _init(ctx: PublicWorksContext) -> void:
	_ctx = ctx


func command_type() -> StringName:
	return SimCommand.KIND_PUBLIC_WORK_DEMOLISH


func validate(state: GameState, params: Dictionary) -> StringName:
	return _problem(state, params, false)["code"]


func validate_submit(state: GameState, params: Dictionary) -> StringName:
	return _problem(state, params, true)["code"]


func reject_args(state: GameState, params: Dictionary) -> Dictionary:
	return _problem(state, params, false)["args"]


func preview_args(state: GameState, params: Dictionary) -> Dictionary:
	var problem := _problem(state, params, false)
	if problem["code"] != &"":
		return {}
	var work: Dictionary = problem["work"]
	var units: Dictionary = work["region_units"]
	var args := {"target_command_id": work["command_id"], "road_class": work["road_class"],
		"length_cm": work["length_cm"], "length_m": roundi(float(work["length_cm"]) * 0.01),
		"regions": units.duplicate(), "units_total": PublicWorksState.total_units(units),
		"edges": (problem["run"]["edges"] as Array).size(), "expropriated": work.has("expropriation"),
		"restores_nothing": true,  # yıkım geri alma değildir: alınan parseller/binalar dönmez
		"cost_available": _ctx.config.cost_available, "cost_reason_key": String(_ctx.config.cost_reason_key)}
	if work.has("expropriation"):
		args["taken_parcels"] = (work["expropriation"]["parcel_ids"] as Array).size()
	return args


func subjects(_params: Dictionary) -> PackedStringArray:
	return PackedStringArray()


func try_apply(state: GameState, params: Dictionary, command_id: int) -> StringName:
	var work := PublicWorksState.standing_road(state, int(params["command_id"]))
	if work.is_empty():
		return CODE_NO_SUCH_ROAD
	var run := DemolitionPlan.run(_ctx.net, _op_of(state, work), true)
	if not bool(run["ok"]):
		if DemolitionPlan.rollback(_ctx.net, run["ops"]) > 0:
			push_error("PublicWorkDemolishHandler: AĞ BOZULDU: başarısız yıkım geri alınamadı")
		return _code_of(run)
	PublicWorksState.append_demolition(state, command_id, int(work["command_id"]), str(work["road_class"]),
		run["ops"], run["hashes"])
	_emit(state, command_id, work, run)
	return &""


func apply_with_id(state: GameState, params: Dictionary, command_id: int) -> void:
	var code := try_apply(state, params, command_id)
	if code != &"":
		push_error("PublicWorkDemolishHandler: doğrulanan yıkım uygulanamadı (%s); durum değişmedi" % String(code))


## {"code": ret kodu ya da &"", "args": ret argümanları, "work": yol satırı, "run": kuru koşu}.
func _problem(state: GameState, params: Dictionary, at_submit: bool) -> Dictionary:
	var out := {"code": &"", "args": {}, "work": {}, "run": {}}
	var shape := SimCommand.make(command_type(), params).validate_shape()
	if not shape.is_empty():
		out["code"] = StringName(String(shape["reason_key"]).trim_prefix(_SHAPE_PREFIX))
		out["args"] = shape["args"]
		return out
	if at_submit and _ctx.is_busy():  # görünüm işi ağı okurken ağ değişmez (kuru koşu da dahil)
		out["code"] = StringName(RoadDraftCheck.key_of(RoadDraftCheck.REASON_BUSY))
		return out
	if not _ctx.tracks(state):  # ağa bu bağlam dışında delta yazılmış: yol listesi ağla tutarsız
		out["code"] = StringName(RoadDraftCheck.key_of(RoadDraftCheck.REASON_BUSY))
		return out
	var work := PublicWorksState.standing_road(state, int(params["command_id"]))
	if work.is_empty():
		out["code"] = CODE_NO_SUCH_ROAD
		out["args"] = {"command_id": int(params["command_id"])}
		return out
	out["work"] = work
	var run := _dry_run(state, work)
	out["run"] = run
	if not bool(run["ok"]):
		out["code"] = _code_of(run)
		out["args"] = {"added_parcels": run["added_parcels"], "removed_parcels": run["removed_parcels"]}
	return out


## Kuru koşu: yıkımı uygula + geri al. Aynı durum + ağ sürümü + yol için tekrar hesaplanmaz. Geri alma ağı öncesiyle
## AYNI içeriğe döndürür; bu yüzden `graph_version` ve değişim günlüğü de öncesine döner (B-020): aksi halde her
## önizleme yol görünümüne sahte "bekleyen değişim" üretir, o iş sürerken sıradaki tick ağa yazabilir.
func _dry_run(state: GameState, work: Dictionary) -> Dictionary:
	var net := _ctx.net
	var key := "%d|%d|%d|%d" % [state.get_instance_id(), net.graph_version, net.parcel_revision,
		int(work["command_id"])]
	if _ctx.demolition_memo_key == key:
		return _ctx.demolition_memo
	var version_before := net.graph_version
	var log_before := net.change_log.duplicate()
	var run := DemolitionPlan.run(net, _op_of(state, work), false)
	if DemolitionPlan.rollback(net, run["ops"]) > 0:
		push_error("PublicWorkDemolishHandler: AĞ BOZULDU: kuru koşu geri alınamadı")
	else:
		net.graph_version = version_before
		net.change_log = log_before
	_ctx.demolition_memo = run
	_ctx.demolition_memo_key = "%d|%d|%d|%d" % [state.get_instance_id(), net.graph_version, net.parcel_revision,
		int(work["command_id"])]
	return run


static func _code_of(run: Dictionary) -> StringName:
	if int(run["added_parcels"]) > 0 or int(run["removed_parcels"]) > 0:
		return CODE_CHANGES_PARCELS
	return CODE_UNAVAILABLE


## Yol satırının kayıtlı `add_road` işlemi (ops, works ile aynı sırada hizalıdır).
static func _op_of(state: GameState, work: Dictionary) -> Dictionary:
	return PublicWorksState.data(state)["ops"][int(work["id"]) - 1]


func _emit(state: GameState, command_id: int, work: Dictionary, run: Dictionary) -> void:
	var target := int(work["command_id"])
	var units: Dictionary = work["region_units"]
	var this_ref := String(SimContract.ref(SimContract.REF_COMMAND, command_id))
	var target_ref := String(SimContract.ref(SimContract.REF_COMMAND, target))
	var rid := state.record_reason(ExpropriationFlow.ACTOR, DECISION,
		[{"name": ExpropriationFlow.FACTOR_ROAD, "value": 1, "source_ref": target_ref},
		{"name": FACTOR_UNITS, "value": PublicWorksState.total_units(units), "weight": 0}], 0, &"demolish",
		PackedStringArray([target_ref, this_ref]))
	var subjects_out := PackedStringArray([this_ref, target_ref])
	var args := {"target_command_id": target, "road_class": work["road_class"], "length_cm": work["length_cm"],
		"length_m": roundi(float(work["length_cm"]) * 0.01), "edges": (run["edges"] as Array).size(),
		"units_total": PublicWorksState.total_units(units), "expropriated": work.has("expropriation")}
	for code: String in PublicWorksState.sorted_codes(units):
		subjects_out.append("%s.%s" % [SimContract.REF_REGION, code])
		args["units.%s" % code] = units[code]
	SimEventLog.emit(state, SimEvent.KIND_PUBLIC_WORK_DEMOLISHED, &"event.road.demolished", subjects_out, args,
		PackedInt64Array([rid]) if rid > 0 else PackedInt64Array(), command_id)
