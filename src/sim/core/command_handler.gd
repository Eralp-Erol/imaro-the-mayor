class_name CommandHandler
extends RefCounted
## Oyuncu/dış komutu için işleyici taban sınıfı (T-002 ölçüt 4). Komut = düz veri {type, params}; işleyici tick
## sınırında önce `validate` (UYGULAMA anındaki durumla), sonra yalnız geçerliyse `apply` çağrılır.
##
## `validate` durumu DEĞİŞTİRMEZ; boş kod = geçerli, aksi halde kısa makine-okur ret kodu döner
## (ör. &"insufficient_funds"). Belediye komutları yalnız KOŞULLARI değiştirir; özel bina oluşturmaz (CAN-03):
## gelişimi yalnız aktör kararları yapar.


## Bu işleyicinin ele aldığı komut türü (benzersiz).
func command_type() -> StringName:
	return &""


## Ret kodu; geçerliyse &"".
func validate(_state: GameState, _params: Dictionary) -> StringName:
	return &"not_implemented"


func apply(_state: GameState, _params: Dictionary) -> void:
	pass
