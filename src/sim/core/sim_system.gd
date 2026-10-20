class_name SimSystem
extends RefCounted
## Simülasyon sistemi taban sınıfı (T-002 ölçüt 1). Zamanlayıcı (`Simulation`) kancaları SABİT sırada çağırır:
## her tick'te önce tüm sistemlerin `on_daily`, ardından (takvim sınırındaysa) tüm `on_monthly`, sonra tüm
## `on_quarterly`; her aşamada kayıt (ekleme) sırası. Kancalar `delta` ALMAZ (TEK-02).
##
## Kurallar (sim-invariants): sistem nesnesi DURUM TUTMAZ; kalıcı veri `state.system_data(system_id())` altındadır
## (kayda ve hash'e otomatik girer). Rastgelelik yalnız `state.rng.stream(system_id())` (sistem başına akış).
## Her aktör kararı `state.record_reason(...)` ile gerekçesini kaydeder (SIM-12). Ayarlanabilir sayılar veridedir.


## Sistemin benzersiz kimliği; veri bölümü ve varsayılan RNG akışı adıdır. Alt sınıf geçersiz kılar.
func system_id() -> StringName:
	return &"unnamed"


func on_daily(_state: GameState) -> void:
	pass


func on_monthly(_state: GameState) -> void:
	pass


func on_quarterly(_state: GameState) -> void:
	pass
