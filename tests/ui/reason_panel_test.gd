extends GdUnitTestSuite
## T-021 ölçüt 1-6 · ReasonPanel, MockSimFacade ile: kayıt -> görünüm eşlemesi (beş mock senaryo), giriş noktaları,
## durumlar (yükleme/boş/hata/MOCK), neden zinciri gezinmesi, tutarsız kaydın görünürde işaretlenmesi, dokunmatik
## hedefler, erişilebilirlik (renk tek başına değil), gömülü/eksik metin.
## Olumsuz varyantlar: tutarlı kayıtta uyarı yok; kayıtsız konuda uydurma içerik yok; sim kaynaklı veride MOCK yok;
## haritada göster yalnız sahibi dinliyorsa; zincirde olmayan önceki kayıt dürüstçe "saklanmıyor".

const DECLINED := "mock_scenario_investment_declined"
const POSITIVE := "mock_scenario_investment_positive"
const GROUPS := "mock_scenario_group_reactions"
const COUNCIL := "mock_scenario_council_budget_vote"
const INVALID := "mock_scenario_invalid_commands"
const ALL_SCENARIOS := [DECLINED, POSITIVE, GROUPS, COUNCIL]
const FORBIDDEN := ["puan", "skor", "mutluluk", "₺", "lira"]


## `sim` kaynaklı (MOCK olmayan) facade: kayıtlar da sim kaynaklı.
class SimSourced:
	extends UiLabReasonFacade

	func provenance() -> StringName:
		return SimContract.PROVENANCE_SIM


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _panel(facade: SimFacade, profile_name: StringName = &"desktop",
		window: Vector2 = Vector2(440, 1200)) -> ReasonPanel:
	var ctx := UiContext.for_profile_name(profile_name)
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = window
	add_child(holder)
	auto_free(holder)
	var p := ReasonPanel.create(ctx, facade)
	holder.add_child(p)
	p.size = window
	return p


func _joined(p: ReasonPanel) -> String:
	return " | ".join(p.texts())


func _role(p: ReasonPanel, role: String) -> Control:
	var found := p.find_roles(role)
	return found[0] if not found.is_empty() else null


func _banner(p: ReasonPanel) -> Control:
	return _role(p, ReasonPanel.NAME_BANNER)


func _chain_facade() -> UiLabReasonFacade:
	return UiLabReasonFacade.with_records(UiTestSupport.FIXTURES + DECLINED + ".json",
		UiLabReasonFacade.chain_records())


func _press(b: Button) -> void:
	assert_object(b).is_not_null()
	b.pressed.emit()


# --- ölçüt 1/3: beş mock senaryoda doğru ve tutarlı görünüm ---

func test_declined_record_is_shown_with_factors_threshold_and_margin() -> void:
	var f := UiTestSupport.played(DECLINED)
	var p := _panel(f)
	p.show_reason_ids(UiTestSupport.all_reason_ids(f))
	assert_that(p.current_mode()).is_equal(ReasonPanel.MODE_DETAIL)  # tek kayıt -> doğrudan ayrıntı
	var t := _joined(p)
	for expected in ["Yatırımcı vazgeçti", "eylem gerçekleşmedi", "Etkenlerin toplamı 0,20, eşik 0,50",
			"Marj −0,30: eşiğe ulaşılmadı", "İnşaat maliyeti (tahmin)", "Altyapı kapasitesi", "Aleyhte", "Lehte",
			"Değer −0,60 × ağırlık 0,10 = −0,06", "Kaynak: Parsel 1", "Öncesinde kayıtlı bir neden yok",
			"En çok etkileyen: Talep, Beklenen getiri, İnşaat maliyeti", "Yatırımcı 1", "1. yıl, 5. gün"]:
		assert_str(t).contains(expected)
	assert_object(_banner(p)).is_null()  # tutarlı kayıt: uyarı yok
	assert_int(p.find_roles(ReasonPanel.NAME_FACTOR).size()).is_equal(4)


func test_positive_record_reports_threshold_exceeded() -> void:
	var f := UiTestSupport.played(POSITIVE)
	var p := _panel(f)
	p.show_reason_ids(UiTestSupport.all_reason_ids(f))
	var t := _joined(p)
	assert_str(t).contains("Yatırımcı yatırım yaptı")
	assert_str(t).contains("eylem gerçekleşti")
	assert_str(t).contains("Etkenlerin toplamı 0,59, eşik 0,50")
	assert_str(t).contains("Marj +0,09: eşik aşıldı")


