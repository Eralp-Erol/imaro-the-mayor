class_name EventCauses
extends RefCounted
## Nedensellik bağlantıları (T-017, SIM-12): bir siyasi kararın `parent_ids`/`subjects` alanına girecek önceki
## gerekçeleri bulur (imar -> yatırım kararı -> kesim tepkisi -> medya -> meclis). Salt okunur; durumu değiştirmez.
## Yalnız hâlâ saklanan kayıtlar döner (budanmış ebeveyn zinciri bozmaz).


## Bölgelerdeki özel gelişmenin (planlanan, inşa halindeki, biten) onay gerekçeleri: en yeni `cause_cap` tane,
## artan sırada, ve parsel referansları. `exposure`: {bölge kodu: pm}. Yalnız tepki değerlendirmesinde çağrılır.
## `scan_cache`: TEK taramaya yerel sözlük (BlocEngine.scan oluşturur, kesimler arası paylaşır; durum/kayda GİRMEZ):
## bölge başına en iyi `cause_cap` aday ilk çağrıda TEK parsel geçişiyle kurulur. Birleşimin ilk `cap`'i, bölgelerin
## ilk-`cap` adaylarının birleşiminin ilk `cap`'idir (anahtar tam sıra: reason_id azalan, parsel kimliği artan).
## Verilmezse çağrı kendi geçişini yapar. Çıktı eski tam-tarama sürümüyle bit-bit aynıdır.
static func region_projects(state: GameState, ctx: PoliticsContext, exposure: Dictionary,
		scan_cache: Variant = null) -> Dictionary:
	var out := {"reason_ids": PackedInt64Array(), "parcel_refs": PackedStringArray()}
	var cache: Dictionary = scan_cache if scan_cache is Dictionary else {}
	if not cache.has("by_region"):
		cache["by_region"] = _top_by_region(state, ctx)
	var by_region: Dictionary = cache["by_region"]
	var found: Array = []
	for code in exposure:
		found.append_array(by_region.get(String(code), []))
	found.sort_custom(_newest_first)
	var cap := int(ctx.politics.cadence["cause_cap"])
	var chosen: Array = found.slice(0, cap)
	chosen.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for pair: Array in chosen:
		out["reason_ids"].append(pair[0])
		out["parcel_refs"].append(String(SimContract.parcel_ref(pair[1])))
	return out


## Son `days` günün olumsuz yatırımcı kararları gerekçe kimlikleri (artan, en çok `cap`). Kayıtları KOPYALAMAZ
## (`peek`; eski sürüm `find` ile her eşleşmeyi derin kopyalıyordu); çıktı aynı.
static func recent_declines(state: GameState, ctx: PoliticsContext, days: int, cap: int) -> PackedInt64Array:
	var key: String = ctx.politics.events["investor_decision"]
	var from_tick := maxi(state.tick - days, 0)
	var ids := PackedInt64Array()
	for id in range(state.reasons.first_id(), state.reasons.last_id() + 1):
		var rec := state.reasons.peek(id)
		if rec.is_empty() or str(rec["decision"]) != key or int(rec["tick"]) < from_tick:
			continue
		if rec["outcome"] == ReasonLog.OUTCOME_NEGATIVE:
			ids.append(rec["id"])
	return ids.slice(maxi(ids.size() - cap, 0))


## {bölge kodu: [[reason_id, parsel_id], ...]}: bölge başına en çok `cause_cap` aday, en yeni önce. TEK parsel geçişi.
static func _top_by_region(state: GameState, ctx: PoliticsContext) -> Dictionary:
	var top := {}
	var d := EconomyState.data(state)
	var cap := int(ctx.politics.cadence["cause_cap"])
	if d.is_empty() or cap < 1:
		return top
	var stage: PackedByteArray = d["stage"]
	var reason_column: PackedInt64Array = d["reason_id"]
	for i in stage.size():
		if reason_column[i] < 1:  # çoğu parselde gerekçe yok: en ucuz eleme önce
			continue
		var skipped: bool = stage[i] == EconomyState.STAGE_VACANT or stage[i] == EconomyState.STAGE_TAKEN  # T-042b
		if skipped:
			continue
		var pair := [reason_column[i], ctx.regions.id_at(i)]
		var code := ctx.regions.code_at(i)
		var list: Array = top.get(code, [])
		if list.size() >= cap and not _newest_first(pair, list[list.size() - 1]):
			continue
		var at := list.size()
		while at > 0 and _newest_first(pair, list[at - 1]):
			at -= 1
		list.insert(at, pair)
		if list.size() > cap:
			list.pop_back()
		top[code] = list
	return top


## Aday sıralama anahtarı (tam sıra): reason_id azalan, eşitlikte parsel kimliği artan.
static func _newest_first(a: Array, b: Array) -> bool:
	return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1])
