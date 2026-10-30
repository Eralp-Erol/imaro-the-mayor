class_name ProposalGate
extends RefCounted
## Oyuncu önerisi (imar/bütçe) için isteğe bağlı kapı (T-017, Q-014): öneri doğrudan yürürlüğe mi girer, meclis
## oylamasına mı gider? Facade katmanı siyaset sınıflarını bilmez; siyaset sistemi bu soyut kapıyı uygular ve
## `SimFacadeImpl.create(..., proposal_gate)` ile takılır. Kapı yoksa (varsayılan) önceki davranış korunur.
## Kapı komutu REDDETMEZ ve özel bina yaratmaz (CAN-03): yalnız önerinin ne zaman/nasıl yürürlüğe gireceğini belirler.


## Bu komut türü (`zoning.propose`, `budget.propose`) meclis oylamasına gider mi?
func requires_vote(_state: GameState, _command_kind: StringName) -> bool:
	return false


## Durum bağımlı ön denetim: {} geçerli; aksi halde {"code": ret kodu, "args": {...}}.
func precheck(_state: GameState, _command_kind: StringName, _params: Dictionary) -> Dictionary:
	return {}


## T-043A: bu parseli içeren, sürmekte olan imar oylamasının kimliği; yoksa 0 (UI plan durumu sorgusu; salt okunur).
func pending_vote_for_parcel(_state: GameState, _parcel_id: int) -> int:
	return 0


## Önerinin yürürlüğe girmesi yerine oylama açılır (`requires_vote` doğruysa). `delay_days`: facade yürürlük gecikmesi.
func open(_state: GameState, _command_kind: StringName, _params: Dictionary, _command_id: int,
		_delay_days: int) -> void:
	pass
