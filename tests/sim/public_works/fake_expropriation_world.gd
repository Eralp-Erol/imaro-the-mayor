class_name FakeExpropriationWorld
extends ExpropriationPort
## T-042b adım 2 (sim) · Dünya köprüsünün TEST İKİZİ (gerçek bağdaştırıcı dünya adımında gelir). Gerçek `WorldNetwork`
## (KEEP_PARCELS ızgarası) üstünde yol denetimi/ekleme/geri alma GERÇEKTİR; yalnız "hangi parseller alınır" tablosu
## enjekte edilir (yol noktaları -> sim parsel kimlikleri) ve op'a `expropriate: true` işareti yazılır. Böylece sim'in
## köprü sözleşmesi (check/commit/undo/replay, kayıt yeniden oynatma, sapma reddi) dünya hattı olmadan sınanır.
## `reported` doluysa commit raporu tablodan FARKLI parsel kümesi bildirir (tick'te sapma: `expropriation_changed`).

var net: WorldNetwork
var rules := RoadDraftRules.new()
var takes: Dictionary = {}
var reported: Dictionary = {}
var supported: bool = true
var commits: int = 0
var undos: int = 0
var replays: int = 0


func _init(p_net: WorldNetwork) -> void:
	net = p_net
	rules.crossing_parcels = RoadDraftRules.CROSSING_ALLOW


## `points_cm` yolu `ids` sim parsellerini alsın.
func take(points_cm: PackedInt64Array, ids: Array) -> void:
	takes[_key(points_cm)] = PackedInt64Array(ids)


## Commit anında `ids` bildirilsin (önizlemeden sapma).
func report_instead(points_cm: PackedInt64Array, ids: Array) -> void:
	reported[_key(points_cm)] = PackedInt64Array(ids)


func available() -> bool:
	return supported


func check(points_cm: PackedInt64Array, road_class: StringName, busy: bool) -> Dictionary:
	var result := RoadDraftCheck.check(net, RoadDraftCheck.points_from_cm(points_cm), road_class, rules, busy)
	result["taken"] = takes.get(_key(points_cm), PackedInt64Array())
	result["fake_key"] = _key(points_cm)
	return result


func commit(checked: Dictionary, road_class: StringName) -> Dictionary:
	var report := net.add_road(checked["points"], road_class)
	if not bool(report["ok"]):
		return {"ok": false, "removed": PackedInt64Array(), "error": str(report["error"])}
	_flag_last_op()
	commits += 1
	var key: String = checked["fake_key"]
	return {"ok": true, "removed": reported.get(key, takes.get(key, PackedInt64Array())), "error": ""}


func undo() -> Dictionary:
	var undone := net.undo_last_op()
	undos += 1
	return {"ok": bool(undone["ok"]), "error": str(undone.get("error", ""))}


func replay(op: Dictionary) -> Dictionary:
	var report := net.add_road(NetworkDelta.decode_points(op["pts_cm"]), StringName(str(op["class"])),
		float(int(op["width_dm"])) * 0.1)
	if not bool(report["ok"]):
		return {"ok": false, "removed": PackedInt64Array(), "error": str(report["error"])}
	_flag_last_op()
	replays += 1
	return {"ok": true, "removed": takes.get(_key(op["pts_cm"]), PackedInt64Array()), "error": ""}


func _flag_last_op() -> void:
	(net.delta.ops[net.delta.ops.size() - 1] as Dictionary)["expropriate"] = true


## Düz (PackedInt64Array) ya da çiftli ([[x, z]...], op biçimi) nokta listesinden aynı anahtar.
static func _key(points_cm: Variant) -> String:
	var parts := PackedStringArray()
	for v: Variant in points_cm:
		if v is Array:
			for c: Variant in v:
				parts.append(str(int(c)))
		else:
			parts.append(str(int(v)))
	return ",".join(parts)
