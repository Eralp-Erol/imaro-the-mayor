class_name SaveSlot
extends RefCounted
## Kayıt yuvası dosya G/Ç'si (T-027 ölçüt 6, CAN-09, ADR-0002 Karar 5). Dosya erişimi YALNIZ bu app katmanındadır;
## simülasyon saf kalır (bayt üretir/tüketir: `SimSave`, `SimFacadeImpl.export_save/import_save`).
##
## Dosya: `<dizin>/<yuva>.imarosave` = `var_to_bytes` ile {format, version, slot_id, campaign_id, tick, world_seed,
## sim_save: PackedByteArray}. Kampanya kimliği KAYIT başlığındadır, sim durumunda değil: yedi bölge kampanyası ayrı
## kayıtlardır (CAN-09); başlık yuvaları kampanyaya göre listeler ve yanlış kampanyanın kaydını yüklemeyi reddeder.
## Sim baytı kendi bütünlük hash'ini taşır (SimSave); okuma onu da doğrular. Hata = istisna değil, anlaşılır
## kod + mesaj.
## Yazma atomiktir: geçici dosyaya yaz, sonra yuvanın üstüne taşı; başarısız yazma eski kaydı bozmaz.
## Nesne kodlaması KAPALIDIR (`bytes_to_var`): kayıt dosyası kod çalıştıramaz.
## Tarih/saat kullanılmaz (duvar saati sim girdisi değildir); yuva sırası kimliğe göredir.

const FORMAT := "imaro-save-slot"
const VERSION := 1
const MIN_SUPPORTED_VERSION := 1
const EXTENSION := "imarosave"
const DEFAULT_DIR := "user://saves"
const _TEMP_SUFFIX := ".tmp"
const _SLOT_ID_PATTERN := "^[a-z0-9][a-z0-9_-]{0,31}\\z"
const _CAMPAIGN_ID_PATTERN := "^[a-z0-9][a-z0-9_.-]{0,47}\\z"


## İşlem sonucu. Başarıda `ok`; aksi halde `error_code` ("invalid_slot_id", "invalid_campaign_id", "not_found",
## "empty", "io_error", "corrupt", "bad_format", "version_too_old", "version_too_new", "campaign_mismatch";
## sim baytı hataları SimSave kodlarını aynen taşır: "hash_mismatch", ...; facade: "world_mismatch") ve `message`.
class Result:
	extends RefCounted
	var ok: bool = false
	var error_code: StringName = &""
	var message: String = ""
	var slot_id: StringName = &""
	var campaign_id: StringName = &""
	var tick: int = 0
	var world_seed: int = 0
	var sim_bytes: PackedByteArray = PackedByteArray()


## Listeleme satırı (yalnız başlık okunur; sim baytı doğrulanmaz, `read` doğrular).
class Info:
	extends RefCounted
	var slot_id: StringName = &""
	var ok: bool = false
	var error_code: StringName = &""
	var message: String = ""
	var campaign_id: StringName = &""
	var tick: int = 0
	var world_seed: int = 0


static func is_valid_slot_id(slot_id: StringName) -> bool:
	return RegEx.create_from_string(_SLOT_ID_PATTERN).search(String(slot_id)) != null


static func is_valid_campaign_id(campaign_id: StringName) -> bool:
	return RegEx.create_from_string(_CAMPAIGN_ID_PATTERN).search(String(campaign_id)) != null


static func path_for(dir: String, slot_id: StringName) -> String:
	return dir.path_join("%s.%s" % [slot_id, EXTENSION])


## Facade'ın durumunu yuvaya yazar.
static func save_facade(dir: String, slot_id: StringName, campaign_id: StringName, facade: SimFacadeImpl) -> Result:
	var bytes := facade.export_save()
	if bytes.is_empty():
		return _fail(&"corrupt", "Sim durumu kayda dönüştürülemedi.")
	return write(dir, slot_id, campaign_id, bytes)


