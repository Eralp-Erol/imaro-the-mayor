class_name UiPrefs
extends RefCounted
## Oyuncu/geliştirme tercihleri (T-022). Değerler `data/ui/ui_config.json`'dan gelir; çalışma anında
## `UiConfig.set_override` ile değiştirilir (kalıcılık platform/kayıt katmanının işidir; bu sınıf dosya yazmaz).
##
## AÇIK kararlar KANONLAŞTIRILMAZ, ayar olarak sunulur:
##  - `auto_pause_agenda`: gündem öğesinde otomatik duraklatma (varsayılan AÇIK SORU, Q-011/AS-11).
##  - `zoning_requires_council`: imar önerisi meclisten geçmeli mi (Q-014). Bu bir OYUNCU ayarı değil sim
##    gerçeğidir; sim bayrağı sözleşmeye girene dek UI iki yolu da gösterebilsin diye veridir.

const KEY_AUTO_PAUSE := "settings.auto_pause_agenda"
const KEY_ZONING_COUNCIL := "zoning.requires_council"
const KEY_BUDGET_STEP := "budget.edit_step"


static func auto_pause_agenda() -> bool:
	return bool(UiConfig.value(KEY_AUTO_PAUSE, false))


static func set_auto_pause_agenda(on: bool) -> void:
	UiConfig.set_override(KEY_AUTO_PAUSE, on)


static func zoning_requires_council() -> bool:
	return bool(UiConfig.value(KEY_ZONING_COUNCIL, false))


static func set_zoning_requires_council(on: bool) -> void:
	UiConfig.set_override(KEY_ZONING_COUNCIL, on)


## Bütçe düzenleyici adımı (birimsiz tamsayı, ≥ 1).
static func budget_step() -> int:
	return maxi(1, int(UiConfig.value(KEY_BUDGET_STEP, 1)))
