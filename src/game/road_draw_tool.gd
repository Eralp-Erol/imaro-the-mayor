# gdlint:disable=max-public-methods
class_name RoadDrawTool
extends RefCounted
## Yol çizim aracının DURUM MAKİNESİ (T-042 adım 3; CAN-04, D-008/D-009). Düğüm/ekran yok: dünya koordinatı (m) alır,
## sim'e YALNIZ `SimFacade` ile konuşur (`validate_command` önizleme, `submit_command` onay). UI/render sim'e yazmaz;
## ağ burada yalnız OKUNUR (yapışma için). Önizleme sayıları (uzunluk, bölge, kapasite birimi) sim'in kendi hesabıdır
## (`CommandResult.args`), burada uydurulmaz. Ret anahtarı sim'in verdiğidir (`public_work.reject.*`).
##
## Akış (iki dokunuş + onay): OFF -> PICK_A (yola/yol ucuna dokun) -> PICK_B (imleç önizlemesi; dokunuşla bitiş) ->
## REVIEW (önizleme sabit; başka yere dokunuş bitişi değiştirir, AYNI noktaya yeniden dokunuş onaylar; Onayla/Enter)
## -> SENDING (komut kuyrukta; `public_work.built`
## ya da `command.rejected` olayı gelince PICK_A). v0 ölçüm bulgusu (production/log/2026-10-30-T-042-yol-olcum.md):
## yoldan başlamayan serbest dokunuşun %98-100'ü reddediliyor; bu yüzden A mutlaka mevcut yola/yol ucuna yapışır.

signal changed

enum Step { OFF, PICK_A, PICK_B, REVIEW, SENDING }

const ROAD_CLASS := &"local"
## Çizim yalnız bu ölçek bantlarında açık; metro/çok uzak bantta "yakınlaşın".
const ACTIVE_BANDS: Array[StringName] = [&"street", &"neighborhood", &"district"]
## Önizleme yeniden doğrulaması için asgari imleç hareketi (m): ~1 ms'lik denetim her piksel değişiminde çağrılmaz.
const HOVER_EPSILON_M := 0.5

const MSG_NONE := &""
const MSG_START_NOT_ON_ROAD := &"road.start_not_on_road"
const MSG_DONE := &"road.step.done"
const MSG_FAILED := &"road.step.failed"
const MSG_UNDONE := &"road.undo_done"
## T-042b (D-011): sim'in `crosses_parcels` retti kamulaştırma teklifini (`taken_parcels` > 0) taşıyorsa teklif vardır.
const REJECT_CROSSES_PARCELS := &"public_work.reject.crosses_parcels"
const REJECT_EXPROPRIATION_CHANGED := &"public_work.reject.expropriation_changed"

var step: Step = Step.OFF
var band_active: bool = true
## Yapışmış başlangıç (m). PICK_A dışında geçerli.
var start: Vector2 = Vector2.ZERO
## Bitiş (m): PICK_B'de imleç, REVIEW'da sabit.
var end: Vector2 = Vector2.ZERO
## PICK_A'da imlecin yapışma durumu: {snapped, pos, kind}.
var hover: Dictionary = {"snapped": false, "pos": Vector2.ZERO, "kind": &""}
## Güncel taslağın kuru koşu sonucu (sim); PICK_B/REVIEW'da dolu.
var verdict: CommandResult = null
## Son durum mesajı anahtarı + argümanları (panel gösterir); başarı/başarısızlık/ret.
var message: StringName = MSG_NONE
var message_args: Dictionary = {}
var sending_command_id: int = SimContract.NO_ID
## T-042b · Oyuncu sim'in kamulaştırma teklifini kabul etti (`accept_offer`): komut `expropriate: true` ile sorulur ve
## gönderilir. Bitiş değişince/taslak sıfırlanınca düşer (teklif her taslak için yeniden okunur).
var expropriate: bool = false

var _net: WorldNetwork = null
var _facade: SimFacade = null
var _verdict_key: String = ""
var _verdict_version: int = -1


static func create(net: WorldNetwork, facade: SimFacade) -> RoadDrawTool:
	var tool := RoadDrawTool.new()
	tool._net = net
	tool._facade = facade
	return tool


func is_active() -> bool:
	return step != Step.OFF


## Çizim bu bantta açık mı (metro: hayır).
static func band_allows(band: StringName) -> bool:
	return ACTIVE_BANDS.has(band) or band == &""


func activate() -> void:
	if step != Step.OFF:
		return
	_reset_draft()
	step = Step.PICK_A
	message = MSG_NONE
	changed.emit()


func deactivate() -> void:
	if step == Step.OFF:
		return
	_reset_draft()
	step = Step.OFF
	message = MSG_NONE
	changed.emit()


func set_band(band: StringName) -> void:
	var ok := band_allows(band)
	if ok != band_active:
		band_active = ok
		changed.emit()


