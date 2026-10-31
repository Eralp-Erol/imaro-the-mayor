class_name AgendaRespondHandler
extends CommandHandler
## `agenda.respond {item_id, option_id}` (T-017, political-events §8): oyuncunun gündem öğesine yanıtı. Yetki kapılı
## seçenek reddedilir (`precondition`, why = authority.locked); etkiler zamana yayılır. Komut `SimCommand`
## kataloğundadır (v1.5 isteğe bağlı ek): sözleşmede listelenen (canlı etkili, bkz. `AgendaOptions`) seçenekler
## seçilebilir; etkisiz seçenek (`defer`) `invalid_value` ile reddedilir. `EventEngine.respond` (motor) `defer`i hâlâ
## kabul eder.

const KIND := &"agenda.respond"

var _ctx: PoliticsContext


func _init(ctx: PoliticsContext) -> void:
	_ctx = ctx


func command_type() -> StringName:
	return KIND


func validate(state: GameState, params: Dictionary) -> StringName:
	return _check(state, params)["code"]


func reject_args(state: GameState, params: Dictionary) -> Dictionary:
	return _check(state, params)["args"]


func subjects(params: Dictionary) -> PackedStringArray:
	return PackedStringArray(["agenda.%d" % int(params.get("item_id", 0))])


func apply(state: GameState, params: Dictionary) -> void:
	EventEngine.respond(state, _ctx, int(params["item_id"]), str(params["option_id"]))


func _check(state: GameState, params: Dictionary) -> Dictionary:
	if typeof(params.get("item_id", null)) != TYPE_INT or typeof(params.get("option_id", null)) != TYPE_STRING \
			and typeof(params.get("option_id", null)) != TYPE_STRING_NAME:
		return {"code": &"bad_param_type", "args": {}}
	var checked := EventEngine.check_response(state, _ctx, int(params["item_id"]), str(params["option_id"]))
	if checked["code"] != &"":
		return checked
	# Sözleşmede listelenmeyen (etkisiz) seçenek komutla da seçilemez: sahte düğme de sahte yanıt da yok.
	if not AgendaOptions.has_live_effect(state, _ctx, EventEngine.item_by_id(state, int(params["item_id"])),
			str(params["option_id"])):
		return {"code": &"invalid_value", "args": {"param": "option_id", "why": AgendaOptions.REJECT_NO_EFFECT}}
	return checked
