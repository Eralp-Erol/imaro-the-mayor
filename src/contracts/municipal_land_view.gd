class_name MunicipalLandView
extends SimDto
## D-018 / sözleşme 1.8: kamulaştırılmış belediye arazisinin yeni imar kararına uygunluğu.
## Alan ve uygunluk gerçek sim/dünya sorgusudur; DTO'yu değiştirmek sim'i değiştirmez.

var id: int = 0
var source_command_id: int = 0
var region_code: StringName = &""
var area_m2: int = 0
var available: bool = false
var reason_key: StringName = &"municipal_land.not_available"


func to_dict() -> Dictionary:
	return {"id": id, "source_command_id": source_command_id, "region_code": region_code,
		"area_m2": area_m2, "available": available, "reason_key": reason_key}


static func from_dict(data: Dictionary) -> MunicipalLandView:
	var view := MunicipalLandView.new()
	view.id = SimContract.to_int(data.get("id", 0))
	view.source_command_id = SimContract.to_int(data.get("source_command_id", 0))
	view.region_code = SimContract.to_name(data.get("region_code", ""))
	view.area_m2 = SimContract.to_int(data.get("area_m2", 0))
	view.available = SimContract.to_bool(data.get("available", false))
	view.reason_key = SimContract.to_name(data.get("reason_key", "municipal_land.not_available"))
	return view
