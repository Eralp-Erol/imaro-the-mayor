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
##
## T-076 hazırlık (format 2): bellek + uzun oturum (ısıl) ölçümü, hepsi aynı bayrağın arkasında (bayrak yoksa
## düğüm yok):
##   bellek       her `--perf-log` oturumunda; `--perf-log-mem-every=N` karede bir örnek (varsayılan 120). Kalemler:
##                Godot statik bellek (+ tepe), video/doku/tampon belleği, düğüm/nesne sayısı, `OS.get_memory_info()`.
##                UYARI: statik bellek sayacı release şablonunda 0 dönebilir [doğrulanmadı]; o zaman `static_available`
##                false yazılır, video/düğüm sayıları geçerlidir, işlem belleği için Xcode/Instruments gerekir.
##   ısıl oturum  `--perf-log-thermal[=SN]` (varsayılan 900 sn = 15 dk; `IMARO_PERF_LOG_THERMAL=SN` ortamı da olur):
##                SN saniyelik kare süresine ulaşınca "tamam" özeti yazılır ve ölçüm donar. `--perf-log-window=SN`
##                (ısıl modda varsayılan 30 sn) aralıklı pencere örnekleri (kare süresi ort/p95/p99/maks + bellek);
##                rapora `thermal` bloğu (son 2 dk p95 / ilk 2 dk p95, sınır 1,25; ADR-0010 Karar 3) eklenir.
##                Godot'tan cihaz ısıl durumu OKUNAMAZ (API yok): ısıl kısma kare süresi kaymasından çıkarılır,
##                gerçek durum Xcode/Kontrol Merkezi'nden elle yazılır.
##   başlangıç    `startup`: motor başlangıcından logger'ın eklenmesine ve ilk işlenen kareye geçen süre (soğuk açılış
##                için; süreç başlatma/dyld süresini içermez) ve ilk 10 karenin süresi.
## Tamamlanan oturumda (`complete`) ölçüm donar: sonraki kareler eklenmez, sonraki yazımlar dosyayı değiştirmez.

const FORMAT_VERSION := 2
const DEFAULT_DIR := "user://perf/"
const ENV_NAME := "IMARO_PERF_LOG"
const FEATURE_TAG := "perf_log"
const DEFAULT_WRITE_EVERY := 3600
const DEFAULT_STABLE_AFTER_S := 30.0
const WORST_COUNT := 20
## Bellek tavanı (kare başına ~16 bayt): aşılırsa kayıt durur, rapor `truncated` işaretler.
const MAX_FRAMES := 1000000
const THERMAL_ENV_NAME := "IMARO_PERF_LOG_THERMAL"
const DEFAULT_THERMAL_SESSION_S := 900.0
const DEFAULT_THERMAL_WINDOW_S := 30.0
## Isıl karşılaştırma uçları (ADR-0010 Karar 3): ilk/son 2 dk, son p95 <= ilk p95 x 1,25.
const THERMAL_EDGE_S := 120.0
const THERMAL_LIMIT_RATIO := 1.25
const DEFAULT_MEMORY_EVERY := 120
const MEMORY_SERIES_MAX := 120
const FIRST_FRAMES_COUNT := 10
const MB := 1048576.0

## Kayıt aralıklı yazılır: iOS uygulamayı haber vermeden sonlandırabilir. 0 = aralıklı yazım yok.
var write_every: int = DEFAULT_WRITE_EVERY
var stable_after_s: float = DEFAULT_STABLE_AFTER_S
## > 0: bu karede "tamam" özeti yazılır (örn. --demo 4x6000).
var complete_at_frames: int = 0
## > 0: ölçülen kare süresi toplamı bu saniyeye ulaşınca "tamam" (ısıl oturum, örn. 900 = 15 dk).
var complete_at_s: float = 0.0
## > 0: bu kadar saniyelik kare süresinde bir pencere örneği kapanır (ısıl modda 30 sn). 0 = pencere yok.
var window_s: float = 0.0
## Bellek örneği kare aralığı (0 = otomatik örnek yok; `sample_memory()` elle çağrılabilir).
var memory_every: int = DEFAULT_MEMORY_EVERY
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
var _truncated: bool = false
var _started_unix: float = 0.0
var _mem: Array[Dictionary] = []
var _static_peak: float = 0.0
var _windows: Array[Dictionary] = []
var _win_start_idx: int = 0
var _win_start_ms: float = 0.0
var _finished: bool = false
var _ready_ticks_ms: int = -1
var _first_process_ticks_ms: int = -1


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
	logger.memory_every = _arg_int(args, "perf-log-mem-every", DEFAULT_MEMORY_EVERY)
	var thermal_s := _thermal_seconds(args)
	if thermal_s > 0.0:
		logger.complete_at_s = thermal_s
		logger.window_s = DEFAULT_THERMAL_WINDOW_S
	if args.has("perf-log-window"):
		logger.window_s = _arg_float(args, "perf-log-window", logger.window_s)
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


