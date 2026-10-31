class_name PoliticsQuery
extends RefCounted
## Siyasi durumun salt okunur sorguları (T-017): sözleşme görünümleri (GroupReactionView, CouncilView), gündem öğeleri,
## medya tonu, tahmin ve yatırımcı siyasi riski. T-022 (karar akışları), T-026 ve HUD için API. Durumu DEĞİŞTİRMEZ;
## dönenler değer kopyasıdır. Gerekçe kimlikleri yalnız hâlâ saklananlardır (budanmış kayıt görünürde kalmaz).

const SCALE := 1000


## Kesim başına tepki (sıralı: kesim anahtarı), toplam skor yok (SIM-09).
static func group_views(state: GameState) -> Array[GroupReactionView]:
	var out: Array[GroupReactionView] = []
	var first := state.reasons.first_id()
	for key in PoliticsState.bloc_keys(state):
		var bloc: Dictionary = PoliticsState.data(state)["blocs"][key]
		var ev: Dictionary = bloc["eval"]
		var view := GroupReactionView.new()
		view.group = actor_ref_of(state, key)
		var hot := str(bloc.get("hot_region", ""))
		view.region_code = StringName(hot if not hot.is_empty() else _largest_region(bloc["exposure"]))
		view.stance = int(ev["stance"])
		view.stance_delta = int(ev["stance_delta"])
		view.reaction = StringName(ev["reaction"])
		view.intensity = int(ev["intensity"])
		view.cause_refs = PackedStringArray(ev["cause_refs"])
		view.reason_ids = _retained(ev["reason_ids"], first)
		view.tick = maxi(int(ev["tick"]), 0)
		out.append(view)
	return out


## Meclis görünümü: üyeler (koltuk başına bir blok) ve oylamalar (kimlik artan).
static func council_view(state: GameState, ctx: PoliticsContext) -> CouncilView:
	var view := CouncilView.new()
	view.council = ReasonAdapter.actor_of(StringName(ctx.politics.council["body"]))
	view.seats_total = (ctx.politics.council["members"] as Array).size()
	var player := ActorStore.protagonist_key(state, ctx.actors)
	for member: String in ctx.politics.council["members"]:
		view.blocs.append(member_view(state, ctx, member, player))
	var first := state.reasons.first_id()
	for vote: Dictionary in PoliticsState.data(state)["council"]["votes"]:
		view.votes.append(vote_view(state, ctx, vote, first))
	return view


static func member_view(state: GameState, ctx: PoliticsContext, member: String, player: String) -> CouncilBlocView:
	var bloc := CouncilBlocView.new()
	bloc.bloc = actor_ref_of(state, member)
	bloc.seats = 1
	bloc.stance = int(ActorStore.relation(state, ctx.actors, member, player)["trust"])
	return bloc


static func vote_view(state: GameState, ctx: PoliticsContext, vote: Dictionary, first_reason: int) -> CouncilVoteView:
	var view := CouncilVoteView.new()
	view.vote_id = int(vote["id"])
	view.subject_ref = StringName(vote["subject_ref"])
	view.title_key = StringName(vote["title_key"])
	view.opened_tick = int(vote["opened_tick"])
	view.closes_tick = int(vote["closes_tick"])
	view.status = StringName(vote["status"])
	view.yes = int(vote["yes"])
	view.no = int(vote["no"])
	view.abstain = int(vote["abstain"])
	var player := ActorStore.protagonist_key(state, ctx.actors)
	for position: Dictionary in vote["positions"]:
		var bloc := member_view(state, ctx, position["member"], player)
		bloc.position = StringName(position["position"])
		bloc.reason_id = int(position["reason_id"]) if int(position["reason_id"]) >= first_reason else 0
		view.positions.append(bloc)
	view.reason_ids = _retained(vote["reason_ids"], first_reason)
	return view


## Bekleyen oylamaların kayıtsız tahmini (sonuçtan ayrı): {oylama kimliği: {yes, no, abstain, swing, passes}}.
static func forecasts(state: GameState, ctx: PoliticsContext) -> Dictionary:
	var out := {}
	for vote: Dictionary in PoliticsState.data(state)["council"]["votes"]:
		if vote["status"] == CouncilEngine.PENDING:
			out[int(vote["id"])] = CouncilEngine.forecast(state, ctx, vote)
	return out


