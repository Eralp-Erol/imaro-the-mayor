class_name ExpropriationSummary
extends RefCounted
## Kamulaştırma özetinden (v1.5, ADR-0005 Ek F) UI'nin göreceği düz argümanları üretir. Gerçek sim ve MOCK AYNI
## yardımcıyı çağırır: önizleme/ret/olay anahtarları bire bir aynıdır (parite testi). Saf veri; hesap YAPMAZ, sayıyı
## çağıran verir (gerçek sim: ekonomi sütunlarından; mock: senaryo verisinden).
##
## Özet sözlüğü: {parcel_ids: PackedInt64Array, built_parcels, project_parcels, res_units, com_units, households,
## regions {bölge_kodu: alınan_parsel}, nearby_households, nearby_parcels}.
##   built_parcels     alınan parsellerden yapılmış olanlar (bina yıkılır)
##   project_parcels   alınan parsellerden planlı/inşaatta/durmuş projeler (iptal olur)
##   res_units/com_units  yıkılan/iptal edilen konut ve ticaret birimi
##   households        yerinden edilen hane (bölge barınan hane farkı; hane kaderi veridir, Q-017)
##   nearby_*          alınmayan ama yola yakın konut parselleri ve hane sayısı (yakınlık tepkisi; mesafeye bağlı)


## Önizleme/ret teklifi argümanları (`CommandResult.args`). `expropriate` anahtarı kabul edilecek komutun bayrağıdır.
static func preview_args(summary: Dictionary) -> Dictionary:
	return {
		"expropriate": true, "taken_parcels": sorted_ids(summary).size(),
		"taken_built_parcels": int(summary.get("built_parcels", 0)),
		"taken_project_parcels": int(summary.get("project_parcels", 0)),
		"taken_res_units": int(summary.get("res_units", 0)), "taken_com_units": int(summary.get("com_units", 0)),
		"displaced_households": int(summary.get("households", 0)),
		"taken_regions": SimContract.to_args(summary.get("regions", {})),
		"nearby_households": int(summary.get("nearby_households", 0)),
		"nearby_parcels": int(summary.get("nearby_parcels", 0)),
	}


## `public_work.expropriated` / `public_work.restored` olay argümanları (anahtarlar aynı sözlükten, `taken_` öneksiz).
static func event_args(summary: Dictionary) -> Dictionary:
	return {
		"parcels": sorted_ids(summary).size(), "built_parcels": int(summary.get("built_parcels", 0)),
		"project_parcels": int(summary.get("project_parcels", 0)), "res_units": int(summary.get("res_units", 0)),
		"com_units": int(summary.get("com_units", 0)), "households": int(summary.get("households", 0)),
		"nearby_households": int(summary.get("nearby_households", 0)),
	}


## Alınan parsel kimlikleri, artan ve tekrarsız.
static func sorted_ids(summary: Dictionary) -> PackedInt64Array:
	var ids := SimContract.to_int64_array(summary.get("parcel_ids", []))
	ids.sort()
	var out := PackedInt64Array()
	for id in ids:
		if out.is_empty() or out[out.size() - 1] != id:
			out.append(id)
	return out


## Olay `subjects`: komut, bölgeler (sıralı kod), parseller (artan kimlik).
static func subjects(command_id: int, summary: Dictionary) -> PackedStringArray:
	var out := PackedStringArray([String(SimContract.ref(SimContract.REF_COMMAND, command_id))])
	var codes: Array = (summary.get("regions", {}) as Dictionary).keys()
	codes.sort()
	for code: Variant in codes:
		out.append("%s.%s" % [SimContract.REF_REGION, str(code)])
	for id in sorted_ids(summary):
		out.append(String(SimContract.parcel_ref(id)))
	return out
