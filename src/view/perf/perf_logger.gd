class_name PerfLogger
extends Node
## T-076: cihazda (iPad) ve masaüstünde çalışan küçük kare ölçümü. Kare süresini (duvar saati, ardışık `_process`
## çağrıları arası), çizim çağrısı ve üçgen sayısını kaydeder; özeti (ort, p50, p95, p99, en kötü, en kötü 20 kare)
## `user://` altına JSON olarak yazar. Yalnız istenince eklenir; kapalıyken düğüm HİÇ oluşturulmaz (sıfır maliyet).
##
## Açma yolları (hiçbiri yoksa `attach_if_requested` null döner ve hiçbir şey değişmez):
##   --perf-log                komut satırı (iPad: `devicectl device process launch ... --perf-log`)
##   --perf-log=<ad|yol>       aynı + dosya adı/yolu (göreli ad `user://perf/` altına;
##                             `user://` ya da `/` ile başlayan olduğu gibi)
##   IMARO_PERF_LOG=1|<ad>     ortam değişkeni (iPad: çağıran ortamda `DEVICECTL_CHILD_IMARO_PERF_LOG=1`)
##   özellik etiketi `perf_log`  dışa aktarma ön ayarında özel özellik
## Diğer: --perf-log-frames=N (N karede "tamam" özeti yazılır, oturum sürer), --perf-log-every=N (aralıklı yazım,
## varsayılan 3600 kare), --perf-log-stable=SN (kararlı evre başlangıcı, varsayılan 30 sn; ADR-0010 Karar 1).
## Dosya yazılamazsa oyun çökmez: neden `push_warning` ile bir kez düşer (`last_error` da tutulur).
## Sim'e dokunmaz: yalnız görünüm tarafı saatini ve ev sahibinin salt okunur `perf_tick()` değerini (sim günü) okur.
## Not: ilk kare (düğüm eklendiği andan ilk `_process`'e kadar kurulum) ölçülmez; taban o andan alınır.

const FORMAT_VERSION := 1
const DEFAULT_DIR := "user://perf/"
const ENV_NAME := "IMARO_PERF_LOG"
const FEATURE_TAG := "perf_log"
const DEFAULT_WRITE_EVERY := 3600
const DEFAULT_STABLE_AFTER_S := 30.0
const WORST_COUNT := 20
## Bellek tavanı (kare başına ~16 bayt): aşılırsa kayıt durur, rapor `truncated` işaretler.
const MAX_FRAMES := 1000000

## Kayıt aralıklı yazılır: iOS uygulamayı haber vermeden sonlandırabilir. 0 = aralıklı yazım yok.
var write_every: int = DEFAULT_WRITE_EVERY
var stable_after_s: float = DEFAULT_STABLE_AFTER_S
## > 0: bu karede "tamam" özeti yazılır (örn. --demo 4x6000).
var complete_at_frames: int = 0
var out_path: String = ""
## Son yazım denemesinin hatası (OK = sorun yok). Test ve tanı için.
var last_error: Error = OK

var _ms: PackedFloat32Array = PackedFloat32Array()
var _draws: PackedFloat32Array = PackedFloat32Array()
var _prims: PackedFloat32Array = PackedFloat32Array()
var _days: PackedInt32Array = PackedInt32Array()
var _host: Node = null
var _last_us: int = -1
var _elapsed_ms: float = 0.0
var _stable_start: int = -1
var _warned: bool = false
var _complete_written: bool = false
var _truncated: bool = false
var _started_unix: float = 0.0


## İstek var mı? `args`: world_preview'in ayrıştırdığı `--anahtar[=değer]` sözlüğü.
static func requested(args: Dictionary) -> bool:
	return args.has("perf-log") or OS.get_environment(ENV_NAME) != "" or OS.has_feature(FEATURE_TAG)


## İstenmişse düğümü `host` altına ekler ve döner; istenmemişse null (hiçbir düğüm/izleyici oluşmaz).
static func attach_if_requested(host: Node, args: Dictionary) -> PerfLogger:
	if host == null or not requested(args):
		return null
	var logger := PerfLogger.new()
	logger.name = "PerfLogger"
	logger.process_mode = Node.PROCESS_MODE_ALWAYS
	var value := ""
	if args.has("perf-log") and args["perf-log"] is String:
		value = String(args["perf-log"])
	if value == "":
		var env := OS.get_environment(ENV_NAME)
		value = "" if env in ["", "1", "true"] else env
	logger.out_path = resolve_path(value)
	logger.write_every = _arg_int(args, "perf-log-every", DEFAULT_WRITE_EVERY)
	logger.complete_at_frames = _arg_int(args, "perf-log-frames", 0)
	logger.stable_after_s = float(str(args.get("perf-log-stable", DEFAULT_STABLE_AFTER_S)))
	logger._host = host
	host.add_child(logger)
	return logger


