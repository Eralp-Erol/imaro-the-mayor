class_name SimConfig
extends RefCounted
## Simülasyon çekirdeği yapılandırması (T-002). Çalışma-modeli sayıları kodda değil `data/sim/core_config.json`'da
## (F05-C: ayarlanabilir, kanon değil). Kurulum anında (tick dışında) okunur; tick kodu dosya G/Ç yapmaz.
##
## İki bölüm:
##   `sim`    durumla KAYDEDİLEN takvim/kapasite değerleri (GameState.config): days_per_month, months_per_quarter,
##            reason_log_capacity, command_log_capacity. Kayıt yüklenince aynı takvim geçerli olur.
##   `driver` yalnız uygulama/görünüm tarafı (TickDriver): speeds (ad -> gerçek saniye başına tick), default_speed,
##            max_ticks_per_advance. Durumun parçası değildir.
## JSON sayıları float döner; tam sayı değerli olanlar int'e çevrilir, kesirli olanlar reddedilir.

const DEFAULT_PATH := "res://data/sim/core_config.json"

const _SIM_INT_KEYS: Array[String] = [
	"days_per_month", "months_per_quarter", "reason_log_capacity", "command_log_capacity",
]

## `sim` bölümü (int değerler).
var sim: Dictionary = {}
## `driver` bölümü: {"speeds": {ad: int}, "default_speed": String, "max_ticks_per_advance": int}.
var driver: Dictionary = {}
## Geçersizse insan-okur hata metni, geçerliyse "".
var error: String = ""


static func load_default() -> SimConfig:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> SimConfig:
	if not FileAccess.file_exists(path):
		return _invalid("yapılandırma dosyası yok: %s" % path)
	return from_json_text(FileAccess.get_file_as_string(path))


static func from_json_text(text: String) -> SimConfig:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _invalid("yapılandırma JSON ayrıştırılamadı (satır %d: %s)"
			% [json.get_error_line(), json.get_error_message()])
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		return _invalid("yapılandırma JSON nesnesi değil veya ayrıştırılamadı")
	return from_dict(parsed)


static func from_dict(data: Dictionary) -> SimConfig:
	var cfg := SimConfig.new()
	var sim_in: Variant = data.get("sim", null)
	var driver_in: Variant = data.get("driver", null)
	if not (sim_in is Dictionary):
		return _invalid("'sim' bölümü eksik")
	if not (driver_in is Dictionary):
		return _invalid("'driver' bölümü eksik")
	for key in _SIM_INT_KEYS:
		var value: Variant = _positive_int(sim_in.get(key, null))
		if value == null:
			return _invalid("sim.%s eksik veya pozitif tam sayı değil" % key)
		cfg.sim[key] = value
	var speeds_in: Variant = driver_in.get("speeds", null)
	if not (speeds_in is Dictionary) or (speeds_in as Dictionary).is_empty():
		return _invalid("driver.speeds eksik veya boş")
	var speeds := {}
	for name: Variant in speeds_in:
		var tps: Variant = _as_int(speeds_in[name])
		if tps == null or int(tps) < 0:
			return _invalid("driver.speeds.%s negatif olmayan tam sayı olmalı" % name)
		speeds[str(name)] = int(tps)
	if not speeds.has("paused") or int(speeds["paused"]) != 0:
		return _invalid("driver.speeds.paused = 0 olmalı")
	var default_speed := str(driver_in.get("default_speed", ""))
	if not speeds.has(default_speed):
		return _invalid("driver.default_speed '%s' speeds içinde yok" % default_speed)
	var max_ticks: Variant = _positive_int(driver_in.get("max_ticks_per_advance", null))
	if max_ticks == null:
		return _invalid("driver.max_ticks_per_advance eksik veya pozitif tam sayı değil")
	cfg.driver = {"speeds": speeds, "default_speed": default_speed, "max_ticks_per_advance": max_ticks}
	return cfg


func is_valid() -> bool:
	return error.is_empty()


static func _invalid(message: String) -> SimConfig:
	var cfg := SimConfig.new()
	cfg.error = message
	return cfg


## int ise kendisi; tam sayı değerli float ise int; aksi halde null.
static func _as_int(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value):
		return int(value)
	return null


static func _positive_int(value: Variant) -> Variant:
	var as_int: Variant = _as_int(value)
	if as_int == null or int(as_int) < 1:
		return null
	return as_int
