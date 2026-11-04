class_name TopologyTestSupport
extends RefCounted
## tests/world/topology_map ortak yardımcıları (test paketi değildir, T-028). Gerçek Ismeral modeli (100 m dünya,
## tam ağ, tam yerleşim) süreç başına bir kez üretilir ve SALT OKUNUR paylaşılır; küçük sentetik dünyalar bellekte
## kurulur.
## Q-015: kalıcı koordinat yok; her şey WorldData/WorldNetwork/T0Settlement'ten çalışma zamanında türer.

static var _full: TopologyModel = null


## Gerçek veriyle tam model (varsayılan tohum): dünya + ağ + yerleşim; süreç başına bir kez.
static func full_model() -> TopologyModel:
	if _full == null:
		_full = TopologyModel.build(WorldTestSupport.default_world(), NetworkTestSupport.default_network(),
				SettlementTestSupport.full())
	return _full


## Küçük sentetik dünya: `rows` metin satırı (üstten alta); '#' = kara (yükseklik 10 m), '.' = su (-5 m), boşluksuz.
## Kara kütlesi kimliği: '#' ana kara (1), '1'..'9' = ada (2..10, yükseklik 10 m). Bölge yok.
static func ascii_world(rows: PackedStringArray, cell: float = 100.0) -> WorldData:
	var w := WorldData.new()
	w.world_id = &"ascii_test"
	w.origin = Vector2.ZERO
	w.cell_size = cell
	w.width = rows[0].length()
	w.height = rows.size()
	w.size = Vector2(w.width - 1, w.height - 1) * cell
	w.sea_level = 0.0
	var count := w.width * w.height
	w.heights.resize(count)
	w.land_mask.resize(count)
	w.region_ids.resize(count)
	w.landmass_ids.resize(count)
	w.shore_distance.resize(count)
	for j in w.height:
		for i in w.width:
			var ch := rows[j].substr(i, 1)
			var idx := j * w.width + i
			var land := ch != "."
			w.heights[idx] = 10.0 if land else -5.0
			w.land_mask[idx] = 1 if land else 0
			w.landmass_ids[idx] = 0 if not land else (1 if ch == "#" else int(ch) + 1)
			w.shore_distance[idx] = 50.0 if land else -50.0
	return w
