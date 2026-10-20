class_name UiTestSupport
extends RefCounted
## tests/ui ortak yardımcıları (test paketi değildir).

const FIXTURES := "res://tests/fixtures/"
const DECLINED := "mock_scenario_investment_declined"
const INVALID := "mock_scenario_invalid_commands"


## MOCK olmayan (provenance = sim) facade taklidi: MOCK bandı/rozetleri KAYBOLMALI (facade bayrağı ile).
class SimProvenanceStub:
	extends MockSimFacade

	func provenance() -> StringName:
		return SimContract.PROVENANCE_SIM


static func mock(scenario_name: String = DECLINED) -> MockSimFacade:
	return MockSimFacade.from_file(FIXTURES + scenario_name + ".json")


static func non_mock(scenario_name: String = DECLINED) -> SimFacade:
	var scenario := MockScenario.load_file(FIXTURES + scenario_name + ".json")
	return SimProvenanceStub.new(scenario)


static func platform(profile_name: StringName, extra: Dictionary = {}) -> PlatformProfile:
	var overrides := {"input_profile": profile_name}
	overrides.merge(extra, true)
	return PlatformProfile.from_tags(PackedStringArray(), overrides)


## Ağaçtaki görünür tüm düğmeler.
static func visible_buttons(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	_collect_buttons(root, out)
	return out


static func button_texts(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for b in visible_buttons(root):
		out.append(b.text)
	out.sort()
	return out


static func _collect_buttons(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		var b := child as Button
		if b != null and b.is_visible_in_tree():
			out.append(b)
		_collect_buttons(child, out)
