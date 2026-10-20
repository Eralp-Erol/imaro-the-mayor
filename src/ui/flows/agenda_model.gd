class_name AgendaModel
extends RefCounted
## Gündem modeli (ux-flows-v0 §I, T-022). `AgendaItemView` sözleşmede v1.0'da YOKTUR (v1.1 isteği); bu yüzden gündem
## v1.0 alanlarından TÜRETİLİR: yanıt süresi olan tek şey açık meclis oylamalarıdır (`CouncilVoteView.closes_tick`).
## Türetilen öğede yanıt SEÇENEĞİ yoktur (oyuncu oylamaya komutla müdahale edemez); UI seçenek/ertele düğmesi
## uydurmaz. `Item.options` ve `can_defer`, v1.1 `AgendaItemView` geldiğinde aynı görünümün seçenek kartlarını
## göstermesi içindir; v1.0'da hep boştur/false'tur.
## Gündem kaynağı yoksa (meclis kurulmamış) liste boştur ve panel "kurulmadı" der.

const KIND_COUNCIL_VOTE := &"council_vote"


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
