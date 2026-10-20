class_name FlowTestSupport
extends RefCounted
## tests/ui/ T-022 ortak yardımcıları (test paketi değildir): gerçek `SimFacadeImpl` ve flow senaryoları.

const FIXTURES := "res://tests/fixtures/"
const UI_FIXTURES := "res://tests/ui/fixtures/"
const COUNCIL_BUDGET := "mock_scenario_council_budget_vote"
const ZONING_COUNCIL := "ui_mock_zoning_council"
const ZONING_COUNCIL_FAILED := "ui_mock_zoning_council_failed"
const SEED := 20261020


static func mock(scenario_name: String) -> MockSimFacade:
	var base := UI_FIXTURES if scenario_name.begins_with("ui_mock_") else FIXTURES
	return MockSimFacade.from_file(base + scenario_name + ".json")


## Gerçek sim (T-027): `parcels` parsel, hepsi `zone.residential`; bütçe/meclis/grup KURULMAMIŞ.
static func real(parcels: int = 3) -> SimFacadeImpl:
	var views: Array[ParcelView] = []
	for i in parcels:
		var v := ParcelView.new()
		v.id = i + 1
		v.region_code = &"F1"
		v.center = Vector2(100.0 * float(i), 0.0)
		v.area_m2 = 1800
		v.zone = &"zone.residential"
		v.land_value = 1000
		views.append(v)
	var source := ListParcelSource.create(&"ui.test.world", views)
	var impl := SimFacadeImpl.create(SEED, source)
	assert(impl != null, "SimFacadeImpl kurulamadı")
	return impl


## Gerçek sim + ekonomi çekirdeği (T-013): yatırımcı kararları gerekçeli, `command.N` konulu.
static func real_economy(parcels: int = 3) -> SimFacadeImpl:
	var views: Array[ParcelView] = []
	for i in parcels:
		var v := ParcelView.new()
		v.id = i + 1
		v.region_code = &"F1"
		v.center = Vector2(100.0 * float(i), 0.0)
		v.area_m2 = 1800
		v.zone = &"zone.residential"
		v.land_value = 1000
		views.append(v)
	var handle := EconomyBootstrap.create(SEED, ListParcelSource.create(&"ui.test.world", views))
	assert(handle != null, "EconomyBootstrap kurulamadı")
	return handle.facade


## Olayları imleçten sonrası için modele/panele dağıtır; yeni imleci döner.
static func pump(facade: SimFacade, cursor: int, handler: Callable) -> int:
	for e in facade.events_since(cursor):
		handler.call(e)
		cursor = e.seq
	return cursor
