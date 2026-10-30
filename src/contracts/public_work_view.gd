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
var provenance: StringName = SimContract.PROVENANCE_SIM


func ref() -> StringName:
	return SimContract.ref(SimContract.REF_COMMAND, command_id)


func to_dict() -> Dictionary:
	return {
		"work_id": work_id, "command_id": command_id, "tick": tick, "road_class": road_class, "length_cm": length_cm,
		"region_units": SimContract.to_args(region_units), "provenance": provenance,
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
	return w
