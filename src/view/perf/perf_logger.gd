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
##   VSync        `--perf-log-novsync`: VSync kapatılır (iOS yok sayabilir); rapor `vsync_mode` (0 = kapalı, 1 = açık)
##                ve `refresh_hz` alanlarını geri okuyarak yazar.
##   başlangıç    `startup`: motor başlangıcından logger'ın eklenmesine ve ilk işlenen kareye geçen süre (soğuk açılış
##                için; süreç başlatma/dyld süresini içermez) ve ilk 10 karenin süresi.
##   CPU meşgul   `busy_ms` (ADR-0010 Karar 3a): her karede, o karenin İLK `physics_frame`/`process_frame` sinyalinden
##                `RenderingServer.frame_post_draw`a geçen süre; VSync/kare tavanı bekleme dışarıda KALMALIDIR [masaüstü
##                kalibrasyonuyla doğrulanır: production/log/2026-11-06-busy-ms-kalibrasyon.md]. Döküm: `pre_draw_ms`
##                (kare başı -> `frame_pre_draw`: fizik + işlem + betik) ve `render_cpu_ms` (kök viewport
##                `viewport_get_measured_render_time_cpu` + `get_frame_setup_time_cpu`; önceki çizilen kare). Rapor:
##                üst düzey `busy_ms`/`pre_draw_ms`/`render_cpu_ms` (tüm oturum), `stable.*` (kararlı evre) ve
##                `utilization` = Σbusy / Σkare süresi (-1 = bilinmiyor). Ölçülemeyen kare (-1) özetlere girmez.
##                `busy_ms` karesi k, k'nın kendi kare süresiyle eşlenir (fizik adımları kare başında olduğundan nadiren
##                busy > kare süresi olabilir: `busy_over_frame` sayar). Yalnız bayrakla bağlanır; oturum bitince
##                sinyaller çözülür. Sinyal bağlantısı ve `viewport_set_measure_render_time` yalnız `_ready`de.
##   yenileme hz  `refresh_hz_start` + pencere başına `refresh_hz`; koşu içinde değişirse `refresh_hz_changed=true`.
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
## true: `_ready`de VSync kapatılır, kare tavanı kalkar (`--perf-log-novsync`; masaüstü perf_probe koşulu).
## Platform yok sayabilir (iOS): rapordaki `vsync_mode` GERİ OKUNAN değerdir.
var novsync: bool = false
var out_path: String = ""
## Son yazım denemesinin hatası (OK = sorun yok). Test ve tanı için.
var last_error: Error = OK

var _ms: PackedFloat32Array = PackedFloat32Array()
var _draws: PackedFloat32Array = PackedFloat32Array()
var _prims: PackedFloat32Array = PackedFloat32Array()
var _days: PackedInt32Array = PackedInt32Array()
var _busy: PackedFloat32Array = PackedFloat32Array()
var _pre_draw: PackedFloat32Array = PackedFloat32Array()
var _render_cpu: PackedFloat32Array = PackedFloat32Array()
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
## Kare başına meşgul süre ölçümü (yalnız `_ready`de bağlanır). `_cycle_open`: bu karenin başlangıç sinyali görüldü.
var _cycle_open: bool = false
var _cycle_start_us: int = 0
var _cycle_pre_us: int = -1
var _busy_done: float = -1.0
var _pre_done: float = -1.0
var _discard_cycle: bool = false
var _signals_connected: bool = false
var _viewport_rid: RID = RID()
var _refresh_start: float = -1.0
var _refresh_now: float = -1.0
var _refresh_changed: bool = false
var _refresh_seen: Array[float] = []


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
	logger.novsync = args.has("perf-log-novsync")
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


