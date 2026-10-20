extends Node
## Export duman sahnesi (T-007 ölçüt 5/6): boş sahne; platform/renderer/cihaz bilgisini loglar, profil katmanını
## çalıştırır, birkaç kare sonra çıkar. `tools/export.sh smoke macos` çıktıdaki `IMARO_SMOKE_OK` satırını arar.
## Dışa aktarılmış ikiliyle: `<ikili> res://src/app/platform_profile_smoke.tscn` (isteğe bağlı `--quit-after`'a gerek yok).

const FRAMES_BEFORE_QUIT := 5

var _frames := 0
var _failed := false


func _ready() -> void:
	var profile := PlatformProfile.detect()
	print("IMARO_SMOKE godot=", Engine.get_version_info().get("string", "?"))
	print("IMARO_SMOKE os=", OS.get_name(), " model=", OS.get_model_name(), " debug_build=", OS.is_debug_build())
	print("IMARO_SMOKE renderer=", RenderingServer.get_current_rendering_method(),
		" driver=", RenderingServer.get_current_rendering_driver_name(),
		" adapter=", RenderingServer.get_video_adapter_name())
	print("IMARO_SMOKE profile ", profile.describe())
	var input := profile.create_input_profile()
	if input == null:
		_fail("InputProfile oluşturulamadı: %s" % profile.input_profile)
	else:
		print("IMARO_SMOKE input_profile=", input.profile_name, " hover=", input.supports_hover)
	if profile.max_game_speed < 1:
		_fail("max_game_speed < 1")


func _process(_delta: float) -> void:
	_frames += 1
	if _frames >= FRAMES_BEFORE_QUIT:
		if _failed:
			print("IMARO_SMOKE_FAIL")
		else:
			print("IMARO_SMOKE_OK frames=", _frames)
		get_tree().quit(1 if _failed else 0)


func _fail(message: String) -> void:
	_failed = true
	printerr("IMARO_SMOKE error: ", message)
