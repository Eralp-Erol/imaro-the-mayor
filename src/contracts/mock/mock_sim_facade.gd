class_name MockSimFacade
extends SimFacade
## MOCK SimFacade (ADR-0005 §mock): MockScenario verisini deterministik oynatır. Rastgelelik, zaman, OS yok.
## UI/render/aktör hatları gerçek sim (T-027) gelmeden buna karşı geliştirir. Her DTO `provenance = &"mock"` taşır;
## UI bunu "MOCK" rozetiyle gösterir (`app.mock_badge`). Buradaki sayılar SAHTEDİR, oyun dengesi değildir.
##
## Davranış (gerçek sim ile aynı sözleşme yüzeyi):
## - `submit_command`: ortak şekil doğrulaması (SimCommand.validate_shape) + duruma bağlı denetim (parsel var mı,
##   bütçe kalemi var mı, bekleyen bütçe oylaması var mı); geçerse kuyruğa, sonraki tick'te uygulanır.
## - Uygulamada: komutun genel anlamı (imar → parsel.pending_zone; bütçe → kalem.proposed + status proposed),
##   `command.applied` olayı, sonra senaryodaki ilk eşleşen kuralın etkileri `after_ticks` sonra yürür.
##   Kural `reject` taşıyorsa komut tick sınırında `command.rejected` olayıyla reddedilir.

const MOCK_WORLD_ID := &"mock.world"

var _scenario: MockScenario = null
var _tick: int = 0
var _speed: int = SPEED_PAUSED
var _available: PackedInt32Array = PackedInt32Array([SPEED_PAUSED, SPEED_NORMAL, SPEED_FAST, SPEED_FASTEST])
var _world_id: StringName = MOCK_WORLD_ID
var _land_uses: PackedStringArray = PackedStringArray()
var _parcels: Dictionary = {}  # int -> ParcelView
var _budget: BudgetView = BudgetView.new()
var _council: CouncilView = CouncilView.new()
var _groups: Array[GroupReactionView] = []
var _events: Array[SimEvent] = []
var _reasons: Array[ReasonRecord] = []
var _queue: Array[Dictionary] = []  # {"id": int, "command": SimCommand}
var _pending: Array[Dictionary] = []  # {"due": int, "order": int, "effect": Dictionary, "ctx": Dictionary}
var _next_command_id: int = 1
var _order: int = 0
var _global_ctx: Dictionary = {"command_id": SimContract.NO_ID, "labels": {}}


## Geçersiz senaryo verilirse durum boş kalır; `load_errors()` nedenleri döner.
func _init(scenario: MockScenario = null) -> void:
	_scenario = scenario if scenario != null else MockScenario.from_dict({})
	if _scenario.is_valid():
		_load_initial(_scenario.data.get("initial", {}))
		var timeline: Array = _scenario.data.get("timeline", [])
		for effect: Dictionary in timeline:
			_schedule(SimContract.to_int(effect.get("at_tick")), effect, _global_ctx)


static func from_file(path: String) -> MockSimFacade:
	return MockSimFacade.new(MockScenario.load_file(path))


func load_errors() -> PackedStringArray:
	return _scenario.errors


func scenario_id() -> StringName:
	return _scenario.id


func provenance() -> StringName:
	return SimContract.PROVENANCE_MOCK


func current_tick() -> int:
	return _tick


func speed() -> int:
	return _speed


func available_speeds() -> PackedInt32Array:
	return _available.duplicate()


func set_speed(level: int) -> bool:
	if not _available.has(level):
		return false
	_speed = level
	return true


func advance(ticks: int) -> int:
	var n := maxi(ticks, 0)
	for _i in n:
		_tick += 1
		var queued := _queue
		_queue = []
		for entry in queued:
			_apply_command(entry["id"], entry["command"])
		_run_due()
	return n


func validate_command(command: SimCommand) -> CommandResult:
	var problem := _precheck(command)
	if not problem.is_empty():
		return CommandResult.rejected(command, problem["reason_key"], problem["args"], _tick, provenance())
	return CommandResult.accepted(command, CommandResult.STATUS_VALID, SimContract.NO_ID, _tick, provenance())


