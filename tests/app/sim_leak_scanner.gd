extends RefCounted
## T-007 ölçüt 4 olumsuz test yardımcısı: simülasyon (ve dünya/sözleşme) kodu platform profilini veya platform
## sorgularını kullanamaz (ADR-0004 gerilim 1, PLT-04, TEK-01/02: sim sonuçları platformdan bağımsız).
## Yorum satırları sayılmaz; tırnak içindeki `#` yorum başlatmaz. Dizeler içindeki kullanım da yakalanır (kasıtlı:
## sim içinde `"OS.has_feature"` dizesi bile kuşkulu).

const FORBIDDEN: PackedStringArray = [
	"PlatformProfile", "InputProfile",  # InputProfile alt dizesi Desktop/TouchInputProfile'ı da kapsar
	"OS.has_feature", "OS.get_name", "OS.get_model_name", "OS.get_distribution_name", "OS.get_processor_name",
	"DisplayServer",
]

## Taranan kök dizinler: sim + onun bağımlı olduğu salt-veri katmanları.
const ROOTS: PackedStringArray = ["res://src/sim", "res://src/world", "res://src/contracts"]


## Kaynak metindeki ihlaller: [{"line": int, "token": String, "text": String}].
static func violations_in(source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := 0
	for raw in source.split("\n"):
		n += 1
		var code := _strip_comment(raw)
		for token in FORBIDDEN:
			if code.contains(token):
				out.append({"line": n, "token": token, "text": raw.strip_edges()})
	return out


## Dizin altındaki tüm .gd dosyaları: [{"file": String, "line": int, "token": String, "text": String}].
static func scan_dir(dir_path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for file in _gd_files(dir_path):
		var f := FileAccess.open(file, FileAccess.READ)
		if f == null:
			continue
		for v in violations_in(f.get_as_text()):
			v["file"] = file
			out.append(v)
	return out


static func scan_roots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for root in ROOTS:
		out.append_array(scan_dir(root))
	return out


static func _strip_comment(line: String) -> String:
	var quote := ""
	for i in line.length():
		var c := line[i]
		if quote != "":
			if c == quote and (i == 0 or line[i - 1] != "\\"):
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
	return line


static func _gd_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_gd_files(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	return out
