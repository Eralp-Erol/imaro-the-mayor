class_name ParcelZoningSystem
extends SimSystem
## Parsel imar bindirmesi (T-027): `zoning.propose` bir parselin yürürlükteki imarını DEĞİŞTİRMEZ, `pending_zone` ve
## yürürlük günü yazar; bu sistem süre dolunca imarı yürürlüğe sokar (`parcel.changed` olayı). Belediye eylemi
## yalnız KOŞULU değiştirir; özel bina oluşturmaz (CAN-03): burada `development` hiç yazılmaz, gelişmeyi yalnız
## aktör kararları (T-013) üretecek. Sayılar ve sözlük `data/sim/facade_config.json`'dadır.
##
## Durum (`state.systems["parcels"]`): {"overlay": {parsel_id (int) -> {zone, pending_zone, due_tick, command_id,
## pending_density, pending_max_height_m, density, max_height_m (yürürlüğe girince pending_*'dan)}}}. Yalnız dokunulan
## parseller girer; kalanı `ParcelSource` şablonudur.
## T-043A: meclis yolu açıkken (`requires_council`) plan oylaması geçmezse (ve `unplanned_land_enabled` iken) kayda
## `rejected_command` / `rejected_tick` eklenir (`set_rejected`): parsel plansız kalır, yeniden teklif
## yeni `set_pending`
## ile bu izi siler. Plan durumu (Plansız/Teklif verildi/Planlı/Plan reddedildi) bu kayıtlardan TÜRER
## (`ParcelPlanning`); yeni sütun/anahtar yoktur.
## Statik gelişme/sahiplik/talep T-013'ün işidir; bu sistem onların yerini TUTMAZ.

const SYSTEM := &"parcels"
const NO_VALUE := -1

## D-018: facade attach_public_works bağlar. Yalnız municipal_reuse:true bekleyen planlar kullanır.
var municipal_context: PublicWorksContext = null


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
		if bool(entry.get("municipal_reuse", false)):
			var group := _municipal_group(overlay, int(entry["command_id"]))
			var activated := MunicipalLandFlow.activate(municipal_context, state, group, int(entry["command_id"]))
			if not bool(activated["ok"]):
				_reject_municipal(state, overlay, group, int(entry["command_id"]),
					StringName(activated["reason_key"]))
				continue
			for group_id in group:
				(overlay[group_id] as Dictionary).erase("municipal_reuse")
				(overlay[group_id] as Dictionary).erase("municipal_group")
		entry["zone"] = entry["pending_zone"]
		entry["pending_zone"] = &""
		# yürürlükteki yoğunluk/yükseklik (NO_VALUE = imar varsayılanı); T-013 ekonomi okur
		entry["density"] = entry["pending_density"]
		entry["max_height_m"] = entry["pending_max_height_m"]
		entry.erase("rejected_command")  # T-043A: yürürlüğe giren plan eski ret izini siler (yoksa etkisiz)
		entry.erase("rejected_tick")
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


## Bindirme sözlüğüne DOĞRUDAN (kopyasız) okuma erişimi: parsel kimliği -> kayıt. Salt okunur kullanın (T-013 ekonomi
## tick'te her gün okur; `overlay_of` kopya verir). Bindirme yoksa boş sözlük.
static func overlay_ref(state: GameState) -> Dictionary:
	var data: Variant = state.systems.get(String(SYSTEM), null)
	if not (data is Dictionary) or not (data.get("overlay", null) is Dictionary):
		return {}
	return data["overlay"]


## `zoning.propose` etkisi: bekleyen öneriyi yazar (yürürlük `due_tick`'te).
static func set_pending(state: GameState, parcel_id: int, land_use: StringName, due_tick: int, command_id: int,
		density: int, max_height_m: int, municipal_group: Array = []) -> void:
	var overlay := _overlay(state)
	var entry: Dictionary = overlay.get(parcel_id, {"zone": &""})
	entry["pending_zone"] = land_use
	entry["due_tick"] = due_tick
	entry["command_id"] = command_id
	entry["pending_density"] = density
	entry["pending_max_height_m"] = max_height_m
	# D-018: belediye arazisi planı grubunun TAMAMI her üyede kayıtlıdır; yüklemede bütünlük denetlenir.
	if not municipal_group.is_empty():
		entry["municipal_reuse"] = true
		entry["municipal_group"] = municipal_group.duplicate()
	else:
		entry.erase("municipal_reuse")
		entry.erase("municipal_group")
	entry.erase("rejected_command")  # T-043A: yeniden teklif eski ret izini siler (yoksa etkisiz)
	entry.erase("rejected_tick")
	overlay[parcel_id] = entry