## Yuvadan okuyup facade'a yükler. Başarısızsa facade DEĞİŞMEZ. `expected_campaign` doluysa kampanya eşleşmeli.
static func load_into(dir: String, slot_id: StringName, facade: SimFacadeImpl,
		expected_campaign: StringName = &"") -> Result:
	var read_result := read(dir, slot_id, expected_campaign)
	if not read_result.ok:
		return read_result
	var imported := facade.import_save(read_result.sim_bytes)
	if not imported.ok:
		return _fail(imported.error_code, imported.message)
	facade.campaign_id = read_result.campaign_id
	return read_result


## Sim kayıt baytlarını (SimSave) kampanya kimliğiyle yuvaya atomik yazar. Baytlar önce doğrulanır.
static func write(dir: String, slot_id: StringName, campaign_id: StringName, sim_bytes: PackedByteArray) -> Result:
	var id_problem := _id_problem(slot_id, campaign_id)
	if id_problem != null:
		return id_problem
	var decoded := SimSave.decode(sim_bytes)
	if not decoded.ok:
		return _fail(decoded.error_code, decoded.message)
	var container := {
		"format": FORMAT, "version": VERSION, "slot_id": String(slot_id), "campaign_id": String(campaign_id),
		"tick": decoded.state.tick, "world_seed": decoded.state.world_seed, "sim_save": sim_bytes,
	}
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return _fail(&"io_error", "Kayıt dizini oluşturulamadı: %s" % dir)
	var path := path_for(dir, slot_id)
	var temp_path := path + _TEMP_SUFFIX
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail(&"io_error", "Kayıt dosyası yazılamadı: %s" % path)
	file.store_buffer(var_to_bytes(container))
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(temp_path, path) != OK:
		DirAccess.remove_absolute(temp_path)
		return _fail(&"io_error", "Kayıt dosyası yazılamadı: %s" % path)
	var result := _ok_result(slot_id, campaign_id, decoded.state.tick, decoded.state.world_seed)
	result.sim_bytes = sim_bytes
	return result


## Yuvayı okur ve doğrular (kap, başlık, sim baytı). Başarıda `sim_bytes` doludur.
static func read(dir: String, slot_id: StringName, expected_campaign: StringName = &"") -> Result:
	if not is_valid_slot_id(slot_id):
		return _fail(&"invalid_slot_id", "Geçersiz yuva kimliği.")
	var path := path_for(dir, slot_id)
	if not FileAccess.file_exists(path):
		return _fail(&"not_found", "Kayıt yuvası yok: %s." % slot_id)
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return _fail(&"empty", "Kayıt dosyası boş.")
	var header := _parse_header(bytes_to_var(bytes), slot_id)
	if not header.ok:
		return header
	var decoded := SimSave.decode(header.sim_bytes)
	if not decoded.ok:
		return _fail(decoded.error_code, "Sim kaydı: %s" % decoded.message)
	if decoded.state.tick != header.tick or decoded.state.world_seed != header.world_seed:
		return _fail(&"corrupt", "Kayıt başlığı sim durumuyla uyuşmuyor.")
	if expected_campaign != &"" and expected_campaign != header.campaign_id:
		return _fail(&"campaign_mismatch", "Bu kayıt başka bir kampanyaya ait (%s, beklenen %s)."
			% [header.campaign_id, expected_campaign])
	return header


## Yuvaları kimliğe göre sıralı listeler; bozuk dosya `ok=false` satırıdır. `campaign_id` doluysa yalnız o
## kampanyanın geçerli yuvaları. Dizin yoksa boş.
static func list(dir: String, campaign_id: StringName = &"") -> Array[Info]:
	var out: Array[Info] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var names: Array = []
	for file_name in DirAccess.get_files_at(dir):
		if file_name.get_extension() == EXTENSION and is_valid_slot_id(StringName(file_name.get_basename())):
			names.append(file_name.get_basename())
	names.sort()
	for slot_name: String in names:
		var info := Info.new()
		info.slot_id = StringName(slot_name)
		var bytes := FileAccess.get_file_as_bytes(path_for(dir, info.slot_id))
		var header := _fail(&"empty", "Kayıt dosyası boş.") if bytes.is_empty() \
			else _parse_header(bytes_to_var(bytes), info.slot_id)
		info.ok = header.ok
		info.error_code = header.error_code
		info.message = header.message
		info.campaign_id = header.campaign_id
		info.tick = header.tick
		info.world_seed = header.world_seed
		if campaign_id != &"" and (not info.ok or info.campaign_id != campaign_id):
			continue
		out.append(info)
	return out


