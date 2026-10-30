class_name ViewWarmup
extends CanvasLayer
## Açılış ısınması (görünüm tarafı; sim durumuna dokunmaz): oyuncu girdi vermeden önce kamerayı zarftaki dar
## bantlarda (başlangıç, sokak, mahalle, ilçe) kısa süre gezdirir ve geri koyar; her bantta ilk kez çizilen mesh
## yükleme, shader/pipeline varyantı ve gölge geçişi bu sırada, opak bir "hazırlanıyor" örtüsü ALTINDA olur.
## Ölçüm (production/log/2026-10-29-demo-kare-suresi.md ve godot-engineer raporu): ısıtmasız ilk core -> sokak 60 m
## geçişi 388-925 ms (makine yüküne göre), tamamı RenderingServer çizim aşamasında (betik ~12-25 ms); ikinci ziyaret
## 22 ms.
## Aynı dünya, aynı veri (WLD-01): yalnız kamera durumu geçici değişir, `CameraRig.pose_snapshot/restore_pose` ile
## birebir geri yüklenir. Sim'e komut/yazma yok; sim sürmesi çağıranın kararıdır.

signal finished

## Örtü katmanı (HUD katmanının üstünde).
const COVER_LAYER := 100
## Her pozda en az bu kadar kare beklenir (ilk kare yeni pozu çizer, sonrakiler kuyruğa alınan işi).
const HOLD_FRAMES := 3
## Bekleyen görünüm işi (örn. bitki hücreleri) varsa en fazla bu kadar kare daha beklenir.
const MAX_HOLD_FRAMES := 12
## Başlangıç poz'unun kendisi de ısıtılır; ardından bu mesafe çarpanları kullanılır: sokak bandında zarfın en
## yakın uzaklığı x STREET_FACTOR, diğer dar bantlarda bant sınırlarının geometrik ortası.
const STREET_FACTOR := 1.2
## Poz eğimleri (derece; zarf/K1 gerekirse dikleştirir). Sokak: CameraPresets.STREET_PITCH_DEG ile aynı.
const STREET_PITCH_DEG := 12.0
const WIDE_PITCH_DEG := 35.0
const COVER_COLOR := Color(0.07, 0.08, 0.10)
const COVER_TEXT := "Şehir hazırlanıyor…"

var poses_done: int = 0
var frames_held_total: int = 0
var duration_ms: float = 0.0

var _rig: CameraRig = null
var _poses: Array[CameraState] = []
var _snapshot: Dictionary = {}
var _idx: int = -1
var _held: int = 0
var _busy: Callable = Callable()
var _active: bool = false
var _t_begin_us: int = 0


## Saf: başlangıç durumundan ısınma poz listesi: [başlangıç] + her dar bant (metro hariç, yakından uzağa). Bitişte
## başlangıç pozu `restore_pose` ile geri yüklenir (ayrı bir son poz beklenmez). Odak ve yön başlangıçtan gelir (aynı
## dünya noktası); yalnız uzaklık/eğim bantlara göre. Zarf çözümü burada uygulanmaz (rig `apply_state` yapar).
static func plan(envelope: CameraEnvelope, start: CameraState) -> Array[CameraState]:
	var out: Array[CameraState] = [start.copy()]
	if envelope == null or envelope.bands.size() < 2:
		return out
	for n in range(envelope.bands.size() - 1):
		var b: Dictionary = envelope.bands[n]
		var lo := float(b["min_m"])
		var hi := float(b["max_m"])
		var s := start.copy()
		if n == 0:
			s.distance = maxf(envelope.d_min_m, lo) * STREET_FACTOR
			s.pitch_deg = STREET_PITCH_DEG
		else:
			s.distance = sqrt(lo * hi)
			s.pitch_deg = WIDE_PITCH_DEG
		out.append(s)
	return out


func is_active() -> bool:
	return _active


## Isınmayı başlatır. `busy`: hâlâ bekleyen görünüm işi var mı (`func() -> bool`); boş ise yalnız HOLD_FRAMES.
func begin(rig: CameraRig, busy: Callable = Callable()) -> void:
	if rig == null or _active:
		return
	_rig = rig
	_busy = busy
	_snapshot = rig.pose_snapshot()
	_poses = plan(rig.envelope, rig.current_state())
	_build_cover()
	rig.set_process_unhandled_input(false)
	_idx = -1
	_held = 0
	poses_done = 0
	frames_held_total = 0
	_t_begin_us = Time.get_ticks_usec()
	_active = true
	set_process(true)
	_next_pose()


func _process(_delta: float) -> void:
	if not _active:
		return
	_held += 1
	frames_held_total += 1
	if _held < HOLD_FRAMES:
		return
	if _held < MAX_HOLD_FRAMES and _busy.is_valid() and bool(_busy.call()):
		return
	poses_done += 1
	_next_pose()


func _next_pose() -> void:
	_idx += 1
	_held = 0
	if _idx >= _poses.size():
		_finish()
		return
	_rig.apply_state(_poses[_idx], true)


func _finish() -> void:
	_active = false
	set_process(false)
	if is_instance_valid(_rig):
		_rig.restore_pose(_snapshot)
		_rig.set_process_unhandled_input(true)
	duration_ms = snappedf((Time.get_ticks_usec() - _t_begin_us) / 1000.0, 0.1)
	finished.emit()
	queue_free()


func _build_cover() -> void:
	layer = COVER_LAYER
	var rect := ColorRect.new()
	rect.name = "Cover"
	rect.color = COVER_COLOR
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(rect)
	var label := Label.new()
	label.name = "CoverText"
	label.text = COVER_TEXT
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.add_child(label)
