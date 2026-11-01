class_name ReactionRehousing
extends RefCounted
## D-014 §3 (2026-11-01): "yeni ev sunulmadığı sürece tepki sürer; sunulursa hiç olmaz."
## Sim'de bunun karşılığı YOKTUR: haneler yalnız bölge toplamıdır (`latent_hh`, barınan = min(talep, biten konut));
## yerinden edilen hane `household_fate = return_to_latent` ile bölge talebinde kalır; ne hanenin "yeni ev bulması"
## ne de belediyenin "yeni ev sunması" modellenmiştir (tepki hattı `ExpropriationFlow.apply` ->
## `PublicWorksState.note_reactions` yalnız bölge başına hane sayısı yazar). Sahip yeniden iskân özelliğini ayrıca
## karara bağlayacaktır (D-015, design/specs/resettlement-social-security-v0.md).
##
## TEK GİRİŞ NOKTASI: tepkinin "bu hane yeniden yerleşti mi" kararı YALNIZ `still_unhoused`dan geçer (yerel okuma ve
## ilçe/bölge sinyali dahil). T-065 (ADR-0009 Değişiklik 1): yeniden iskân politikası AÇIKKEN yol, tahsis kaydını
## (`works[i].expropriation.resettlement.effective/unplaced_by/moves`) `index` ile verir; tepki defteri HAM kalır
## (gerçek yerinden edilen hane), rahatlama OKUMA anında yapılır. `index` boşsa (politika hiç açılmadı, kayıt yok)
## davranış bit-bit eskisi gibidir: sayı aynen döner. SAF ve durumsuz; rastgelelik yok.


## Tahsis kayıtlarından {komut: {effective, unplaced_by, rehoused_by}} (her biri {kod: hane}). Ayakta yolların
## (`standing_roads`) kaydı; kayıt yoksa BOŞ sözlük (kapalı yol). Tarama başına BİR KEZ kurulur.
static func index(state: GameState) -> Dictionary:
	var out := {}
	for work: Dictionary in PublicWorksState.standing_roads(state):
		var record: Dictionary = (work.get("expropriation", {}) as Dictionary).get("resettlement", {})
		if record.is_empty():
			continue
		var rehoused_by := {}
		for move: Array in record["moves"]:
			rehoused_by[String(move[0])] = int(rehoused_by.get(String(move[0]), 0)) + int(move[2])
		out[int(work["command_id"])] = {"effective": record["effective"], "unplaced_by": record["unplaced_by"],
			"rehoused_by": rehoused_by}
	return out


## (Bölge, komut) satırındaki `households` yerinden edilen haneden kaçı HÂLÂ barınamıyor (tepki sayar). `index` boş ya
## da
## bu (komut, bölge) için kayıt yoksa tümü; kayıt varsa tahsisin kalan tepkisi (`effective`, en çok `households`).
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
