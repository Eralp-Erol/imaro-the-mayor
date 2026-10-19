class_name DistrictLayout
extends RefCounted

static func parcels() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var colors := ["cream", "sand", "white", "sage", "rose", "blue"]
	for block in range(4):
		var bx := -22.0 if block % 2 == 0 else 22.0
		var bz := -20.0 if block < 2 else 20.0
		for row in range(2):
			for col in range(4):
				var id := result.size()
				var use := "apartment"
				if id in [2, 10, 18, 19, 23, 27, 30]: use = "empty"
				if id == 17: use = "park"
				if id == 3: use = "service"
				result.append({"id": id, "x": bx + (col - 1.5) * 8.3, "z": bz + (row - 0.5) * 13.0,
					"width": 7.8, "depth": 11.6, "floors": 4 + (id * 7 % 3), "color": colors[id % colors.size()],
					"use": use, "shop": "BAKKAL" if id == 21 else ("KAFE" if id == 20 else ("FIRIN" if id == 8 else "")),
					"rotation": PI if row == 0 else 0.0})
	return result
