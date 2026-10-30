class_name PublicWorksState
extends RefCounted
## Oyuncu yolu durum bölümü `state.systems["public_works"]` (T-042 adım 2, ADR-0005 Ek E). Bölüm YALNIZ ilk uygulanan
## yolda yaratılır; okuma/doğrulama (`validate_command`) bölüm yaratmaz. Böylece yolsuz koşuların `state_hash`'i (altın
## değerler `tests/sim/m2_query_test.gd`) bit-bit aynıdır.
##
## Düzen (hepsi düz veri, ondalık yok):
##   version               VERSION
##   base_graph_hash       yolların uygulandığı TABAN ağın graf özeti (`WorldNetwork.base_hash`); yükleme uyuşmazsa
## reddeder
##   ops                   [NetworkDelta op'ları] (add_road: pts_cm [[x, z]...], class, width_dm), uygulama sırasıyla
##   hashes                [graf hash'i, op i uygulandıktan SONRA]; kayıt/yükleme her adımda karşılaştırır
##   works                 [{id, command_id, tick, road_class, length_cm, region_units {kod: birim}}]; ops ile aynı
## uzunluk
##   infra_bonus           TÜRETİLMİŞ {kod: birim}: bölge altyapı kapasitesine EKLENEN (ekonomi okur; sütun yazılmaz)
##   infra_source          TÜRETİLMİŞ {kod: "command.N"}: bölgede kapasiteyi EN SON artıran yol (gerekçe `source_ref`i)
## Türetilmiş iki sözlük `works`ten yeniden hesaplanabilir; `validate_data` uyuşmayı bozuk kayıt sayar. Ekonomi sütunu
## `regions.infra_cap`a DOKUNULMAZ: etkin kapasite = taban + bonus; geri alma bonusu kendiliğinden düşürür.

const KEY := "public_works"
const VERSION := 1
const OP_ADD_ROAD := "add_road"
const COMMAND_PREFIX := "command."


## Bölüm (DOĞRUDAN durumun parçası); yoksa boş sözlük.
static func data(state: GameState) -> Dictionary:
	var d: Variant = state.systems.get(KEY, null)
	return d if d is Dictionary else {}


static func is_present(state: GameState) -> bool:
	return not data(state).is_empty()


## Kayıtlı yol sayısı (bölüm yoksa 0).
static func work_count(state: GameState) -> int:
	var d := data(state)
	return 0 if d.is_empty() else (d["works"] as Array).size()


## Tabana eklenen kapasite birimi (bölüm/kod yoksa 0). Ekonomi karar yolunda çağrılır: O(1).
static func infra_bonus(state: GameState, region_code: Variant) -> int:
	var d: Variant = state.systems.get(KEY, null)
	return 0 if not (d is Dictionary) else int((d["infra_bonus"] as Dictionary).get(String(region_code), 0))


## Bölgede kapasiteyi en son artıran yolun komut referansı (`command.N`); yoksa &"".
static func infra_source(state: GameState, region_code: Variant) -> StringName:
	var d: Variant = state.systems.get(KEY, null)
	if not (d is Dictionary):
		return &""
	return StringName(str((d["infra_source"] as Dictionary).get(String(region_code), "")))


## Yeni yolu ekler (bölüm yoksa yaratır). `work`: {command_id, tick, road_class, length_cm, region_units}.
static func append_work(state: GameState, base_graph_hash: String, op: Dictionary, graph_hash_after: String,
		work: Dictionary) -> void:
	var d := state.system_data(StringName(KEY))
	if d.is_empty():
		d["version"] = VERSION
		d["base_graph_hash"] = base_graph_hash
		d["ops"] = []
		d["hashes"] = []
		d["works"] = []
		d["infra_bonus"] = {}
		d["infra_source"] = {}
	(d["ops"] as Array).append(op.duplicate(true))
	(d["hashes"] as Array).append(graph_hash_after)
	var entry := work.duplicate(true)
	entry["id"] = (d["works"] as Array).size() + 1
	(d["works"] as Array).append(entry)
	rebuild_derived(d)


## Son yolu çıkarır ve döndürür ({} = yok). Türetilmiş sözlükler yeniden hesaplanır.
static func pop_work(state: GameState) -> Dictionary:
	var d := data(state)
	if d.is_empty() or (d["works"] as Array).is_empty():
		return {}
	(d["ops"] as Array).pop_back()
	(d["hashes"] as Array).pop_back()
	var work: Dictionary = (d["works"] as Array).pop_back()
	rebuild_derived(d)
	return work


