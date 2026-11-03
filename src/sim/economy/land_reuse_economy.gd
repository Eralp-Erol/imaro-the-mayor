class_name LandReuseEconomy
extends RefCounted
## D-018 · Belediye arazisi yeni planla BOŞ yatırım koşuluna döner. Eski snapshot/bina/hane/sahip geri dönmez.


static func can_release(state: GameState, ids: PackedInt64Array) -> bool:
	var d := EconomyState.data(state)
	if d.is_empty() or ids.is_empty():
		return false
	for id in ids:
		var i := EconomyState.index_of(d, id)
		if i < 0 or int(d["stage"][i]) != EconomyState.STAGE_TAKEN:
			return false
	return true


## Önce dünya grubunun TAMAMI uygulanmış ve can_release doğrulanmış olmalı. Bölge toplamlarına dokunulmaz.
static func release(state: GameState, ids: PackedInt64Array) -> void:
	var d := EconomyState.data(state)
	for id in ids:
		var i := EconomyState.index_of(d, id)
		d["stage"][i] = EconomyState.STAGE_VACANT
		d["use"][i] = EconomyConfig.USE_NONE
		d["units"][i] = 0
		d["owner_id"][i] = 0
		d["days_left"][i] = 0
		d["reason_id"][i] = 0
		d["last_code"][i] = EconomyState.CODE_NONE
		d["last_reason_tick"][i] = -1
		d["next_review"][i] = 0
		for key in ["active", "attention", "attention_cmd", "priority", "priority_cmd", "zone_seen"]:
			if d.has(key):
				(d[key] as Dictionary).erase(i)
