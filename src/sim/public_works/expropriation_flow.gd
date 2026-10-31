class_name ExpropriationFlow
extends RefCounted
## T-042b · `public_work.road {expropriate: true}` ve `public_work.undo_last` komutlarının KAMULAŞTIRMA akışı
## (D-011, ADR-0005 Ek F). Saf statik yardımcılar; işleyiciler (`PublicWorkRoadHandler`/`PublicWorkUndoHandler`)
## çağırır.
##
## - `problem`  : doğrulama + önizleme: dünya köprüsü (alınan küme) -> korunan yapı -> ekonomi planı (bina/hane sayıları
##                SİM'in hesabı) -> yakınlık. Durumu ve ağı DEĞİŞTİRMEZ.
## - `apply`    : ağa kamulaştırmalı op ekler; dünyanın bildirdiği küme hesaplananla farklıysa ağı geri alır ve
##                `expropriation_changed` döner (durum DEĞİŞMEZ). Aksi halde parselleri alır, gerekçeleri/olayları
## yazar.
## - `revert`   : geri alma tarafı (parseller anlık görüntüden geri gelir; tepki defteri GERİ ALINMAZ).
## Para yok (bedel T-014/Q-003): yalnız gösterge.

const ACTOR := &"actor.municipality.1"
const DECISION_EXPROPRIATE := &"decision.municipal.expropriate"
const DECISION_RESTORE := &"decision.municipal.restore_parcel"
const FACTOR_ROAD := &"reason.factor.road_work"
const FACTOR_UNITS := &"reason.factor.demolished_units"
const KEY_PREFIX := "public_work.reject."
const CODE_PROTECTED := &"public_work.reject.protected_structure"
const CODE_DISABLED := &"public_work.reject.expropriation_disabled"
const CODE_CHANGED := &"public_work.reject.expropriation_changed"
const CODE_NOT_STARTED := &"public_work.reject.economy_not_started"


static func requested(params: Dictionary) -> bool:
	return bool(params.get("expropriate", false))


## Doğrulama sonucu: {code (&"" = geçerli), args, draft, plan ({} = bu yol parsel almıyor), nearby, taken}.
static func problem(ctx: PublicWorksContext, state: GameState, params: Dictionary, at_submit: bool) -> Dictionary:
	if at_submit and ctx.is_busy():  # "dünya meşgul" cevabı çalışma zamanına bağlı: önbelleğe girmez
		return _problem(ctx, state, params, at_submit)
	var key := "%d|%d|%d|%d|%s|%s" % [state.get_instance_id(), state.tick, ctx.net.graph_version,
		PublicWorksState.taken_count(state), params["road_class"], str(params["points_cm"])]
	if ctx.problem_memo_key != key:
		ctx.problem_memo = _problem(ctx, state, params, at_submit)
		ctx.problem_memo_key = key
	return ctx.problem_memo.duplicate()


static func _problem(ctx: PublicWorksContext, state: GameState, params: Dictionary, at_submit: bool) -> Dictionary:
	var out := {"code": &"", "args": {}, "draft": {}, "plan": {}, "nearby": {}, "taken": PackedInt64Array()}
	if not ctx.expropriation_available():
		out["code"] = CODE_DISABLED
		return out
	if EconomyState.data(state).is_empty():  # ekonomi ilk günlük tick'te kurulur: alınacak sütun yok
		out["code"] = CODE_NOT_STARTED
		return out
	var road_class: StringName = params["road_class"]
	var points_cm: PackedInt64Array = params["points_cm"]
	var draft := ctx.draft_expropriating(points_cm, road_class, at_submit and ctx.is_busy())
	out["draft"] = draft
	if not bool(draft["ok"]):
		out["code"] = StringName(draft["key"])
		out["args"] = PublicWorkRoadHandler.reject_args_of(draft)
		return out
	var taken := ExpropriationSummary.sorted_ids({"parcel_ids": draft["taken"]})
	out["taken"] = taken
	if taken.is_empty():  # bu yol parsel almıyor: düz yol gibi (bayrak zararsız)
		var plain := ctx.draft(points_cm, road_class, at_submit and ctx.is_busy())
		out["draft"] = plain
		if not bool(plain["ok"]):
			out["code"] = StringName(plain["key"])
			out["args"] = PublicWorkRoadHandler.reject_args_of(plain)
		return out
	var protected_ids := _protected_in(ctx, taken)
	if ctx.config.protect_heritage and not protected_ids.is_empty():
		out["code"] = CODE_PROTECTED
		out["args"] = {"protected_parcels": protected_ids.size(), "protected_parcel_id": protected_ids[0],
			"taken_parcels": taken.size()}
		return out
	var cols := ctx.economy.static_columns()
	var plan := ParcelExpropriation.plan(state, cols, taken, ctx.config.household_fate)
	if not bool(plan["ok"]):  # dünya sim'de olmayan ya da zaten alınmış parsel bildirdi
		out["code"] = CODE_CHANGED
		return out
	var nearby := ParcelExpropriation.nearby(state, cols, taken, _points_of(points_cm),
		ctx.config.proximity_radius_m)
	var summary: Dictionary = plan["summary"]
	summary["nearby_households"] = nearby["households"]
	summary["nearby_parcels"] = nearby["parcels"]
	out["plan"] = plan
	out["nearby"] = nearby
	return out


