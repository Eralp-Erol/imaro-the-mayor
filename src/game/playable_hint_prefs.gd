class_name PlayableHintPrefs
extends RefCounted
## Oynanabilir sahnenin tek seferlik ipuçları için kapatıldı bilgisi (T-043B C). Oyun/zaman katmanı tercihidir:
## sim durumunun parçası DEĞİL (kayda girmez, hash'i etkilemez). `UiPrefs`/`UiConfig` yalnız bellekte tutar;
## "kapatılınca bir daha çıkmasın" oturumlar arası olmalı, bu yüzden küçük bir `ConfigFile` (`user://`) kullanılır.
## Dosya yoksa ya da okunamazsa ipucu kapatılmamış sayılır (güvenli varsayılan: ipucu gösterilir).

const DEFAULT_PATH := "user://game_hints.cfg"
const SECTION := "dismissed"

var _path: String


## `path`: testler geçici yol verir; boş = `DEFAULT_PATH`.
static func create(path: String = "") -> PlayableHintPrefs:
	var p := PlayableHintPrefs.new()
	p._path = path if path != "" else DEFAULT_PATH
	return p


func is_dismissed(hint_id: StringName) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(_path) != OK:
		return false
	return bool(cfg.get_value(SECTION, String(hint_id), false))


## Kalıcı yazar. Yazılamazsa false (ipucu o oturumda yine tekrar etmez; çağıran oturum bayrağını tutar).
func dismiss(hint_id: StringName) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(_path)  # yoksa boş başlar
	cfg.set_value(SECTION, String(hint_id), true)
	return cfg.save(_path) == OK
