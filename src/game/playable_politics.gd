class_name PlayablePolitics
extends RefCounted
## Oynanabilir sahnenin siyaset YAPILANDIRMASI (T-043A, D-010, Q-014 AÇIK): sim varsayılan siyaset verisi
## (`data/politics/*.json`) + `data/game/playable_politics.json` yaması. Şimdilik tek yama: `requires_council` girdileri
## (oynanabilir varsayılan "meclis yok": imar planı teklifi oylamaya gitmeden `apply_delay_days` sonra yürürlüğe girer).
## Sim varsayılanı (GOLDEN A/B) DEĞİŞMEZ: dosyalar kopyalanır ve yama kopyaya uygulanır. Sim bu sınıfı bilmez.

const PATH := "res://data/game/playable_politics.json"


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
	var patch_ok: bool = patch is Dictionary and (patch as Dictionary).get("requires_council", null) is Dictionary
	if not (patch_ok and files["council"] is Dictionary):
		push_error("playable_politics: yama ya da meclis verisi okunamadı")
		return null
	var council: Dictionary = files["council"]
	var required: Dictionary = (council.get("requires_council", {}) as Dictionary).duplicate()
	for kind: Variant in (patch as Dictionary)["requires_council"]:
		required[kind] = (patch as Dictionary)["requires_council"][kind]
	council["requires_council"] = required
	var cfg := PoliticsConfig.from_files(files, actor_cfg)
	if not cfg.is_valid():
		push_error("playable_politics: yamalı siyaset yapılandırması geçersiz: %s" % cfg.error)
		return null
	return cfg


static func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))
