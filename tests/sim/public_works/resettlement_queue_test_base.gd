class_name ResettlementQueueTestBase
extends "res://tests/sim/public_works/resettlement_test_base.gd"
## T-067 (D-019 E1) · Ev bulunamayan aileler BEKLEME LİSTESİNE girer; yatırımcıların SONRADAN bitirdiği yeni evler önce
## onlara verilir. Yol DIAGONAL D1'de 16 haneyi yerinden eder (D1: 420 hane, yıkımdan sonra 6 konut). Hedef D2: 40 hane,
## 40 konut (boş ev yok). "Yatırımcı yeni ev bitirdi" benzetimi: hedef bölgenin `res_built` sütunu artırılır
## (`_complete`; gerçek bir tamamlanma gibi yalnız bu sütunu artırır, sim bunu "yeni birim" olarak görür). Beklenen
## değerler testte bağımsız hesaplanır.

const FULL := {"max_distance_m": 5000}  # D2'nin parseli yola ~1160 m: yer şartı tamam (tam ev)
const LEAVE := {"household_fate": "leave_region"}


## Politika AÇIK, D2'de boş ev YOK; 16 aile bekleme listesinde.
func _queued(resettlement: Dictionary = FULL, expropriation: Dictionary = {}) -> Dictionary:
	var run := _rworld(0, resettlement, expropriation)
	_set_region(run, TARGET, 40, 40)
	_policy(run, true)
	_road(run)
	return run


## Yatırımcı `code` bölgesinde `units` konut birimi bitirdi (test benzetimi; bina nesnesi yok, yalnız sütun).
func _complete(run: Dictionary, code: String, units: int) -> void:
	_set_region(run, code, _latent(run, code), _res_built(run, code) + units)


func _state(run: Dictionary) -> GameState:
	return _h(run).state()


func _command_of(run: Dictionary, index: int = 0) -> int:
	return int(PublicWorksState.standing_roads(_state(run))[index]["command_id"])


func _wait(run: Dictionary) -> PolicyView:
	return _f(run).policies()[0]
