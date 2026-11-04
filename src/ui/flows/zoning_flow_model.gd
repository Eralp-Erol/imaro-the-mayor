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
## Plan yoğunluğu (‰, imar varsayılanına göre); -1 = imar varsayılanı (komuta yazılmaz).
var density_pm: int = -1
var last_validation: CommandResult = null
var last_submit: CommandResult = null
## Tick sınırında ret: sim olayı; anında ret: komut sonucu (ikisinden biri dolu).
var refusal_event: SimEvent = null
var refusal_result: CommandResult = null
var applied_tick: int = -1
var vote_ref: StringName = &""
var vote_passed: bool = false
var reason_ids: PackedInt64Array = PackedInt64Array()
## D-018 (T-066): alan boş belediye arazisinden kuruldu (`municipal_reuse`); karışık seçim yok.
var municipal_mode: bool = false

## Parselde sim dışı (T0 stok) yapı var mı: `Callable(parcel_id: int) -> bool`. İlk günlük tick'ten önce T0 stoku
## parselleri sim'de `vacant` görünür; sahne (playable) dünya yapı verisinden bunu enjekte eder. Boş = yalnız sim.
var structure_probe: Callable = Callable()

## Gönderim anında yapılı olan parseller: gönderimden SONRA yatırımcının bu plan yüzünden diktiği yapı "mevcut yapı"
## sayılmaz (uyarı yanlış olurdu). Gönderimden önce canlı okunur.
var _structures_at_send: PackedInt64Array = PackedInt64Array()
var _route_sent: String = ""
var _facade: SimFacade = null
var _phase: Phase = Phase.PICK_AREA
var _effective_ticks: Dictionary = {}  # parsel referansı (String) -> tick


static func create(facade: SimFacade, probe: Callable = Callable()) -> ZoningFlowModel:
	var m := ZoningFlowModel.new()
	m._facade = facade
	m.structure_probe = probe
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
	if is_locked() or municipal_mode or parcel_id <= SimContract.NO_ID or parcel_ids.has(parcel_id):
		return false
	if at_parcel_limit():
		return false
	parcel_ids.append(parcel_id)
	_revalidate()
	return true


## Sim'in şu an uygun (`available`) saydığı boş belediye arazileri (kimlik sıralı). Kaynak sunmuyorsa boş.
func municipal_available_ids() -> PackedInt64Array:
	var out := PackedInt64Array()
	for land in _facade.municipal_lands():
		if land.available and land.id > SimContract.NO_ID and not out.has(land.id):
			out.append(land.id)
	out.sort()
	return out


## Uygun belediye arazisini (sim parsel üst sınırına kadar) alana ekler ve belediye arazisi kipine geçer.
## Alanda sıradan parsel varsa ya da uygun arazi yoksa false (karışık seçim yok).
func use_municipal_land() -> bool:
	if is_locked() or municipal_mode or not parcel_ids.is_empty():
		return false
	var ids := municipal_available_ids()
	if ids.is_empty():
		return false
	var limit := max_parcels()
	if limit > 0 and ids.size() > limit:
		ids = ids.slice(0, limit)
	parcel_ids = ids
	municipal_mode = true
	_revalidate()
	return true


## Alan sim üst sınırına ulaştı mı (yeni parsel eklenemez)?
func at_parcel_limit() -> bool:
	var limit := max_parcels()
	return limit > 0 and parcel_ids.size() >= limit


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
	municipal_mode = false
	_revalidate()


func choose_use(use: StringName) -> void:
	if is_locked() or parcel_ids.is_empty():
		return
	land_use = use
	_revalidate()


## Yoğunluk seçimi (T-043A): -1 = varsayılan. Yalnız yapılandırmadaki seçenekler (`density_options`) kabul edilir.
func choose_density(pm: int) -> void:
	if is_locked() or (pm >= 0 and not density_options().has(pm)):
		return
	density_pm = pm
	_revalidate()


## Yapılandırmadaki yoğunluk seçenekleri (‰; çalışma verisi, Q-024 AÇIK). Varsayılan seçenek ayrıca (-1) sunulur.
static func density_options() -> Array[int]:
	var out: Array[int] = []
	var raw: Variant = UiConfig.value("zoning.density_options_pm", [])
	if raw is Array:
		for item: Variant in raw:
			if int(item) > 0:
				out.append(int(item))
	return out


## Plan önizlemesi (`SimFacade.plan_preview`): seçili parseller + kullanım + yoğunluk için sim hesabı. Kullanım ya da
## alan yoksa null. Sayıları UI üretmez; `ok == false` ise `reason` gösterilir.
func preview() -> PlanPreviewView:
	if parcel_ids.is_empty() or land_use == &"":
		return null
	return _facade.plan_preview(parcel_ids, land_use, density_pm, -1, municipal_mode)


## Sim bayrakları (teklif üst sınırı, meclis yolu): alan/kullanım gerektirmez. Kaynak plan kavramı sunmuyorsa (mock)
## `provenance` sim değildir ve `max_parcels` 0'dır.
func plan_flags() -> PlanPreviewView:
	return _facade.plan_preview(PackedInt64Array(), &"")


## Meclis yolu açık mı? Gerçek sim bayrağı (`requires_council.zoning.propose`); yalnız kaynak sim değilse (mock/ui_lab)
## `UiPrefs` yer tutucusuna düşer. "Meclis" sözcüğü yalnız bu true iken görünür.
func council_required() -> bool:
	var pv := preview()  # seçim varsa O PLANIN kararı (D-011 Soru 4); yoksa genel bayrak
	var flags := pv if pv != null else plan_flags()
	if flags.provenance == SimContract.PROVENANCE_SIM:
		return flags.council_required
	return UiPrefs.zoning_requires_council()