static func remove(dir: String, slot_id: StringName) -> Result:
	if not is_valid_slot_id(slot_id):
		return _fail(&"invalid_slot_id", "Geçersiz yuva kimliği.")
	var path := path_for(dir, slot_id)
	if not FileAccess.file_exists(path):
		return _fail(&"not_found", "Kayıt yuvası yok: %s." % slot_id)
	if DirAccess.remove_absolute(path) != OK:
		return _fail(&"io_error", "Kayıt dosyası silinemedi: %s" % path)
	return _ok_result(slot_id, &"", 0, 0)


# --- İç ---

## Kap ve başlık doğrulaması (sim baytını çözmez). Başarıda sim baytı dahil dolu Result.
static func _parse_header(container: Variant, slot_id: StringName) -> Result:
	if not (container is Dictionary):
		return _fail(&"corrupt", "Kayıt dosyası bozuk veya tanınmayan biçimde.")
	if container.get("format", null) != FORMAT:
		return _fail(&"bad_format", "Bu dosya bir Imaro kayıt yuvası değil.")
	var version: Variant = container.get("version", null)
	if typeof(version) != TYPE_INT:
		return _fail(&"corrupt", "Kayıtta sürüm alanı yok veya geçersiz.")
	if int(version) < MIN_SUPPORTED_VERSION:
		return _fail(&"version_too_old", "Yuva sürümü %d çok eski; desteklenen en eski sürüm %d."
			% [version, MIN_SUPPORTED_VERSION])
	if int(version) > VERSION:
		return _fail(&"version_too_new", "Yuva sürümü %d bu oyun sürümünden yeni; desteklenen en yeni sürüm %d."
			% [version, VERSION])
	for key in ["slot_id", "campaign_id"]:
		if typeof(container.get(key, null)) != TYPE_STRING:
			return _fail(&"corrupt", "Kayıt başlığında %s yok veya geçersiz." % key)
	for key in ["tick", "world_seed"]:
		if typeof(container.get(key, null)) != TYPE_INT:
			return _fail(&"corrupt", "Kayıt başlığında %s yok veya geçersiz." % key)
	if container["slot_id"] != String(slot_id):
		return _fail(&"corrupt", "Kayıt başlığındaki yuva kimliği dosya adıyla uyuşmuyor.")
	if not is_valid_campaign_id(StringName(container["campaign_id"])):
		return _fail(&"corrupt", "Kayıt başlığındaki kampanya kimliği geçersiz.")
	if typeof(container.get("sim_save", null)) != TYPE_PACKED_BYTE_ARRAY:
		return _fail(&"corrupt", "Kayıtta sim durumu baytları yok.")
	var result := _ok_result(slot_id, StringName(container["campaign_id"]), container["tick"], container["world_seed"])
	result.sim_bytes = container["sim_save"]
	return result


static func _id_problem(slot_id: StringName, campaign_id: StringName) -> Result:
	if not is_valid_slot_id(slot_id):
		return _fail(&"invalid_slot_id", "Geçersiz yuva kimliği.")
	if not is_valid_campaign_id(campaign_id):
		return _fail(&"invalid_campaign_id", "Geçersiz kampanya kimliği.")
	return null


static func _ok_result(slot_id: StringName, campaign_id: StringName, tick: int, world_seed: int) -> Result:
	var result := Result.new()
	result.ok = true
	result.slot_id = slot_id
	result.campaign_id = campaign_id
	result.tick = tick
	result.world_seed = world_seed
	return result


static func _fail(code: StringName, message: String) -> Result:
	var result := Result.new()
	result.error_code = code
	result.message = message
	return result
