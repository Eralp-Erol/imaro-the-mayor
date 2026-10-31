class_name PublicWorksContext
extends RefCounted
## Oyuncu yolu işinin ÇALIŞMA bağlamı (T-042 adım 2, ADR-0005 Ek E): sim'in kullandığı AYNI `WorldNetwork` nesnesi (oyun
## katmanı kurar ve sahip olur; sim onu YALNIZ tick sınırında ve ana iş parçacığında değiştirir), yetki/uzunluk/eğim
## kuralları (`RoadDraftRules`, ağ verisi) ve sim kural verisi (`PublicWorksConfig`). Ağın kendisi sim durumu DEĞİLDİR;
## durum `systems.public_works` bölümündeki yol listesidir ve ağ kayıt/yüklemede ona eşitlenir (`sync_to`).
##
## Hesap yazılmaz: geometri denetimi `RoadDraftCheck` (world hattı), kapasite birimi `PublicWorksConfig.infra_units`.
## Sim yalnız komutu doğrular ve işler. Saf RefCounted: Node/zaman/OS yok.

## Dünya meşgulse (bitki yükleyicisi ya da iş parçacıklı yol kurulumu sürüyor) true döndüren çağrılabilir. YALNIZ
## gönderimde
## (`validate_submit`) sorulur; tick sınırında asla (sim sonucu çalışma zamanına bağlı olmamalı). Varsayılan: asla
## meşgul değil.
var busy_probe: Callable = Callable()
var net: WorldNetwork
var rules: RoadDraftRules
var config: PublicWorksConfig
## T-042b · Kamulaştırma: dünya köprüsü (yoksa/desteklemiyorsa kamulaştırma KAPALI), ekonomi (statik sütunlar), korunan
## parsel kimlikleri (oyun katmanı T0 bayraklarından kurar; `set_protected`) ve değişim halkasına tick içinde
## yazılacak parseller (`ExpropriationFlushSystem` boşaltır: halka yalnız günlük tick başında başlar).
var expropriation: ExpropriationPort
var economy: EconomySystem
var protected_ids: Dictionary = {}
var pending_notes: PackedInt64Array = PackedInt64Array()
## Kamulaştırma doğrulama sonucunun SON hesabı (aynı durum + ağ sürümü + komut için tekrar hesaplanmaz; yakınlık
## taraması O(parsel)). Anahtar durum NESNESİNİ içerir (kayıt yükleme yeni nesne getirir), tick ve alınan sayısını.
var problem_memo_key: String = ""
var problem_memo: Dictionary = {}
var _x_memo: Dictionary = {}
var _x_memo_version: int = -1
var _x_memo_class: StringName = &""
var _x_memo_points := PackedInt64Array()
var _memo: Dictionary = {}
var _memo_version: int = -1
var _memo_class: StringName = &""
var _memo_points := PackedInt64Array()


## Kurulum sorunu varsa push_error + null (ağ mühürlü ve boş delta ile gelmeli; sınıflar kural kümesinde olmalı).
static func create(p_net: WorldNetwork, p_rules: RoadDraftRules, p_config: PublicWorksConfig) -> PublicWorksContext:
	var problem := setup_problem(p_net, p_rules, p_config)
	if not problem.is_empty():
		push_error("PublicWorksContext: %s" % problem)
		return null
	var ctx := PublicWorksContext.new()
	ctx.net = p_net
	ctx.rules = p_rules
	ctx.config = p_config
	return ctx


static func setup_problem(p_net: WorldNetwork, p_rules: RoadDraftRules, p_config: PublicWorksConfig) -> String:
	if p_net == null or not p_net.sealed:
		return "ağ yok ya da mühürlü değil"
	if p_rules == null:
		return "yol kuralları yok"
	if p_config == null or not p_config.is_valid():
		return "yol işi yapılandırması geçersiz: %s" % ("null" if p_config == null else p_config.error)
	for road_class in p_config.class_names():
		if not p_rules.allowed_classes.has(road_class):
			return "sınıf '%s' ağ kurallarında (player_roads.allowed_classes) izinli değil" % road_class
	return ""


func is_busy() -> bool:
	return busy_probe.is_valid() and bool(busy_probe.call())


## T-042b · Kamulaştırma köprüsünü takar (dünya adımı gerçek bağdaştırıcıyı, testler kendi ikizini verir).
func set_expropriation(port: ExpropriationPort) -> void:
	expropriation = port
	_x_memo_version = -1
	problem_memo_key = ""


## Korunan (kamulaştırılamaz: tarihî/simge/kamu) parsel kimlikleri. Oyun katmanı T0 bayraklarından türetir.
func set_protected(ids: PackedInt64Array) -> void:
	protected_ids = {}
	for id in ids:
		protected_ids[id] = true
	problem_memo_key = ""