## "Neden meclise gitti / gitmez" (SIM-12): plan eşikleri sim'den (`PlanPreviewView.council_min_*`), plan boyutu aynı
## önizlemeden. Eşik yoksa (kapı yok / eşik kapalı / sim değil) "". Gönderimden sonra gönderim anındaki cümle kalır.
func route_text() -> String:
	if _phase >= Phase.SENT and _route_sent != "":
		return _route_sent
	var pv := preview()
	if pv == null or pv.provenance != SimContract.PROVENANCE_SIM:
		return ""
	return _route_of(pv)


## Teklifte en çok parsel (sim `plan_max_parcels_per_proposal`); 0 = sınır bilinmiyor.
func max_parcels() -> int:
	return plan_flags().max_parcels


## Parselin plan durumu (sim türetmesi); alandaki parsellerden plansız/reddedilmiş olanların sayısı.
func plan_state_of(parcel_id: int) -> PlanStateView:
	return _facade.plan_state(parcel_id)


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
	_route_sent = route_text()
	_structures_at_send = structure_parcels()
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
	density_pm = -1
	last_validation = null
	last_submit = null
	refusal_event = null
	refusal_result = null
	applied_tick = -1
	vote_ref = &""
	vote_passed = false
	reason_ids = PackedInt64Array()
	_effective_ticks = {}
	_structures_at_send = PackedInt64Array()
	_route_sent = ""
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
	return UiText.t(&"zoning.path.council" if council_required() else &"zoning.path.direct")


## Alandaki yapılı parseller: sim aşaması `vacant` değil (planlı/inşaatta/yapılı/durmuş) YA DA enjekte sorgu
## "yapı var" der.
func structure_parcels() -> PackedInt64Array:
	var out := PackedInt64Array()
	if parcel_ids.is_empty():
		return out
	if _phase >= Phase.SENT and last_submit != null and not last_submit.is_rejected():
		return _structures_at_send
	var by_id := {}
	for v in _facade.parcel_views(parcel_ids):
		by_id[v.id] = v
	for id in parcel_ids:
		var v := by_id.get(id) as ParcelView
		# T-042b: kamulaştırılmış (yıkılmış) parselde yapı yoktur.
		var built := v != null and v.development != ParcelView.DEVELOPMENT_VACANT \
				and v.development != ParcelView.DEVELOPMENT_TAKEN
		if not built and structure_probe.is_valid():
			built = bool(structure_probe.call(id))
		if built:
			out.append(id)
	return out


## Seçili kullanım özel yatırıma izin vermiyorsa (yeşil alan) kısa not; yoksa "".
func no_private_use_note() -> String:
	if land_use == &"":
		return ""
	var raw: Variant = UiConfig.value("zoning.no_private_use", [])
	if raw is Array and (raw as Array).has(String(land_use)):
		return UiText.t(&"zoning.note.no_private_use", {"zone": UiText.t(land_use)})
	return ""


## Yapılı parsel uyarısı (imar etiketi yapıyı kaldırmaz); yapılı parsel yoksa "".
func structure_warning() -> String:
	var n := structure_parcels().size()
	if n == 0:
		return ""
	if parcel_ids.size() == 1:
		return UiText.t(&"zoning.warn.structure_one")
	return UiText.t(&"zoning.warn.structure_many", {"n": n})


func submit_label() -> String:
	return UiText.t(&"zoning.submit" if council_required() else &"zoning.submit_direct")


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
				if not structure_parcels().is_empty():
					key = &"zoning.status.effective_structure"
	var text := UiText.t(key, args) if key != &"" else ""
	if text != "" and _phase >= Phase.SENT:
		var warn := structure_warning()
		if warn != "":
			text += "\n" + warn
	return text


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

## Eşik sayıları ve plan boyutu yalnız `pv`den; yalnız karşılanan ölçüt "neden"e yazılır.
func _route_of(pv: PlanPreviewView) -> String:
	var min_p := pv.council_min_parcels
	var min_u := pv.council_min_units
	if min_p <= 0 and min_u <= 0:
		return ""
	var met := PackedStringArray()
	if min_p > 0 and parcel_ids.size() >= min_p:
		met.append(UiText.t(&"zoning.route.part_parcels",
				{"n": UiText.number(parcel_ids.size()), "min": UiText.number(min_p)}))
	if min_u > 0 and pv.ok and pv.total_units >= min_u:
		met.append(UiText.t(&"zoning.route.part_units",
				{"n": UiText.number(pv.total_units), "min": UiText.number(min_u)}))
	if pv.council_required:
		return UiText.t(&"zoning.route.large", {"why": " · ".join(met)}) if not met.is_empty() else ""
	var limits := PackedStringArray()
	if min_p > 0:
		limits.append(UiText.t(&"zoning.route.limit_parcels", {"min": UiText.number(min_p)}))
	if min_u > 0:
		limits.append(UiText.t(&"zoning.route.limit_units", {"min": UiText.number(min_u)}))
	return UiText.t(&"zoning.route.small", {"limit": " / ".join(limits)})

func _command() -> SimCommand:
	# Yeni komut türü YOK (CAN-03): mevcut `zoning.propose`, yoğunluk isteğe bağlı parametre.
	if density_pm >= 0:
		var params := {"parcel_ids": parcel_ids, "land_use": land_use, "density": density_pm}
		if municipal_mode:
			params["municipal_reuse"] = true
		return SimCommand.make(SimCommand.KIND_ZONING_PROPOSE, params)
	return SimCommand.zoning_propose(parcel_ids, land_use, municipal_mode)


func _revalidate() -> void:
	if parcel_ids.is_empty():
		municipal_mode = false
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
