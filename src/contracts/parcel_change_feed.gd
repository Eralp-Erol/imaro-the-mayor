class_name ParcelChangeFeed
extends SimDto
## `SimFacade.parcel_changes_since(tick)` sonucu (v1.2, ADR-0005 Ek D): `tick`ten SONRA (tick, `up_to_tick`] aralığında
## DEĞİŞEN parsellerin kimlikleri. Olay günlüğünden ve gerekçe/olay saklama ufkundan BAĞIMSIZDIR (B-002).
##
## Tüketici protokolü:
## 1. İlk eşitleme: tüm parselleri bir kez oku, `parcel_changes_since(current_tick())` ile `up_to_tick` ve `epoch` al.
## 2. Sonra: `feed = parcel_changes_since(son_up_to_tick)`. `feed.epoch != son_epoch` VEYA `not feed.complete` ise
##    TAM yeniden eşitle (bir kez), sonra yeni `up_to_tick`/`epoch`u sakla. Aksi halde yalnız `feed.ids` parsellerini
##    `parcel_views` ile yeniden oku; `up_to_tick`i sakla.
## 3. `epoch`: kayıt YÜKLENİNCE artar; yüklenen durum aynı tick'te olsa bile tüketici epoch karşılaştırmasıyla tam
##    yeniden eşitler.
## Kapsam: `ParcelView.development/use/units/owner/developed_by_sim/decision*` alanlarını değiştiren olaylar (karar,
## aşama geçişi, imar sonrası karar sıfırlama). KAPSAM DIŞI: `progress_pm` (aşama içinde her gün ilerler; aşama ve
## süreden türetin), `land_value`, `zone/pending_zone`, `reason_ids` ve `decision_reason_id`ın budanma ile 0'a düşmesi.
## `complete == false`: istenen tick bekletme penceresinden eski, gelecekte ya da durum yüklenmiş; `ids` boştur ve
## GÜVENİLMEZ.

var provenance: StringName = SimContract.PROVENANCE_SIM
## Değişen parsel kimlikleri, artan, tekrarsız. `complete == false` iken boş.
var ids: PackedInt64Array = PackedInt64Array()
## false: tüketici tam yeniden eşitlemelidir.
var complete: bool = false
## Bu okumanın kapsadığı son tick (= okuma anındaki `current_tick()`); tüketici bir sonraki sorguda bunu verir.
var up_to_tick: int = 0
## Durum kuşağı: kayıt yüklenince artar.
var epoch: int = 0


## Eksik/geçersiz kapsam: tam yeniden eşitleme gerekir.
static func incomplete(source: StringName, at_tick: int, at_epoch: int = 0) -> ParcelChangeFeed:
	var f := ParcelChangeFeed.new()
	f.provenance = source
	f.up_to_tick = at_tick
	f.epoch = at_epoch
	return f


func to_dict() -> Dictionary:
	return {"provenance": provenance, "ids": ids, "complete": complete, "up_to_tick": up_to_tick, "epoch": epoch}


static func from_dict(d: Dictionary) -> ParcelChangeFeed:
	var f := ParcelChangeFeed.new()
	f.provenance = SimContract.to_name(d.get("provenance", SimContract.PROVENANCE_SIM))
	f.ids = SimContract.to_int64_array(d.get("ids", []))
	f.complete = SimContract.to_bool(d.get("complete", false))
	f.up_to_tick = SimContract.to_int(d.get("up_to_tick"))
	f.epoch = SimContract.to_int(d.get("epoch"))
	return f
