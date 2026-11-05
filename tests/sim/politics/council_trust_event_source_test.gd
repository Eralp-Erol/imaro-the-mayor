extends "res://tests/sim/politics/reaction_world_base.gd"
## B-080 (ADR-0011, karar B) · PE-03 `council.trust_gap` olay kaynağı meclis üyesi güvenini D-021 kesintisinden SONRA
## (`CouncilTrust.effective_trust`) okur; oy girdisi ve üye görünümüyle aynı kavram, aynı işlev (SIM-12). Yıkımsız
## koşuda kesinti tablosu yoktur: `effective_trust` özdeşliktir, kaynak ham ilişki formülüyle bit-eşit kalır.
## Beklenen değerler testte bağımsız hesaplanır (ham ilişki kaydından), `EventSources`/`CouncilTrust` çağrısı yapılmaz.
## Dünya `council_trust_test.gd` ile aynı (5 üyeli meclis; üye 1-2 ve 5 "barınan hane" kesimini temsil eder).

const MEMBERS := ["actor.council.1", "actor.council.2", "actor.council.3", "actor.council.4", "actor.council.5"]
const HOUSED := ["actor.council.1", "actor.council.2", "actor.council.5"]
const TRUST := {"enabled": true, "decision": "decision.council.displacement_trust", "cohorts": ["housed"],
	"window_days": 100, "threshold_households": 5, "drop_per_household_pm": 10, "cap_pm": 400,
	"recover_per_scan_pm": 20}


func _edit(changes: Dictionary) -> Callable:
	return func(files: Dictionary) -> void:
		files["reactions"] = _raw_reactions()
		files["reactions"]["council_trust"] = TRUST.duplicate(true).merged(changes, true)


func _road_world(changes: Dictionary = {}, expropriate: bool = true) -> PoliticsHandle:
	return _world(expropriate, _edit(changes))["handle"]


func _next_scan(h: PoliticsHandle) -> void:
	h.facade.advance(WEEK - h.state().tick % WEEK)


func _pen(h: PoliticsHandle, member: String) -> int:
	return int(pol(h).get(CouncilTrust.KEY, {}).get("penalty", {}).get(member, 0))


## Bağımsız beklenen `council.trust_gap`: ham ilişki güveninden (isteğe bağlı kesintiyle) clamp((1000 - ort) / 2).
func _expected_trust_gap(h: PoliticsHandle, with_cut: bool) -> int:
	var st := h.state()
	var player := ActorStore.protagonist_key(st, h.context.actors)
	var total := 0
	for member: String in MEMBERS:
		var relation := int(ActorStore.relation(st, h.context.actors, member, player)["trust"])
		total += clampi(relation - (_pen(h, member) if with_cut else 0), -1000, 1000)
	return clampi((1000 - total / MEMBERS.size()) / 2, 0, 1000)


func _trust_gap(h: PoliticsHandle) -> int:
	var rows := EconomyQuery.region_stats(h.state(), h.context.economy)
	return int(EventSources.compute(h.state(), h.context, rows)["council.trust_gap"])


func _pe03(h: PoliticsHandle) -> int:
	return int(pol(h)["events"]["last_pressure"].get("PE-03", -1))


func test_the_trust_gap_event_source_reads_the_trust_after_the_displacement_cut() -> void:
	var h := _road_world()
	_next_scan(h)
	assert_int(_pen(h, HOUSED[0])).override_failure_message("fikstürde kesinti olmalı").is_greater(0)
	var raw_gap := _expected_trust_gap(h, false)
	var cut_gap := _expected_trust_gap(h, true)
	assert_int(cut_gap).override_failure_message("kesinti açığı büyütmeli").is_greater(raw_gap)
	assert_int(_trust_gap(h)).override_failure_message("council.trust_gap kesintili güveni okumalı (ham %d)" % raw_gap) \
		.is_equal(cut_gap)


func test_without_a_demolition_the_trust_gap_is_the_raw_relation_formula() -> void:
	var h := _road_world({}, false)
	_next_scan(h)
	assert_bool(pol(h).has(CouncilTrust.KEY)).override_failure_message("yıkımsız koşuda kesinti durumu yok").is_false()
	assert_int(_trust_gap(h)).is_equal(_expected_trust_gap(h, false))
	var off := _road_world({"enabled": false})
	_next_scan(off)
	assert_int(_trust_gap(off)).override_failure_message("kural kapalı = ham formül").is_equal(
		_expected_trust_gap(off, false))


func test_the_pe03_pressure_rises_with_the_cut_and_returns_to_the_rule_off_value_after_recovery() -> void:
	# Güçlü kesinti (kuralın veri büyüklüğünden bağımsız). Haftalık taramada olay taraması kesinti taramasından ÖNCE
	# koşar: kesinti yazıldıktan sonraki taramada PE-03 baskısı kesintisiz koşudan büyük olur. Pencere kısa ve toparlanma
	# tam olduğundan kesinti sönünce iki koşu aynı baskıyı verir.
	var strong := {"drop_per_household_pm": 1000, "cap_pm": 1000, "window_days": 20, "recover_per_scan_pm": 1000}
	var cut := _road_world(strong)
	var off := _road_world({"enabled": false})
	_next_scan(cut)
	_next_scan(off)
	assert_int(_pen(cut, HOUSED[0])).override_failure_message("ilk taramada kesinti yazılmalı").is_greater(0)
	_next_scan(cut)
	_next_scan(off)
	assert_int(_pe03(off)).override_failure_message("PE-03 baskısı taranmalı").is_greater_equal(0)
	assert_int(_pe03(cut)).override_failure_message("kesinti PE-03 baskısını artırmalı").is_greater(_pe03(off))
	for _i in 8:
		_next_scan(cut)
		_next_scan(off)
	assert_int(_pen(cut, HOUSED[0])).override_failure_message("toparlanmış olmalı").is_equal(0)
	assert_int(_pe03(cut)).is_equal(_pe03(off))
