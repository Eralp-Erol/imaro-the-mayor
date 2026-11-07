class_name SectionValidators
extends RefCounted
## Bölüm doğrulayıcı kaydı (T-078): `GameState.validate_dict` kayıttaki `systems` bölümlerini BU tablodan doğrular.
## Yeni sim bölümü kendi `validate_data(value) -> String` işlevini yazar ve `_table()`a TEK satır ekler
## (`game_state.gd` değişmez; paralel işlerde çakışma noktası bu tablodur). Kural: bölüm yoksa (null) geçerlidir
## ("takılmazsa sıfır bayt"); bozuksa Türkçe hata metni döner ve kayıt yüklenmez.
## Sıra SABİTTİR (ilk hata döner); mevcut beş bölüm T-078 öncesi zincirle aynı sırada ve aynı iletilerle doğrulanır.
## Ekonomi ve bütçe doğrulayıcıları bağlam ister (dünya parsel sayısı) ve facade yüklemesinde (`import_save`) çalışır.


## Sıralı kayıt: [{key, validate}]. Yeni bölüm: buraya bir satır.
static func _table() -> Array[Dictionary]:
	return [
		{"key": SimEventLog.SYSTEM_KEY, "validate": SimEventLog.validate_data},
		{"key": ActorStore.SYSTEM_KEY, "validate": ActorStore.validate_data},  # T-017
		{"key": PoliticsState.KEY, "validate": PoliticsState.validate_data},  # T-017
		{"key": PublicWorksState.KEY, "validate": PublicWorksState.validate_data},  # T-042: oyuncu yolu bölümü
		{"key": PolicyState.KEY, "validate": PolicyState.validate_data},  # T-065: kalıcı politika (yoksa = kapalı)
	]


## Kayıtlı bölüm anahtarları, doğrulama sırasıyla.
static func keys() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in _table():
		out.append(String(entry["key"]))
	return out


## `systems` sözlüğündeki kayıtlı bölümleri doğrular; ilk hata metni, hepsi geçerliyse "". Kayıtta olmayan bölümler
## (ör. `world`, `economy`, `budget`) bu kapıda denetlenmez.
static func validate_systems(systems: Dictionary) -> String:
	for entry in _table():
		var validate: Callable = entry["validate"]
		var error: String = validate.call(systems.get(String(entry["key"]), null))
		if not error.is_empty():
			return error
	return ""