## Boş: `user://perf/perf-log-<tarih>.json`; `user://` ya da `/` ile başlayan: olduğu gibi; başka: `user://perf/<ad>`.
static func resolve_path(value: String) -> String:
	if value == "":
		var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
		return DEFAULT_DIR + "perf-log-%s.json" % stamp
	if value.begins_with("user://") or value.begins_with("/"):
		return value
	return DEFAULT_DIR + value


## Dizi istatistiği (en yakın sıra yüzdeliği; tools/godot/perf_probe.gd ile aynı tanım, masaüstü serisiyle
## karşılaştırılabilir).
static func stats(values: PackedFloat32Array) -> Dictionary:
	var n := values.size()
	if n == 0:
		return {"count": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in values:
		total += v
	return {
		"count": n, "mean": snappedf(total / n, 0.01), "p50": snappedf(sorted[n / 2], 0.01),
		"p95": snappedf(sorted[mini(n - 1, int(ceil(n * 0.95)) - 1)], 0.01),
		"p99": snappedf(sorted[mini(n - 1, int(ceil(n * 0.99)) - 1)], 0.01),
		"max": snappedf(sorted[n - 1], 0.01), "min": snappedf(sorted[0], 0.01),
	}


## En yavaş `count` kare (azalan süre; eşitlikte önce gelen kare). Sıralama yalnız aday küme üzerinde (24 bin kareyi
## Callable ile sıralamak yüzlerce ms tutardı).
static func worst_frames(ms: PackedFloat32Array, draws: PackedFloat32Array, prims: PackedFloat32Array,
		days: PackedInt32Array, count: int = WORST_COUNT) -> Array:
	var n := ms.size()
	if n == 0 or count <= 0:
		return []
	var sorted := ms.duplicate()
	sorted.sort()
	var threshold: float = sorted[maxi(0, n - count)]
	var picked: Array = []
	for k in n:
		if ms[k] >= threshold:
			picked.append([ms[k], k])
	picked.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array = []
	for item in picked.slice(0, count):
		var k: int = item[1]
		out.append({"frame": k + 1, "ms": snappedf(ms[k], 0.01), "day": days[k] if k < days.size() else -1,
				"draw_calls": int(draws[k]) if k < draws.size() else -1,
				"triangles": int(prims[k]) if k < prims.size() else -1})
	return out


## Rapor sözlüğü (saf: oyun düğümüne bağlı değil; test bunu doğrudan çağırır). Günler: kare başına sim günü,
## -1 = bilinmiyor. "Tick'li kare": gün bir önceki kareden farklı olan kare (perf_probe `tick_correlation` gibi).
static func summarize(ms: PackedFloat32Array, draws: PackedFloat32Array, prims: PackedFloat32Array,
		days: PackedInt32Array, stable_start: int = -1) -> Dictionary:
	var tick_ms := PackedFloat32Array()
	var idle_ms := PackedFloat32Array()
	var over_33 := 0
	var over_50 := 0
	var over_100 := 0
	for k in ms.size():
		var ticked := k > 0 and k < days.size() and days[k] >= 0 and days[k - 1] >= 0 and days[k] != days[k - 1]
		if ticked:
			tick_ms.append(ms[k])
		else:
			idle_ms.append(ms[k])
		over_33 += 1 if ms[k] > 33.3 else 0
		over_50 += 1 if ms[k] > 50.0 else 0
		over_100 += 1 if ms[k] > 100.0 else 0
	var peak_frame := 0
	for k in prims.size():
		if prims[k] > prims[peak_frame]:
			peak_frame = k
	var report := {
		"frames": ms.size(), "frame_ms": stats(ms),
		"tick_frame_ms": stats(tick_ms), "non_tick_frame_ms": stats(idle_ms),
		"frames_over_33ms": over_33, "frames_over_50ms": over_50, "frames_over_100ms": over_100,
		"draw_calls": stats(draws), "triangles": stats(prims),
		"triangle_peak_frame": peak_frame + 1 if prims.size() > 0 else 0,
		"worst_frames": worst_frames(ms, draws, prims, days),
	}
	if stable_start >= 0 and stable_start < ms.size():
		report["stable"] = {"from_frame": stable_start + 1, "frame_ms": stats(ms.slice(stable_start)),
				"draw_calls": stats(draws.slice(stable_start)), "triangles": stats(prims.slice(stable_start))}
	else:
		report["stable"] = {"reached": false}
	return report


## JSON'u yazar. Çökmez; hata kodunu döner (OK = yazıldı): dizin açılamadı / dosya açılamadı / yazım hatası.
static func write_report(path: String, report: Dictionary) -> Error:
	var dir_abs := ProjectSettings.globalize_path(path.get_base_dir())
	if not DirAccess.dir_exists_absolute(dir_abs):
		var dir_err := DirAccess.make_dir_recursive_absolute(dir_abs)
		if dir_err != OK:
			return dir_err
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(report, "\t"))
	var err := file.get_error()
	file.close()
	return err


