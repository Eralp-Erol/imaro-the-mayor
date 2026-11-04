extends SceneTree
## Kit import doğrulama CLI'ı. Kullanım (repo kökünden):
##   tools/godot.sh --headless --path . -s res://assets/kit/validate_kit.gd
## Önce `tools/godot.sh --headless --path . --editor --import --quit` ile glb'ler içe aktarılmış olmalı
## (aksi halde çalışma zamanı glTF okumasına düşer; ayarlar - generate_lods vb. - doğrulanmaz).
## Çıkış 0 = tüm girdiler geçti, 1 = hata.


func _initialize() -> void:
	var lib := KitLibrary.load_manifest()
	if lib.entries().is_empty():
		printerr("validate_kit: manifest boş/okunamadı")
		quit(1)
		return
	var result := KitValidator.check_all(lib)
	for e in result["errors"]:
		printerr("FAIL " + str(e))
	print("validate_kit: %d modül denetlendi, LOD0 mesh=%d, hata=%d" % [
		result["checked"], result["lod0_meshes"], (result["errors"] as Array).size()])
	quit(0 if (result["errors"] as Array).is_empty() else 1)