## Ölçülemeyen (< 0) değerleri atar (busy/pre_draw/render_cpu: -1 = bilinmiyor).
static func valid_only(values: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for v in values:
		if v >= 0.0:
			out.append(v)
	return out


## `from`dan sonrası; dizi daha kısaysa (eski çağıranlar busy vermez) boş.
static func _tail(values: PackedFloat32Array, from: int) -> PackedFloat32Array:
	return values.slice(from) if from < values.size() else PackedFloat32Array()


## Kullanım = Σbusy / Σkare süresi, yalnız busy'si ölçülmüş karelerde. Ölçülmüş kare yoksa -1.
static func utilization(busy: PackedFloat32Array, ms: PackedFloat32Array) -> float:
	var sum_busy := 0.0
	var sum_ms := 0.0
	for k in mini(busy.size(), ms.size()):
		if busy[k] >= 0.0:
			sum_busy += busy[k]
			sum_ms += ms[k]
	return snappedf(sum_busy / sum_ms, 0.001) if sum_ms > 0.0 else -1.0


## busy'si kare süresini aşan kare sayısı (fizik adımı kare başında olduğundan eşleme payı: 0,05 ms hoşgörü).
static func busy_over_frame(busy: PackedFloat32Array, ms: PackedFloat32Array) -> int:
	var count := 0
	for k in mini(busy.size(), ms.size()):
		if busy[k] >= 0.0 and busy[k] > ms[k] + 0.05:
			count += 1
	return count


## busy/pre_draw/render_cpu özet alanları (`prefix` yok: aynı anahtarlar üst düzeyde ve `stable` içinde).
static func busy_block(busy: PackedFloat32Array, pre_draw: PackedFloat32Array, render_cpu: PackedFloat32Array,
		ms: PackedFloat32Array) -> Dictionary:
	return {"busy_ms": stats(valid_only(busy)), "pre_draw_ms": stats(valid_only(pre_draw)),
			"render_cpu_ms": stats(valid_only(render_cpu)), "utilization": utilization(busy, ms)}


## Rapor sözlüğü (saf: oyun düğümüne bağlı değil; test bunu doğrudan çağırır). Günler: kare başına sim günü,
## -1 = bilinmiyor. "Tick'li kare": gün bir önceki kareden farklı olan kare (perf_probe `tick_correlation` gibi).
## `busy`/`pre_draw`/`render_cpu` (isteğe bağlı, kare başına, -1 = ölçülemedi) üst düzeye ve `stable` içine
## `busy_ms`, `pre_draw_ms`, `render_cpu_ms`, `utilization` ekler.
static func summarize(ms: PackedFloat32Array, draws: PackedFloat32Array, prims: PackedFloat32Array,
		days: PackedInt32Array, stable_start: int = -1, busy: PackedFloat32Array = PackedFloat32Array(),
		pre_draw: PackedFloat32Array = PackedFloat32Array(),
		render_cpu: PackedFloat32Array = PackedFloat32Array()) -> Dictionary:
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
	report.merge(busy_block(busy, pre_draw, render_cpu, ms))
	report["busy_over_frame"] = busy_over_frame(busy, ms)
	if stable_start >= 0 and stable_start < ms.size():
		var stable := {"from_frame": stable_start + 1, "frame_ms": stats(ms.slice(stable_start)),
				"draw_calls": stats(draws.slice(stable_start)), "triangles": stats(prims.slice(stable_start))}
		stable.merge(busy_block(_tail(busy, stable_start), _tail(pre_draw, stable_start),
				_tail(render_cpu, stable_start), ms.slice(stable_start)))
		report["stable"] = stable
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
## `busy` (kare başına, ms ile aynı uzunlukta) verilirse aynı uçlar için `busy_ms` p95 oranı da yazılır (ADR-0010 Karar
## 3a: ısıl kapı busy p95'e bağlanır); `busy_reached` false = uçlarda ölçülmüş busy yok.
static func thermal_summary(ms: PackedFloat32Array, edge_s: float = THERMAL_EDGE_S,
		busy: PackedFloat32Array = PackedFloat32Array()) -> Dictionary:
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
	var out := {"reached": true, "edge_s": edge_s, "session_s": snappedf(total / 1000.0, 0.1), "first": first,
			"last": last, "p95_ratio": ratio, "limit_ratio": THERMAL_LIMIT_RATIO,
			"within_limit": ratio <= THERMAL_LIMIT_RATIO and ratio > 0.0}
	if busy.size() == ms.size():
		var busy_first := stats(valid_only(busy.slice(0, head)))
		var busy_last := stats(valid_only(busy.slice(tail)))
		var have := int(busy_first["count"]) > 0 and int(busy_last["count"]) > 0 and float(busy_first["p95"]) > 0.0
		out["busy_reached"] = have
		if have:
			var busy_ratio := snappedf(float(busy_last["p95"]) / float(busy_first["p95"]), 0.001)
			out["busy_first_p95"] = busy_first["p95"]
			out["busy_last_p95"] = busy_last["p95"]
			out["busy_p95_ratio"] = busy_ratio
			out["busy_within_limit"] = busy_ratio <= THERMAL_LIMIT_RATIO
	return out


func _ready() -> void:
	_started_unix = Time.get_unix_time_from_system()
	_ready_ticks_ms = Time.get_ticks_msec()
	if novsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	if out_path == "":
		out_path = resolve_path("")
	_connect_busy_signals()
	note_refresh_hz(DisplayServer.screen_get_refresh_rate())
	print("PERF_LOG on path=%s (%s)" % [out_path, ProjectSettings.globalize_path(out_path)])


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us < 0:
		_last_us = now
		_busy_done = -1.0  # taban karesi: önceki döngünün meşgul süresi bu ölçüme ait değil
		_pre_done = -1.0
		if _first_process_ticks_ms < 0:
			_first_process_ticks_ms = Time.get_ticks_msec()
		return
	var dt_ms := (now - _last_us) / 1000.0
	var day := -1
	if _host != null and is_instance_valid(_host) and _host.has_method(&"perf_tick"):
		day = int(_host.call(&"perf_tick"))
	var busy := _busy_done
	var pre_draw := _pre_done
	var render_cpu := -1.0
	if busy >= 0.0 and _viewport_rid.is_valid():
		render_cpu = (RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid)
				+ RenderingServer.get_frame_setup_time_cpu())
	_busy_done = -1.0
	_pre_done = -1.0
	record_frame(dt_ms, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), day, busy, pre_draw, render_cpu)
	var frames := _ms.size()
	if memory_every > 0 and (frames == 1 or frames % memory_every == 0):
		sample_memory()
		note_refresh_hz(DisplayServer.screen_get_refresh_rate())
	if target_reached():
		sample_memory()
		mark_complete()
		set_process(false)  # ölçüm bitti: sonraki kareler için maliyet yok
		return
	if write_every > 0 and frames % write_every == 0:
		flush("periodic")
		# Yazım süresi bir sonraki karenin süresine girmesin; bu döngünün meşgul süresi yazımı içerir, atılır.
		_last_us = Time.get_ticks_usec()
		_discard_cycle = true
	else:
		_last_us = now


