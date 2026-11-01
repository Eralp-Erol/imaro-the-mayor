# gdlint:disable=max-public-methods
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
## v1.3 · Uygulanmış oyuncu yolları (LIFO): {"work": PublicWorkView}. Mock geometri hesaplamaz; bölge birimleri senaryo
## kuralının `preview.regions` verisidir.
var _roads: Array[PublicWorkView] = []
## D-014: klasik geri al penceresi (yeni yol açar, geri alma kapatır).
var _undo_open: bool = false
## v1.5 · Kamulaştırmada alınan parsellerin önceki hali: komut kimliği -> {parsel kimliği -> ParcelView.to_dict()}.
var _taken_saved: Dictionary = {}
## v1.5 · Senaryonun `agenda` etkisiyle açtığı gündem öğeleri (kimlik artan). Geri alma onları kaldırmaz (D-011).
var _agenda: Array[AgendaItemView] = []
var _order: int = 0
var _global_ctx: Dictionary = {"command_id": SimContract.NO_ID, "labels": {}}
## v1.2 · Parsel değişim günlüğü (mock: sınırsız, kayıt yüklemesi yok): tick ve kimlik paralel, tick artan.
var _change_ticks: PackedInt32Array = PackedInt32Array()
var _change_ids: PackedInt64Array = PackedInt64Array()


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
	return _accepted(command, CommandResult.STATUS_VALID, SimContract.NO_ID)


func submit_command(command: SimCommand) -> CommandResult:
	var problem := _precheck(command)
	if not problem.is_empty():
		return CommandResult.rejected(command, problem["reason_key"], problem["args"], _tick, provenance())
	var id := _next_command_id
	_next_command_id += 1
	_queue.append({"id": id, "command": SimCommand.from_dict(command.to_dict())})
	return _accepted(command, CommandResult.STATUS_QUEUED, id)


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


## v1.2 · `parcel` etkisiyle değişen parseller (mock'ta olay saklama ufku yoktur; epoch hep 0). `tick` -1 = baştan.
func parcel_changes_since(tick: int) -> ParcelChangeFeed:
	var feed := ParcelChangeFeed.incomplete(provenance(), _tick)
	if tick < -1 or tick > _tick:
		return feed
	feed.complete = true
	var seen := {}
	for k in _change_ticks.size():
		if _change_ticks[k] > tick:
			seen[_change_ids[k]] = true
	var ids: Array = seen.keys()
	ids.sort()
	feed.ids = PackedInt64Array(ids)
	return feed


## v1.6 (D-014) · Klasik geri al: yalnız en son yol ve henüz geri alınmadıysa (gerçek sim ile aynı kural).
func undo_available() -> bool:
	return _undo_open and not _roads.is_empty()


## v1.3 · Uygulanmış yollar (eskiden yeniye).
func public_works() -> Array[PublicWorkView]:
	var out: Array[PublicWorkView] = []
	for w in _roads:
		out.append(PublicWorkView.from_dict(w.to_dict()))
	return out


## v1.5 (isteğe bağlı) · Senaryonun `agenda` etkisiyle açtığı AÇIK, süresi dolmamış öğeler (kimlik artan).
func agenda_items() -> Array[AgendaItemView]:
	var out: Array[AgendaItemView] = []
	for it in _agenda:
		if it.status == AgendaItemView.STATUS_OPEN and it.deadline_tick > _tick:
			out.append(AgendaItemView.from_dict(it.to_dict()))
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
		SimCommand.KIND_PUBLIC_WORK_ROAD, SimCommand.KIND_PUBLIC_WORK_UNDO_LAST, SimCommand.KIND_AGENDA_RESPOND:
			return _public_work_problem(command) if command.kind != SimCommand.KIND_AGENDA_RESPOND \
				else _agenda_response_problem(command)
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


## v1.5 · Gündem yanıtı: gerçek sim ile aynı ret kodları (hedef yok -> invalid_target; kapalı öğe -> precondition
## agenda.closed; listede olmayan seçenek -> invalid_value; kilitli -> precondition authority.locked).
func _agenda_response_problem(command: SimCommand) -> Dictionary:
	var item_id: int = command.params["item_id"]
	var item := _agenda_item(item_id)
	var ref := String(SimContract.ref(SimContract.REF_AGENDA, item_id))
	if item == null:
		return _problem(CommandResult.REJECT_INVALID_TARGET, {"ref": ref})
	if item.status != AgendaItemView.STATUS_OPEN or item.deadline_tick <= _tick:
		return _problem(CommandResult.REJECT_PRECONDITION, {"why": "agenda.closed", "ref": ref})
	for option in item.options:
		if option.option_id == command.params["option_id"]:
			if not option.available:
				return _problem(CommandResult.REJECT_PRECONDITION,
					{"why": "authority.locked", "authority": String(option.locked_by)})
			return {}
	return _problem(CommandResult.REJECT_INVALID_VALUE, {"param": "option_id"})


