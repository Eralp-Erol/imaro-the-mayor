class_name PublicWorkView
extends SimDto
## Ağa eklenmiş bir oyuncu yolu (v1.3, ADR-0005 Ek E): `SimFacade.public_works()` satırı. Sim'in kendi kaydıdır
## (uydurma yok): komut kimliği (`command.N`), uygulandığı tick, sınıf, uzunluk ve bölge başına kapasite birimi.
## Maliyet YOKTUR (bütçe sistemi T-014 kurulu değil, para birimi Q-003 AÇIK).

var work_id: int = SimContract.NO_ID
## Yolu uygulayan komutun sözleşme kimliği (`command.N` = gerekçe etkeninin `source_ref`i).
var command_id: int = SimContract.NO_ID
var tick: int = 0
var road_class: StringName = &""
## Santimetre tamsayı (komutun yuvarlanmış uzunluğu).
var length_cm: int = 0
## Bölge kodu (String) -> eklenen altyapı kapasitesi birimi (> 0). Anahtarlar sıralı yazılır.
var region_units: Dictionary = {}
## v1.5 (ADR-0005 Ek F) · Yol parselleri aldı mı ve sim'in kaydı: alınan parsel kimlikleri (artan), bunlardan yapılı
## olanların sayısı, yıkılan konut/ticaret birimi ve yerinden edilen hane. Eski yollarda varsayılan (false/boş/0).
## Bedel YOK (T-014).
var expropriated: bool = false
var taken_parcel_ids: PackedInt64Array = PackedInt64Array()
var taken_built_parcels: int = 0
var taken_res_units: int = 0
var taken_com_units: int = 0
var displaced_households: int = 0
## v1.7 (ADR-0005 Ek I, T-065) · Bu yol yapılırken yeniden iskân politikası AÇIK mıydı ve sim'in kaydı: ev ayrılan hane
## (`rehoused_households`), ev bulunamayan hane (`unplaced_households`; ikisinin toplamı `displaced_households`),
## gösterge bedel. Politika kapalıyken (ve eski yollarda) varsayılan (false/0/0/0); sahte "karşılandı" yok (SIM-07).
var resettlement_applied: bool = false
var rehoused_households: int = 0
var unplaced_households: int = 0
var resettlement_cost: int = 0
var provenance: StringName = SimContract.PROVENANCE_SIM


func ref() -> StringName:
	return SimContract.ref(SimContract.REF_COMMAND, command_id)


func to_dict() -> Dictionary:
	return {
		"work_id": work_id, "command_id": command_id, "tick": tick, "road_class": road_class, "length_cm": length_cm,
		"region_units": SimContract.to_args(region_units), "provenance": provenance,
		"expropriated": expropriated, "taken_parcel_ids": taken_parcel_ids, "taken_built_parcels": taken_built_parcels,
		"taken_res_units": taken_res_units, "taken_com_units": taken_com_units,
		"displaced_households": displaced_households, "resettlement_applied": resettlement_applied,
		"rehoused_households": rehoused_households, "unplaced_households": unplaced_households,
		"resettlement_cost": resettlement_cost,
	}


static func from_dict(d: Dictionary) -> PublicWorkView:
	var w := PublicWorkView.new()
	w.work_id = SimContract.to_int(d.get("work_id"))
	w.command_id = SimContract.to_int(d.get("command_id"))
	w.tick = SimContract.to_int(d.get("tick"))
	w.road_class = SimContract.to_name(d.get("road_class", ""))
	w.length_cm = SimContract.to_int(d.get("length_cm"))
	w.region_units = SimContract.to_args(d.get("region_units", {}))
	w.provenance = SimContract.to_name(d.get("provenance", SimContract.PROVENANCE_SIM))
	w.expropriated = SimContract.to_bool(d.get("expropriated", false))
	w.taken_parcel_ids = SimContract.to_int64_array(d.get("taken_parcel_ids", []))
	w.taken_built_parcels = SimContract.to_int(d.get("taken_built_parcels"))
	w.taken_res_units = SimContract.to_int(d.get("taken_res_units"))
	w.taken_com_units = SimContract.to_int(d.get("taken_com_units"))
	w.displaced_households = SimContract.to_int(d.get("displaced_households"))
	w.resettlement_applied = SimContract.to_bool(d.get("resettlement_applied", false))
	w.rehoused_households = SimContract.to_int(d.get("rehoused_households"))
	w.unplaced_households = SimContract.to_int(d.get("unplaced_households"))
	w.resettlement_cost = SimContract.to_int(d.get("resettlement_cost"))
	return w