## Bir karenin ölçümünü ekler (`_process` çağırır; test sentetik seriyi doğrudan besler). Tamamlanmış oturumda no-op.
## `busy_ms`/`pre_draw_ms`/`render_cpu_ms`: -1 = ölçülemedi (özetlere girmez).
func record_frame(dt_ms: float, draw_calls: float, triangles: float, day: int, busy_ms: float = -1.0,
		pre_draw_ms: float = -1.0, render_cpu_ms: float = -1.0) -> void:
	if _finished:
		return
	if _ms.size() >= MAX_FRAMES:
		_truncated = true
		return
	_ms.append(dt_ms)
	_draws.append(draw_calls)
	_prims.append(triangles)
	_days.append(day)
	_busy.append(busy_ms)
	_pre_draw.append(pre_draw_ms)
	_render_cpu.append(render_cpu_ms)
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
	_disconnect_busy_signals()  # ölçüm donar: kare başına sinyal maliyeti de biter
	return flush("complete")


func _close_window() -> void:
	var count := _ms.size() - _win_start_idx
	var win_busy := stats(valid_only(_tail(_busy, _win_start_idx)))
	var entry := {"t_s": snappedf(_elapsed_ms / 1000.0, 0.01), "frames": count,
			"frame_ms": stats(_ms.slice(_win_start_idx)), "draw_calls_mean": stats(_draws.slice(_win_start_idx))["mean"],
			"busy_ms_p95": win_busy.get("p95", -1.0), "busy_ms_mean": win_busy.get("mean", -1.0)}
	if is_inside_tree():
		note_refresh_hz(DisplayServer.screen_get_refresh_rate())
	entry["refresh_hz"] = _refresh_now
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
	var report := summarize(_ms, _draws, _prims, _days, _stable_start, _busy, _pre_draw, _render_cpu)
	report.merge(_environment_info())
	if is_inside_tree():
		note_refresh_hz(DisplayServer.screen_get_refresh_rate())
	report["refresh_hz_start"] = _refresh_start
	report["refresh_hz_seen"] = _refresh_seen
	report["refresh_hz_changed"] = _refresh_changed
	report["busy_source"] = "first physics_frame|process_frame -> frame_post_draw"
	report["busy_signals_connected"] = _signals_connected
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
		report["thermal"] = thermal_summary(_ms, THERMAL_EDGE_S, _busy)
	last_error = write_report(out_path, report)
	if last_error != OK and not _warned:
		_warned = true
		push_warning("PerfLogger: ölçüm dosyası yazılamadı (%s): %s. Oyun devam ediyor, ölçüm bellekte tutulur."
				% [out_path, error_string(last_error)])
	return last_error


