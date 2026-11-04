class_name ContractTestSupport
extends RefCounted
## tests/contracts ortak yardımcıları (test paketi değildir).

const FIXTURES := "res://tests/fixtures/"
const SCENARIO_POSITIVE := "mock_scenario_investment_positive"
const SCENARIO_DECLINED := "mock_scenario_investment_declined"
const SCENARIO_GROUPS := "mock_scenario_group_reactions"
const SCENARIO_COUNCIL := "mock_scenario_council_budget_vote"
const SCENARIO_INVALID := "mock_scenario_invalid_commands"
const ALL_SCENARIOS: Array[String] = [
	SCENARIO_POSITIVE, SCENARIO_DECLINED, SCENARIO_GROUPS, SCENARIO_COUNCIL, SCENARIO_INVALID,
]


static func scenario_path(scenario_name: String) -> String:
	return FIXTURES + scenario_name + ".json"


static func scenario(scenario_name: String) -> MockScenario:
	return MockScenario.load_file(scenario_path(scenario_name))


## Ham JSON sözlüğü (olumsuz testler bozar).
static func scenario_dict(scenario_name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(scenario_path(scenario_name)))


static func facade(scenario_name: String) -> MockSimFacade:
	return MockSimFacade.from_file(scenario_path(scenario_name))


static func ids(values: Array) -> PackedInt64Array:
	return PackedInt64Array(values)


static func observable_hash(f: SimFacade) -> String:
	return StateHash.of(SimContractChecks.observable_state(f))


## Belirli türdeki olaylar.
static func events_of(f: SimFacade, kind: StringName) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in f.events_since(0):
		if e.kind == kind:
			out.append(e)
	return out
