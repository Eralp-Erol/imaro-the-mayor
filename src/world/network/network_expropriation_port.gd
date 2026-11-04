class_name NetworkExpropriationPort
extends ExpropriationPort
## T-042b · Sim `ExpropriationPort`unun GERÇEK dünya bağdaştırıcısı (ADR-0005 Ek F; D-009, D-011). Sim "hangi parseller
## alınır" hesabını yapmaz: `check` `RoadDraftCheck.check` biçimini (parselli bloktan geçmeye izin vererek) + `taken`
## kümesini verir; `commit` `expropriate: true` işaretli op'u ağa ekler (parseller kimlikleriyle emekliye ayrılır, yeni
## parsel YOK) ve alınanları bildirir; `undo` ağın son op'unu geri alır (parseller kimlik ve `owner_id` ile döner);
## `replay` kayıtlı op'u yeniden uygular (op'taki `taken` yeniden hesaplananla aynı değilse hata, ağa dokunmaz).
##
## Kullanılabilirlik: `player_roads.crossing_parcels == "expropriate"` ve `player_roads.keep_parcels`. Aksi halde taban
## sınıf davranışı (`expropriation_disabled`). Parsel kimliği sim ile aynıdır (sim parsel kimliği = dünya kimliği).

var net: WorldNetwork
var rules: RoadDraftRules
var _enabled: bool = false


func _init(p_net: WorldNetwork, p_rules: RoadDraftRules) -> void:
	net = p_net
	_enabled = p_rules.expropriation_enabled() and p_net.rules.keep_parcels_on_delta
	rules = RoadDraftRules.from_control({"player_roads": p_rules.to_dict()})
	rules.crossing_parcels = RoadDraftRules.CROSSING_ALLOW  # düz denetim parselli bloğa sormaz; alınanlar `taken`


func available() -> bool:
	return _enabled


func check(points_cm: PackedInt64Array, road_class: StringName, busy: bool) -> Dictionary:
	if not _enabled:
		return super.check(points_cm, road_class, busy)
	var result := RoadDraftCheck.check(net, RoadDraftCheck.points_from_cm(points_cm), road_class, rules, busy)
	result["taken"] = RoadDraftCheck.taken_parcels(net, result["points"], road_class) if bool(result["ok"]) \
			else PackedInt64Array()
	return result


func commit(checked: Dictionary, road_class: StringName) -> Dictionary:
	if not _enabled:
		return super.commit(checked, road_class)
	return _result_of(net.add_road_expropriating(checked["points"], road_class))


func undo() -> Dictionary:
	if not _enabled:
		return super.undo()
	var undone := net.undo_last_op()
	return {"ok": bool(undone["ok"]), "error": str(undone.get("error", ""))}


func replay(op: Dictionary) -> Dictionary:
	if not _enabled:
		return super.replay(op)
	if not NetworkExpropriation.is_flagged(op):
		return {"ok": false, "removed": PackedInt64Array(), "error": "op kamulaştırmalı değil"}
	return _result_of(net.add_road_expropriating(NetworkDelta.decode_points(op["pts_cm"]),
			StringName(str(op["class"])), float(int(op["width_dm"])) * 0.1, op.get(NetworkExpropriation.KEY_TAKEN)))


func available_land(source_op: int, parcel_ids: PackedInt64Array) -> Dictionary:
	if not _enabled:
		return {"ok": false, "error": "arsa geri açma desteklenmiyor", "parcel_ids": []}
	return NetworkLandReuse.available(net, source_op, parcel_ids)


func restore_land(source_op: int, parcel_ids: PackedInt64Array) -> Dictionary:
	if not _enabled:
		return {"ok": false, "error": "arsa geri açma desteklenmiyor", "restored": PackedInt64Array()}
	var report := net.restore_parcels(source_op, parcel_ids)
	return {"ok": report["ok"], "error": report["error"], "restored": PackedInt64Array(report["added_parcels"])}


func archived_land(source_op: int, parcel_ids: PackedInt64Array) -> Array:
	return NetworkLandReuse.archive_rows(net, source_op, parcel_ids) if _enabled else []


## `add_road_expropriating` raporu -> köprü sonucu. Yeni parsel çıkarsa (olmamalı) işlem geri alınır. Yeniden oynatmada
## alınan küme kayıttakinden farklıysa `add_road_expropriating` ağa dokunmadan hata verir.
func _result_of(report: Dictionary) -> Dictionary:
	if not bool(report["ok"]):
		return {"ok": false, "removed": PackedInt64Array(), "error": str(report["error"])}
	if not (report["added_parcels"] as Array).is_empty():
		net.undo_last_op()
		return {"ok": false, "removed": PackedInt64Array(), "error": "kamulaştırma yeni parsel üretti (olmamalı)"}
	return {"ok": true, "removed": PackedInt64Array(report["removed_parcels"]), "error": ""}
