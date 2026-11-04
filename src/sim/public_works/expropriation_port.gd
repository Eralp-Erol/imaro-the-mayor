class_name ExpropriationPort
extends RefCounted
## T-042b · Sim <-> dünya köprüsü (kamulaştırma kipi). Sim "hangi parseller alınır" hesabını YAPMAZ: geometri ve parsel
## kümesi dünya hattındadır (`RoadDraftCheck`/`WorldNetwork`, ADR-0005 Ek F). Dünya adımı gerçek bağdaştırıcıyı verir
## (`player_roads.crossing_parcels: "expropriate"`, op'ta `expropriate: true`, `removed_parcels` raporu); sim testleri
## kendi test ikizini verir. Taban sınıf = "dünya kamulaştırmayı DESTEKLEMİYOR": `available()` false, sim komutu
## `expropriation_disabled` ile reddeder (hiçbir şey değişmez).
##
## Sözleşme (tümü SAF değil: `commit`/`undo`/`replay` AYNI `WorldNetwork` nesnesini değiştirir; yalnız tick sınırında):
## - `check`  : `RoadDraftCheck.check` biçiminde sonuç, ama parselli bloktan geçmeye İZİN VERİR; + `taken`
##              (PackedInt64Array, artan, bu yolun alacağı parsel kimlikleri). Ağa dokunmaz.
## - `commit` : `check` sonucunu `expropriate: true` işaretli op olarak ağa ekler. {ok, removed (PackedInt64Array),
## error}.
## - `undo`   : ağın son op'unu geri alır (alınan parselleri dünya geri koyar). {ok, error}.
## - `replay` : kayıt yüklemesinde kayıtlı bir `expropriate` op'unu yeniden uygular. {ok, removed, error}.


## Dünya kamulaştırma kipini destekliyor mu?
func available() -> bool:
	return false


func check(_points_cm: PackedInt64Array, _road_class: StringName, _busy: bool) -> Dictionary:
	return {"ok": false, "reason": &"expropriation_disabled", "key": "public_work.reject.expropriation_disabled",
		"taken": PackedInt64Array()}


func commit(_checked: Dictionary, _road_class: StringName) -> Dictionary:
	return {"ok": false, "removed": PackedInt64Array(), "error": "kamulaştırma desteklenmiyor"}


func undo() -> Dictionary:
	return {"ok": false, "error": "kamulaştırma desteklenmiyor"}


func replay(_op: Dictionary) -> Dictionary:
	return {"ok": false, "removed": PackedInt64Array(), "error": "kamulaştırma desteklenmiyor"}


## D-018: kaynak kamulaştırma işleminin boş belediye arazisi yeniden kullanılabilir mi? Salt okunur.
func available_land(_source_op: int, _ids: PackedInt64Array) -> Dictionary:
	return {"ok": false, "error": "belediye arazisi desteklenmiyor", "parcel_ids": PackedInt64Array()}


## Yalnız onaylanan plan yürürlüğe girerken: aynı kimlikli BOŞ parselleri kronolojik dünya işlemiyle geri koyar.
func restore_land(_source_op: int, _ids: PackedInt64Array) -> Dictionary:
	return {"ok": false, "error": "belediye arazisi desteklenmiyor", "restored": PackedInt64Array()}