func submit_command(command: SimCommand) -> CommandResult:
	var problem := _precheck(command)
	if not problem.is_empty():
		return CommandResult.rejected(command, problem["reason_key"], problem["args"], _tick, provenance())
	var id := _next_command_id
	_next_command_id += 1
	_queue.append({"id": id, "command": SimCommand.from_dict(command.to_dict())})
	return CommandResult.accepted(command, CommandResult.STATUS_QUEUED, id, _tick, provenance())


func snapshot() -> SimSnapshot:
	var s := SimSnapshot.new()
	s.provenance = provenance()
	s.world_id = _world_id
	s.scenario_id = _scenario.id
	s.clock.tick = _tick
	s.clock.speed = _speed
	s.clock.available_speeds = _available.duplicate()
	s.last_event_seq = last_event_seq()
	s.parcel_count = _parcels.size()
	s.budget = BudgetView.from_dict(_budget.to_dict())
	s.council = CouncilView.from_dict(_council.to_dict())
	for g in _groups:
		s.group_reactions.append(GroupReactionView.from_dict(g.to_dict()))
	return s


func parcel_ids(region_code: StringName = &"") -> PackedInt64Array:
	var ids: Array = _parcels.keys()
	ids.sort()
	var out := PackedInt64Array()
	for id: int in ids:
		if region_code == &"" or (_parcels[id] as ParcelView).region_code == region_code:
			out.append(id)
	return out


func parcel_views(ids: PackedInt64Array) -> Array[ParcelView]:
	var out: Array[ParcelView] = []
	for id in ids:
		if _parcels.has(id):
			out.append(ParcelView.from_dict((_parcels[id] as ParcelView).to_dict()))
	return out


func events_since(after_seq: int, max_count: int = 0) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for i in range(maxi(after_seq, 0), _events.size()):
		if max_count > 0 and out.size() >= max_count:
			break
		out.append(SimEvent.from_dict(_events[i].to_dict()))
	return out


func last_event_seq() -> int:
	return _events.size()


func first_retained_event_seq() -> int:
	return 1


func reasons_for(subject_ref: StringName) -> Array[ReasonRecord]:
	var out: Array[ReasonRecord] = []
	for r in _reasons:
		if r.is_about(subject_ref):
			out.append(ReasonRecord.from_dict(r.to_dict()))
	return out


func reason(reason_id: int) -> ReasonRecord:
	if reason_id < 1 or reason_id > _reasons.size():
		return null
	return ReasonRecord.from_dict(_reasons[reason_id - 1].to_dict())


# --- Yükleme ---

func _load_initial(initial: Dictionary) -> void:
	_tick = SimContract.to_int(initial.get("tick"))
	_speed = SimContract.to_int(initial.get("speed", SPEED_PAUSED))
	_world_id = SimContract.to_name(initial.get("world_id", MOCK_WORLD_ID))
	_land_uses = SimContract.to_string_array(initial.get("land_uses", []))
	for pd: Variant in initial.get("parcels", []):
		var p := ParcelView.from_dict(pd)
		p.provenance = provenance()
		_parcels[p.id] = p
	if initial.get("budget") is Dictionary:
		_budget = BudgetView.from_dict(initial["budget"])
	if initial.get("council") is Dictionary:
		_council = CouncilView.from_dict(initial["council"])
	for gd: Variant in initial.get("groups", []):
		_upsert_group(GroupReactionView.from_dict(gd))


# --- Doğrulama ---

func _precheck(command: SimCommand) -> Dictionary:
	if command == null:
		return {"reason_key": CommandResult.REJECT_UNKNOWN_KIND, "args": {}}
	var shape := command.validate_shape()
	return shape if not shape.is_empty() else _state_problem(command)


func _state_problem(command: SimCommand) -> Dictionary:
	match command.kind:
		SimCommand.KIND_ZONING_PROPOSE:
			for id: int in command.params["parcel_ids"]:
				if not _parcels.has(id):
					return _problem(CommandResult.REJECT_INVALID_TARGET, {"ref": SimContract.parcel_ref(id)})
			if not _land_uses.is_empty() and not _land_uses.has(String(command.params["land_use"])):
				return _problem(CommandResult.REJECT_INVALID_VALUE, {"param": "land_use"})
		SimCommand.KIND_BUDGET_PROPOSE:
			if _budget.status == BudgetView.STATUS_PROPOSED:
				return _problem(CommandResult.REJECT_PRECONDITION,
					{"ref": SimContract.ref(SimContract.REF_VOTE, _budget.pending_vote_id)})
			for key: StringName in command.params["lines"]:
				if _budget.line(key) == null:
					return _problem(CommandResult.REJECT_INVALID_TARGET, {"ref": key})
	return {}