## Gündem öğeleri (kimlik artan): {öğe alanları, options [{id, verb, label_key, available, locked_by, costs}],
## days_left}. `only_open` ise yalnız açık olanlar.
static func agenda(state: GameState, ctx: PoliticsContext, only_open: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Dictionary in PoliticsState.data(state)["events"]["agenda"]:
		if only_open and item["status"] != EventEngine.OPEN:
			continue
		var entry: Dictionary = item.duplicate(true)
		entry["options"] = EventEngine.option_views(ctx, item)
		entry["days_left"] = maxi(int(item["deadline"]) - state.tick, 0)
		out.append(entry)
	return out


## Sözleşme görünümü (`SimFacade.agenda_items`, T-042b): AÇIK gündem öğeleri, kimlik artan. Sim'in kendi kaydıdır:
## `reason_ids` = ateşleme gerekçesi (hâlâ saklanıyorsa), `cause_refs` = ateşleme gerekçesinin ebeveyn (neden)
## kayıtlarındaki komut/parsel konuları (sıralı, yinelemesiz; PE-01 yerinden edilmede komut + alınan parseller).
static func agenda_views(state: GameState, ctx: PoliticsContext) -> Array[AgendaItemView]:
	var out: Array[AgendaItemView] = []
	var first := state.reasons.first_id()
	for item: Dictionary in PoliticsState.data(state)["events"]["agenda"]:
		if item["status"] != EventEngine.OPEN:
			continue
		var template := ctx.politics.template(item["template"])
		var view := AgendaItemView.new()
		view.item_id = int(item["id"])
		view.template_id = StringName(item["template"])
		view.delivery = StringName(item["delivery"])
		view.status = AgendaItemView.STATUS_OPEN
		view.region_code = StringName(item["region"])
		var bloc := str(item["bloc"])
		view.group = actor_ref_of(state, bloc) if not bloc.is_empty() else null
		view.opened_tick = int(item["opened_tick"])
		view.deadline_tick = int(item["deadline"])
		view.title_key = StringName(template.get("reason_key", ""))
		view.args = {"topic": str(item["topic"]), "stage": int(item["stage"])}
		view.reason_ids = _retained([int(item["reason_id"])], first)
		view.cause_refs = _cause_refs(state, view.reason_ids)
		out.append(view)
	return out


## Ateşleme gerekçelerinin ebeveyn kayıtlarındaki `command.N` / `parcel.N` konuları (kayıt sırası, yinelemesiz).
static func _cause_refs(state: GameState, fire_ids: PackedInt64Array) -> PackedStringArray:
	var out := PackedStringArray()
	for fire_id in fire_ids:
		var fire := state.reasons.peek(fire_id)
		for parent_id: int in fire.get("parent_ids", PackedInt64Array()):
			for subject: String in state.reasons.peek(parent_id).get("subjects", PackedStringArray()):
				if (subject.begins_with("command.") or subject.begins_with("parcel.")) and not out.has(subject):
					out.append(subject)
	return out


## Konu tonları (kopya).
static func media_tone(state: GameState) -> Dictionary:
	return PoliticsState.data(state)["media"]["tone"].duplicate()


## Bir kesimin gördüğü ton (-1000..1000).
static func tone_for(state: GameState, ctx: PoliticsContext, bloc_key: String) -> int:
	return MediaEngine.tone_for(state, ctx, bloc_key)


## Yatırımcı siyasi riski, 0..1000 (T-013 yatırım kararına faktör olarak girebilir); bilinmeyen bölge için taban.
static func political_risk(state: GameState, ctx: PoliticsContext, region: String) -> int:
	var risk: Dictionary = PoliticsState.data(state).get("risk", {})
	if risk.is_empty():
		return 0
	return int(risk["level"].get(region, clampi(EventSources.risk_base(state, ctx), 0, SCALE)))


## `actor.<tür>.<n>` anahtarı -> ActorRef (ad anahtarı aktörün kaydındaki `name_key`).
static func actor_ref_of(state: GameState, key: String) -> ActorRef:
	var ref := ReasonAdapter.actor_of(StringName(key))
	if ref == null:
		return null
	var template := ActorStore.actor_ref(state, key)
	if not template.is_empty():
		ref.name_key = StringName(template["name_key"])
	return ref


static func _largest_region(exposure: Dictionary) -> String:
	var best := ""
	var best_share := 0
	var codes: Array = exposure.keys()
	codes.sort()
	for code: String in codes:
		if int(exposure[code]) > best_share:
			best_share = int(exposure[code])
			best = code
	return best


static func _retained(ids: Array, first_reason: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	for id: int in ids:
		if id >= first_reason and id >= 1:
			out.append(id)
	return out
