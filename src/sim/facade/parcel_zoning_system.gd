class_name ParcelZoningSystem
extends SimSystem
## Parsel imar bindirmesi (T-027): `zoning.propose` bir parselin yürürlükteki imarını DEĞİŞTİRMEZ, `pending_zone` ve
## yürürlük günü yazar; bu sistem süre dolunca imarı yürürlüğe sokar (`parcel.changed` olayı). Belediye eylemi
## yalnız KOŞULU değiştirir; özel bina oluşturmaz (CAN-03): burada `development` hiç yazılmaz, gelişmeyi yalnız
## aktör kararları (T-013) üretecek. Sayılar ve sözlük `data/sim/facade_config.json`'dadır.
##
## Durum (`state.systems["parcels"]`): {"overlay": {parsel_id (int) -> {zone, pending_zone, due_tick, command_id,
## pending_density, pending_max_height_m}}}. Yalnız dokunulan parseller girer; kalanı `ParcelSource` şablonudur.
## Statik gelişme/sahiplik/talep T-013'ün işidir; bu sistem onların yerini TUTMAZ.

const SYSTEM := &"parcels"
const NO_VALUE := -1


func system_id() -> StringName:
	return SYSTEM


func on_daily(state: GameState) -> void:
	var data: Variant = state.systems.get(String(SYSTEM), null)
	if not (data is Dictionary) or not (data.get("overlay", null) is Dictionary):
		return  # henüz hiçbir öneri yok: durum oluşturma
	var overlay: Dictionary = data["overlay"]
	var ids: Array = overlay.keys()
	ids.sort()
	for id: int in ids:
		var entry: Dictionary = overlay[id]
		if entry["pending_zone"] == &"" or state.tick < int(entry["due_tick"]):
			continue
		entry["zone"] = entry["pending_zone"]
		entry["pending_zone"] = &""
		SimEventLog.emit(state, &"parcel.changed", &"event.zoning.applied",
			PackedStringArray([String(SimContract.parcel_ref(id))]), {"zone": String(entry["zone"])},
			PackedInt64Array(), int(entry["command_id"]))


## Parselin bindirme kaydı (salt okunur kopya); yoksa boş sözlük. Durumu değiştirmez.
static func overlay_of(state: GameState, parcel_id: int) -> Dictionary:
	var data: Variant = state.systems.get(String(SYSTEM), null)
	if not (data is Dictionary) or not (data.get("overlay", null) is Dictionary):
		return {}
	var entry: Variant = data["overlay"].get(parcel_id, null)
	return (entry as Dictionary).duplicate(true) if entry is Dictionary else {}


## `zoning.propose` etkisi: bekleyen öneriyi yazar (yürürlük `due_tick`'te).
static func set_pending(state: GameState, parcel_id: int, land_use: StringName, due_tick: int, command_id: int,
		density: int, max_height_m: int) -> void:
	var overlay := _overlay(state)
	var entry: Dictionary = overlay.get(parcel_id, {"zone": &""})
	entry["pending_zone"] = land_use
	entry["due_tick"] = due_tick
	entry["command_id"] = command_id
	entry["pending_density"] = density
	entry["pending_max_height_m"] = max_height_m
	overlay[parcel_id] = entry


static func _overlay(state: GameState) -> Dictionary:
	var data := state.system_data(SYSTEM)
	if not data.has("overlay"):
		data["overlay"] = {}
	return data["overlay"]