## `crosses_parcels` reddine eklenecek TEKLİF: kamulaştırarak geçilirse ne olacağı (sim'in sayısı). Korunan yapı varsa
## teklif yok, yalnız sayı. Kamulaştırma kapalıysa boş.
static func offer_args(ctx: PublicWorksContext, state: GameState, params: Dictionary) -> Dictionary:
	if not ctx.expropriation_available():
		return {}
	var asked := params.duplicate()
	asked["expropriate"] = true
	var p := problem(ctx, state, asked, false)
	if p["code"] == &"" and not (p["plan"] as Dictionary).is_empty():
		return ExpropriationSummary.preview_args((p["plan"] as Dictionary)["summary"])
	if p["code"] == CODE_PROTECTED:
		return {"protected_parcels": p["args"]["protected_parcels"]}
	return {}


## Önizleme argümanları (düz yol bilgisine eklenir). Parsel almayan yolda boş.
static func preview_args(p: Dictionary) -> Dictionary:
	var plan: Dictionary = p.get("plan", {})
	return {} if plan.is_empty() else ExpropriationSummary.preview_args(plan["summary"])


## Kamulaştırmalı yolu uygular. `p`: `problem` sonucu (kod boş, plan dolu). Dönüş: &"" ya da ret kodu (durum
## değişmeden).
static func apply(ctx: PublicWorksContext, state: GameState, params: Dictionary, command_id: int,
		p: Dictionary) -> StringName:
	var road_class: StringName = params["road_class"]
	var plan: Dictionary = p["plan"]
	var draft: Dictionary = p["draft"]
	var result := ctx.expropriation.commit(draft, road_class)
	if not bool(result["ok"]):
		push_error("ExpropriationFlow: doğrulanan kamulaştırmalı yol uygulanamadı (%s); durum değişmedi" %
			str(result.get("error", "")))
		return CODE_CHANGED
	if ExpropriationSummary.sorted_ids({"parcel_ids": result["removed"]}) != (p["taken"] as PackedInt64Array):
		var undone := ctx.expropriation.undo()  # dünya önizlemeden farklı küme aldı: ağı eski haline getir
		if not bool(undone["ok"]):
			push_error("ExpropriationFlow: AĞ BOZULDU: sapan kamulaştırma geri alınamadı (%s)" %
				str(undone.get("error", "")))
		return CODE_CHANGED
	var snapshots := ParcelExpropriation.apply(state, plan)
	var summary: Dictionary = plan["summary"]
	var record := _record_of(summary, snapshots, plan)
	var units: Dictionary = draft["region_units"]
	var work := {"command_id": command_id, "tick": state.tick, "road_class": String(road_class),
		"length_cm": draft["length_cm"], "region_units": units, "expropriation": record}
	PublicWorksState.append_work(state, ctx.net.base_hash, ctx.net.peek_last_op(), ctx.net.graph_hash(), work)
	PublicWorksState.note_reactions(state, command_id, plan["displaced"], (p["nearby"] as Dictionary)["by_region"],
		ctx.config.reaction_keep_days)
	var reason_ids := _record_reasons(state, command_id, snapshots)
	ctx.pending_notes.append_array(summary["parcel_ids"])
	var args := ExpropriationSummary.event_args(summary)
	args["work_id"] = PublicWorksState.work_count(state)
	SimEventLog.emit(state, SimEvent.KIND_PUBLIC_WORK_EXPROPRIATED, &"event.road.expropriated",
		ExpropriationSummary.subjects(command_id, summary), args, reason_ids, command_id)
	PublicWorkRoadHandler.emit_built(state, command_id, road_class, draft)  # expropriated -> built -> applied
	return &""