static func _problem(key: StringName, args: Dictionary) -> Dictionary:
	return {"reason_key": key, "args": args}


# --- Uygulama ---

func _apply_command(id: int, command: SimCommand) -> void:
	var ctx := {"command_id": id, "labels": {}}
	var command_ref := String(SimContract.ref(SimContract.REF_COMMAND, id))
	var rule := _match_rule(command)
	var problem := _state_problem(command)
	if problem.is_empty() and rule.get("reject") is Dictionary:
		problem = _problem(SimContract.to_name(rule["reject"].get("reason_key")),
			(rule["reject"].get("args", {}) as Dictionary).duplicate(true))
	if not problem.is_empty():
		_emit({"kind": SimEvent.KIND_COMMAND_REJECTED, "message_key": problem["reason_key"],
			"args": problem["args"], "subjects": [command_ref]}, ctx)
		return
	var subjects := _apply_semantics(command)
	subjects.append(command_ref)
	_emit({"kind": SimEvent.KIND_COMMAND_APPLIED, "message_key": &"event.command.applied",
		"args": {"kind": command.kind}, "subjects": subjects}, ctx)
	var effects: Array = rule.get("effects", [])
	for effect: Dictionary in effects:
		_schedule(_tick + SimContract.to_int(effect.get("after_ticks")), effect, ctx)


## Komutun senaryodan bağımsız genel anlamı; etkilenen varlık referanslarını döner.
func _apply_semantics(command: SimCommand) -> PackedStringArray:
	var subjects := PackedStringArray()
	match command.kind:
		SimCommand.KIND_ZONING_PROPOSE:
			for id: int in command.params["parcel_ids"]:
				(_parcels[id] as ParcelView).pending_zone = command.params["land_use"]
				subjects.append(String(SimContract.parcel_ref(id)))
		SimCommand.KIND_BUDGET_PROPOSE:
			var lines: Dictionary = command.params["lines"]
			for key: StringName in lines:
				_budget.line(key).proposed = lines[key]
			_budget.status = BudgetView.STATUS_PROPOSED
			subjects.append(String(SimContract.ref(SimContract.REF_BUDGET, _budget.period)))
	return subjects


func _match_rule(command: SimCommand) -> Dictionary:
	var rules: Array = _scenario.data.get("rules", [])
	for rule: Dictionary in rules:
		var when: Dictionary = rule["when"]
		if SimContract.to_name(when.get("kind")) != command.kind:
			continue
		var wanted := SimCommand.from_dict({"kind": command.kind, "params": when.get("params", {})}).params
		var matches := true
		for p: String in wanted:
			if not command.params.has(p) or command.params[p] != wanted[p]:
				matches = false
		if matches:
			return rule
	return {}


func _schedule(due: int, effect: Dictionary, ctx: Dictionary) -> void:
	_order += 1
	_pending.append({"due": due, "order": _order, "effect": effect, "ctx": ctx})


func _run_due() -> void:
	var due: Array[Dictionary] = []
	var later: Array[Dictionary] = []
	for p in _pending:
		if int(p["due"]) <= _tick:
			due.append(p)
		else:
			later.append(p)
	_pending = later
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	for p in due:
		_run_effect(p["effect"], p["ctx"])


func _run_effect(effect: Dictionary, ctx: Dictionary) -> void:
	var labels := _resolve(effect.get("reason_labels", []), ctx)
	match str(effect.get("type")):
		"reason":
			_add_reason(effect, ctx)
		"event":
			_emit(effect["event"], ctx)
		"parcel":
			var id := SimContract.to_int(effect.get("parcel_id"))
			if _parcels.has(id):
				var merged: Dictionary = (_parcels[id] as ParcelView).to_dict().merged(effect.get("set", {}), true)
				var p := ParcelView.from_dict(merged)
				p.provenance = provenance()
				if not labels.is_empty():
					p.reason_ids = labels
				_parcels[id] = p
		"group":
			var g := GroupReactionView.from_dict(effect.get("reaction", {}))
			g.tick = _tick
			g.reason_ids = labels
			_upsert_group(g)
		"budget":
			_patch_budget(effect, labels)
		"council_vote":
			_upsert_vote(effect.get("vote", {}), labels, ctx)


