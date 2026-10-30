class_name RoadDevScenario
extends RefCounted
## Yol çizimi için DEV/yakalama yardımcıları (T-042 adım 3). Oynanışı ve sim kurallarını değiştirmez; playable'ın dev
## bayraklarını (`--draw-road`, `--road-preview`) çözer. Komut AYNI yoldan (`submit_command`) gider; sim'e başka
## giriş yok.


## "ax,az,bx,bz" -> 4 sayı (bozuksa boş).
static func parse_vec4(text: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for part in text.split(",", false):
		out.append(float(part))
	return out if out.size() == 4 else PackedFloat64Array()


## `--draw-road`: yol komutunu gönderir. Dönüş: sim sonucu (bozuk argümanda null).
static func submit_road(facade: SimFacade, text: String) -> CommandResult:
	var v := parse_vec4(text)
	if v.is_empty():
		print("PLAYABLE_DRAW_ROAD bozuk bağımsız değişken (ax,az,bx,bz bekleniyor)")
		return null
	var cm := PackedInt64Array()
	for value in v:
		cm.append(roundi(value * 100.0))
	var res := facade.submit_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS))
	print("PLAYABLE_DRAW_ROAD tick=%d status=%s reason=%s args=%s" % [facade.current_tick(), String(res.status),
			String(res.reason_key), str(res.args)])
	return res


## `--road-preview`: aracı açar, A (yola yapışır) ve B'ye dokunmuş gibi REVIEW durumunda bırakır.
static func preview(ctrl: RoadDrawController, text: String) -> void:
	var v := parse_vec4(text)
	if v.is_empty() or ctrl == null:
		return
	ctrl.activate()
	# Önce sokak bandı: çizim yalnız yakın bantta açık.
	ctrl.dev_focus_draft(Vector2(v[0], v[1]), Vector2(v[2], v[3]), 140.0)
	ctrl.dev_tip_world = Vector2(v[2], v[3])
	ctrl.tool.tap_at(Vector2(v[0], v[1]), 30.0)
	ctrl.tool.tap_at(Vector2(v[2], v[3]), 0.5)
	var verdict := ctrl.tool.verdict
	print("PLAYABLE_ROAD_PREVIEW step=%s valid=%s reason=%s" % [str(ctrl.tool.step), str(ctrl.tool.is_valid()),
			str(verdict.reason_key) if verdict != null else "-"])


## `--draw-road` sonrası (dev): bölgedeki parsellerin karar kodu dağılımı ve en yakın onaylı parsel (yakalama senaryosu
## ayarı için; sim'i değiştirmez).
static func report(facade: SimFacade, region: StringName, near: Vector2) -> void:
	var codes := {}
	var best_id := -1
	var best_d := INF
	for v in facade.parcel_views(facade.parcel_ids(region)):
		codes[String(v.decision_code)] = int(codes.get(String(v.decision_code), 0)) + 1
		if v.decision == &"approved" and v.center.distance_to(near) < best_d:
			best_d = v.center.distance_to(near)
			best_id = v.id
	print("PLAYABLE_ROAD_REPORT region=%s codes=%s nearest_approved=%d at_m=%.0f" % [region, str(codes), best_id,
			best_d if best_id > 0 else -1.0])


## `--road-reason` (dev, yakalama): yola en yakın ONAYLI parselin yatırımcı gerekçesini gerekçe panelinde açar.
## Dönüş: açılan parsel kimliği (yoksa -1).
static func open_reason(facade: SimFacade, results: M2Results, region: StringName, near: Vector2) -> int:
	if results == null:
		return -1
	var best: ParcelView = null
	var best_d := INF
	for v in facade.parcel_views(facade.parcel_ids(region)):
		if v.decision == &"approved" and v.center.distance_to(near) < best_d:
			best_d = v.center.distance_to(near)
			best = v
	if best == null:
		return -1
	var found: ReasonRecord = null
	for r in facade.reasons_for(best.ref()):
		if r.decision_key == &"decision.investor.develop":
			found = r
	if found == null:
		return -1
	var rid := found.id
	results.open_reason(func(p: ReasonPanel) -> void: p.show_record(rid))
	return best.id