static func _arg_float(args: Dictionary, key: String, fallback: float) -> float:
	if not args.has(key):
		return fallback
	var text := str(args[key])
	return maxf(0.0, text.to_float()) if text.is_valid_float() else fallback


## Isıl oturum süresi (sn): `--perf-log-thermal[=SN]` ya da `IMARO_PERF_LOG_THERMAL=1|SN`; istek yoksa 0.
static func _thermal_seconds(args: Dictionary) -> float:
	var text := ""
	if args.has("perf-log-thermal"):
		text = str(args["perf-log-thermal"])
	else:
		text = OS.get_environment(THERMAL_ENV_NAME)
		if text == "":
			return 0.0
	if text.is_valid_float() and text.to_float() > 1.0:
		return text.to_float()
	return DEFAULT_THERMAL_SESSION_S


## Bellek örnekleri özeti (MB). Örnek yoksa yalnız `samples: 0` (uydurma sıfır yok). `peak_bytes`: Godot'nun bildirdiği
## statik bellek tepesi. `static_available` false = sayaç hiç sıfırdan büyük değer vermedi (release şablonu olabilir).
static func memory_summary(samples: Array, peak_bytes: float) -> Dictionary:
	var n := samples.size()
	if n == 0:
		return {"samples": 0}
	var out := {"samples": n, "static_peak_mb": snappedf(peak_bytes / MB, 0.1)}
	for key in ["static", "video", "texture", "buffer"]:
		var first: float = float(samples[0][key]) / MB
		var last: float = float(samples[n - 1][key]) / MB
		var peak := first
		for s in samples:
			peak = maxf(peak, float(s[key]) / MB)
		out[key + "_mb"] = {"first": snappedf(first, 0.1), "last": snappedf(last, 0.1), "max": snappedf(peak, 0.1),
				"growth": snappedf(last - first, 0.1)}
	for key in ["nodes", "objects"]:
		var top := 0
		for s in samples:
			top = maxi(top, int(s[key]))
		out[key] = {"first": int(samples[0][key]), "last": int(samples[n - 1][key]), "max": top}
	out["static_available"] = float(out["static_mb"]["max"]) > 0.0
	var series: Array = []
	var take := mini(n, MEMORY_SERIES_MAX)
	for k in take:
		var s: Dictionary = samples[0 if take == 1 else roundi(k * (n - 1.0) / (take - 1.0))]
		series.append({"frame": int(s["frame"]), "static_mb": snappedf(float(s["static"]) / MB, 0.1),
				"video_mb": snappedf(float(s["video"]) / MB, 0.1), "nodes": int(s["nodes"])})
	out["series"] = series
	return out


