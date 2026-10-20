class_name MockBanner
extends PanelContainer
## Sabit MOCK bandı (`app.mock_banner`): gerçek sim bağlı değilken ekranın üstünde kalıcı görünür.
## Gizleme tek yoldan:
## `apply_facade` (facade bayrağı). Ekran görüntülerinde kalmalıdır (ux-layout §4).

var _label: Label = null


static func create() -> MockBanner:
	var banner := MockBanner.new()
	banner.theme_type_variation = UiTheme.V_MOCK_BANNER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner._label = UiFactory.label(UiText.t(&"app.mock_banner"), UiTheme.V_LABEL_ON_MOCK)
	banner._label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner._label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner._label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.add_child(banner._label)
	return banner


func apply_facade(facade: SimFacade) -> void:
	visible = facade != null and facade.is_mock()
