class_name BudgetDraft
extends RefCounted
## Bütçe tahsis düzenleyicisinin taslağı (ux-flows-v0 §F adım 4): kalem başına +/- adımlayıcı (dokunmatik ve
## masaüstü aynı fiil). Taslak panelden AYRI yaşar: profil/yön değişince panel yeniden kurulsa da düzenleme
## kaybolmaz. Adım büyüklüğü `UiPrefs.budget_step()` (girdi granülerliği; denge değil). Komut yalnız DEĞİŞEN
## kalemleri taşır; geçerlilik (negatif, bilinmeyen kalem, bekleyen öneri) sim'in `validate_command`ıyla denetlenir.

## Son ön doğrulama ve gönderim (panel yeniden kurulsa da görünür kalır).
var last_validation: CommandResult = null
var last_submit: CommandResult = null
## Tick sınırında ret olayı (varsa); gerekçe ayrıntısı "Nedenini gör" ile açılır.
var refusal_event: SimEvent = null

var _base: Dictionary = {}  # kalem anahtarı -> yürürlükteki tutar
var _draft: Dictionary = {}  # kalem anahtarı -> taslak tutar
var _order: Array[StringName] = []


## Görünümdeki kalemlerden kurar. Yürürlükteki tutarlar değiştiyse (ör. öneri onaylandı) taslak sıfırlanır.
func sync(model: BudgetModel) -> void:
	var fresh := {}
	var order: Array[StringName] = []
	for r in model.rows:
		fresh[r.key] = r.amount
		order.append(r.key)
	if fresh != _base:
		_base = fresh
		_draft = fresh.duplicate()
		_order = order
		clear_results()


func keys() -> Array[StringName]:
	return _order


func base_amount(key: StringName) -> int:
	return int(_base.get(key, 0))


func amount(key: StringName) -> int:
	return int(_draft.get(key, 0))


func can_step_down(key: StringName) -> bool:
	return _draft.has(key) and amount(key) - UiPrefs.budget_step() >= 0


func step(key: StringName, direction: int) -> bool:
	if not _draft.has(key) or direction == 0:
		return false
	var next := amount(key) + signi(direction) * UiPrefs.budget_step()
	if next < 0:
		return false
	_draft[key] = next
	last_validation = null
	return true


func reset() -> void:
	_draft = _base.duplicate()
	last_validation = null


func clear_results() -> void:
	last_validation = null
	last_submit = null
	refusal_event = null


## Sim'in kendi olayı: gönderilen önerinin tick sınırında reddi.
func handle_event(event: SimEvent) -> void:
	if last_submit != null and last_submit.command_id > SimContract.NO_ID \
			and event.command_id == last_submit.command_id and event.kind == SimEvent.KIND_COMMAND_REJECTED:
		refusal_event = event


## Gönderildi ama komut henüz işlenmedi (apply_tick gelmedi).
func in_flight(current_tick: int) -> bool:
	return last_submit != null and not last_submit.is_rejected() and refusal_event == null \
		and current_tick < last_submit.apply_tick


func has_changes() -> bool:
	return not changed_lines().is_empty()


## Değişen kalemler: anahtar -> taslak tutar.
func changed_lines() -> Dictionary:
	var out := {}
	for key: StringName in _order:
		if amount(key) != base_amount(key):
			out[key] = amount(key)
	return out


func delta(key: StringName) -> int:
	return amount(key) - base_amount(key)


func total_delta() -> int:
	var total := 0
	for key: StringName in _order:
		total += delta(key)
	return total


func command() -> SimCommand:
	return SimCommand.budget_propose(changed_lines())
