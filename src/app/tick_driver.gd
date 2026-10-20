class_name TickDriver
extends RefCounted
## Tick sürücüsü (T-002 ölçüt 2, TEK-02): gerçek zaman x hız -> TAMSAYI tick. Simülasyon `delta` görmez; yalnız bu
## sınıf süre alır. Düğüm değildir (RefCounted): bir Node'un `_process`'i her karede `advance(delta)` çağırır.
##
## Kare bağımsızlığı: süre tam sayı mikrosaniyeye çevrilir ve birikim "mikro-tick" olarak (süre x tick/sn) TAM SAYI
## tutulur; kesirli float birikimi yoktur. Aynı toplam süreyi veren her kare dizisi aynı tick sayısını (ve hash'i) verir.
## `advance(float)` her kareyi bir kez yuvarlar; tam bağımsızlık için çağıran tam sayı mikrosaniye (`advance_usec`)
## vermelidir. Hız tablosu `data/sim/core_config.json` `driver` bölümündedir. Duraklatılmışken süre birikmez.
## Tek çağrıda en fazla `max_ticks_per_advance` tick koşar; geri kalan borç birikimde kalır (zaman kaybolmaz).

const _MICRO := 1_000_000

## Geçerli hız adı (ör. &"normal"); `set_speed` ile değişir.
var speed: StringName = &"paused"

var _sim: Simulation
var _state: GameState
var _speeds: Dictionary
var _max_ticks: int
var _micro_ticks: int = 0


## `driver_config`: SimConfig.driver sözlüğü.
func _init(sim: Simulation, state: GameState, driver_config: Dictionary) -> void:
	_sim = sim
	_state = state
	_speeds = driver_config["speeds"]
	_max_ticks = int(driver_config["max_ticks_per_advance"])
	speed = StringName(str(driver_config["default_speed"]))


## Yüklenen/yeni bir durumu bağlar (birikim korunur).
func bind_state(state: GameState) -> void:
	_state = state


## Bilinen hız adını seçer; bilinmeyende false döner ve hız değişmez.
func set_speed(speed_name: StringName) -> bool:
	if not _speeds.has(String(speed_name)):
		return false
	speed = speed_name
	return true


## Gerçek süre (saniye, float) ilerletir; yürütülen tick sayısını döndürür. Her kare tek yuvarlama.
func advance(delta_seconds: float) -> int:
	return advance_usec(roundi(delta_seconds * _MICRO))


## Gerçek süre (tam sayı mikrosaniye) ilerletir; yürütülen tick sayısını döndürür. Negatif süre yok sayılır.
@warning_ignore("integer_division")
func advance_usec(usec: int) -> int:
	var ticks_per_second := int(_speeds[String(speed)])
	if ticks_per_second <= 0:
		return 0
	if usec > 0:
		_micro_ticks += usec * ticks_per_second
	var due := mini(_micro_ticks / _MICRO, _max_ticks)
	if due <= 0:
		return 0
	_micro_ticks -= due * _MICRO
	_sim.advance(_state, due)
	return due
