class_name RoadDrawKeys
extends Node
## Yol çiziminin klavye girdisi (Enter = taslak yolu onayla). UI'nin tüketmediği tuşlar `_unhandled_input`a gelir; odak
## bir düğmedeyse Godot kendi `ui_accept`ini işler ve buraya düşmez (çift onay olmaz). Karar `RoadDrawController`da.

var ctrl: RoadDrawController = null


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and ctrl != null and ctrl.handle_key(key):
		get_viewport().set_input_as_handled()
