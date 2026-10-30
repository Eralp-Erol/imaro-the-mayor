class_name BudgetConfig
extends RefCounted
## Gösterge bütçe yapılandırması (T-043C, D-010 karar 3). Çalışma-modeli sayıları kodda değil
## `data/sim/budget/budget_config.json`'dadır (F05-C: ayarlanabilir, kanon değil). Para birimi adı/simgesi YOKTUR
## (Q-003 AÇIK): tutarlar birimsiz tamsayıdır. Kurulumda okunur (tick dışında); tick kodu dosya G/Ç yapmaz.
## Bilinmeyen anahtar/bölüm hatadır (yazım hatası sessizce yok sayılmaz); `_` ile başlayanlar belgedir.

const DEFAULT_PATH := "res://data/sim/budget/budget_config.json"
const _SECTIONS: Array[String] = ["tax", "road", "ledger"]
const _BIG := 1 << 40

var error: String = ""
## Başlangıç kasası (birimsiz; negatif olabilir: gösterge).
var initial_balance: int = 0
var tax_rate_pm: int = 0
var public_cost_share_pm: int = 0
## Yol giderinin birim maliyetini aldığı kullanım (`economy_config.json uses` anahtarı).
var road_cost_use: StringName = &"residential"
var ledger_max: int = 64
var view_reason_limit: int = 8
var reason_parcel_limit: int = 6


static func load_default() -> BudgetConfig:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> BudgetConfig:
	if not FileAccess.file_exists(path):
		return _invalid("bütçe yapılandırma dosyası yok: %s" % path)
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return _invalid("bütçe yapılandırma JSON ayrıştırılamadı (satır %d: %s)"
			% [json.get_error_line(), json.get_error_message()])
	if not (json.data is Dictionary):
		return _invalid("bütçe yapılandırma JSON nesnesi değil")
	return from_dict(json.data)


static func from_dict(data: Dictionary) -> BudgetConfig:
	var cfg := BudgetConfig.new()
	for key: Variant in data:
		var name := str(key)
		if not name.begins_with("_") and name != "initial_balance" and not _SECTIONS.has(name):
			return _invalid("bilinmeyen bölüm '%s'" % name)
	var balance: Variant = data.get("initial_balance", null)
	if not _is_whole(balance) or absf(float(balance)) > _BIG:
		return _invalid("initial_balance tamsayı olmalı")
	cfg.initial_balance = int(balance)
	for section in _SECTIONS:
		if not (data.get(section, null) is Dictionary):
			return _invalid("'%s' bölümü eksik veya nesne değil" % section)
	var problem := _read_int(data["tax"], "tax", "tax_rate_pm", 0, 1000)
	if problem.is_empty():
		problem = _read_int(data["road"], "road", "public_cost_share_pm", 0, 1000)
	if problem.is_empty():
		problem = _read_int(data["ledger"], "ledger", "max_entries", 1, 100000)
	if problem.is_empty():
		problem = _read_int(data["ledger"], "ledger", "view_reason_limit", 1, 1000)
	if problem.is_empty():
		problem = _read_int(data["ledger"], "ledger", "reason_parcel_limit", 0, 1000)
	if problem.is_empty():
		problem = _only_known(data)
	var use: Variant = (data["road"] as Dictionary).get("cost_use", null)
	if problem.is_empty() and (typeof(use) != TYPE_STRING or (use as String).is_empty()):
		problem = "road.cost_use boş olmayan dizge olmalı"
	if not problem.is_empty():
		return _invalid(problem)
	cfg.tax_rate_pm = int(data["tax"]["tax_rate_pm"])
	cfg.public_cost_share_pm = int(data["road"]["public_cost_share_pm"])
	cfg.road_cost_use = StringName(use)
	cfg.ledger_max = int(data["ledger"]["max_entries"])
	cfg.view_reason_limit = int(data["ledger"]["view_reason_limit"])
	cfg.reason_parcel_limit = int(data["ledger"]["reason_parcel_limit"])
	return cfg


func is_valid() -> bool:
	return error.is_empty()


static func _read_int(section: Dictionary, section_name: String, key: String, low: int, high: int) -> String:
	var value: Variant = section.get(key, null)
	if not _is_whole(value) or int(value) < low or int(value) > high:
		return "%s.%s %d..%d aralığında tamsayı olmalı" % [section_name, key, low, high]
	return ""


## Bilinmeyen alt anahtarları yakalar (yazım hatası).
static func _only_known(data: Dictionary) -> String:
	var known := {
		"tax": ["tax_rate_pm"], "road": ["public_cost_share_pm", "cost_use"],
		"ledger": ["max_entries", "view_reason_limit", "reason_parcel_limit"],
	}
	for section: String in known:
		for key: Variant in data[section]:
			if not str(key).begins_with("_") and not (known[section] as Array).has(str(key)):
				return "bilinmeyen anahtar '%s.%s'" % [section, str(key)]
	return ""


static func _is_whole(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and value == floorf(value))


static func _invalid(message: String) -> BudgetConfig:
	var cfg := BudgetConfig.new()
	cfg.error = message
	return cfg
