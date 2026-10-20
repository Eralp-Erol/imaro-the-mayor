class_name WorldSite
extends RefCounted
## T0 sahası işareti (liman, ilk ana sanayi). Parsel değil; parsel/arazi kullanımı T-005'tir.
## `kind` değerleri: &"port", &"first_industry" (veride serbest genişler).

var id: StringName = &""
var kind: StringName = &""
## Dünya metresi (x doğu, z güney).
var position: Vector2 = Vector2.ZERO
var basis: String = ""


func state_dict() -> Dictionary:
	return {"id": id, "kind": kind, "position": [position.x, position.y]}