## Isıl kayma: toplam kare süresinin ilk ve son `edge_s` saniyesindeki p95 oranı. İki ucu da kapsayacak kadar uzun
## oturum yoksa `reached: false` (geçti DEĞİL; ADR-0010: 15 dk oturumda son 2 dk p95 <= ilk 2 dk p95 x 1,25).
static func thermal_summary(ms: PackedFloat32Array, edge_s: float = THERMAL_EDGE_S) -> Dictionary:
	var total := 0.0
	for v in ms:
		total += v
	var edge_ms := edge_s * 1000.0
	if total < 2.0 * edge_ms:
		return {"reached": false, "edge_s": edge_s, "session_s": snappedf(total / 1000.0, 0.1)}
	var head := 0
	var acc := 0.0
	while head < ms.size() and acc < edge_ms:
		acc += ms[head]
		head += 1
	var tail := ms.size()
	acc = 0.0
	while tail > 0 and acc < edge_ms:
		tail -= 1
		acc += ms[tail]
	var first := stats(ms.slice(0, head))
	var last := stats(ms.slice(tail))
	var ratio := snappedf(float(last["p95"]) / float(first["p95"]), 0.001) if float(first["p95"]) > 0.0 else 0.0
	return {"reached": true, "edge_s": edge_s, "session_s": snappedf(total / 1000.0, 0.1), "first": first,
			"last": last, "p95_ratio": ratio, "limit_ratio": THERMAL_LIMIT_RATIO,
			"within_limit": ratio <= THERMAL_LIMIT_RATIO and ratio > 0.0}


func _ready() -> void:
	_started_unix = Time.get_unix_time_from_system()
	_ready_ticks_ms = Time.get_ticks_msec()
	if out_path == "":
		out_path = resolve_path("")
	print("PERF_LOG on path=%s (%s)" % [out_path, ProjectSettings.globalize_path(out_path)])


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us < 0:
		_last_us = now
		if _first_process_ticks_ms < 0:
			_first_process_ticks_ms = Time.get_ticks_msec()
		return
	var dt_ms := (now - _last_us) / 1000.0
	var day := -1
	if _host != null and is_instance_valid(_host) and _host.has_method(&"perf_tick"):
		day = int(_host.call(&"perf_tick"))
	record_frame(dt_ms, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), day)
	var frames := _ms.size()
	if memory_every > 0 and (frames == 1 or frames % memory_every == 0):
		sample_memory()
	if target_reached():
		sample_memory()
		mark_complete()
		set_process(false)  # ölçüm bitti: sonraki kareler için maliyet yok
		return
	if write_every > 0 and frames % write_every == 0:
		flush("periodic")
		# Yazım süresi bir sonraki karenin süresine girmesin.
		_last_us = Time.get_ticks_usec()
	else:
		_last_us = now


## Bir karenin ölçümünü ekler (`_process` çağırır; test sentetik seriyi doğrudan besler). Tamamlanmış oturumda no-op.
func record_frame(dt_ms: float, draw_calls: float, triangles: float, day: int) -> void:
	if _finished:
		return
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
	if window_s > 0.0 and _elapsed_ms - _win_start_ms >= window_s * 1000.0 - 0.001:
		_close_window()


func frame_count() -> int:
	return _ms.size()


func windows() -> Array[Dictionary]:
	return _windows


func memory_sample_count() -> int:
	return _mem.size()


## Hedefe (kare sayısı ya da kare süresi toplamı) ulaşıldı mı. Hedef yoksa hep false.
func target_reached() -> bool:
	if complete_at_frames > 0 and _ms.size() >= complete_at_frames:
		return true
	return complete_at_s > 0.0 and _elapsed_ms >= complete_at_s * 1000.0 - 0.001


## Bellek örneği ekler (test sentetik değer verir). Alanlar: frame, static, video, texture, buffer (bayt), nodes,
## objects.
func record_memory(sample: Dictionary) -> void:
	_mem.append(sample)
	_static_peak = maxf(_static_peak, float(sample["static"]))


## Godot monitörlerinden şimdiki belleği okur ve kaydeder. Yalnız `memory_every` karede bir çağrılır (her kare değil).
func sample_memory() -> Dictionary:
	var sample := {
		"frame": _ms.size(), "static": float(OS.get_static_memory_usage()),
		"video": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"texture": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"buffer": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
	}
	record_memory(sample)
	return sample


## Oturumu bitirir: "complete" raporunu yazar ve ölçümü dondurur. Yazılamazsa hata döner; ölçüm bellekte kalır ve
## çıkış/arka plan yazımları aynı raporu yeniden dener.
func mark_complete() -> Error:
	_finished = true
	return flush("complete")


