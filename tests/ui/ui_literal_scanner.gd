class_name UiLiteralScanner
extends RefCounted
## Test aracı: src/ui ve scenes/ui içinde oyuncuya görünebilecek GÖMÜLÜ metin literali arar (ux-text-system
## §1.1).
## Sezgisel: (a) Türkçe harf içeren literal, (b) boşlukla ayrılmış ≥ 2 sözcüklü düz-harf literal,
## (c) .tscn'de `text = "..."`, (d) tek sözcük "Onayla" biçimi (Godot sınıf adı değilse).
## Anahtarlar (nokta içeren küçük harf), yollar, biçim dizgeleri ve push_error/assert/print satırları
## serbesttir.

const TURKISH_CHARS := "çğıöşüÇĞİÖŞÜâîû"
const SKIP_CALLS := ["push_error(", "push_warning(", "assert(", "print(", "printerr(", "print_rich("]


static func violations_in_dir(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(violations_in_dir(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			var path := dir_path.path_join(file)
			out.append_array(violations_in_source(FileAccess.get_file_as_string(path), path))
	return out


static func violations_in_source(source: String, path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := source.split("\n")
	var lit_re := RegEx.new()
	lit_re.compile('"((?:[^"\\\\]|\\\\.)*)"')
	for i in lines.size():
		var line := lines[i]
		var stripped := line.strip_edges()
		if stripped.begins_with("#") or stripped.begins_with("##"):
			continue
		if path.ends_with(".tscn") and not stripped.begins_with("text ="):
			continue
		if _has_skip_call(stripped):
			continue
		var code := _strip_trailing_comment(line)
		for m in lit_re.search_all(code):
			var literal := m.get_string(1)
			if _is_player_text(literal):
				out.append("%s:%d: %s" % [path, i + 1, literal])
	return out


static func _has_skip_call(line: String) -> bool:
	for call in SKIP_CALLS:
		if line.contains(call):
			return true
	return false


static func _strip_trailing_comment(line: String) -> String:
	# Literal içinde # olabilir; basit yaklaşım: tırnak sayısı çiftken ilk # sonrasını at.
	var in_quote := false
	for i in line.length():
		var c := line[i]
		if c == '"':
			in_quote = not in_quote
		elif c == "#" and not in_quote:
			return line.substr(0, i)
	return line


static func _is_player_text(s: String) -> bool:
	if s.is_empty():
		return false
	for ch in s:
		if TURKISH_CHARS.contains(ch):
			return true
	if s.begins_with("res://") or s.begins_with("user://") or s.contains("%"):
		return false
	# Tek sözcük: yalnız "Büyük + küçük harfler" (ör. "Onayla") ve Godot sınıf adı değilse oyuncu metnidir.
	if not s.contains(" "):
		return _is_capitalised_word(s) and not ClassDB.class_exists(s)
	var words := s.split(" ", false)
	if words.size() < 2:
		return false
	for w in words:
		if not _is_plain_word(w):
			return false
	return true


static func _is_capitalised_word(s: String) -> bool:
	if s.length() < 3 or s[0] != s[0].to_upper() or s[0] == s[0].to_lower():
		return false
	for i in range(1, s.length()):
		if s[i] != s[i].to_lower() or s[i] == s[i].to_upper():
			return false
	return true


static func _is_plain_word(w: String) -> bool:
	for ch in w:
		if not (ch.to_lower() != ch.to_upper() or ch == "'" or ch == "." or ch == ","):
			return false
	return true