## Kamulaştırma yapılabilir mi? Veri bayrağı açık + dünya destekliyor + ekonomi kurulu (alınan parselin sütunları
## orada).
func expropriation_available() -> bool:
	return config.expropriation_enabled and expropriation != null and expropriation.available() and economy != null


## Kamulaştırma kipinde taslak: `ExpropriationPort.check` + sim'in kapasite planı + `taken`. `draft` ile aynı önbellek
## kuralı (ağ sürümü + noktalar + sınıf). Port yoksa/desteklemiyorsa ret.
func draft_expropriating(points_cm: PackedInt64Array, road_class: StringName, busy: bool = false) -> Dictionary:
	if not busy and _x_memo_version == net.graph_version and _x_memo_class == road_class \
			and _x_memo_points == points_cm:
		return _x_memo.duplicate()
	var result := expropriation.check(points_cm, road_class, busy)
	if bool(result["ok"]) and not config.has_class(road_class):
		result["ok"] = false
		result["reason"] = RoadDraftCheck.REASON_BAD_CLASS
		result["key"] = RoadDraftCheck.key_of(RoadDraftCheck.REASON_BAD_CLASS)
	result = _with_plan(result, road_class)
	if not busy:
		_x_memo = result
		_x_memo_version = net.graph_version
		_x_memo_class = road_class
		_x_memo_points = points_cm.duplicate()
		return result.duplicate()
	return result


## Komut kuyruğuna girecek işleyiciler (facade `attach_public_works` kaydeder).
func handlers() -> Array[CommandHandler]:
	return [PublicWorkRoadHandler.new(self), PublicWorkUndoHandler.new(self)]


## Ağın yol listesi sim durumuyla tutarlı mı? (Bu bağlam dışında ağa delta yazılmamış olmalı.)
func tracks(state: GameState) -> bool:
	return net.delta.ops.size() == PublicWorksState.work_count(state)


## Taslağı denetler (ağa dokunmaz) ve sim'in kapasite hesabını ekler. Dönüş: `RoadDraftCheck.check` sonucu +
## {length_cm: int, region_units: {kod: birim}} (yalnız ok iken dolu).
##
## Son denetim ÖNBELLEKLİDİR (T-049): ağ sürümü (`graph_version`), noktalar ve sınıf aynıysa denetim yeniden çalışmaz
## (doğrulama, uygulama ve gönderim aynı taslağı ağ değişmeden sorar; denetim 5-14 ms). Ağ her değiştiğinde
## (`_touch`) sürüm artar, eski cevap verilmez. "Meşgul" cevabı ucuzdur ve önbelleğe alınmaz. Dönüş sığ kopyadır.
func draft(points_cm: PackedInt64Array, road_class: StringName, busy: bool = false) -> Dictionary:
	if not busy and _memo_version == net.graph_version and _memo_class == road_class and _memo_points == points_cm:
		return _memo.duplicate()
	var result := RoadDraftCheck.check(net, RoadDraftCheck.points_from_cm(points_cm), road_class, rules, busy)
	if bool(result["ok"]) and not config.has_class(road_class):
		result["ok"] = false
		result["reason"] = RoadDraftCheck.REASON_BAD_CLASS
		result["key"] = RoadDraftCheck.key_of(RoadDraftCheck.REASON_BAD_CLASS)
	result = _with_plan(result, road_class)
	if not busy:
		_memo = result
		_memo_version = net.graph_version
		_memo_class = road_class
		_memo_points = points_cm.duplicate()
		return result.duplicate()
	return result


## Kapasite planı: yolun bölge başına uzunluğu (cm tamsayı) x sınıf katsayısı. Sıralı bölge kodları, sıfır birim
## yazılmaz.
func _with_plan(result: Dictionary, road_class: StringName) -> Dictionary:
	result["length_cm"] = roundi(float(result["length_m"]) * 100.0)
	var units := {}
	if bool(result["ok"]):
		var lengths: Dictionary = result["regions"]
		var codes: Array = lengths.keys()
		codes.sort()
		for code: String in codes:
			if code.is_empty():
				continue
			var amount := config.infra_units(road_class, roundi(float(lengths[code]) * 100.0))
			if amount > 0:
				units[code] = amount
	result["region_units"] = units
	return result


