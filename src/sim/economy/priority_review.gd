class_name PriorityReview
extends RefCounted
## T-043B · Öncelikli değerlendirme kuyruğunun SAF yardımcıları (D-010 karar 1, core-loop-v0 §3): yol geometrisi, aday
## sıralama, kuyruk durumu (`state.systems["economy"]` içindeki `priority` / `priority_cmd` sözlükleri) ve vade
## anahtarları.
## Durum TUTMAZ; karar vermez (karar `EconomySystem._evaluate` = yatırımcı kararı, CAN-03). Tüm mesafeler cm^2,
## deterministik
## yuvarlama; sıralama (mesafe, parsel indeksi). Yeni durum yalnız ilk girişte yaratılır (kayıt sürümü
## `VERSION_PRIORITY`).

## Kırık çizgide segment yokken "çok uzak" mesafe (cm^2); yarıçap karesinin her zaman üstünde.
const NO_DISTANCE := 1 << 60


## Bu tick onaylanan yollar: [{pts: [[x, z]...] (cm), command_id}], onay sırasıyla. Komutlar tick sınırında, tick
## artmadan uygulanır; sistemler tick artınca çalışır: yeni yolun `tick`'i `state.tick - 1`dir.
static func new_roads(state: GameState) -> Array:
	var out: Array = []
	var section := PublicWorksState.data(state)
	if section.is_empty():
		return out
	var works: Array = section["works"]
	var first := works.size()
	while first > 0 and int((works[first - 1] as Dictionary)["tick"]) == state.tick - 1:
		first -= 1
	for k in range(first, works.size()):
		out.append({"pts": (section["ops"][k] as Dictionary)["pts_cm"],
			"command_id": int((works[k] as Dictionary)["command_id"])})
	return out


## Durumdaki tüm oyuncu yollarının nokta listeleri ([[x, z]...] cm), yol sırasıyla.
static func road_polylines(state: GameState) -> Array:
	var out: Array = []
	var section := PublicWorksState.data(state)
	if section.is_empty():
		return out
	for op: Dictionary in section["ops"]:
		out.append(op["pts_cm"])
	return out


## Noktanın (cm) tüm yollara uzaklığının karesi (cm^2, en yakın yol); yol yoksa -1.
static func dist2_to_roads(cx: int, cz: int, roads: Array) -> int:
	var best := -1
	for pts: Array in roads:
		var dist2 := dist2_to_polyline(cx, cz, pts)
		if best < 0 or dist2 < best:
			best = dist2
	return best


## Noktanın (cm) kırık çizgiye uzaklığının karesi (cm^2). Noktalar [x, z] tamsayı cm.
static func dist2_to_polyline(cx: int, cz: int, pts: Array) -> int:
	var px := float(cx)
	var pz := float(cz)
	var best := INF
	for k in range(1, pts.size()):
		var ax := float(pts[k - 1][0])
		var az := float(pts[k - 1][1])
		var dx := float(pts[k][0]) - ax
		var dz := float(pts[k][1]) - az
		var len2 := dx * dx + dz * dz
		var t := 0.0
		if len2 > 0.0:
			t = clampf(((px - ax) * dx + (pz - az) * dz) / len2, 0.0, 1.0)
		var ex := ax + t * dx - px
		var ez := az + t * dz - pz
		best = minf(best, ex * ex + ez * ez)
	return roundi(best) if best != INF else NO_DISTANCE


## Adaylar `[dist2, parsel indeksi]`, en yakın önce (eşitlikte küçük indeks). İlk `max_parcels` aday kuyruğa girer;
## kuyruğa alınmayanların `[indeks, komut]` çiftleri döner. `replace` true: aday daha önce kuyruktaysa yeni tetikleyici
## ve vadeyle değiştirilir; false: eski vade/komut korunur. Kuyruk durumu ilk girişte yaratılır, aday yoksa yazılmaz.
static func enqueue(d: Dictionary, candidates: Array, max_parcels: int, due: int, command_id: int,
		replace: bool) -> Array:
	var overflow: Array = []
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for n in candidates.size():
		var i: int = candidates[n][1]
		if n >= max_parcels:
			overflow.append([i, command_id])
			continue
		if not d.has("priority"):  # ilk giriş: durum bir kez yaratılır, bölüm sürümü yükselir
			d["priority"] = {}
			d["priority_cmd"] = {}
			d["version"] = EconomyState.VERSION_PRIORITY
		if replace or not (d["priority"] as Dictionary).has(i):
			d["priority"][i] = due
			d["priority_cmd"][i] = command_id
	return overflow


## Vadesi gelmiş girişlerin (vade, indeks) sıralı birleşik anahtarları (`index_of_key` indeksi çözer). Kuyruk
## yoksa/boşsa [].
static func due_keys(d: Dictionary, tick: int) -> Array:
	var out: Array = []
	if not d.has("priority"):
		return out
	var queue: Dictionary = d["priority"]
	for i: int in queue:
		if int(queue[i]) <= tick:
			out.append((int(queue[i]) << 32) | i)
	out.sort()
	return out


static func index_of_key(key: int) -> int:
	return key & 0xFFFFFFFF