func _close_window() -> void:
	var count := _ms.size() - _win_start_idx
	var entry := {"t_s": snappedf(_elapsed_ms / 1000.0, 0.01), "frames": count,
			"frame_ms": stats(_ms.slice(_win_start_idx)), "draw_calls_mean": stats(_draws.slice(_win_start_idx))["mean"]}
	if not _mem.is_empty():
		var last_mem: Dictionary = _mem[_mem.size() - 1]
		entry["static_mb"] = snappedf(float(last_mem["static"]) / MB, 0.1)
		entry["video_mb"] = snappedf(float(last_mem["video"]) / MB, 0.1)
		entry["nodes"] = int(last_mem["nodes"])
	_windows.append(entry)
	_win_start_idx = _ms.size()
	_win_start_ms = _elapsed_ms


## Raporu şimdi yazar. `reason`: periodic | complete | exit | pause. Dönen: hata kodu (OK = yazıldı).
## Tamamlanmış oturumda dosya donuk: önceki "complete" yazımı başarılıysa sonraki çağrılar dosyaya dokunmaz.
func flush(reason: String) -> Error:
	if _ms.is_empty():
		return OK
	if _finished and reason != "complete" and last_error == OK:
		return OK
	var why := "complete" if _finished else reason
	var report := summarize(_ms, _draws, _prims, _days, _stable_start)
	report.merge(_environment_info())
	report["reason"] = why
	report["complete"] = why == "complete" or why == "exit"
	report["truncated"] = _truncated
	report["wall_s"] = snappedf(_elapsed_ms / 1000.0, 0.1)
	report["stable_after_s"] = stable_after_s
	report["session_target_s"] = complete_at_s
	report["memory"] = _memory_block()
	report["startup"] = _startup_block()
	if window_s > 0.0 or complete_at_s > 0.0:
		report["window_s"] = window_s
		report["windows"] = _windows
		report["thermal"] = thermal_summary(_ms)
	last_error = write_report(out_path, report)
	if last_error != OK and not _warned:
		_warned = true
		push_warning("PerfLogger: ölçüm dosyası yazılamadı (%s): %s. Oyun devam ediyor, ölçüm bellekte tutulur."
				% [out_path, error_string(last_error)])
	return last_error


func _memory_block() -> Dictionary:
	var block := memory_summary(_mem, maxf(_static_peak, float(OS.get_static_memory_peak_usage())))
	var info := OS.get_memory_info()
	var os_mb := {}
	for key in ["physical", "free", "available", "stack"]:
		# Godot desteklenmeyen alan için -1 verir; olduğu gibi (-1 = bilinmiyor) yazılır.
		var value := float(info.get(key, -1))
		os_mb[key] = snappedf(value / MB, 0.1) if value >= 0.0 else -1.0
	block["os_memory_mb"] = os_mb
	return block


## Soğuk açılış verisi: motor başlangıcından (Time.get_ticks_*) logger'ın eklenmesine ve ilk işlenen kareye süre, ilk
## kare süreleri. Süreç başlatma/dyld süresi YOKTUR (motor `main` sonrası); toplam açılış için dış kronometre gerekir.
func _startup_block() -> Dictionary:
	var first_ms: Array = []
	for k in mini(FIRST_FRAMES_COUNT, _ms.size()):
		first_ms.append(snappedf(_ms[k], 0.1))
	return {"logger_ready_s": snappedf(_ready_ticks_ms / 1000.0, 0.01),
			"first_process_s": snappedf(_first_process_ticks_ms / 1000.0, 0.01),
			"first_frames_ms": first_ms}


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
		"args": OS.get_cmdline_user_args(), "cmdline_args": OS.get_cmdline_args(),
		"started_unix": snappedf(_started_unix, 1.0), "path": out_path,
		"template_build": OS.has_feature("template"), "editor_build": OS.has_feature("editor"),
	}


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			flush("pause")
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			# Arka planda geçen süre bir "kare" sayılmasın: sonraki işlenen kare yeni taban olur.
			_last_us = -1
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_EXIT_TREE:
			flush("exit")