func _add_reason(effect: Dictionary, ctx: Dictionary) -> void:
	var rd: Dictionary = effect["reason"]
	var r := ReasonRecord.from_dict(rd)
	r.id = _reasons.size() + 1
	r.tick = _tick
	r.provenance = provenance()
	r.parent_ids = _resolve(rd.get("parent_labels", []), ctx)
	if int(ctx["command_id"]) != SimContract.NO_ID:
		r.subjects.append(String(SimContract.ref(SimContract.REF_COMMAND, ctx["command_id"])))
	r.finalize()
	_reasons.append(r)
	(ctx["labels"] as Dictionary)[str(effect["label"])] = r.id


func _emit(ed: Dictionary, ctx: Dictionary) -> void:
	var e := SimEvent.from_dict(ed)
	e.seq = _events.size() + 1
	e.tick = _tick
	e.provenance = provenance()
	e.command_id = ctx["command_id"]
	e.reason_ids.append_array(_resolve(ed.get("reason_labels", []), ctx))
	_events.append(e)


## `commit_proposal`: öneri yürürlüğe girer (approved); `discard_proposal`: öneri düşer (rejected).
func _patch_budget(effect: Dictionary, labels: PackedInt64Array) -> void:
	var b := BudgetView.from_dict(_budget.to_dict().merged(effect.get("set", {}), true))
	if SimContract.to_bool(effect.get("commit_proposal", false)):
		for l in b.lines:
			l.amount = l.proposed
		b.status = BudgetView.STATUS_APPROVED
		b.pending_vote_id = SimContract.NO_ID
	elif SimContract.to_bool(effect.get("discard_proposal", false)):
		for l in b.lines:
			l.proposed = l.amount
		b.status = BudgetView.STATUS_REJECTED
		b.pending_vote_id = SimContract.NO_ID
	if not labels.is_empty():
		b.reason_ids = labels
	_budget = b


## Oylama verisi mevcut oylamayla BİRLEŞTİRİLİR (açılış tick'i korunur). Yeni oylamada `opened_tick` yoksa şimdiki
## tick; `closes_after` verilirse `closes_tick = şimdiki tick + closes_after`.
func _upsert_vote(vote_data: Dictionary, labels: PackedInt64Array, ctx: Dictionary) -> void:
	var vd := vote_data.duplicate(true)
	var existing_vote := _council.vote(SimContract.to_int(vd.get("vote_id")))
	if existing_vote != null:
		vd = existing_vote.to_dict().merged(vd, true)
	elif not vd.has("opened_tick"):
		vd["opened_tick"] = _tick
	if vd.has("closes_after"):
		vd["closes_tick"] = _tick + SimContract.to_int(vd["closes_after"])
	for pos: Variant in vd.get("positions", []):
		if pos is Dictionary and pos.has("reason_label"):
			var ids := _resolve([pos["reason_label"]], ctx)
			pos["reason_id"] = ids[0] if not ids.is_empty() else SimContract.NO_ID
	var v := CouncilVoteView.from_dict(vd)
	if not labels.is_empty():
		v.reason_ids = labels
	var kept: Array[CouncilVoteView] = []
	for existing in _council.votes:
		if existing.vote_id != v.vote_id:
			kept.append(existing)
	kept.append(v)
	kept.sort_custom(func(a: CouncilVoteView, b: CouncilVoteView) -> bool: return a.vote_id < b.vote_id)
	_council.votes = kept


func _upsert_group(g: GroupReactionView) -> void:
	var kept: Array[GroupReactionView] = []
	for existing in _groups:
		if existing.group.ref() != g.group.ref():
			kept.append(existing)
	kept.append(g)
	kept.sort_custom(_group_before)
	_groups = kept


# StringName `<` sırası garanti değil; String karşılaştırması deterministiktir.
static func _group_before(a: GroupReactionView, b: GroupReactionView) -> bool:
	return String(a.group.ref()) < String(b.group.ref())


func _resolve(labels: Variant, ctx: Dictionary) -> PackedInt64Array:
	var out := PackedInt64Array()
	var local: Dictionary = ctx["labels"]
	var global: Dictionary = _global_ctx["labels"]
	for label in SimContract.to_string_array(labels):
		if local.has(label):
			out.append(local[label])
		elif global.has(label):
			out.append(global[label])
	return out
