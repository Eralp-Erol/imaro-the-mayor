class_name SnapshotProvider
extends RefCounted
## Facade snapshot'ına bölüm ekleyen soyut sağlayıcı (T-017): grup tepkileri ve meclis gibi sistemler kurulunca
## `SimSnapshot` bölümlerini gerçek veriyle doldurur ve `x.sim.available.<bölüm>` bayrağını açar. Facade siyaset
## sınıflarını bilmez. Salt okunur: durumu DEĞİŞTİRMEZ; çıktı değer kopyasıdır.


## `snapshot`ı yerinde doldurur.
func fill(_state: GameState, _snapshot: SimSnapshot) -> void:
	pass


## v1.5 (isteğe bağlı) · Açık gündem öğeleri (`SimFacade.agenda_items`); kaynağı olmayan sağlayıcı boş döner.
func agenda_items(_state: GameState) -> Array[AgendaItemView]:
	return []