static func _municipal_group(overlay: Dictionary, command_id: int) -> PackedInt64Array:
	var ids := PackedInt64Array()
	for id: int in overlay:
		var entry: Dictionary = overlay[id]
		if int(entry.get("command_id", 0)) == command_id and bool(entry.get("municipal_reuse", false)) \
				and entry.get("pending_zone", &"") != &"":
			ids.append(id)
	ids.sort()
	return ids


## Kayıt bütünlüğü (D-018): bekleyen belediye arazisi planı grubu bölünmemiş, aynı komut/bölge/vade ve kayıtlı grup
## listesi gerçek üyelerle eşit olmalı. Sorun metni ya da "". Durumu değiştirmez.
static func municipal_problem(state: GameState) -> String:
	var overlay := overlay_ref(state)
	var ids: Array = overlay.keys()
	ids.sort()
	var members := {}  # komut -> bekleyen parsel kimlikleri (sıralı)
	for id: int in ids:
		var entry: Dictionary = overlay[id]
		if entry.get("pending_zone", &"") != &"":
			var list: Array = members.get(int(entry.get("command_id", 0)), [])
			list.append(id)
			members[int(entry.get("command_id", 0))] = list
		elif entry.has("municipal_reuse") or entry.has("municipal_group"):
			return "belediye arazisi işareti bekleyen planı olmayan parselde (%d)" % id
	for id: int in ids:
		var entry: Dictionary = overlay[id]
		var marked := entry.has("municipal_reuse") or entry.has("municipal_group")
		if entry.get("pending_zone", &"") == &"" or not marked:
			continue
		var group: Variant = entry.get("municipal_group", null)
		if not bool(entry.get("municipal_reuse", false)) or not (group is Array) or (group as Array).is_empty():
			return "belediye arazisi planı işareti eksik (%d)" % id
		var expected: Array = members[int(entry["command_id"])]
		if group != expected or not expected.has(id):
			return "belediye arazisi plan grubu bölünmüş ya da değiştirilmiş (%d)" % id
		for member: int in expected:
			var other: Dictionary = overlay[member]
			if not bool(other.get("municipal_reuse", false)) or other["pending_zone"] != entry["pending_zone"] \
					or int(other["due_tick"]) != int(entry["due_tick"]) or other.get("municipal_group", null) != group:
				return "belediye arazisi plan grubu üyeleri uyuşmuyor (%d)" % member
	return ""


## Onaylanmış plan yürürlükte artık uygulanamıyorsa bütün seçili arazi kapalı kalır; sahte applied sonucu yoktur.
static func _reject_municipal(state: GameState, overlay: Dictionary, ids: PackedInt64Array,
		command_id: int, reason: StringName) -> void:
	var subjects := PackedStringArray()
	var zone := &""
	for id in ids:
		var entry: Dictionary = overlay[id]
		zone = StringName(entry["pending_zone"])
		entry["pending_zone"] = &""
		entry.erase("municipal_reuse")
		entry.erase("municipal_group")
		entry["rejected_command"] = command_id
		entry["rejected_tick"] = state.tick
		subjects.append(String(SimContract.parcel_ref(id)))
	SimEventLog.emit(state, SimEvent.KIND_PARCEL_CHANGED, &"event.zoning.plan_rejected", subjects,
		{"parcels": ids.size(), "zone": String(zone), "why": String(reason)}, PackedInt64Array(), command_id)


## T-043A · Meclis planı reddetti: parselin yürürlükteki/bekleyen durumuna DOKUNMAZ (yoksa boş kayıt açar: imar yok,
## bekleyen yok); yalnız ret izini yazar. Yalnız `unplanned_land_enabled` iken çağrılır (bayrak kapalıyken kayıt
## yazılmaz: eski davranış bit-eşit).
static func set_rejected(state: GameState, parcel_id: int, command_id: int) -> void:
	var overlay := _overlay(state)
	var entry: Dictionary = overlay.get(parcel_id, {"zone": &"", "pending_zone": &"", "due_tick": 0, "command_id": 0,
		"pending_density": NO_VALUE, "pending_max_height_m": NO_VALUE})
	entry["rejected_command"] = command_id
	entry["rejected_tick"] = state.tick
	overlay[parcel_id] = entry


static func _overlay(state: GameState) -> Dictionary:
	var data := state.system_data(SYSTEM)
	if not data.has("overlay"):
		data["overlay"] = {}
	return data["overlay"]