## Ağı `target` durumundaki yol listesine eşitler (ortak önek -> fazlası LIFO geri al -> eksiği uygula, her adımda graf
## hash'i). Bölüm yoksa hedef = boş liste. Hata: Türkçe metin (BOŞ DEĞİL) ve ağ ESKİ durumuna geri getirilmiş olur;
## geri getirme de başarısızsa metin "AĞ BOZULDU" ile başlar. Başarı: "".
func sync_to(target: GameState) -> String:
	var section := PublicWorksState.data(target)
	var ops: Array = [] if section.is_empty() else section["ops"]
	var hashes: Array = [] if section.is_empty() else section["hashes"]
	if not section.is_empty() and section["base_graph_hash"] != net.base_hash:
		return "kayıt başka bir taban yol ağına ait (taban özeti uyuşmuyor)"
	var current: Array = net.delta.ops.duplicate(true)
	var original_hash := net.graph_hash()
	var takens: Array = []
	if not section.is_empty():
		for work: Dictionary in section["works"]:
			takens.append(work["expropriation"]["parcel_ids"] if work.has("expropriation") else null)
	var problem := _move_to(ops, hashes, takens)
	if problem.is_empty():
		return ""
	var restore := _move_to(current, [], [])  # geri getirme: özet karşılaştırması aşağıda tek sefer
	if not restore.is_empty() or net.graph_hash() != original_hash:
		return "AĞ BOZULDU: %s; eski ağ geri getirilemedi (%s)" % [problem, restore]
	return problem


# `net.delta.ops`u `target`a getirir: ortak önek, fazlası geri al, eksiği uygula. `hashes` (boş olabilir) i. op'tan
# sonraki
# graf özetleridir. Hata metni ya da "".
func _move_to(target: Array, hashes: Array, takens: Array) -> String:
	var common := 0
	var live := net.delta.ops
	while common < live.size() and common < target.size() and _same_op(live[common], target[common]):
		common += 1
	while net.delta.ops.size() > common:
		var undone := undo_live_op()
		if not bool(undone["ok"]):
			return "yol geri alınamadı (%s)" % undone["error"]
	if not hashes.is_empty():
		var expected := net.base_hash if common == 0 else str(hashes[common - 1])
		if net.graph_hash() != expected:
			return "ortak önek sonrası graf özeti kayıttakiyle uyuşmuyor"
	for i in range(common, target.size()):
		var op: Dictionary = target[i]
		var problem := _applied_problem(i, op, _replay_op(op), hashes, takens)
		if not problem.is_empty():
			return problem
	return ""


# Yeniden oynatılan i. yolun sonucu kayıtla uyuşuyor mu? Sorun metni ya da "".
func _applied_problem(i: int, op: Dictionary, report: Dictionary, hashes: Array, takens: Array) -> String:
	if not bool(report["ok"]):
		return "%d. yol uygulanamadı (%s)" % [i + 1, str(report["error"])]
	if not _same_op(net.peek_last_op(), op):
		return "%d. yol uygulandıktan sonra op kayıttakinden farklı" % [i + 1]
	if i < takens.size() and takens[i] != null and not _same_taken(report.get("removed_parcels", null), takens[i]):
		return "%d. yolun aldığı parseller kayıttakinden farklı (network_mismatch)" % [i + 1]
	if not hashes.is_empty() and net.graph_hash() != str(hashes[i]):
		return "%d. yol sonrası graf özeti kayıttakiyle uyuşmuyor" % [i + 1]
	return ""


## Canlı son op kamulaştırmalıysa geri alma dünya köprüsünden geçer (alınan parselleri dünya geri koyar).
func undo_live_op() -> Dictionary:
	var ops := net.delta.ops
	if not ops.is_empty() and bool((ops[ops.size() - 1] as Dictionary).get("expropriate", false)) \
			and expropriation != null:
		var undone := expropriation.undo()
		return {"ok": bool(undone["ok"]), "error": undone.get("error", "")}
	return net.undo_last_op()


# `add_road` biçiminde rapor: kamulaştırmalı op köprüden (`removed_parcels` = alınan kimlikler), diğeri ağdan.
func _replay_op(op: Dictionary) -> Dictionary:
	if bool(op.get("expropriate", false)):
		if expropriation == null or not expropriation.available():
			return {"ok": false, "error": "kayıtta kamulaştırmalı yol var ama dünya köprüsü yok"}
		var replayed := expropriation.replay(op)
		return {"ok": bool(replayed["ok"]), "error": replayed.get("error", ""),
			"removed_parcels": replayed.get("removed", PackedInt64Array())}
	return net.add_road(NetworkDelta.decode_points(op["pts_cm"]), StringName(str(op["class"])),
		float(int(op["width_dm"])) * 0.1)


static func _same_taken(reported: Variant, saved: Variant) -> bool:
	if reported == null:
		return false
	var a := ExpropriationSummary.sorted_ids({"parcel_ids": reported})
	var b := ExpropriationSummary.sorted_ids({"parcel_ids": saved})
	return a == b


func _same_op(a: Dictionary, b: Dictionary) -> bool:
	return StateHash.of(a) == StateHash.of(b)
