# gdlint:disable=max-public-methods
class_name ZoningFlowModel
extends RefCounted
## İmar değişikliği önerisi akışı: durum makinesi (ux-flows-v0 §B, T-022). Görünümden bağımsız ve testlidir.
##
## Akış: alan (parsel) -> arazi kullanımı -> `validate_command` (kuru koşu; gerekçeli ret) -> gönder ->
## olay akışında sonuç (`command.applied` / `command.rejected` / meclis oylaması / `parcel.changed`) -> "Nedenini gör".
## - Belediye bina yaratmaz, yalnız KOŞUL önerir (CAN-03); metin bunu söyler.
## - UI sonucu tahmin etmez: aşamalar yalnız sim olaylarından ilerler. `requires_council` (Q-014 AÇIK) yalnız
##   BEKLENEN yolun metnini seçer ("Meclise sun" / "Uygula"); oylama ancak sim `council.vote_opened` verirse görünür.
## - Yürürlük gecikmesi UI'da varsayılmaz: `command.applied` ile `parcel.changed` tickleri arasındaki GÖZLENEN gün
##   gösterilir (mock 1, gerçek sim `apply_delay_days`).
## Aşamalar ileri yönlüdür; sonuç aşamasındaki (EFFECTIVE/REFUSED/VOTE_FAILED) akış `reset()` ile yeniden başlar.

enum Phase {
	PICK_AREA, PICK_USE, INVALID, READY, SENT, APPLIED, VOTING, VOTE_FAILED, EFFECTIVE, REFUSED,
}

const ZONING_APPLIED_KEY := &"event.zoning.applied"

var parcel_ids: PackedInt64Array = PackedInt64Array()
var land_use: StringName = &""
var last_validation: CommandResult = null
var last_submit: CommandResult = null
## Tick sınırında ret: sim olayı; anında ret: komut sonucu (ikisinden biri dolu).
var refusal_event: SimEvent = null
var refusal_result: CommandResult = null
var applied_tick: int = -1
var vote_ref: StringName = &""
var vote_passed: bool = false
var reason_ids: PackedInt64Array = PackedInt64Array()

var _facade: SimFacade = null
var _phase: Phase = Phase.PICK_AREA
var _effective_ticks: Dictionary = {}  # parsel referansı (String) -> tick


static func create(facade: SimFacade) -> ZoningFlowModel:
	var m := ZoningFlowModel.new()
	m._facade = facade
	return m


func phase() -> Phase:
	return _phase


## 1 alan · 2 arazi kullanımı · 3 gönder · 4 sonuç.
func step_number() -> int:
	match _phase:
		Phase.PICK_AREA:
			return 1
		Phase.PICK_USE, Phase.INVALID:
			return 2
		Phase.READY:
			return 3
	return 4


static func step_count() -> int:
	return 4


func step_name_key() -> StringName:
	return [&"zoning.step.area", &"zoning.step.use", &"zoning.step.send", &"zoning.step.result"][step_number() - 1]


func is_locked() -> bool:
	return _phase >= Phase.SENT


func is_finished() -> bool:
	return _phase == Phase.EFFECTIVE or _phase == Phase.REFUSED or _phase == Phase.VOTE_FAILED


# --- Alan ve kullanım ---

func add_parcel(parcel_id: int) -> bool:
	if is_locked() or parcel_id <= SimContract.NO_ID or parcel_ids.has(parcel_id):
		return false
	parcel_ids.append(parcel_id)
	_revalidate()
	return true


func remove_parcel(parcel_id: int) -> void:
	var idx := parcel_ids.find(parcel_id)
	if is_locked() or idx < 0:
		return
	parcel_ids.remove_at(idx)
	_revalidate()


func clear_area() -> void:
	if is_locked():
		return
	parcel_ids = PackedInt64Array()
	_revalidate()


func choose_use(use: StringName) -> void:
	if is_locked() or parcel_ids.is_empty():
		return
	land_use = use
	_revalidate()


## Hazır ve geçerliyse gönderilebilir (ret edilen öneri GÖNDERİLEMEZ).
func can_send() -> bool:
	return _phase == Phase.READY


## Gönderilemiyorsa nedeni (düğme altında kalıcı metin); gönderilebiliyorsa boş.
func send_block_reason() -> String:
	match _phase:
		Phase.PICK_AREA:
			return UiText.t(&"zoning.pick_parcel")
		Phase.PICK_USE:
			return UiText.t(&"zoning.pick_use")
		Phase.INVALID:
			return UiText.t(&"zoning.validate.rejected")
		Phase.READY:
			return ""
	return UiText.t(&"zoning.queued")


func send() -> bool:
	if not can_send():
		return false
	var result := _facade.submit_command(_command())
	last_submit = result
	if result.is_rejected():
		refusal_result = result
		_phase = Phase.REFUSED
		return false
	_phase = Phase.SENT
	return true


func reset() -> void:
	land_use = &""
	last_validation = null
	last_submit = null
	refusal_event = null
	refusal_result = null
	applied_tick = -1
	vote_ref = &""
	vote_passed = false
	reason_ids = PackedInt64Array()
	_effective_ticks = {}
	_phase = Phase.PICK_USE if not parcel_ids.is_empty() else Phase.PICK_AREA


# --- Olaylar ---

