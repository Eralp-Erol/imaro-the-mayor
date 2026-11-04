class_name ActorScenarioSystem
extends SimSystem
## Test sistemi (T-016 entegrasyon testleri; T-017/T-013'ün yapacağının iskeleti; nesne DURUM TUTMAZ): aktör
## sisteminden SONRA kayıtlıdır, tamsayı tick aritmetiğiyle (rastgelelik yok) olay uygular ve karar verir;
## her karar için `actor.decided` olayı yayar. Test paketi değildir. `variant` 0 değilse bir ek olay ekler
## (SIM-10: farklı oyuncu, farklı sonuç).

const COUNCIL: Array[String] = ["actor.council.1", "actor.council.2", "actor.council.3", "actor.council.4",
	"actor.council.5"]
const BLOCS: Array[String] = ["actor.bloc.1", "actor.bloc.2"]
const TOPICS: Array[String] = ["housing_cost", "mobility", "fiscal_burden"]

var _config: ActorConfig
var _variant: int


func _init(config: ActorConfig, variant: int = 0) -> void:
	_config = config
	_variant = variant


func system_id() -> StringName:
	return &"actor_scenario"


func on_daily(state: GameState) -> void:
	var t := state.tick
	var player := ActorStore.protagonist_key(state, _config)
	if t % 10 == 3:
		var step := t / 10
		var event := {"topic_id": TOPICS[step % 3], "valence": -600 if step % 2 == 0 else 400, "magnitude": 700,
			"attributed_to": player, "source_ref": "command.1"}
		ActorMemory.apply_event(state, _config, COUNCIL[step % 5], event)
	if _variant != 0 and t == 20:
		ActorMemory.apply_event(state, _config, COUNCIL[0], {"topic_id": "housing_cost", "valence": -900,
			"magnitude": 1000, "attributed_to": player, "source_ref": "command.9"})
	if t % 30 == 0:
		_council_session(state, player, t / 30)
	if t % 45 == 0:
		_bloc_reactions(state, player, t)


func _council_session(state: GameState, player: String, session: int) -> void:
	for i in COUNCIL.size():
		var factors := ActorInputs.relation_factors(state, _config, COUNCIL[i], player, "housing_cost")
		factors.erase("topic_memory")
		factors["stance_distance"] = (session * 211 + i * 137) % 1400 - 700
		factors["bloc_pressure"] = {"value": (session * 97 + i * 211) % 1200 - 600, "source_ref": BLOCS[i % 2]}
		factors["lobby_pressure"] = (session * 53 + i * 29) % 400 - 200
		factors["budget_realism"] = 100
		var last := int(state.system_data(system_id()).get("last_reason", 0))
		var parents := PackedInt64Array() if last == 0 else PackedInt64Array([last])
		var result := ActorDecision.evaluate(state, _config, COUNCIL[i], "council.vote", factors,
			PackedStringArray(["vote.%d" % (session + 1)]), parents)
		_publish(state, COUNCIL[i], result, &"event.council.vote")


func _bloc_reactions(state: GameState, player: String, t: int) -> void:
	for i in BLOCS.size():
		var factors := {"grievance_level": (t * 11 + i * 400) % 1000, "satisfaction_level": (t * 7) % 500,
			"media_amplification": 300, "organizer_capacity": 400 + i * 100,
			"trust_in_player": ActorInputs.relation_factors(state, _config, BLOCS[i], player)["trust_in_player"]}
		var result := ActorDecision.evaluate(state, _config, BLOCS[i], "bloc.react", factors,
			PackedStringArray(["parcel.1"]))
		_publish(state, BLOCS[i], result, &"event.group.reacted")


func _publish(state: GameState, actor_key: String, result: Dictionary, message_key: StringName) -> void:
	if not result["ok"]:
		return
	var ids := PackedInt64Array()
	for rec: Dictionary in result["records"]:
		ids.append(rec["reason_id"])
		state.system_data(system_id())["last_reason"] = rec["reason_id"]
	SimEventLog.emit(state, &"actor.decided", message_key, PackedStringArray(), {}, ids, 0, StringName(actor_key))
