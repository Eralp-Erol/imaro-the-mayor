class_name CityModel
extends RefCounted
## Plain state. No renderer, input, wall-clock or scene-tree dependency.

const ZONES := {"restricted": "Kısıtlı kullanım", "housing": "Konut", "mixed": "Karma kullanım", "commerce": "Ticaret", "green": "Yeşil alan"}

class Owner:
	extends RefCounted
	var id: int
	var title: String
	var public_owner: bool
	func _init(number: int, name_text: String, is_public: bool = false) -> void:
		id = number
		title = name_text
		public_owner = is_public

class Parcel:
	extends RefCounted
	var id: int
	var geometry: Dictionary
	var owner_id: int
	var zone: String = "restricted"
	var use: String = "empty"
	var land_value: int = 80000
	var cleanup: int = 0
	var access: float = 0.85
	var homes: int = 0
	var shops: int = 0
	var occupied: int = 0
	var last_evaluation: String = "İmar koşulları yatırım için uygun değil."
	func _init(spec: Dictionary) -> void:
		id = spec.id
		geometry = spec.duplicate(true)
		use = spec.use
		owner_id = id
	func to_data() -> Dictionary:
		return {"id": id, "owner": owner_id, "zone": zone, "use": use, "land": land_value,
			"cleanup": cleanup, "access": access, "homes": homes, "shops": shops, "occupied": occupied, "evaluation": last_evaluation}

class Investor:
	extends RefCounted
	var id: int
	var title: String
	var profile: String
	var capital: int = 1800000
	var threshold: float
	func _init(number: int, name_text: String, kind: String, minimum: float) -> void:
		id = number
		title = name_text
		profile = kind
		threshold = minimum
	func to_data() -> Dictionary:
		return {"id": id, "capital": capital}

class Development:
	extends RefCounted
	var parcel_id: int
	var investor_id: int
	var started_day: int
	var duration: int = 18
	var cost: int
	var revenue: int
	var homes: int
	var shops: int
	var completed: bool = false
	func to_data() -> Dictionary:
		return {"parcel_id": parcel_id, "investor_id": investor_id, "started_day": started_day,
			"duration": duration, "cost": cost, "revenue": revenue, "homes": homes, "shops": shops, "completed": completed}

class Municipality:
	extends RefCounted
	var cash: int = 320000
	var mobility: bool = false
	var care: bool = false
	var income_today: int = 0
	var expense_today: int = 0
	var ledger: Array[Dictionary] = []
	func transact(day: int, amount: int, reason: String) -> void:
		cash += amount
		ledger.append({"day": day, "amount": amount, "reason": reason})
		if ledger.size() > 120: ledger.pop_front()

class CitizenGroup:
	extends RefCounted
	var title: String
	var support: int
	var reason: String
	func _init(name_text: String, initial: int, explanation: String) -> void:
		title = name_text
		support = initial
		reason = explanation
	func react(amount: int, explanation: String) -> void:
		support = clampi(support + amount, 0, 100)
		reason = explanation
	func to_data() -> Dictionary:
		return {"title": title, "support": support, "reason": reason}
