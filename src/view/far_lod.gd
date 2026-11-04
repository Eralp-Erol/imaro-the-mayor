class_name FarLod
extends RefCounted
## Uzak (metro) görünümde chunk'lı katmanlar yerine TEK birleşik mesh çizme kararı (T-049 perf).
##
## Neden: Compatibility/OpenGL'de maliyet draw call başınadır (bu makinede ölçüm: ~15-20 us/çağrı; 259 yol chunk'ı
## + 152 arazi/su chunk'ı metroda ~4,3 + ~3,2 ms). Metro uzaklığında (varsayılan kamera 58 km) tüm harita zaten
## kadrajdadır; chunk'lara bölmek görünürlük ayıklaması kazandırmaz. Aynı dünya verisi, aynı köşeler: yalnız temsil.
## Karar KAMERA UZAKLIĞINDAN (script, geçiş anında tek sefer); kare başına iş yok.
##
## Histerezis: ENTER üstünde uzak mod başlar, EXIT altında biter (titreme yok). ENTER, gölge kapanma eşiğinden
## (world_preview SHADOW_MAX_CAMERA_DISTANCE_M = 30 km) bağımsızdır: uzak mesh de gölge düşürür (aynı ayar).

const ENTER_M := 24000.0
const EXIT_M := 21000.0


## Mevcut durum + kamera uzaklığından yeni durum.
static func next_state(distance_m: float, currently_far: bool) -> bool:
	if currently_far:
		return distance_m > EXIT_M
	return distance_m >= ENTER_M


## Parça dizilerini tek diziye birleştirir; köşe dizilerini `offsets[i]` kadar öteler (chunk yerel -> dünya).
## `parts`: [{vertices, normals, colors, uvs?, uv2s?, indices?}], `offsets`: Vector3 listesi.
## Çıktı: aynı anahtarlarla birleşik diziler. `indices` varsa köşe tabanına göre kaydırılır.
static func merge_parts(parts: Array, offsets: Array) -> Dictionary:
	var out := {}
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var any_uv := false
	var any_uv2 := false
	var any_idx := false
	var base := 0
	for i in parts.size():
		var p: Dictionary = parts[i]
		var verts: PackedVector3Array = p["vertices"]
		if verts.is_empty():
			continue
		# Transform3D * PackedVector3Array = ileri dönüşüm (PackedVector3Array * Transform3D TERS dönüşümdür).
		vertices.append_array(Transform3D(Basis.IDENTITY, offsets[i]) * verts)
		normals.append_array(p["normals"])
		colors.append_array(p["colors"])
		if p.has("uvs"):
			any_uv = true
			uvs.append_array(p["uvs"])
		if p.has("uv2s"):
			any_uv2 = true
			uv2s.append_array(p["uv2s"])
		if p.has("indices"):
			any_idx = true
			var src: PackedInt32Array = p["indices"]
			var n := src.size()
			var start := indices.size()
			indices.resize(start + n)
			for k in n:
				indices[start + k] = src[k] + base
		base += verts.size()
	out["vertices"] = vertices
	out["normals"] = normals
	out["colors"] = colors
	if any_uv:
		out["uvs"] = uvs
	if any_uv2:
		out["uv2s"] = uv2s
	if any_idx:
		out["indices"] = indices
	return out
