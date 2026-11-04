class_name ContractPurityScanner
extends RefCounted
## `src/contracts/` saflık taraması (T-023 ölçüt 5, TEK-01/02, PLT-04). Yorumlar ve dizge sabitleri çıkarılıp
## kalan kod yasak API'lere karşı taranır. Olumsuz testler `scan_source()`'u sentetik kaynakla besler.

const ROOT := "res://src/contracts"
## [ad, düzenli ifade]. Kod gövdesinde (yorum/dizge dışında) eşleşme = ihlal.
const FORBIDDEN := [
	["Node", "\\b(Node|Node2D|Node3D|SceneTree|Viewport|CanvasItem)\\b"],
	["get_tree", "\\bget_tree\\s*\\("],
	["Time", "\\bTime\\s*\\."],
	["OS", "\\bOS\\s*\\."],
	["Engine", "\\bEngine\\s*\\."],
	["global rand", "(?<![\\w.])(randf|randi|randf_range|randi_range|randfn|randomize|seed)\\s*\\("],
	["RandomNumberGenerator", "\\bRandomNumberGenerator\\b"],
	["Input/Display/Rendering", "\\b(Input|DisplayServer|RenderingServer|PhysicsServer3D)\\b"],
	["DirAccess", "\\bDirAccess\\b"],
	["Resource I/O", "\\b(ResourceLoader|ResourceSaver)\\b|(?<![\\w.])(load|preload)\\s*\\("],
]
## Sözleşme içi soyut tabanlar (bunlardan türeyenler dolaylı olarak RefCounted'dır).
const CONTRACT_BASES: Array[String] = ["SimDto", "SimFacade"]
## Dosya okuma yalnız MOCK senaryo yükleyicisinde (geliştirme aracı; tick içinde değil).
const FILE_ACCESS_ALLOWED: Array[String] = ["res://src/contracts/mock/mock_scenario.gd"]


## Tüm sözleşme dosyalarındaki ihlaller ("dosya:satır: ad").
static func scan_tree(root: String = ROOT) -> PackedStringArray:
	var out := PackedStringArray()
	for path in gd_files(root):
		var source := FileAccess.get_file_as_string(path)
		for problem in scan_source(source, FILE_ACCESS_ALLOWED.has(path)):
			out.append("%s:%s" % [path, problem])
	return out


static func gd_files(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	var files := dir.get_files()
	files.sort()
	for f in files:
		if f.ends_with(".gd"):
			out.append(root.path_join(f))
	var dirs := dir.get_directories()
	dirs.sort()
	for d in dirs:
		out.append_array(gd_files(root.path_join(d)))
	return out


## Tek kaynak metni; dönen satırlar "satır: ad". `extends` RefCounted ya da sözleşme sınıfı olmalı.
static func scan_source(source: String, allow_file_access: bool = false) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := source.split("\n")
	var has_extends := false
	for n in lines.size():
		var code := strip_comments_and_strings(lines[n])
		for rule: Array in FORBIDDEN:
			if _matches(rule[1], code):
				out.append("%d: %s" % [n + 1, rule[0]])
		if not allow_file_access and _matches("\\bFileAccess\\b", code):
			out.append("%d: FileAccess" % (n + 1))
		var ext := _extends_target(code)
		if not ext.is_empty():
			has_extends = true
			if ext != "RefCounted" and not CONTRACT_BASES.has(ext):
				out.append("%d: extends %s (must be RefCounted or a contract base class)" % [n + 1, ext])
	if not has_extends:
		out.append("0: missing 'extends RefCounted'")
	return out


## Satırdan `#` yorumunu ve "..."/'...' dizge sabitlerini çıkarır (tek satırlık yaklaşım; çok satırlı dizge yok).
static func strip_comments_and_strings(line: String) -> String:
	var out := ""
	var quote := ""
	var i := 0
	while i < line.length():
		var ch := line[i]
		if quote.is_empty():
			if ch == "#":
				break
			if ch == "\"" or ch == "'":
				quote = ch
			else:
				out += ch
		elif ch == "\\":
			i += 1
		elif ch == quote:
			quote = ""
		i += 1
	return out


static func _extends_target(code: String) -> String:
	var re := RegEx.create_from_string("^\\s*extends\\s+(\\w+)")
	var m := re.search(code)
	return "" if m == null else m.get_string(1)


static func _matches(pattern: String, code: String) -> bool:
	return RegEx.create_from_string(pattern).search(code) != null