static func _arg_int(args: Dictionary, key: String, fallback: int) -> int:
	if not args.has(key):
		return fallback
	var text := str(args[key])
	return maxi(0, int(text)) if text.is_valid_int() else fallback


func _ready() -> void:
	_started_unix = Time.get_unix_time_from_system()
	if out_path == "":
		out_path = resolve_path("")
	print("PERF_LOG on path=%s (%s)" % [out_path, ProjectSettings.globalize_path(out_path)])


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us < 0:
		_last_us = now
		return
	var dt_ms := (now - _last_us) / 1000.0
	var day := -1
	if _host != null and is_instance_valid(_host) and _host.has_method(&"perf_tick"):
		day = int(_host.call(&"perf_tick"))
	record_frame(dt_ms, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), day)
	var frames := _ms.size()
	var done := complete_at_frames > 0 and frames >= complete_at_frames and not _complete_written
	if done or (write_every > 0 and frames % write_every == 0):
		_complete_written = _complete_written or done
		flush("complete" if done else "periodic")
		# Yazım süresi bir sonraki karenin süresine girmesin.
		_last_us = Time.get_ticks_usec()
	else:
		_last_us = now


## Bir karenin ölçümünü ekler (`_process` çağırır; test sentetik seriyi doğrudan besler).
func record_frame(dt_ms: float, draw_calls: float, triangles: float, day: int) -> void:
	if _ms.size() >= MAX_FRAMES:
		_truncated = true
		return
	_ms.append(dt_ms)
	_draws.append(draw_calls)
	_prims.append(triangles)
	_days.append(day)
	_elapsed_ms += dt_ms
	if _stable_start < 0 and _elapsed_ms >= stable_after_s * 1000.0:
		_stable_start = _ms.size()


func frame_count() -> int:
	return _ms.size()


## Raporu şimdi yazar. `reason`: periodic | complete | exit | pause. Dönen: hata kodu (OK = yazıldı).
func flush(reason: String) -> Error:
	if _ms.is_empty():
		return OK
	var report := summarize(_ms, _draws, _prims, _days, _stable_start)
	report.merge(_environment_info())
	report["reason"] = reason
	report["complete"] = reason == "complete" or reason == "exit"
	report["truncated"] = _truncated
	report["wall_s"] = snappedf(_elapsed_ms / 1000.0, 0.1)
	report["stable_after_s"] = stable_after_s
	last_error = write_report(out_path, report)
	if last_error != OK and not _warned:
		_warned = true
		push_warning("PerfLogger: ölçüm dosyası yazılamadı (%s): %s. Oyun devam ediyor, ölçüm bellekte tutulur."
				% [out_path, error_string(last_error)])
	return last_error


func _environment_info() -> Dictionary:
	var method := String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	var window_size := Vector2i.ZERO
	if is_inside_tree():
		window_size = get_window().size
	return {
		"format": FORMAT_VERSION, "kind": "imaro_perf_log",
		"os": OS.get_name(), "os_version": OS.get_version(), "model": OS.get_model_name(),
		"godot": String(Engine.get_version_info()["string"]), "debug_build": OS.is_debug_build(),
		"app_version": String(ProjectSettings.get_setting("application/config/version", "")),
		"renderer": {"method": method, "driver": RenderingServer.get_current_rendering_driver_name(),
				"adapter": RenderingServer.get_video_adapter_name()},
		"refresh_hz": snappedf(DisplayServer.screen_get_refresh_rate(), 0.1),
		"window": [window_size.x, window_size.y],
		"args": OS.get_cmdline_user_args(), "started_unix": snappedf(_started_unix, 1.0),
		"path": out_path,
	}


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			flush("pause")
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_EXIT_TREE:
			flush("exit")
