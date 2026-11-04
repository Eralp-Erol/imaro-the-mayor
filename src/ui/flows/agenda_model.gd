class_name AgendaModel
extends RefCounted
## Gündem modeli (ux-flows-v0 §I, T-022). İki kaynak: açık meclis oylamaları (`CouncilVoteView.closes_tick`, `derive`)
## ve sim'in açık gündem öğeleri (`SimFacade.agenda_items`, v1.5 isteğe bağlı ek; `derive_all`).
## Meclis oylamasından türetilen öğede yanıt SEÇENEĞİ yoktur (oyuncu oylamaya komutla müdahale edemez). Sim öğesinde
## (`AgendaItemView.options`, v1.5) seçenekler sim'in verdiği gibi taşınır; `options` boşsa düğme YOKTUR. Bedel yok
## (sim düşmüyor), "ertele" yok (sim'de etkisiz; öğe zaten açık kalır).
## Gündem kaynağı yoksa (meclis kurulmamış) liste boştur ve panel "kurulmadı" der.

const KIND_COUNCIL_VOTE := &"council_vote"
## Sim gündem öğesi (`AgendaItemView`); gerekçe zincirinde yerinden edilme hane sayısı varsa `displacement`.
const KIND_EVENT := &"event"
const KIND_DISPLACEMENT := &"displacement"
## Sim'in yerinden edilme neden kaydı: bu etken adı kayıtta hane SAYISI taşır (T-042b, ağırlık 0 = yalnız gösterim).
const DISPLACED_COUNT_FACTOR := &"reason.factor.displaced_household_count"
## T-065: aynı neden kaydındaki yeniden iskân tahsisi sayımları (gerçek hane sayısı, ağırlık 0); yalnız politika AÇIK ve
## tahsis kaydı varken yazılır.
const REHOUSED_FACTOR := &"reason.factor.rehoused_households"
const UNPLACED_FACTOR := &"reason.factor.unplaced_households"
const CHAIN_DEPTH := 4


## Sim'in `AgendaOptionView`ı: kilit (`available`/`locked_by`) ve etki önizlemesi (yön + zaman, büyüklük YOK) aynen.
class Option:
	extends RefCounted
	var id: StringName = &""
	var verb: StringName = &""
	var label_key: StringName = &""
	var available: bool = true
	var locked_by: StringName = &""
	## `{target, scope, direction, delay_days, duration_days, curve}` sözlükleri.
	var effects: Array = []


class Item:
	extends RefCounted
	var id: StringName = &""
	var kind: StringName = KIND_COUNCIL_VOTE
	var title_key: StringName = &""
	var subject_ref: StringName = &""
	var vote_id: int = SimContract.NO_ID
	## Sim gündem öğesinin sayısal kimliği (`agenda_respond` komutu için); meclis oylamasında NO_ID.
	var agenda_item_id: int = SimContract.NO_ID
	var deadline_tick: int = 0
	var days_left: int = 0
	var options: Array[Option] = []
	var reason_ids: PackedInt64Array = PackedInt64Array()

	func answerable() -> bool:
		return not options.is_empty()



## `derive_all` önbelleği (kare başı maliyet: yerinden-edilme zinciri taraması + sıralama her tick koşmasın).
## Öğe KÜMESİ imzası (meclis oylamaları + sim gündem öğeleri: kimlik, süre, gerekçe, başlık, seçenekler) aynıysa önceki
## liste döner; yalnız `days_left` o günün tick'ine göre yenilenir (görünen sayılar `derive_all` ile birebir).
## İmza değişince `derive_all` yeniden koşar. Sayaçlar test/ölçüm içindir.
class Cache:
	extends RefCounted

	var builds: int = 0
	var hits: int = 0
	var _signature: String = ""
	var _items: Array[Item] = []
	var _valid: bool = false

	func items_for(facade: SimFacade, snapshot: SimSnapshot) -> Array[Item]:
		var views: Array[AgendaItemView] = facade.agenda_items() if facade != null else []
		var sig := AgendaModel.set_signature(snapshot, views)
		if _valid and sig == _signature:
			hits += 1
			var tick := snapshot.tick()
			for it in _items:
				it.days_left = maxi(0, it.deadline_tick - tick)
			return _items
		builds += 1
		_items = AgendaModel.derive_with(facade, snapshot, views)
		_signature = sig
		_valid = true
		return _items

	func invalidate() -> void:
		_valid = false