## Dünya konumu (m) için yol yapışması: en yakın açık yol kenarı; uçlardan biri yarıçap içindeyse DÜĞÜME, değilse
## kenar üstündeki en yakın noktaya. Dönüş: {snapped: bool, pos: Vector2, kind: &"node"|&"edge"|&""}.
func snap_to_road(p: Vector2, radius_m: float) -> Dictionary:
	var best: WorldRoadEdge = null
	var best_d := INF
	for e in _net.edges_near(p.x, p.y, radius_m):
		if e.mode() != WorldNetwork.MODE_ROAD or not e.open:
			continue
		var d := NetworkGeometry.distance_point_segment(p, _net.node_pos(e.a), _net.node_pos(e.b))
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return {"snapped": false, "pos": p, "kind": &""}
	var a := _net.node_pos(best.a)
	var b := _net.node_pos(best.b)
	var da := p.distance_to(a)
	var db := p.distance_to(b)
	if minf(da, db) <= radius_m:
		return {"snapped": true, "pos": a if da <= db else b, "kind": &"node"}
	var t := NetworkGeometry.project_param(p, a, b)
	return {"snapped": true, "pos": a + (b - a) * t, "kind": &"edge"}


## İmleç hareketi (masaüstü). PICK_A: yapışma göstergesi; PICK_B: bitişi izler ve önizlemeyi sim'e doğrulatır.
func hover_at(p: Vector2, radius_m: float) -> void:
	if not band_active:
		return
	match step:
		Step.PICK_A:
			var snap := snap_to_road(p, radius_m)
			if snap["snapped"] != hover["snapped"] or (snap["pos"] as Vector2).distance_to(hover["pos"]) > 0.05:
				hover = snap
				changed.emit()
		Step.PICK_B:
			var target := _end_target(p, radius_m)
			if target.distance_to(end) >= HOVER_EPSILON_M or verdict == null:
				if target.distance_to(end) >= HOVER_EPSILON_M:
					expropriate = false
				end = target
				_revalidate()
				changed.emit()


## Birincil eylem (tıklama / dokunma-bırakma) dünya konumunda.
func tap_at(p: Vector2, radius_m: float) -> void:
	if not band_active:
		return
	match step:
		Step.PICK_A:
			var snap := snap_to_road(p, radius_m)
			if not bool(snap["snapped"]):
				message = MSG_START_NOT_ON_ROAD
				message_args = {}
				changed.emit()
				return
			start = snap["pos"]
			end = start
			verdict = null
			message = MSG_NONE
			step = Step.PICK_B
			changed.emit()
		Step.PICK_B, Step.REVIEW:
			var target := _end_target(p, radius_m)
			# Aynı noktaya (yapışma yarıçapı içinde) yeniden tıklamak/dokunmak yolu onaylar; başka bir yere tıklamak bitişi
			# değiştirir. Yalnız yapılabilir taslakta (ret varken yeniden tıklama hiçbir şey göndermez).
			# Yıkım içeren yol yeniden dokunuşla ONAYLANMAZ (kazara dokunuş bina yıkmasın): onay panelden/Enter/işaretten.
			if step == Step.REVIEW and can_confirm() and not demolishes() and target.distance_to(end) <= radius_m:
				confirm()
				return
			if target.distance_to(end) >= HOVER_EPSILON_M:
				expropriate = false
			end = target
			_revalidate()
			step = Step.REVIEW
			changed.emit()


## İptal: taslak varsa PICK_A'ya döner (true = bu çağrı bir şey iptal etti); PICK_A'da false (çağıran aracı kapatır).
func cancel() -> bool:
	match step:
		Step.PICK_B, Step.REVIEW:
			_reset_draft()
			step = Step.PICK_A
			message = MSG_NONE
			changed.emit()
			return true
		Step.SENDING:
			return true  # kuyruktaki komut geri çekilemez; Esc yutulur
	return false


func can_confirm() -> bool:
	return step == Step.REVIEW and band_active and verdict != null and not verdict.is_rejected()


## Onay: komutu YALNIZ `submit_command` ile gönderir. Dönüş: sim sonucu (ret ise anahtarıyla; durum REVIEW kalır).
func confirm() -> CommandResult:
	if not can_confirm():
		return null
	var result := _facade.submit_command(_command())
	if result.is_rejected():
		message = MSG_FAILED
		message_args = {"reason_key": result.reason_key, "args": result.args}
		verdict = result
		_verdict_key = ""  # sonraki dokunuş taslağı sim'e yeniden sordurur
		changed.emit()
		return result
	sending_command_id = result.command_id
	step = Step.SENDING
	message = MSG_NONE
	changed.emit()
	return result


## T-042b · Sim'in kamulaştırma teklifi: taslak `crosses_parcels` ile reddedildiyse ve ret args'ı alınacak arsa sayısını
## (sim hesabı) taşıyorsa o args; teklif yoksa (kamulaştırma kapalı / korunan yapı / başka ret) boş.
func offer() -> Dictionary:
	if verdict == null or not verdict.is_rejected() or expropriate:
		return {}
	if verdict.reason_key != REJECT_CROSSES_PARCELS or int(verdict.args.get("taken_parcels", 0)) <= 0:
		return {}
	return verdict.args


