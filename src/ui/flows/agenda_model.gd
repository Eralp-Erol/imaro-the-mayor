class_name AgendaModel
extends RefCounted
## Gündem modeli (ux-flows-v0 §I, T-022). İki kaynak: açık meclis oylamaları (`CouncilVoteView.closes_tick`, `derive`)
## ve sim'in açık gündem öğeleri (`SimFacade.agenda_items`, v1.5 isteğe bağlı ek; `derive_all`).
## Türetilen öğede yanıt SEÇENEĞİ yoktur (oyuncu oylamaya komutla müdahale edemez); UI seçenek/ertele düğmesi
## uydurmaz. `Item.options` ve `can_defer`, v1.1 `AgendaItemView` geldiğinde aynı görünümün seçenek kartlarını
## göstermesi içindir; v1.0'da hep boştur/false'tur.
## Gündem kaynağı yoksa (meclis kurulmamış) liste boştur ve panel "kurulmadı" der.

const KIND_COUNCIL_VOTE := &"council_vote"
## Sim gündem öğesi (`AgendaItemView`); gerekçe zincirinde yerinden edilme hane sayısı varsa `displacement`.
const KIND_EVENT := &"event"
const KIND_DISPLACEMENT := &"displacement"
## Sim'in yerinden edilme neden kaydı: bu etken adı kayıtta hane SAYISI taşır (T-042b, ağırlık 0 = yalnız gösterim).
const DISPLACED_COUNT_FACTOR := &"reason.factor.displaced_household_count"
const CHAIN_DEPTH := 4


class Option:
	extends RefCounted
	var id: StringName = &""
	var label_key: StringName = &""
	var has_cost: bool = false
	var cost: int = 0
	## Etki önizlemesi yalnız sim verirse; her zaman TAHMİN işaretlidir (`is_estimate`).
	var preview_key: StringName = &""
	var preview_is_estimate: bool = true


class Item:
	extends RefCounted
	var id: StringName = &""
	var kind: StringName = KIND_COUNCIL_VOTE
	var title_key: StringName = &""
	var subject_ref: StringName = &""
	var vote_id: int = SimContract.NO_ID
	var deadline_tick: int = 0
	var days_left: int = 0
	var options: Array[Option] = []
	var can_defer: bool = false
	var reason_ids: PackedInt64Array = PackedInt64Array()

	func answerable() -> bool:
		return not options.is_empty() or can_defer


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
## yerinden edilme dahil). İnce köprü: facade öğesi sözleşme alanlarını aynen taşır, yanıt seçeneği/erteleme UYDURMAZ
## (`agenda.respond` komutu yok). Gerekçe zincirinde hane sayısı varsa tür `displacement`, yoksa `event`.
static func derive_all(facade: SimFacade, snapshot: SimSnapshot) -> Array[Item]:
	var out := derive(snapshot)
	if facade != null:
		for v in facade.agenda_items():
			var it := Item.new()
			it.id = v.ref()
			it.kind = KIND_DISPLACEMENT if bool(displaced_cause(facade, v.reason_ids)["found"]) else KIND_EVENT
			it.title_key = v.title_key
			it.deadline_tick = v.deadline_tick
			it.days_left = maxi(0, v.deadline_tick - snapshot.tick())
			it.reason_ids = v.reason_ids
			out.append(it)
	out.sort_custom(func(a: Item, b: Item) -> bool:
		if a.deadline_tick != b.deadline_tick:
			return a.deadline_tick < b.deadline_tick
		return a.vote_id < b.vote_id or (a.vote_id == b.vote_id and String(a.id) < String(b.id)))
	return out


## Öğenin gerekçe zincirinde (öğe kaydı -> ebeveyn ... en çok `CHAIN_DEPTH` basamak) sim'in yazdığı yerinden edilme
## sayısını arar. Dönüş: `{found, households, record_id}`; yoksa `found=false` (UI sayı UYDURMAZ, satır gizlenir).
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
					return {"found": true, "households": f.value, "record_id": rid}
			for pid in rec.parent_ids:
				next.append(pid)
		queue = next
		depth += 1
	return {"found": false, "households": 0, "record_id": SimContract.NO_ID}


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
