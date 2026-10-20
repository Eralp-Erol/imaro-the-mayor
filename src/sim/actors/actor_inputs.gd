class_name ActorInputs
extends RefCounted
## Karar faktörlerinin ilişki/hafıza/emsal kaynakları (T-016, characters-npc §4.3): ilişki ve hafıza kararı değiştirir
## (SIM-10/SIM-11), gizli zarla değil. Dönüş değerleri `ActorDecision.decide` girdisine doğrudan verilebilir
## ({ad: {value, source_ref}}, değer -1000..1000). Duruş uzaklığı, kesim baskısı vb. durum kaynakları T-017'nindir.


## `trust_in_player` (güven), `resentment` (-kırgınlık), `obligation`; `topic_id` verilirse `topic_memory`.
## `target_key`: ilişkinin hedefi (genellikle protagonist anahtarı: `ActorStore.protagonist_key`). İlişki yoksa
## varsayılan ilişki okunur (durum değişmez).
static func relation_factors(state: GameState, config: ActorConfig, actor_key: String, target_key: String,
		topic_id: String = "") -> Dictionary:
	var rel := ActorStore.relation(state, config, actor_key, target_key)
	var out := {
		"trust_in_player": {"value": int(rel["trust"]), "source_ref": target_key},
		"resentment": {"value": -int(rel["resentment"]), "source_ref": target_key},
		"obligation": {"value": int(rel["obligation"]), "source_ref": target_key},
	}
	if not topic_id.is_empty():
		out["topic_memory"] = {"value": ActorMemory.topic_memory(state, config, actor_key, topic_id),
			"source_ref": ""}
	return out


## Emsal: aynı kararın son sonuçlarının işaret ortalaması, -1000..1000 (geçmiş yoksa 0).
@warning_ignore("integer_division")
static func precedent(state: GameState, actor_key: String, decision_id: String) -> int:
	var recent := ActorStore.recent_outcomes(state, actor_key, decision_id)
	if recent.is_empty():
		return 0
	var sum := 0
	for sign_value: int in recent:
		sum += sign_value
	return sum * SimContract.FIXED_SCALE / recent.size()
