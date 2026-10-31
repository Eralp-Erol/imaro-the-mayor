class_name EventCauses
extends RefCounted
## Nedensellik bağlantıları (T-017, SIM-12): bir siyasi kararın `parent_ids`/`subjects` alanına girecek önceki
## gerekçeleri bulur (imar -> yatırım kararı -> kesim tepkisi -> medya -> meclis). Salt okunur; durumu değiştirmez.
## Yalnız hâlâ saklanan kayıtlar döner (budanmış ebeveyn zinciri bozmaz).


## Bölgelerdeki özel gelişmenin (planlanan, inşa halindeki, biten) onay gerekçeleri: en yeni `cause_cap` tane,
## artan sırada, ve parsel referansları. `exposure`: {bölge kodu: pm}. Yalnız tepki değerlendirmesinde çağrılır
## (parsel sütunlarını bir kez tarar; ölçekte nadir).
static func region_projects(state: GameState, ctx: PoliticsContext, exposure: Dictionary) -> Dictionary:
	var out := {"reason_ids": PackedInt64Array(), "parcel_refs": PackedStringArray()}
	var d := EconomyState.data(state)
	if d.is_empty():
		return out
	var stage: PackedByteArray = d["stage"]
	var reason_column: PackedInt64Array = d["reason_id"]
	var found: Array = []
	for i in stage.size():
		var skipped: bool = stage[i] == EconomyState.STAGE_VACANT or stage[i] == EconomyState.STAGE_TAKEN  # T-042b
		if skipped or reason_column[i] < 1 or not exposure.has(ctx.regions.code_at(i)):
			continue
		found.append([reason_column[i], ctx.regions.id_at(i)])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var cap := int(ctx.politics.cadence["cause_cap"])
	var chosen: Array = found.slice(0, cap)
	chosen.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for pair: Array in chosen:
		out["reason_ids"].append(pair[0])
		out["parcel_refs"].append(String(SimContract.parcel_ref(pair[1])))
	return out


## Son `days` günün olumsuz yatırımcı kararları gerekçe kimlikleri (artan, en çok `cap`).
static func recent_declines(state: GameState, ctx: PoliticsContext, days: int, cap: int) -> PackedInt64Array:
	var key: String = ctx.politics.events["investor_decision"]
	var found := state.reasons.find({"decision": key, "from_tick": maxi(state.tick - days, 0)})
	var ids := PackedInt64Array()
	for rec: Dictionary in found:
		if rec["outcome"] == ReasonLog.OUTCOME_NEGATIVE:
			ids.append(rec["id"])
	return ids.slice(maxi(ids.size() - cap, 0))
