class_name ReactionRehousing
extends RefCounted
## Yerinden edilen ailenin tepkisi (D-014 §3 -> D-016 §2 -> D-019 E1): "yeni ev sunulmadığı sürece tepki sürer; ev
## verilince BİRAZ KALIR" (sıfır DEĞİL; D-016 §2 D-014 §3'ün "sunulursa hiç olmasın" cümlesini güncelledi). Ev yoksa
## aile bekleme listesine girer (D-019 E1, T-067): yatırımcıların sonradan bitirdiği yeni evler önce onlara verilir
## (`ResettlementQueue`), ev verilene dek tepki tam sürer.
## Sim'de haneler yalnız bölge toplamıdır (`latent_hh`, barınan = min(talep, biten konut)); ev tahsisi
## `ResettlementPlanner` (yol anı) ve `ResettlementQueue` (sonradan biten evler) ile yapılır, sonuç yolun kaydındadır.
## Yeniden iskân politikası KAPALIYKEN (hiç açılmamış) hiçbir kayıt yoktur ve tepki bugünkü gibi tam sürer (hane
## `household_fate = return_to_latent` ile bölge talebinde kalır); belediye hiçbir durumda bina yapmaz (CAN-03).
##
## TEK GİRİŞ NOKTASI: tepkinin "bu hane yeniden yerleşti mi" kararı YALNIZ `still_unhoused`dan geçer (yerel okuma ve
## ilçe/bölge sinyali dahil). T-065 (ADR-0009 Değişiklik 1): yeniden iskân politikası AÇIKKEN yol, tahsis kaydını
## (`works[i].expropriation.resettlement.effective/unplaced_by/moves/served`) `index` ile verir; tepki defteri HAM
## kalır (gerçek yerinden edilen hane), rahatlama OKUMA anında yapılır. `index` boşsa (politika hiç açılmadı, kayıt
## yok) davranış bit-bit eskisi gibidir: sayı aynen döner. SAF ve durumsuz; rastgelelik yok.


## Tahsis kayıtlarından {komut: {effective, unplaced_by, rehoused_by}} (her biri {kod: hane}). Yolların
## kaydı (yıkılmış yol dahil: yıkım tepki satırlarını silmez); kayıt yoksa BOŞ sözlük (kapalı yol). Tarama başına
## BİR KEZ kurulur.
static func index(state: GameState) -> Dictionary:
	var out := {}
	var records := PublicWorksState.resettlement_records(state)
	for command_id: int in records:
		var record: Dictionary = records[command_id]
		var rehoused_by := {}
		for move: Array in record["moves"]:
			rehoused_by[String(move[0])] = int(rehoused_by.get(String(move[0]), 0)) + int(move[2])
		for row: Array in record.get("served", []):  # bekleme listesinden sonradan verilen evler (T-067)
			rehoused_by[String(row[1])] = int(rehoused_by.get(String(row[1]), 0)) + int(row[3])
		out[command_id] = {"effective": record["effective"], "unplaced_by": record["unplaced_by"],
			"rehoused_by": rehoused_by}
	return out


## (Bölge, komut) satırındaki `households` yerinden edilen haneden kaçı HÂLÂ barınamıyor (tepki sayar). `index` boş ya
## da bu (komut, bölge) için kayıt yoksa tümü; kayıt varsa tahsisin kalan tepkisi (`effective`, en çok `households`).
static func still_unhoused(region_code: String, command_id: int, households: int, index: Dictionary = {}) -> int:
	if index.is_empty() or not index.has(command_id):
		return households
	var effective: Dictionary = index[command_id]["effective"]
	return households if not effective.has(region_code) else mini(int(effective[region_code]), households)


## Ham defter satırlarının [tick, hane, komut] rahatlamış hâli (bölge sinyali için). `index` boşsa AYNI nesne döner.
static func relieved_rows(region_code: String, rows: Array, index: Dictionary) -> Array:
	if index.is_empty():
		return rows
	var out: Array = []
	for row: Array in rows:
		out.append([row[0], still_unhoused(region_code, int(row[2]), int(row[1]), index), row[2]])
	return out


## Okuma için tahsis ayrıntısı: {rehoused, unplaced} (komut + bölge); kayıt yoksa {}.
static func detail(region_code: String, command_id: int, index: Dictionary) -> Dictionary:
	if not index.has(command_id) or not (index[command_id]["effective"] as Dictionary).has(region_code):
		return {}
	return {"rehoused": int(index[command_id]["rehoused_by"].get(region_code, 0)),
		"unplaced": int(index[command_id]["unplaced_by"].get(region_code, 0))}