## Yenileme hızı gözlemi (başta, pencere başlarında, bellek örneğinde, yazımda). İlk değerden > 0,5 Hz sapma
## `refresh_hz_changed` yapar (ADR-0010 Karar 3a: koşu içinde değişirse koşu geçersiz).
func note_refresh_hz(hz: float) -> void:
	var value := snappedf(hz, 0.1)
	_refresh_now = value
	if _refresh_start < 0.0:
		_refresh_start = value
	elif absf(value - _refresh_start) > 0.5:
		_refresh_changed = true
	if not _refresh_seen.has(value):
		_refresh_seen.append(value)


## Kare başı / çizim öncesi / çizim sonrası sinyallerini bağlar (yalnız bu düğüm varken; düğüm yoksa hiçbiri yok).
func _connect_busy_signals() -> void:
	if _signals_connected or not is_inside_tree():
		return
	var tree := get_tree()
	tree.physics_frame.connect(_on_cycle_start)
	tree.process_frame.connect(_on_cycle_start)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	_viewport_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	_signals_connected = true


func _disconnect_busy_signals() -> void:
	if not _signals_connected:
		return
	_signals_connected = false
	var tree := get_tree()
	if tree != null:
		if tree.physics_frame.is_connected(_on_cycle_start):
			tree.physics_frame.disconnect(_on_cycle_start)
		if tree.process_frame.is_connected(_on_cycle_start):
			tree.process_frame.disconnect(_on_cycle_start)
	if RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)
	if RenderingServer.frame_post_draw.is_connected(_on_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_post_draw)
	if _viewport_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(_viewport_rid, false)


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
		"vsync_mode": int(DisplayServer.window_get_vsync_mode()), "max_fps": Engine.max_fps,
		"novsync_requested": novsync,
		"window": [window_size.x, window_size.y],
		"args": OS.get_cmdline_user_args(), "cmdline_args": OS.get_cmdline_args(),
		"started_unix": snappedf(_started_unix, 1.0), "path": out_path,
		"template_build": OS.has_feature("template"), "editor_build": OS.has_feature("editor"),
	}


## Karenin İLK başlangıç sinyali (physics_frame ya da process_frame, hangisi önce) süreyi başlatır; ikincisi no-op.
func _on_cycle_start() -> void:
	if _cycle_open:
		return
	_cycle_open = true
	_cycle_start_us = Time.get_ticks_usec()
	_cycle_pre_us = -1


func _on_pre_draw() -> void:
	if _cycle_open and _cycle_pre_us < 0:
		_cycle_pre_us = Time.get_ticks_usec()


func _on_post_draw() -> void:
	if not _cycle_open:
		return  # başlangıcı görülmeyen döngü (düğüm döngü ortasında eklendi): ölçülmez
	var end_us := Time.get_ticks_usec()
	_cycle_open = false
	if _discard_cycle:
		_discard_cycle = false
		_busy_done = -1.0
		_pre_done = -1.0
		return
	_busy_done = (end_us - _cycle_start_us) / 1000.0
	_pre_done = (_cycle_pre_us - _cycle_start_us) / 1000.0 if _cycle_pre_us >= 0 else -1.0


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			flush("pause")
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			# Arka planda geçen süre bir "kare" sayılmasın: sonraki işlenen kare yeni taban olur.
			_last_us = -1
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_EXIT_TREE:
			flush("exit")
			if what == NOTIFICATION_EXIT_TREE:
				_disconnect_busy_signals()
