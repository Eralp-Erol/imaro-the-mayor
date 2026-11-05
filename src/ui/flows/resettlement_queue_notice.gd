class_name ResettlementQueueNotice
extends RefCounted
## "Eve kavuştu" bildirimi (T-067 UI): sim'de bunun için olay türü yoktur (sözleşme 1.9); bu yüzden
## `PolicyView.served_households` TOPLAMININ artışı izlenir. İlk gözlem taban çizgisidir (açılış/yüklemedeki eski toplam
## "yeni" sayılmaz). Saf durum; HUD şeridini `DecisionPanels` besler.

var _baseline: int = -1
var _last_batch: int = 0
var _waiting: int = 0


## Politika satırını gözlemler. Toplam arttıysa son küme = artış; düştüyse (geri alma/yükleme) eski bildirim silinir.
func observe(views: Array[PolicyView]) -> void:
	var served := 0
	_waiting = 0
	for v in views:
		if v.policy_id == PolicyView.ID_RESETTLEMENT:
			served = v.served_households
			_waiting = v.waiting_households
	if _baseline < 0:
		_baseline = served
		return
	if served > _baseline:
		_last_batch = served - _baseline
	elif served < _baseline:
		_last_batch = 0
	_baseline = served


func waiting() -> int:
	return _waiting


func last_batch() -> int:
	return _last_batch
