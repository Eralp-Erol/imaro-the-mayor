class_name MockBadge
extends PanelContainer
## "MOCK" rozeti (`app.mock_badge`): gerçek sim bağlı değilken her mock değerin yanında görünür (ux-layout
## §4).
## Görünürlük facade bayrağından (`SimFacade.is_mock()`) gelir, kodla sabitlenmez.

var _label: Label = null


static func create() -> MockBadge:
	var badge := MockBadge.new()
	badge.theme_type_variation = UiTheme.V_MOCK_CHIP
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge._label = UiFactory.label(UiText.t(&"app.mock_badge"), UiTheme.V_LABEL_ON_MOCK)
	badge.add_child(badge._label)
	return badge


func apply_facade(facade: SimFacade) -> void:
	visible = facade != null and facade.is_mock()