func _agenda_item(item_id: int) -> AgendaItemView:
	for item in _agenda:
		if item.item_id == item_id:
			return item
	return null


## v1.3 · Yol komutları: ret senaryo kuralından (`reject.reason_key` `public_work.reject.*`), geri alma durumdan.
func _public_work_problem(command: SimCommand) -> Dictionary:
	if command.kind == SimCommand.KIND_PUBLIC_WORK_UNDO_LAST:
		if _roads.is_empty():
			return _problem(CommandResult.REJECT_NOTHING_TO_UNDO, {})
		if not _undo_open:  # geri alma yığılmaz (D-014)
			return _problem(&"public_work.reject.undo_window_closed", {"cause": "superseded"})
		return {}
	var rule := _match_rule(command)
	var reject: Variant = rule.get("reject")
	if reject is Dictionary and String(SimContract.to_name(reject.get("reason_key"))).begins_with(
			CommandResult.REJECT_PUBLIC_WORK_PREFIX):
		return _problem(SimContract.to_name(reject["reason_key"]), (reject.get("args", {}) as Dictionary).duplicate(true))
	if _expropriates(command) and _expropriation_of(rule).is_empty():  # v1.5: senaryo kamulaştırma sunmuyor
		return _problem(CommandResult.REJECT_EXPROPRIATION_DISABLED, {})
	return {}


## `valid`/`queued` sonucu: yol komutunda ön izleme `args` (uzunluk komut noktalarından düz aritmetik; bölge birimleri
## senaryo verisi); geri almada kaldırılacak yol. Mock geometri hesaplamaz.
func _accepted(command: SimCommand, status: StringName, id: int) -> CommandResult:
	var result := CommandResult.accepted(command, status, id, _tick, provenance())
	if command.kind == SimCommand.KIND_PUBLIC_WORK_ROAD:
		var regions: Dictionary = (_match_rule(command).get("preview", {}) as Dictionary).get("regions", {})
		var length_cm := _length_cm(command.params["points_cm"])
		result.args = {"length_cm": length_cm, "length_m": roundi(length_cm * 0.01),
			"regions": SimContract.to_args(regions), "units_total": _sum(regions),
			"cost_available": false, "cost_reason_key": "public_work.cost.not_built"}
		if _expropriates(command):  # v1.5: sayılar senaryo verisi, anahtarlar gerçek sim ile aynı yardımcıdan
			result.args.merge(SimContract.to_args(ExpropriationSummary.preview_args(
				_expropriation_of(_match_rule(command)))))
	elif command.kind == SimCommand.KIND_PUBLIC_WORK_UNDO_LAST and not _roads.is_empty():
		var last := _roads[_roads.size() - 1]
		result.args = {"removed_command_id": last.command_id, "length_cm": last.length_cm,
			"regions": last.region_units.duplicate()}
	return result


static func _length_cm(points_cm: PackedInt64Array) -> int:
	var total := 0.0
	var i := 0
	while i + 3 < points_cm.size():
		total += Vector2(points_cm[i], points_cm[i + 1]).distance_to(Vector2(points_cm[i + 2], points_cm[i + 3]))
		i += 2
	return roundi(total)


static func _sum(units: Dictionary) -> int:
	var total := 0
	for k: Variant in units:
		total += SimContract.to_int(units[k])
	return total


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
	_apply_public_work(id, command, ctx)
	var subjects := _apply_semantics(command)
	subjects.append(command_ref)
	_emit({"kind": SimEvent.KIND_COMMAND_APPLIED, "message_key": &"event.command.applied",
		"args": {"kind": command.kind}, "subjects": subjects}, ctx)
	var effects: Array = rule.get("effects", [])
	for effect: Dictionary in effects:
		_schedule(_tick + SimContract.to_int(effect.get("after_ticks")), effect, ctx)


