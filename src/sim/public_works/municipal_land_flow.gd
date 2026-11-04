class_name MunicipalLandFlow
extends RefCounted
## D-018 · Onaylanan imarın yürürlük sınırında belediye arazisini yeniden açar. Render/zaman bağımlılığı yok.

const NOT_AVAILABLE := &"municipal_land.not_available"
const ROAD_STANDING := &"municipal_land.road_still_standing"
const PLAN_PENDING := &"municipal_land.plan_pending"
const WORLD_UNAVAILABLE := &"municipal_land.world_unavailable"


## UI/facade için salt okunur gerçek adaylar. Aktif yolların aldığı alanlar da gerekçeli kapalı satırdır.
static func rows(ctx: PublicWorksContext, state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var data := PublicWorksState.data(state)
	var ids: Array = (data.get("taken", {}) as Dictionary).keys()
	ids.sort()
	for id: int in ids:
		var source := _source(state, id)
		var reason := _reason(ctx, state, id, 0)
		out.append({"id": id, "source_op": int(source.get("source_op", -1)),
			"source_command_id": int(source.get("source_command_id", 0)), "available": reason == &"",
			"reason_key": String(reason)})
	return out


## Mevcut precondition sözleşmesi. own_command yalnız yürürlükte grubun kendi bekleyen planını dışlar.
static func problem(ctx: PublicWorksContext, state: GameState, ids: PackedInt64Array,
		own_command: int = 0) -> Dictionary:
	if ids.is_empty():
		return _problem(NOT_AVAILABLE, 0)
	for id in _sorted(ids):
		var reason := _reason(ctx, state, id, own_command)
		if reason != &"":
			return _problem(reason, id)
	return {}


## Grubun tamamı önce denetlenir. Dünya grupları başarısız olursa yeni ops geri alınır; ekonomi henüz yazılmamıştır.
static func activate(ctx: PublicWorksContext, state: GameState, ids: PackedInt64Array,
		command_id: int) -> Dictionary:
	var checked := problem(ctx, state, ids, command_id)
	if not checked.is_empty():
		return {"ok": false, "reason_key": checked["args"]["why"]}
	var grouped := {}
	for id in _sorted(ids):
		var source_op := int(_source(state, id)["source_op"])
		# `as PackedInt64Array` Variant'tan KOPYA verir; ekleme sözlüğe yansımaz. Okuyup yeniden yazılır.
		var bucket: PackedInt64Array = grouped.get(source_op, PackedInt64Array())
		bucket.append(id)
		grouped[source_op] = bucket
	var sources := grouped.keys()
	sources.sort()
	var start_count := ctx.net.delta.ops.size()
	var world_before := ctx.net.state_hash()
	var records: Array[Dictionary] = []
	for source_op: int in sources:
		var selected: PackedInt64Array = grouped[source_op]
		var report := ctx.expropriation.restore_land(source_op, selected)
		if not bool(report["ok"]) or _sorted(report.get("restored", PackedInt64Array())) != selected:
			_rollback(ctx, start_count, world_before)
			return {"ok": false, "reason_key": WORLD_UNAVAILABLE}
		if ctx.net.delta.ops.size() != start_count + records.size() + 1:
			_rollback(ctx, start_count, world_before)
			return {"ok": false, "reason_key": WORLD_UNAVAILABLE}
		records.append({"source_op": source_op, "ids": selected, "op": ctx.net.peek_last_op(),
			"hash": ctx.net.graph_hash()})
	# Bundan sonra yalnız önceden doğrulanmış sim sütunları yazılır; eski binalar/haneler restore edilmez.
	for record: Dictionary in records:
		PublicWorksState.append_land_reuse(state, command_id, record["source_op"], record["ids"],
			record["op"], record["hash"])
	LandReuseEconomy.release(state, _sorted(ids))
	for id in _sorted(ids):
		ctx.pending_notes.append(id)
	return {"ok": true, "reason_key": &""}


static func _rollback(ctx: PublicWorksContext, count_before: int, world_before: String) -> void:
	while ctx.net.delta.ops.size() > count_before:
		if not bool(ctx.undo_live_op()["ok"]):
			push_error("MunicipalLandFlow: AĞ BOZULDU: başarısız arazi grubu geri alınamadı")
			return
	if ctx.net.state_hash() != world_before:
		push_error("MunicipalLandFlow: AĞ BOZULDU: başarısız arazi grubu eski dünyaya dönmedi")


static func _source(state: GameState, id: int) -> Dictionary:
	var command_id := PublicWorksState.taken_command(state, id)
	if command_id <= 0:
		return {}
	for work: Dictionary in PublicWorksState.data(state).get("works", []):
		if PublicWorksState.is_road_work(work) and int(work["command_id"]) == command_id:
			return {"source_op": int(work["id"]) - 1, "source_command_id": command_id,
				"demolished": work.has("demolished_by")}
	return {}


static func _reason(ctx: PublicWorksContext, state: GameState, id: int, own_command: int) -> StringName:
	if ctx == null or ctx.expropriation == null or not ctx.expropriation.available() or not ctx.tracks(state):
		return WORLD_UNAVAILABLE
	var source := _source(state, id)
	if source.is_empty() or not LandReuseEconomy.can_release(state, PackedInt64Array([id])):
		return NOT_AVAILABLE
	if not bool(source["demolished"]):
		return ROAD_STANDING
	var overlay := ParcelZoningSystem.overlay_of(state, id)
	if overlay.get("pending_zone", &"") != &"" and int(overlay.get("command_id", 0)) != own_command:
		return PLAN_PENDING
	if CouncilEngine.pending_vote_for_parcel(state, id) > 0:
		return PLAN_PENDING
	var world := ctx.expropriation.available_land(int(source["source_op"]), PackedInt64Array([id]))
	return &"" if bool(world["ok"]) else WORLD_UNAVAILABLE


static func _problem(reason: StringName, id: int) -> Dictionary:
	return {"code": &"precondition", "args": {"why": String(reason), "ref": String(SimContract.parcel_ref(id))}}


static func _sorted(ids: Variant) -> PackedInt64Array:
	return ExpropriationSummary.sorted_ids({"parcel_ids": ids})


## Kayıt için sıralı, tekrarsız kimlik listesi (Array[int]).
static func sorted_ids(ids: PackedInt64Array) -> Array:
	var out: Array = []
	for id in _sorted(ids):
		if out.is_empty() or out[-1] != id:
			out.append(int(id))
	return out
