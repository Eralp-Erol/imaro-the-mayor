class_name PlayablePolitics
extends RefCounted
## Oynanabilir sahnenin siyaset YAPILANDIRMASI (T-043A, D-010, Q-014 AÇIK): sim varsayılan siyaset verisi
## (`data/politics/*.json`) + `data/game/playable_politics.json` yaması. Yamalar: `requires_council` girdileri,
## D-011 Soru 4 imar planı büyüklük eşikleri (`plan_council_min_parcels` / `plan_council_min_units`; ÇALIŞMA DEĞERİ:
## küçük plan oylamaya gitmeden `apply_delay_days` sonra yürürlüğe girer, BÜYÜK plan meclise gider)
## ve `blocs_grievance_rule_overrides` (altyapı baskısı şikâyetini yalnız gerçek aşımda başlatır; bölge ~%99,9 dolu).
## Sim varsayılanı (GOLDEN A/B) DEĞİŞMEZ: dosyalar kopyalanır ve yama kopyaya uygulanır. Sim bu sınıfı bilmez.

const PATH := "res://data/game/playable_politics.json"
const REACTIONS_PATH := "res://data/politics/reactions.json"
## Meclis bölümüne kopyalanan, imar planı büyüklük eşiği yama anahtarları (D-011 Soru 4).
const PLAN_COUNCIL_KEYS: Array[String] = ["plan_council_min_parcels", "plan_council_min_units"]


## Yamalı siyaset yapılandırması; okunamaz/geçersizse push_error + null (çağıran `PoliticsBootstrap` varsayılana düşer).
static func config(actors: ActorConfig = null) -> PoliticsConfig:
	var actor_cfg := actors if actors != null else ActorConfig.load_default()
	var patch: Variant = _read(PATH)
	var files := {}
	for file_name in PoliticsConfig.FILE_NAMES:
		files[file_name] = _read(PoliticsConfig.DIR + file_name + ".json")
	var templates := {}
	var index: Variant = files["events"]
	if index is Dictionary and (index as Dictionary).get("templates", null) is Array:
		for template_id: Variant in (index as Dictionary)["templates"]:
			templates[str(template_id)] = _read(PoliticsConfig.EVENT_DIR + str(template_id) + ".json")
	files["templates"] = templates
	if FileAccess.file_exists(REACTIONS_PATH):  # T-042b: isteğe bağlı, digest dışı (mahalle ölçekli yıkım tepkisi dahil)
		files["reactions"] = _read(REACTIONS_PATH)
	var patch_ok: bool = patch is Dictionary and (patch as Dictionary).get("requires_council", null) is Dictionary
	if not (patch_ok and files["council"] is Dictionary):
		push_error("playable_politics: yama ya da meclis verisi okunamadı")
		return null
	var council: Dictionary = files["council"]
	var required: Dictionary = (council.get("requires_council", {}) as Dictionary).duplicate()
	for kind: Variant in (patch as Dictionary)["requires_council"]:
		required[kind] = (patch as Dictionary)["requires_council"][kind]
	council["requires_council"] = required
	for key in PLAN_COUNCIL_KEYS:  # D-011 Soru 4: yoksa sim varsayılanı (anahtar yok = eşik kapalı) korunur
		if (patch as Dictionary).has(key):
			council[key] = (patch as Dictionary)[key]
	_override_grievance_rules(files["blocs"], (patch as Dictionary).get("blocs_grievance_rule_overrides", []))
	var cfg := PoliticsConfig.from_files(files, actor_cfg)
	if not cfg.is_valid():
		push_error("playable_politics: yamalı siyaset yapılandırması geçersiz: %s" % cfg.error)
		return null
	return cfg


## Her kesimin aynı sinyalli şikâyet kuralına `lo`/`hi` yamasını uygular (kopya sözlük; sim varsayılanı değişmez).
static func _override_grievance_rules(blocs: Variant, overrides: Variant) -> void:
	if not (blocs is Dictionary and overrides is Array and (blocs as Dictionary).get("cohorts", null) is Dictionary):
		return
	for cohort: Variant in (blocs as Dictionary)["cohorts"].values():
		for rule: Variant in (cohort as Dictionary).get("grievance_rules", []):
			for override: Variant in overrides:
				if (rule as Dictionary).get("signal", null) == (override as Dictionary).get("signal", ""):
					rule["lo"] = (override as Dictionary)["lo"]
					rule["hi"] = (override as Dictionary)["hi"]


static func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))
