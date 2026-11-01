class_name ReactionWorldBase
extends PoliticsTestBase
## tests/sim/politics ortak kamulaştırma dünyası (T-042b). Kendi başına test paketi değildir (dosya adı `_test` ile
## bitmez). Dünya köprüsü test ikizidir; koordinatlar sınanan mesafeleri belirler (yakın parsel 25 m).

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const DIAGONAL: Array[int] = [110000, 110000, 126000, 120000]
const WINDOW := 360


## Parseller 1-3 köşegenin üstünde (alınır), 6 köşegenden ~25 m uzakta (yakın, alınmaz), 4 boş ve uzak, 5 D2'de uzak.
func _views() -> Array[ParcelView]:
	var out: Array[ParcelView] = []
	var spec := [[1, P.CODE_A, Vector2(1130, 1110)], [2, P.CODE_A, Vector2(1150, 1120)],
		[3, P.CODE_A, Vector2(1170, 1130)], [4, P.CODE_A, Vector2(300, 300)], [5, P.CODE_B, Vector2(2100, 300)],
		[6, P.CODE_A, Vector2(1180, 1180)]]
	for row: Array in spec:
		var v := ParcelView.new()
		v.id = row[0]
		v.region_code = row[1]
		v.center = row[2]
		v.area_m2 = P.AREA_M2
		v.zone = P.ZONE
		v.land_value = 1000
		out.append(v)
	return out


## `edit`: ham siyaset dosyası düzenleyici (isteğe bağlı). `stock_rows`: varsayılan stok yerine konacak satırlar.
## `with_budget`: gerçek bütçe sistemi de takılır (varsayılan kapalı: mevcut testler değişmez).
## `works_config`: yol işi yapılandırması (varsayılan: gerçek `data/` dosyası; T-065 testleri yeniden iskân sayılarını
## değiştirir).
func _world(expropriate: bool = true, edit: Callable = Callable(), stock_rows: Array = [],
		with_budget: bool = false, works_config: PublicWorksConfig = null) -> Dictionary:
	var net := P.network()
	var stock := ListStockSource.create(stock_rows if not stock_rows.is_empty() else [
		{"parcel_id": 1, "use": "residential", "units": 10, "owner": 1},
		{"parcel_id": 2, "use": "residential", "units": 6, "owner": 1},
		{"parcel_id": 3, "use": "commercial", "units": 4, "owner": 1},
		{"parcel_id": 5, "use": "residential", "units": 8, "owner": 1},
		{"parcel_id": 6, "use": "residential", "units": 6, "owner": 1}])
	var source := ListParcelSource.create(&"expropriation.reaction_world", _views())
	var h := PoliticsBootstrap.create(SEED, source, E.config(P.economy_patch()), stock, config(),
		pol_valid(edit, config()) if edit.is_valid() else politics_config())
	assert_object(h).is_not_null()
	var ctx := PublicWorksContext.create(net, RoadDraftRules.new(),
		works_config if works_config != null else PublicWorksConfig.load_default())
	var fake := FakeExpropriationWorld.new(net)
	fake.take(PackedInt64Array(DIAGONAL), [1, 2, 3])
	ctx.set_expropriation(fake)
	assert_bool(h.facade.attach_public_works(ctx)).is_true()
	if with_budget:  # tick 0'da takılmalı (GOLDEN_X)
		assert_bool(h.facade.attach_budget(BudgetConfig.load_default())).is_true()
	h.facade.advance(1)
	if expropriate:
		h.facade.submit_command(SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true))
		h.facade.advance(1)
	return {"handle": h, "net": net, "fake": fake}


func _signal(h: PoliticsHandle, name: String) -> int:
	return int(pol(h)["blocs"][BLOC_HOUSED]["signals"].get(name, -1))


func _raw_reactions() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(POLITICS_DIR + "reactions.json"))
