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


## Ret kodunun yanında UI'ya gidecek ek argümanlar (düz veri; örn. {"ref": "parcel.99"}). `validate` ret verdiyse
## çağrılır; durumu DEĞİŞTİRMEZ.
func reject_args(_state: GameState, _params: Dictionary) -> Dictionary:
	return {}


## Komutun etkilediği varlık referansları (`parcel.12` ...); `command.applied/rejected` olaylarının
## `subjects`'ine girer.
func subjects(_params: Dictionary) -> PackedStringArray:
	return PackedStringArray()


## Komut kimliğiyle uygulama (kimlik = sözleşme `command_id`, 1'den). Varsayılan `apply`'a düşer; uygulamanın sonucu
## komut kimliğiyle ilişkilendirmesi (olay `command_id`) gereken işleyiciler bunu geçersiz kılar.
func apply_with_id(state: GameState, params: Dictionary, _command_id: int) -> void:
	apply(state, params)