## Anlık görüntüden gündem öğeleri (süresi yakın olan önce).
static func derive(snapshot: SimSnapshot) -> Array[Item]:
	var out: Array[Item] = []
	if snapshot == null or not SimSections.council_built(snapshot):
		return out
	for v in snapshot.council.pending_votes():
		var it := Item.new()
		it.id = v.ref()
		it.title_key = v.title_key
		it.subject_ref = v.subject_ref
		it.vote_id = v.vote_id
		it.deadline_tick = v.closes_tick
		it.days_left = maxi(0, v.closes_tick - snapshot.tick())
		it.reason_ids = v.reason_ids
		out.append(it)
	out.sort_custom(func(a: Item, b: Item) -> bool:
		return a.deadline_tick < b.deadline_tick or (a.deadline_tick == b.deadline_tick and a.vote_id < b.vote_id))
	return out


## Gündem = açık meclis oylamaları (`derive`) + sim'in açık gündem öğeleri (`SimFacade.agenda_items`, v1.5; PE-01
## yerinden edilme dahil). İnce köprü: facade öğesi sözleşme alanlarını ve `options`ı aynen taşır; seçenek/erteleme
## UYDURMAZ (yanıt komutu `SimCommand.agenda_respond`, gönderimi panel yapar). Gerekçe zincirinde hane sayısı varsa
## tür `displacement`, yoksa `event`.
static func derive_all(facade: SimFacade, snapshot: SimSnapshot) -> Array[Item]:
	var views: Array[AgendaItemView] = facade.agenda_items() if facade != null else []
	return derive_with(facade, snapshot, views)


## `derive_all` ile aynı; sim gündem öğeleri çağıran tarafından verilir (önbellek imzayla aynı okumayı paylaşır).
static func derive_with(facade: SimFacade, snapshot: SimSnapshot, views: Array[AgendaItemView]) -> Array[Item]:
	var out := derive(snapshot)
	if facade != null:
		for v in views:
			var it := Item.new()
			it.id = v.ref()
			it.kind = KIND_DISPLACEMENT if bool(displaced_cause(facade, v.reason_ids)["found"]) else KIND_EVENT
			it.title_key = v.title_key
			it.deadline_tick = v.deadline_tick
			it.days_left = maxi(0, v.deadline_tick - snapshot.tick())
			it.reason_ids = v.reason_ids
			it.agenda_item_id = v.item_id
			for ov in v.options:
				it.options.append(_option_from(ov))
			out.append(it)
	out.sort_custom(func(a: Item, b: Item) -> bool:
		if a.deadline_tick != b.deadline_tick:
			return a.deadline_tick < b.deadline_tick
		return a.vote_id < b.vote_id or (a.vote_id == b.vote_id and String(a.id) < String(b.id)))
	return out


## Gündem KÜMESİNİN imzası: öğe listesini/sırasını/gösterilen alanları değiştirecek her sim okuması buradadır
## (`tick` HARİÇ: kalan gün ayrıca hesaplanır).
static func set_signature(snapshot: SimSnapshot, views: Array[AgendaItemView]) -> String:
	var parts: Array[String] = []
	if snapshot != null and SimSections.council_built(snapshot):
		for v in snapshot.council.pending_votes():
			parts.append("v%d/%s/%s/%d/%s" % [v.vote_id, v.title_key, v.subject_ref, v.closes_tick, v.reason_ids])
	for v in views:
		var opts: Array[String] = []
		for ov in v.options:
			opts.append("%s/%s/%s/%s/%s/%s" % [ov.option_id, ov.verb, ov.label_key, ov.available, ov.locked_by,
					ov.effects])
		parts.append("a%d/%s/%d/%s/%s/%s" % [v.item_id, v.title_key, v.deadline_tick, v.reason_ids,
				v.status, ";".join(opts)])
	return "|".join(parts)


static func _option_from(ov: AgendaOptionView) -> Option:
	var o := Option.new()
	o.id = ov.option_id
	o.verb = ov.verb
	o.label_key = ov.label_key
	o.available = ov.available
	o.locked_by = ov.locked_by
	o.effects = ov.effects.duplicate(true)
	return o