func test_group_reactions_list_then_each_record_detail() -> void:
	var f := UiTestSupport.played(GROUPS)
	var p := _panel(f)
	p.show_reason_ids(UiTestSupport.all_reason_ids(f))
	assert_that(p.current_mode()).is_equal(ReasonPanel.MODE_LIST)
	var rows := p.named_buttons(ReasonPanel.NAME_ROW)
	assert_int(rows.size()).is_equal(2)
	assert_str(rows[0].text).contains("Grup destek verdi")
	assert_str(rows[1].text).contains("Grup protesto etti")
	_press(rows[1])
	assert_that(p.current_mode()).is_equal(ReasonPanel.MODE_DETAIL)
	var t := _joined(p)
	assert_str(t).contains("Marj +0,20: eşik aşıldı")  # 0,70 - 0,50
	assert_str(t).contains("Kira baskısı (tahmin)")
	assert_str(t).contains("Trafik gürültüsü")
	p.back()
	assert_that(p.current_mode()).is_equal(ReasonPanel.MODE_LIST)


func test_council_votes_show_both_blocs_with_their_own_margins() -> void:
	var f := UiTestSupport.played(COUNCIL)
	var p := _panel(f)
	p.show_reason_ids(UiTestSupport.all_reason_ids(f))
	var rows := p.named_buttons(ReasonPanel.NAME_ROW)
	assert_int(rows.size()).is_equal(2)
	_press(rows[0])
	assert_str(_joined(p)).contains("Meclis grubu evet oyu verdi")
	assert_str(_joined(p)).contains("Marj +0,05: eşik aşıldı")
	p.back()
	_press(p.named_buttons(ReasonPanel.NAME_ROW)[1])
	assert_str(_joined(p)).contains("Meclis grubu evet oyu vermedi")
	assert_str(_joined(p)).contains("Marj −0,55: eşiğe ulaşılmadı")


func test_rejected_command_event_shows_the_recorded_rejection_reason() -> void:
	var f := UiTestSupport.played(INVALID)
	var rejected: SimEvent = null
	for e in f.events_since(0):
		if e.kind == SimEvent.KIND_COMMAND_REJECTED:
			rejected = e
	assert_object(rejected).is_not_null()
	var p := _panel(f)
	p.show_event(rejected)
	assert_that(p.current_mode()).is_equal(ReasonPanel.MODE_REJECTION)
	var t := _joined(p)
	assert_str(t).contains("Komut kabul edilmedi")
	assert_str(t).contains("Koruma alanında imar değişikliği önerilemez")
	assert_str(t).contains("Hedef bu işlem için uygun değil")
	assert_str(t).contains("ayrı bir gerekçe kaydı vermedi")  # kayıt yoksa uydurma yok, dürüst not
	assert_bool(p.badge.visible).is_true()


func test_immediate_rejection_result_shows_reason_and_command_kind() -> void:
	var f := UiTestSupport.mock(INVALID)
	var result := f.submit_command(SimCommand.make(&"zoning.build_private_house"))
	assert_bool(result.is_rejected()).is_true()
	var p := _panel(f)
	p.show_command_result(result)
	assert_str(_joined(p)).contains("Komut kabul edilmedi")
	assert_str(_joined(p)).contains(UiText.t(result.reason_key, result.args))


func test_every_scenario_record_renders_consistent_with_direction_text_and_no_missing_strings() -> void:
	var rendered := 0
	for scenario in ALL_SCENARIOS:
		var f := UiTestSupport.played(scenario)
		var p := _panel(f)
		for id in UiTestSupport.all_reason_ids(f):
			p.show_record(id)
			rendered += 1
			var t := _joined(p).to_lower()
			assert_bool(p.badge.visible).is_true()  # mock veri her yerde işaretli
			assert_object(_banner(p)).is_null()
			for bad in FORBIDDEN:
				assert_bool(t.contains(bad)).override_failure_message(
					"yasak ifade '%s' (%s #%d)" % [bad, scenario, id]).is_false()
			# Renk tek başına anlam taşımaz: her etken satırında yön METNİ ve yön SİMGESİ vardır.
			for row in p.find_roles(ReasonPanel.NAME_FACTOR):
				var row_text := " ".join(ReasonTestSupport.labels_of(row))
				var has_direction := false
				for word in ["Lehte", "Aleyhte", "Etkisiz", "Yalnız bilgi"]:
					has_direction = has_direction or row_text.contains(word)
				assert_bool(has_direction).override_failure_message(row_text).is_true()
				assert_int(row.find_children("*", "ReasonGlyph", true, false).size()).is_equal(1)
	assert_int(rendered).is_greater_equal(6)
	assert_array(Array(UiText.missing_keys())).is_empty()  # sim anahtarlarının hepsi tabloda


# --- ölçüt 2: giriş noktaları ---