## v1.3 · Yol uygulaması: gerçek sim sırası (işleyici olayı, sonra `command.applied`). Mock geometri hesaplamaz.
func _apply_public_work(id: int, command: SimCommand, ctx: Dictionary) -> void:
	var command_ref := String(SimContract.ref(SimContract.REF_COMMAND, id))
	if command.kind == SimCommand.KIND_PUBLIC_WORK_ROAD:
		var w := PublicWorkView.new()
		w.provenance = provenance()
		w.work_id = _roads.size() + 1
		w.command_id = id
		w.tick = _tick
		w.road_class = command.params["road_class"]
		w.length_cm = _length_cm(command.params["points_cm"])
		var rule := _match_rule(command)
		w.region_units = SimContract.to_args((rule.get("preview", {}) as Dictionary).get("regions", {}))
		if _expropriates(command):
			_take_parcels(id, w, _expropriation_of(rule), ctx)
		_roads.append(w)
		_undo_open = true
		_emit_road_event(SimEvent.KIND_PUBLIC_WORK_BUILT, &"event.road.built", command_ref, w, {}, ctx)
	elif command.kind == SimCommand.KIND_PUBLIC_WORK_UNDO_LAST and not _roads.is_empty():
		var removed: PublicWorkView = _roads.pop_back()
		_undo_open = false
		if removed.expropriated:
			_restore_parcels(removed, ctx, id)
		_emit_road_event(SimEvent.KIND_PUBLIC_WORK_REMOVED, &"event.road.removed", command_ref, removed,
			{"removed_command_id": removed.command_id}, ctx)


## v1.5 · Kamulaştırma bayrağı ve senaryonun kamulaştırma verisi (`preview.expropriation`, yoksa {}).
static func _expropriates(command: SimCommand) -> bool:
	return command.kind == SimCommand.KIND_PUBLIC_WORK_ROAD and bool(command.params.get("expropriate", false))


static func _expropriation_of(rule: Dictionary) -> Dictionary:
	var preview: Variant = rule.get("preview", {})
	var data: Variant = preview.get("expropriation", {}) if preview is Dictionary else {}
	return data if data is Dictionary else {}


## Senaryodaki parselleri `taken` yapar (önceki hali saklanır), `public_work.expropriated` olayını yayımlar.
func _take_parcels(id: int, w: PublicWorkView, data: Dictionary, ctx: Dictionary) -> void:
	var saved := {}
	for pid in ExpropriationSummary.sorted_ids(data):
		if not _parcels.has(pid):
			continue
		var p: ParcelView = _parcels[pid]
		saved[pid] = p.to_dict()
		p.development = ParcelView.DEVELOPMENT_TAKEN
		p.use = ParcelView.USE_NONE
		p.units = 0
		p.progress_pm = 0
		p.developed_by_sim = false
		p.decision = ParcelView.DECISION_NONE
		p.decision_code = &""
		p.decision_tick = -1
		p.decision_reason_id = SimContract.NO_ID
		p.taken_by_command = id
		_change_ticks.append(_tick)
		_change_ids.append(pid)
	_taken_saved[id] = saved
	w.expropriated = true
	w.taken_parcel_ids = ExpropriationSummary.sorted_ids(data)
	w.taken_built_parcels = SimContract.to_int(data.get("built_parcels"))
	w.taken_res_units = SimContract.to_int(data.get("res_units"))
	w.taken_com_units = SimContract.to_int(data.get("com_units"))
	w.displaced_households = SimContract.to_int(data.get("households"))
	_emit({"kind": SimEvent.KIND_PUBLIC_WORK_EXPROPRIATED, "message_key": &"event.road.expropriated",
		"args": ExpropriationSummary.event_args(data),
		"subjects": ExpropriationSummary.subjects(id, data)}, ctx)


## Geri alma: parseller önceki haline döner; halk tepkisi (grup durumu) GERİ ALINMAZ.
func _restore_parcels(removed: PublicWorkView, ctx: Dictionary, undo_id: int) -> void:
	var saved: Dictionary = _taken_saved.get(removed.command_id, {})
	for pid: int in saved:
		var p := ParcelView.from_dict(saved[pid])
		p.provenance = provenance()
		_parcels[pid] = p
		_change_ticks.append(_tick)
		_change_ids.append(pid)
	_taken_saved.erase(removed.command_id)
	var data := {"parcel_ids": removed.taken_parcel_ids, "built_parcels": removed.taken_built_parcels,
		"res_units": removed.taken_res_units, "com_units": removed.taken_com_units,
		"households": removed.displaced_households, "regions": _regions_of(removed.taken_parcel_ids)}
	var args := ExpropriationSummary.event_args(data)
	args["removed_command_id"] = removed.command_id
	_emit({"kind": SimEvent.KIND_PUBLIC_WORK_RESTORED, "message_key": &"event.road.restored", "args": args,
		"subjects": ExpropriationSummary.subjects(undo_id, data)}, ctx)