## Teklifi kabul eder: taslak `expropriate: true` ile sim'e yeniden sordurulur (önizleme sayıları sim'den). Sonuç hâlâ
## ret ise (örn. korunan yapı) kabul düşer. Dönüş: kabul edilen taslak geçerli mi.
func accept_offer() -> bool:
	if offer().is_empty() or step != Step.REVIEW:
		return false
	expropriate = true
	_verdict_key = ""
	_revalidate()
	if not is_valid():
		expropriate = false
	changed.emit()
	return is_valid()


## Kabul edilen teklifi geri çeker (taslak kamulaştırmasız yeniden sorulur; teklif tekrar görünür).
func withdraw_offer() -> void:
	if not expropriate:
		return
	expropriate = false
	_verdict_key = ""
	_revalidate()
	changed.emit()


## Geçerli taslak yıkım/yerinden edilme/proje kaybı içeriyor mu (sim önizlemesi)? Onay metni ve tek-dokunuş onayı
## buna bağlı.
func demolishes() -> bool:
	return expropriate and is_valid() and ExpropriationText.demolishes(verdict.args)


## Son yol kamulaştırmalı mı (sim `public_works()` kaydı)? Geri alma onayı buna bağlı.
func last_road() -> PublicWorkView:
	var works := _facade.public_works()
	return works[works.size() - 1] if not works.is_empty() else null


## Son oyuncu yolunu geri alma komutu (LIFO). Dönüş: sim sonucu.
func undo_last() -> CommandResult:
	var result := _facade.submit_command(SimCommand.public_work_undo_last())
	if result.is_rejected():
		message = MSG_FAILED
		message_args = {"reason_key": result.reason_key, "args": result.args}
	else:
		message = MSG_UNDONE
		message_args = {}
	changed.emit()
	return result


func has_undoable_road() -> bool:
	return not _facade.public_works().is_empty()


## Sim olayları: gönderilen komutun sonucu. `public_work.built` -> yeni yol için PICK_A; `command.rejected` -> REVIEW.
func on_events(events: Array[SimEvent]) -> void:
	for e in events:
		if step == Step.SENDING and e.command_id == sending_command_id:
			if e.kind == SimEvent.KIND_PUBLIC_WORK_BUILT:
				_reset_draft()
				step = Step.PICK_A
				message = MSG_DONE
				message_args = {}
				changed.emit()
			elif e.kind == SimEvent.KIND_COMMAND_REJECTED:
				if e.message_key == REJECT_EXPROPRIATION_CHANGED:
					expropriate = false  # etki onay anında değişti: teklif yeni sayılarla yeniden gösterilir
				_verdict_key = ""
				step = Step.REVIEW
				message = MSG_FAILED
				message_args = {"reason_key": e.message_key, "args": e.args}
				sending_command_id = SimContract.NO_ID
				_revalidate()
				changed.emit()
		elif e.kind == SimEvent.KIND_PUBLIC_WORK_REMOVED:
			changed.emit()  # geri alma: panelin "geri alınabilir yol" durumu değişir


## Ağ başka bir yoldan değiştiyse (ya da geri alma) açık taslağı yeniden doğrular.
func refresh_if_graph_changed() -> void:
	if (step == Step.PICK_B or step == Step.REVIEW) and _net.graph_version != _verdict_version:
		_revalidate()
		changed.emit()


func points_cm() -> PackedInt64Array:
	var out := PackedInt64Array()
	for p in [start, end]:
		out.append(roundi((p as Vector2).x * 100.0))
		out.append(roundi((p as Vector2).y * 100.0))
	return out


func length_m() -> float:
	return start.distance_to(end)


## Taslak geçerli mi (sim kuru koşu)? Taslak yoksa false.
func is_valid() -> bool:
	return verdict != null and not verdict.is_rejected()


## Sim'in önizleme argümanları (geçerliyse `length_m, regions {kod: birim}, units_total, cost_*`).
func preview_args() -> Dictionary:
	return verdict.args if is_valid() else {}


func _end_target(p: Vector2, radius_m: float) -> Vector2:
	var snap := snap_to_road(p, radius_m)
	return snap["pos"] if bool(snap["snapped"]) else p


func _command() -> SimCommand:
	return SimCommand.public_work_road(points_cm(), ROAD_CLASS, expropriate)


func _revalidate() -> void:
	var cmd := _command()
	var key := "%s|%s" % [str(cmd.params["points_cm"]), expropriate]
	if key == _verdict_key and _net.graph_version == _verdict_version and verdict != null:
		return
	verdict = _facade.validate_command(cmd)
	_verdict_key = key
	_verdict_version = _net.graph_version


func _reset_draft() -> void:
	start = Vector2.ZERO
	end = Vector2.ZERO
	verdict = null
	expropriate = false
	_verdict_key = ""
	_verdict_version = -1
	sending_command_id = SimContract.NO_ID
	hover = {"snapped": false, "pos": Vector2.ZERO, "kind": &""}