## Geri alma: alınan parselleri anlık görüntüden geri koyar, `public_work.restored` olayını yazar. `work`: çıkarılan iş.
static func revert(ctx: PublicWorksContext, state: GameState, work: Dictionary, command_id: int) -> void:
	var record: Dictionary = work["expropriation"]
	ParcelExpropriation.restore(state, record)
	var summary := summary_of(record)
	var ids := ExpropriationSummary.sorted_ids(summary)
	ctx.pending_notes.append_array(ids)
	var reason_ids := PackedInt64Array()
	for id in ids:
		var rid := state.record_reason(ACTOR, DECISION_RESTORE,
			[{"name": FACTOR_ROAD, "value": 1, "source_ref": String(SimContract.ref(SimContract.REF_COMMAND,
				int(work["command_id"])))}], 0, &"restore", PackedStringArray([String(SimContract.parcel_ref(id)),
				String(SimContract.ref(SimContract.REF_COMMAND, command_id))]))
		if rid > 0:
			reason_ids.append(rid)
	var args := ExpropriationSummary.event_args(summary)
	args["removed_command_id"] = work["command_id"]
	SimEventLog.emit(state, SimEvent.KIND_PUBLIC_WORK_RESTORED, &"event.road.restored",
		ExpropriationSummary.subjects(command_id, summary), args, reason_ids, command_id)


## İş kaydındaki kamulaştırma satırından `ExpropriationSummary` sözlüğü.
static func summary_of(record: Dictionary) -> Dictionary:
	return {"parcel_ids": record["parcel_ids"], "built_parcels": record["built_parcels"],
		"project_parcels": record["project_parcels"], "res_units": record["res_units"],
		"com_units": record["com_units"], "households": record["households"], "regions": record["regions"],
		"nearby_households": record["nearby_households"], "nearby_parcels": record["nearby_parcels"]}


## Kayıt yüklemesi: ekonomideki TAKEN parsel kümesi `public_works.taken` ile aynı olmalı. Sorun metni ya da "".
static func consistency_problem(state: GameState) -> String:
	var d := EconomyState.data(state)
	var taken_in_economy := PackedInt64Array()
	if not d.is_empty():
		var stage: PackedByteArray = d["stage"]
		var ids: PackedInt64Array = d["parcel_ids"]
		for i in stage.size():
			if stage[i] == EconomyState.STAGE_TAKEN:
				taken_in_economy.append(ids[i])
	var section := PublicWorksState.data(state)
	var taken_in_works := PackedInt64Array()
	if not section.is_empty() and section.has("taken"):
		for id: Variant in section["taken"]:
			taken_in_works.append(int(id))
		taken_in_works.sort()
	if taken_in_economy != taken_in_works:
		return "alınmış parseller ekonomi ile yol kayıtları arasında uyuşmuyor"
	return ""


static func _record_of(summary: Dictionary, snapshots: Array, plan: Dictionary) -> Dictionary:
	var ids: Array = []
	for id in summary["parcel_ids"]:
		ids.append(int(id))
	return {"parcel_ids": ids, "snapshots": snapshots, "built_parcels": summary["built_parcels"],
		"project_parcels": summary["project_parcels"], "res_units": summary["res_units"],
		"com_units": summary["com_units"], "households": summary["households"],
		"regions": (summary["regions"] as Dictionary).duplicate(), "latent_removed": plan["latent_removed"].duplicate(),
		"nearby_households": summary["nearby_households"], "nearby_parcels": summary["nearby_parcels"],
		"fate": String(plan["fate"])}


## Parsel başına gerekçe (SIM-12): "Kamulaştırıldı <- Yol". Alınan parselin ekonomi gerekçe sütununa yazılır.
static func _record_reasons(state: GameState, command_id: int, snapshots: Array) -> PackedInt64Array:
	var d := EconomyState.data(state)
	var reason_col: PackedInt64Array = d["reason_id"]
	var out := PackedInt64Array()
	var ref := String(SimContract.ref(SimContract.REF_COMMAND, command_id))
	for snap: Dictionary in snapshots:
		var id: int = snap["id"]
		var factors: Array = [{"name": FACTOR_ROAD, "value": 1, "source_ref": ref},
			{"name": FACTOR_UNITS, "value": int(snap["units"]), "weight": 0}]
		var rid := state.record_reason(ACTOR, DECISION_EXPROPRIATE, factors, 0, &"expropriated",
			PackedStringArray([String(SimContract.parcel_ref(id)), ref]))
		if rid > 0:
			out.append(rid)
			reason_col[EconomyState.index_of(d, id)] = rid
	return out


static func _protected_in(ctx: PublicWorksContext, taken: PackedInt64Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for id in taken:
		if ctx.protected_ids.has(id):
			out.append(id)
	return out


## `points_cm` (düz x,z çiftleri) -> [[x, z]...] (yakınlık hesabı).
static func _points_of(points_cm: PackedInt64Array) -> Array:
	var out: Array = []
	for k in range(0, points_cm.size() - 1, 2):
		out.append([points_cm[k], points_cm[k + 1]])
	return out