func _regions_of(parcel_ids: PackedInt64Array) -> Dictionary:
	var out := {}
	for pid in parcel_ids:
		if _parcels.has(pid):
			var code := String((_parcels[pid] as ParcelView).region_code)
			out[code] = int(out.get(code, 0)) + 1
	return out


func _emit_road_event(kind: StringName, message_key: StringName, command_ref: String, w: PublicWorkView,
		extra: Dictionary, ctx: Dictionary) -> void:
	var subjects: Array = [command_ref]
	var codes: Array = w.region_units.keys()
	codes.sort()
	var args := {"road_class": w.road_class, "length_cm": w.length_cm, "length_m": roundi(w.length_cm * 0.01),
		"units_total": _sum(w.region_units)}
	args.merge(extra)
	for code: String in codes:
		subjects.append("%s.%s" % [SimContract.REF_REGION, code])
		args["units.%s" % code] = w.region_units[code]
	_emit({"kind": kind, "message_key": message_key, "args": args, "subjects": subjects}, ctx)


## Komutun senaryodan bağımsız genel anlamı; etkilenen varlık referanslarını döner.
func _apply_semantics(command: SimCommand) -> PackedStringArray:
	var subjects := PackedStringArray()
	match command.kind:
		SimCommand.KIND_ZONING_PROPOSE:
			for id: int in command.params["parcel_ids"]:
				(_parcels[id] as ParcelView).pending_zone = command.params["land_use"]
				subjects.append(String(SimContract.parcel_ref(id)))
		SimCommand.KIND_AGENDA_RESPOND:  # öğe kapanır; mock sayı/etki uydurmaz (senaryo kuralı isterse ekler)
			var item := _agenda_item(command.params["item_id"])
			item.status = AgendaItemView.STATUS_RESOLVED
			subjects.append(String(item.ref()))
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
		# v1.5: kuralda `expropriate` yazmıyorsa false demektir (kamulaştırmalı komut kamulaştırmasız kurala düşmez)
		if matches and command.kind == SimCommand.KIND_PUBLIC_WORK_ROAD \
				and bool(wanted.get("expropriate", false)) != _expropriates(command):
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
				_apply_decision(p, effect, ctx)
				_parcels[id] = p
				_change_ticks.append(_tick)
				_change_ids.append(id)
		"group":
			var g := GroupReactionView.from_dict(effect.get("reaction", {}))
			g.tick = _tick
			g.reason_ids = labels
			_upsert_group(g)
		"budget":
			_patch_budget(effect, labels)
		"council_vote":
			_upsert_vote(effect.get("vote", {}), labels, ctx)
		"agenda":
			_open_agenda_item(effect.get("item", {}), labels)


## v1.2: `set` içinde `decision` varsa karar tick'i yoksa şimdiki tick olur; `decision_reason_label` (etiket) kararın
## gerekçe kimliğini çözer (yoksa 0). Sim'deki `ParcelView.decision*` ile aynı alanlar.
func _apply_decision(p: ParcelView, effect: Dictionary, ctx: Dictionary) -> void:
	var set_fields: Dictionary = effect.get("set", {})
	if set_fields.has("decision") and not set_fields.has("decision_tick"):
		p.decision_tick = _tick if p.decision != ParcelView.DECISION_NONE else -1
	if effect.has("decision_reason_label"):
		var ids := _resolve([effect["decision_reason_label"]], ctx)
		p.decision_reason_id = ids[0] if not ids.is_empty() else SimContract.NO_ID


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


## Gündem öğesi açar: `opened_tick` yoksa şimdiki tick; `expires_after` varsa `deadline_tick = şimdi + expires_after`.
## Etiketler (`reason_labels`) öğenin `reason_ids`ini çözer. Aynı kimlikli öğe değiştirilir.
func _open_agenda_item(item_data: Dictionary, labels: PackedInt64Array) -> void:
	var d := item_data.duplicate(true)
	if not d.has("opened_tick"):
		d["opened_tick"] = _tick
	if d.has("expires_after"):
		d["deadline_tick"] = _tick + SimContract.to_int(d["expires_after"])
	var v := AgendaItemView.from_dict(d)
	v.provenance = provenance()
	if not labels.is_empty():
		v.reason_ids = labels
	var kept: Array[AgendaItemView] = []
	for existing in _agenda:
		if existing.item_id != v.item_id:
			kept.append(existing)
	kept.append(v)
	kept.sort_custom(func(a: AgendaItemView, b: AgendaItemView) -> bool: return a.item_id < b.item_id)
	_agenda = kept


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