## Türetilmiş `infra_bonus`/`infra_source`u `works`ten yeniden kurar (bölge kodu sıralı; boş bonus yazılmaz).
static func rebuild_derived(d: Dictionary) -> void:
	var derived := derive(d["works"])
	d["infra_bonus"] = derived["bonus"]
	d["infra_source"] = derived["source"]


static func derive(works: Array) -> Dictionary:
	var bonus := {}
	var source := {}
	for work: Dictionary in works:
		var units: Dictionary = work["region_units"]
		for code: Variant in units:
			var key := str(code)
			var amount := int(units[code])
			if amount <= 0:
				continue
			bonus[key] = int(bonus.get(key, 0)) + amount
			source[key] = "%s%d" % [COMMAND_PREFIX, int(work["command_id"])]
	return {"bonus": bonus, "source": source}


## Bölge birimleri toplamı.
static func total_units(units: Dictionary) -> int:
	var sum := 0
	for code: Variant in units:
		sum += int(units[code])
	return sum


## Bölge kodları (String), sıralı: olay/öznitelik üretiminde deterministik sıra.
static func sorted_codes(units: Dictionary) -> Array:
	var codes: Array = units.keys()
	codes.sort()
	return codes


## Bölüm biçim hatası (Türkçe) ya da "". Bölüm yoksa geçerli. Ağa bakmaz (ağ eşitleme ayrıdır).
static func validate_data(value: Variant) -> String:
	if value == null:
		return ""
	if not (value is Dictionary) or value.get("version", null) != VERSION:
		return "durum.systems.public_works sürümü geçersiz"
	if typeof(value.get("base_graph_hash", null)) != TYPE_STRING:
		return "durum.systems.public_works.base_graph_hash dizge değil"
	for field_name in ["ops", "hashes", "works"]:
		if not (value.get(field_name, null) is Array):
			return "durum.systems.public_works.%s dizi değil" % field_name
	for field_name in ["infra_bonus", "infra_source"]:
		if not (value.get(field_name, null) is Dictionary):
			return "durum.systems.public_works.%s sözlük değil" % field_name
	var n: int = (value["ops"] as Array).size()
	if (value["hashes"] as Array).size() != n or (value["works"] as Array).size() != n:
		return "durum.systems.public_works ops/hashes/works uzunlukları farklı"
	for i in n:
		var problem := _op_problem(value["ops"][i]) + _hash_problem(value["hashes"][i]) + _work_problem(value["works"][i], i)
		if not problem.is_empty():
			return "durum.systems.public_works[%d]: %s" % [i, problem]
	var derived := derive(value["works"])
	if StateHash.of(derived["bonus"]) != StateHash.of(value["infra_bonus"]) \
			or StateHash.of(derived["source"]) != StateHash.of(value["infra_source"]):
		return "durum.systems.public_works türetilmiş kapasite yollarla uyuşmuyor"
	return ""


static func _op_problem(op: Variant) -> String:
	if not (op is Dictionary) or str(op.get("op", "")) != OP_ADD_ROAD:
		return "op add_road değil"
	if typeof(op.get("class", null)) != TYPE_STRING or typeof(op.get("width_dm", null)) != TYPE_INT:
		return "op sınıf/genişlik geçersiz"
	var pts: Variant = op.get("pts_cm", null)
	if not (pts is Array) or (pts as Array).size() < 2:
		return "op noktaları geçersiz"
	for pair: Variant in pts:
		if not (pair is Array) or (pair as Array).size() != 2 \
				or typeof(pair[0]) != TYPE_INT or typeof(pair[1]) != TYPE_INT:
			return "op noktası [x, z] tamsayı çifti değil"
	return ""


static func _hash_problem(h: Variant) -> String:
	return "" if typeof(h) == TYPE_STRING and not (h as String).is_empty() else "graf özeti boş"


static func _work_problem(work: Variant, index: int) -> String:
	if not (work is Dictionary):
		return "yol kaydı sözlük değil"
	for field_name in ["id", "command_id", "tick", "length_cm"]:
		if typeof(work.get(field_name, null)) != TYPE_INT:
			return "yol.%s tamsayı değil" % field_name
	if int(work["id"]) != index + 1 or int(work["command_id"]) < 1 or int(work["tick"]) < 0:
		return "yol kimliği/komut/tick geçersiz"
	if typeof(work.get("road_class", null)) != TYPE_STRING or not (work.get("region_units", null) is Dictionary):
		return "yol sınıfı/bölge birimleri geçersiz"
	for code: Variant in work["region_units"]:
		if typeof(code) != TYPE_STRING or typeof(work["region_units"][code]) != TYPE_INT:
			return "yol bölge birimi tamsayı değil"
	return ""