func handle_event(event: SimEvent) -> void:
	if last_submit == null or last_submit.command_id <= SimContract.NO_ID or not _is_mine(event):
		return
	if is_finished():
		return
	match event.kind:
		SimEvent.KIND_COMMAND_REJECTED:
			refusal_event = event
			reason_ids = event.reason_ids
			_phase = Phase.REFUSED
		SimEvent.KIND_COMMAND_APPLIED:
			if _phase == Phase.SENT:
				applied_tick = event.tick
				_phase = Phase.APPLIED
		SimEvent.KIND_COUNCIL_VOTE_OPENED:
			vote_ref = _vote_subject(event)
			if _phase <= Phase.APPLIED:
				_phase = Phase.VOTING
		SimEvent.KIND_COUNCIL_VOTE_RESOLVED:
			_on_vote_resolved(event)
		SimEvent.KIND_PARCEL_CHANGED:
			if event.message_key == ZONING_APPLIED_KEY:
				_on_zone_changed(event)


# --- Metinler ---

func verdict_text() -> String:
	if last_validation == null:
		return ""
	if last_validation.is_rejected():
		return UiText.reject_reason(last_validation.reason_key, last_validation.args)
	return UiText.t(&"zoning.validate.ok")


func path_text() -> String:
	return UiText.t(&"zoning.path.council" if UiPrefs.zoning_requires_council() else &"zoning.path.direct")


func submit_label() -> String:
	return UiText.t(&"zoning.submit" if UiPrefs.zoning_requires_council() else &"zoning.submit_direct")


## Şimdiki aşamanın tek cümlelik durumu ("" = gösterilecek durum yok).
func status_text() -> String:
	var key: StringName = &""
	var args := {}
	var partial := effective_done() > 0 and (_phase == Phase.SENT or _phase == Phase.APPLIED)
	if partial:
		key = &"zoning.status.effective_partial"
		args = {"done": effective_done(), "total": parcel_ids.size()}
	elif _phase == Phase.REFUSED:
		var head := UiText.t(&"zoning.outcome.rejected" if refusal_event != null else &"zoning.rejected_now")
		return "%s: %s" % [head, refusal_text()]
	else:
		match _phase:
			Phase.SENT:
				key = &"zoning.status.sent"
				args = {"date": UiText.tick_date(last_submit.apply_tick)}
			Phase.APPLIED:
				key = &"zoning.status.vote_passed" if vote_passed else &"zoning.status.applied"
			Phase.VOTING:
				key = &"zoning.status.awaiting_vote"
			Phase.VOTE_FAILED:
				key = &"zoning.status.vote_failed"
			Phase.EFFECTIVE:
				key = &"zoning.status.effective"
				args = {"days": effective_days()}
	return UiText.t(key, args) if key != &"" else ""


func refusal_text() -> String:
	if refusal_event != null:
		return UiText.reject_reason(refusal_event.message_key, refusal_event.args)
	if refusal_result != null:
		return UiText.reject_reason(refusal_result.reason_key, refusal_result.args)
	return ""


## "Nedenini gör" yalnız bir gerekçe/ret varsa.
func can_open_reason() -> bool:
	return _phase == Phase.REFUSED or not reason_ids.is_empty() or _phase == Phase.VOTE_FAILED


# --- Yürürlük ölçümü ---

func effective_done() -> int:
	var done := 0
	for id in parcel_ids:
		if _effective_ticks.has(String(SimContract.parcel_ref(id))):
			done += 1
	return done


## Komut işlendikten yürürlüğe kadar GÖZLENEN gün (tüm parseller yürürlükteyse, son değişikliğe göre).
func effective_days() -> int:
	if _phase != Phase.EFFECTIVE:
		return 0
	var last := 0
	for tick: int in _effective_ticks.values():
		last = maxi(last, tick)
	return maxi(0, last - maxi(applied_tick, 0))


func command() -> SimCommand:
	return _command()


# --- İç ---

func _command() -> SimCommand:
	return SimCommand.zoning_propose(parcel_ids, land_use)


func _revalidate() -> void:
	if parcel_ids.is_empty():
		last_validation = null
		_phase = Phase.PICK_AREA
		return
	if land_use == &"":
		last_validation = null
		_phase = Phase.PICK_USE
		return
	last_validation = _facade.validate_command(_command())
	_phase = Phase.INVALID if last_validation.is_rejected() else Phase.READY


func _is_mine(event: SimEvent) -> bool:
	if event.command_id == last_submit.command_id:
		return true
	return event.subjects.has(String(SimContract.ref(SimContract.REF_COMMAND, last_submit.command_id)))


func _vote_subject(event: SimEvent) -> StringName:
	for s in event.subjects:
		if s.begins_with("vote."):
			return StringName(s)
	return &""


func _on_vote_resolved(event: SimEvent) -> void:
	var resolved_ref := _vote_subject(event)
	if resolved_ref != &"":
		vote_ref = resolved_ref
	var parsed := SimContract.parse_ref(vote_ref)
	var vote := _facade.snapshot().council.vote(int(parsed["id"]))
	reason_ids = event.reason_ids
	if vote != null and vote.status == CouncilVoteView.STATUS_FAILED:
		_phase = Phase.VOTE_FAILED
	elif vote != null and vote.status == CouncilVoteView.STATUS_PASSED:
		vote_passed = true
		if _phase <= Phase.VOTING:
			_phase = Phase.APPLIED


func _on_zone_changed(event: SimEvent) -> void:
	for s in event.subjects:
		if parcel_ids.has(int(SimContract.parse_ref(StringName(s))["id"])) and s.begins_with("parcel."):
			_effective_ticks[s] = event.tick
	if effective_done() == parcel_ids.size() and _phase >= Phase.SENT:
		_phase = Phase.EFFECTIVE