func test_subject_entry_with_one_record_opens_detail_and_with_many_opens_list() -> void:
	var f := UiTestSupport.played(GROUPS)
	var p := _panel(f)
	p.show_subject(&"parcel.2")  # iki grup kaydı aynı parselle ilgili
	assert_that(p.current_mode()).is_equal(ReasonPanel.MODE_LIST)
	assert_str(_joined(p)).contains("Parsel 2")
	assert_str(_joined(p)).contains("2 kayıt, zaman sırasıyla")
	p.show_subject(&"actor.group.2")  # tek kayıt
	assert_that(p.current_mode()).is_equal(ReasonPanel.MODE_DETAIL)
	assert_str(_joined(p)).contains("Grup protesto etti")


func test_actor_entry_works_for_an_investor() -> void:
	var f := UiTestSupport.played(DECLINED)
	var p := _panel(f)
	p.show_subject(&"actor.investor.1")
	assert_str(_joined(p)).contains("Yatırımcı vazgeçti")


func test_event_with_reason_ids_opens_those_records() -> void:
	var f := UiTestSupport.played(DECLINED)
	var event: SimEvent = null
	for e in f.events_since(0):
		if not e.reason_ids.is_empty():
			event = e
	assert_object(event).is_not_null()
	var p := _panel(f)
	p.show_event(event)
	assert_str(_joined(p)).contains("Yatırımcı vazgeçti")


func test_subject_without_records_shows_honest_empty_state_without_invented_content() -> void:
	var f := UiTestSupport.played(DECLINED)
	var p := _panel(f)
	p.show_subject(&"parcel.3")  # kayıt yok
	assert_that(p.state_view.state()).is_equal(StateView.State.EMPTY)
	assert_str(p.state_view.visible_text()).is_equal("Henüz kayıtlı gerekçe yok")
	assert_bool(p.state_view.content_visible()).is_false()
	assert_int(p.named_buttons("").size()).is_equal(0)  # uydurma gezinti/eylem düğmesi yok


func test_missing_record_id_says_it_is_no_longer_stored() -> void:
	var p := _panel(UiTestSupport.played(DECLINED))
	p.show_record(999)
	assert_that(p.state_view.state()).is_equal(StateView.State.EMPTY)
	assert_str(p.state_view.visible_text()).is_equal("Bu kayıt artık saklanmıyor")


# --- ölçüt 3: durumlar ---

func test_error_state_when_no_facade_with_retry() -> void:
	var p := _panel(null)
	p.show_subject(&"parcel.1")
	assert_that(p.state_view.state()).is_equal(StateView.State.ERROR)
	assert_str(p.state_view.visible_text()).contains("Simülasyondan veri alınamadı")
	assert_bool(p.state_view.retry_visible()).is_true()


func test_loading_and_explicit_error_states() -> void:
	var p := _panel(UiTestSupport.played(DECLINED))
	p.show_loading()
	assert_that(p.state_view.state()).is_equal(StateView.State.LOADING)
	assert_str(p.state_view.visible_text()).contains("Yükleniyor")
	p.show_error()
	assert_that(p.state_view.state()).is_equal(StateView.State.ERROR)
	assert_str(p.state_view.visible_text()).contains("Gerekçe kayıtları okunamadı")


func test_retry_replays_the_last_request() -> void:
	var f := UiTestSupport.played(DECLINED)
	var p := _panel(f)
	p.show_subject(&"parcel.1")
	p.show_error()
	p.state_view.retry_requested.emit()
	assert_that(p.state_view.state()).is_equal(StateView.State.NORMAL)
	assert_str(_joined(p)).contains("Yatırımcı vazgeçti")


func test_mock_badge_follows_facade_and_record_provenance_not_a_constant() -> void:
	var sim_record := ReasonRecord.new()
	sim_record.id = 1
	sim_record.tick = 3
	sim_record.actor = ActorRef.make(&"investor", 1)
	sim_record.decision_key = &"decision.investor.develop"
	sim_record.threshold = 100
	sim_record.subjects = PackedStringArray(["parcel.1"])
	sim_record.factors = [ReasonFactor.make(&"reason.factor.demand", 300, 1000)]
	sim_record.provenance = SimContract.PROVENANCE_SIM
	sim_record.finalize()
	var real := SimSourced.new(MockScenario.load_file(UiTestSupport.FIXTURES + DECLINED + ".json"))
	real.records = [sim_record]
	assert_bool(real.is_mock()).is_false()
	var p := _panel(real)
	p.show_record(1)
	assert_bool(p.badge.visible).is_false()  # sim kaynaklı veri: MOCK rozeti YOK
	# Facade sim olsa bile kayıt mock kaynaklıysa rozet çıkar.
	sim_record.provenance = SimContract.PROVENANCE_MOCK
	var p2 := _panel(real)
	p2.show_record(1)
	assert_bool(p2.badge.visible).is_true()
	assert_bool(_panel(UiTestSupport.played(DECLINED)).badge.visible).is_true()