## Etki önizlemesinin düz Türkçe satırı: "Yatırımcı riski artar; 7 gün sonra başlar, 30 gün sürer". Büyüklük sayısı
## YOKTUR (sim vermiyor). Bilinmeyen hedef/kapsam için anahtar adı değil, hedefin okunur adı gösterilir.
static func effect_text(effect: Dictionary) -> String:
	var target := String(effect.get("target", ""))
	var up := int(effect.get("direction", 0)) > 0
	var key := StringName("agenda.effect.%s.%s" % [target, "up" if up else "down"])
	var what := UiText.t(key) if UiText.has(key) else "%s %s" % [UiText.humanize(target),
		UiText.t(&"agenda.effect.generic_up" if up else &"agenda.effect.generic_down")]
	var scope_key := StringName("agenda.effect.scope.%s" % String(effect.get("scope", "")))
	if UiText.has(scope_key):
		what = "%s (%s)" % [what, UiText.t(scope_key)]
	var delay := int(effect.get("delay_days", 0))
	var length := int(effect.get("duration_days", 0))
	var when := UiText.t(&"agenda.effect.starts_now")
	if delay > 0:
		when = UiText.t(&"agenda.effect.starts_in", {"days": delay})
	if length > 0:
		when += ", " + UiText.t(&"agenda.effect.lasts", {"days": length})
	else:
		when += ", " + UiText.t(&"agenda.effect.once")
	return "%s; %s" % [what, when]


## Öğenin gerekçe zincirinde (öğe kaydı -> ebeveyn ... en çok `CHAIN_DEPTH` basamak) sim'in yazdığı yerinden edilme
## sayısını arar. Dönüş: `{found, households, record_id, resettled, rehoused, unplaced}`; yoksa `found=false` (UI sayı
## UYDURMAZ, satır gizlenir). `resettled`: aynı kayıtta yeniden iskân sayımları var (T-065: `rehoused` ev ayrılan,
## `unplaced` ev bulunamayan hane).
static func displaced_cause(facade: SimFacade, reason_ids: PackedInt64Array) -> Dictionary:
	var queue: Array[int] = []
	for rid in reason_ids:
		queue.append(rid)
	var seen: Dictionary = {}
	var depth := 0
	while not queue.is_empty() and depth < CHAIN_DEPTH:
		var next: Array[int] = []
		for rid in queue:
			if seen.has(rid):
				continue
			seen[rid] = true
			var rec := facade.reason(rid)
			if rec == null:
				continue
			for f in rec.factors:
				if f.name_key == DISPLACED_COUNT_FACTOR:
					return _cause_of(facade, rec, f.value)
			for pid in rec.parent_ids:
				next.append(pid)
		queue = next
		depth += 1
	return {"found": false, "households": 0, "record_id": SimContract.NO_ID, "resettled": false, "rehoused": 0,
			"unplaced": 0, "scope": &"record"}


## Sayım kaynağı: önce aynı kaydın tahsis etkenleri (mahalle kaydı); yoksa kaydın özne olarak andığı yolların sim kaydı
## (`PublicWorkView.rehoused_households/unplaced_households`, bölge ölçekli kayıtta etken yoktur). İkisi de yoksa
## `resettled=false` (satır çıkmaz, sayı uydurulmaz). `scope`: `record` (mahalle) ya da `road` (yolun toplamı).
static func _cause_of(facade: SimFacade, rec: ReasonRecord, households: int) -> Dictionary:
	var out := {"found": true, "households": households, "record_id": rec.id, "resettled": false, "rehoused": 0,
			"unplaced": 0, "scope": &"record"}
	var housed := false
	var unplaced := false
	for f in rec.factors:
		if f.name_key == REHOUSED_FACTOR:
			out["rehoused"] = f.value
			housed = true
		elif f.name_key == UNPLACED_FACTOR:
			out["unplaced"] = f.value
			unplaced = true
	out["resettled"] = housed and unplaced
	if not out["resettled"]:
		var commands := PackedInt64Array()
		for subject in rec.subjects:
			var ref := SimContract.parse_ref(StringName(subject))
			if str(ref["kind"]) == String(SimContract.REF_COMMAND):
				commands.append(int(ref["id"]))
		var rehoused_total := 0
		var unplaced_total := 0
		var any := false
		for work in facade.public_works():
			if work.resettlement_applied and commands.has(work.command_id):
				rehoused_total += work.rehoused_households
				unplaced_total += work.unplaced_households
				any = true
		if any:
			out["resettled"] = true
			out["rehoused"] = rehoused_total
			out["unplaced"] = unplaced_total
			out["scope"] = &"road"
	return out


## Gündemin kaynağı kurulu mu (kurulmadıysa "Olay sistemi henüz kurulmadı").
static func source_built(snapshot: SimSnapshot) -> bool:
	return SimSections.council_built(snapshot)


## En yakın kalan gün; öğe yoksa -1.
static func nearest_days(items: Array[Item]) -> int:
	var best := -1
	for it in items:
		if best < 0 or it.days_left < best:
			best = it.days_left
	return best


## Daha önce görülmeyen öğe kimlikleri (otomatik duraklatma için); `seen` kimlik -> true.
static func unseen(items: Array[Item], seen: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for it in items:
		if not seen.has(it.id):
			out.append(it.id)
	return out
