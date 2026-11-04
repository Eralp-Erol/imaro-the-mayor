class_name PlayableStock
extends RefCounted
## T0 yapı sütunlarından sim başlangıç stoğu (playable.gd'den çıkarıldı; testler aynı adaptörü kullanır).


## `BuildingColumns` her satırını değil, parsel başına başlangıç kullanım/birim toplamını verir. Bu başlangıç
## durumu olduğundan ReasonLog'a karar yazılmaz; yeni yapılar hâlâ EconomySystem yatırımcı kararından doğar.
static func from_columns(cols: BuildingColumns) -> ListStockSource:
	if cols == null:
		return ListStockSource.create([])
	var grouped := {}
	for i in cols.count:
		var pid := int(cols.parcel_id[i])
		var commercial := (int(cols.flags[i]) & (BuildingColumns.FLAG_GROUND_SHOP | BuildingColumns.FLAG_INDUSTRY)) != 0
		var use: StringName = &"commercial" if commercial else &"residential"
		if not grouped.has(pid):
			grouped[pid] = {"residential": 0, "commercial": 0}
		var units := maxi(1, int(cols.floors[i]))
		(grouped[pid] as Dictionary)[String(use)] += units
	var entries: Array = []
	for pid in grouped.keys():
		var uses: Dictionary = grouped[pid]
		# Tek ekonomi parseli tek kullanım taşır; karma parsellerde zemin dükkânı baskınsa ticaret seçilir.
		var use: StringName = &"commercial" if int(uses["commercial"]) > int(uses["residential"]) else &"residential"
		entries.append({"parcel_id": int(pid), "use": use, "units": int(uses[String(use)]), "owner": 0})
	return ListStockSource.create(entries)
