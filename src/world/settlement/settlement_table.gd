class_name SettlementTable
extends RefCounted
## T0 yerleşimin modül tablosu yükleyicisi (T-062 A2; ADR-0006 §2.2/§3.2). Tablo `data/library/game_buildings.json`
## (derleme kapısı: approved + hash eşleşen 21 hero; `tools/library/build_game_set.py`). Çalışma zamanı ikinci kilit:
## her kimlik `LibraryGate`ten geçer; geçmeyen kimlik tablodan ÇIKARILIR ve sayılır (sessiz geçiş yok).
## Reddedilmiş kit tablosu (`kit_manifest.json`) bu katmanda OKUNMAZ. Saf veri, node/RNG/zaman yok.

const PATH := "res://data/library/game_buildings.json"


## {"table": Dictionary (modules[] yalnız kapıdan geçenler; diğer alanlar korunur), "gate": LibraryGate}.
## `table` boş sözlükse dosya okunamadı. Kapıdan geçmeyen kimlikler `gate.unapproved_ids`ta kalır.
static func load_game_table(path: String = PATH, gate: LibraryGate = null) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("SettlementTable: bina tablosu okunamadı: %s" % path)
		return {"table": {}, "gate": gate}
	var the_gate := gate if gate != null else LibraryGate.load_default()
	return {"table": filter(parsed as Dictionary, the_gate), "gate": the_gate}


## `table.modules[]` içinden yalnız `gate`ten geçen kimlikleri tutan KOPYA (sıra korunur; diğer alanlar aynen).
static func filter(table: Dictionary, gate: LibraryGate) -> Dictionary:
	var out: Dictionary = table.duplicate(true)
	var kept: Array = []
	for rec in out.get("modules", []):
		var id := str((rec as Dictionary).get("id", ""))
		if gate.request(id).is_empty():
			continue   # LibraryGate zaten izledi (unapproved_ids, push_error)
		kept.append(rec)
	out["modules"] = kept
	return out


## Yalnız tablo sözlüğü (yükleyici çağrıları için kısayol).
static func game_table() -> Dictionary:
	return load_game_table()["table"]
