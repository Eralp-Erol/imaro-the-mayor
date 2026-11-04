# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-022 ölçüt 3/4/5 · Meclis, bütçe ve gündem MODELLERİ (saf): sim verisi -> satırlar, TAHMİN kaynağı, tutarlılık
## denetimi, bütçe taslağı, gündem türetmesi. Olumsuz varyantlar: kurulmamış bölüm, tutarsız sayılar, kilitli taslak.


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _played_council() -> MockSimFacade:
	var f := FlowTestSupport.mock(FlowTestSupport.COUNCIL_BUDGET)
	f.submit_command(SimCommand.budget_propose({&"budget.line.roads": 45000}))
	return f


# --- CouncilModel ---

func test_council_blocs_have_seat_shares_and_stance_kinds() -> void:
	var f := FlowTestSupport.mock(FlowTestSupport.COUNCIL_BUDGET)
	var m := CouncilModel.build(f.snapshot().council, 0)
	assert_int(m.blocs.size()).is_equal(2)
	assert_int(m.blocs[0].seats).is_equal(6)
	assert_int(m.blocs[0].share_permille).is_equal(545)  # 6/11
	assert_that(m.blocs[0].stance_kind()).is_equal(CouncilModel.Stance.SUPPORTIVE)
	assert_that(m.blocs[1].stance_kind()).is_equal(CouncilModel.Stance.OPPOSED)
	assert_array(Array(m.issues())).is_empty()


func test_pending_vote_expectation_comes_from_stance_and_is_marked_so() -> void:
	var f := _played_council()
	f.advance(1)  # oylama açıldı (kararlar yok)
	var m := CouncilModel.build(f.snapshot().council, f.current_tick())
	assert_int(m.pending.size()).is_equal(1)
	var e := m.pending[0].expectation
	assert_that(e.source).is_equal(CouncilModel.Source.STANCE)
	assert_int(e.yes).is_equal(6)
	assert_int(e.no).is_equal(5)
	assert_int(e.undecided).is_equal(0)
	assert_that(e.verdict).is_equal(CouncilModel.Verdict.PASS)
	assert_int(m.pending[0].days_left).is_equal(3)  # closes_tick - şimdiki tick


func test_expectation_prefers_sim_positions_over_stance() -> void:
	var council := CouncilView.new()
	council.seats_total = 10
	var b1 := CouncilBlocView.new()
	b1.seats = 6
	b1.stance = 800  # eğilim "evet" der
	var b2 := CouncilBlocView.new()
	b2.seats = 4
	b2.stance = -100
	council.blocs = [b1, b2]
	var vote := CouncilVoteView.new()
	vote.vote_id = 1
	var p1 := CouncilBlocView.new()
	p1.seats = 6
	p1.position = CouncilBlocView.POSITION_NO  # sim beklenen oy: hayır
	var p2 := CouncilBlocView.new()
	p2.seats = 4
	p2.position = CouncilBlocView.POSITION_YES
	vote.positions = [p1, p2]
	var e := CouncilModel.expectation_for(council, vote)
	assert_that(e.source).is_equal(CouncilModel.Source.POSITIONS)
	assert_int(e.yes).is_equal(4)
	assert_int(e.no).is_equal(6)
	assert_that(e.verdict).is_equal(CouncilModel.Verdict.FAIL)


func test_expectation_tie_and_unknown_and_undecided_seats() -> void:
	var council := CouncilView.new()
	council.seats_total = 10
	var vote := CouncilVoteView.new()
	assert_that(CouncilModel.expectation_for(council, vote).verdict).is_equal(CouncilModel.Verdict.UNKNOWN)
	assert_that(CouncilModel.expectation_for(council, vote).source).is_equal(CouncilModel.Source.NONE)
	var a := CouncilBlocView.new()
	a.seats = 4
	a.stance = 100
	var b := CouncilBlocView.new()
	b.seats = 4
	b.stance = -100
	var c := CouncilBlocView.new()
	c.seats = 2
	c.stance = 0
	council.blocs = [a, b, c]
	var e := CouncilModel.expectation_for(council, vote)
	assert_that(e.verdict).is_equal(CouncilModel.Verdict.TIE)
	assert_int(e.undecided).is_equal(2)


func test_resolved_vote_keeps_sim_result_and_has_no_expectation() -> void:
	var f := _played_council()
	f.advance(6)
	var m := CouncilModel.build(f.snapshot().council, f.current_tick())
	assert_int(m.pending.size()).is_equal(0)
	assert_int(m.resolved.size()).is_equal(1)
	var row := m.resolved[0]
	assert_that(row.vote.status).is_equal(CouncilVoteView.STATUS_PASSED)
	assert_int(row.vote.yes).is_equal(6)
	assert_object(row.expectation).is_null()
	assert_int(row.vote.reason_ids.size()).is_equal(2)  # oylama sonrası neden zinciri bağlantısı


func test_inconsistent_council_numbers_are_flagged() -> void:
	var council := CouncilView.new()
	council.seats_total = 11
	var b := CouncilBlocView.new()
	b.seats = 5
	council.blocs = [b]  # 5 != 11
	var vote := CouncilVoteView.new()
	vote.vote_id = 1
	vote.status = CouncilVoteView.STATUS_PASSED
	vote.yes = 9
	vote.no = 9
	council.votes = [vote]
	var issues := CouncilModel.build(council, 0).issues()
	assert_bool(issues.has("seats_mismatch")).is_true()
	assert_bool(issues.has("tally_exceeds_seats")).is_true()


# --- BudgetModel ---

func test_budget_model_reads_sim_amounts_and_shares() -> void:
	var f := FlowTestSupport.mock(FlowTestSupport.COUNCIL_BUDGET)
	var m := BudgetModel.build(f.snapshot().budget)
	assert_int(m.revenue).is_equal(120000)
	assert_int(m.balance).is_equal(30000)
	assert_int(m.expenses).is_equal(105000)
	assert_int(m.line(&"budget.line.roads").share_permille).is_equal(380)  # 40000/105000
	assert_bool(m.is_debt()).is_false()
	assert_bool(m.is_locked()).is_false()


func test_budget_debt_and_locked_status_flags() -> void:
	var v := BudgetView.new()
	v.balance = -500
	v.status = BudgetView.STATUS_PROPOSED
	var m := BudgetModel.build(v)
	assert_bool(m.is_debt()).is_true()
	assert_bool(m.is_locked()).is_true()
	assert_int(m.rows.size()).is_equal(0)  # kalem yoksa satır uydurulmaz


func test_budget_proposal_delta_after_command() -> void:
	var f := _played_council()
	f.advance(1)
	var m := BudgetModel.build(f.snapshot().budget)
	assert_that(m.status).is_equal(BudgetView.STATUS_PROPOSED)
	assert_int(m.line(&"budget.line.roads").delta()).is_equal(5000)
	assert_int(m.proposed_delta()).is_equal(5000)
	assert_bool(m.is_locked()).is_true()


# --- BudgetDraft ---

func test_draft_steps_by_configured_step_and_builds_command_from_changed_lines_only() -> void:
	var f := FlowTestSupport.mock(FlowTestSupport.COUNCIL_BUDGET)
	var d := BudgetDraft.new()
	d.sync(BudgetModel.build(f.snapshot().budget))
	assert_bool(d.has_changes()).is_false()
	UiConfig.set_override(UiPrefs.KEY_BUDGET_STEP, 500)
	assert_bool(d.step(&"budget.line.roads", 1)).is_true()
	assert_int(d.amount(&"budget.line.roads")).is_equal(40500)
	assert_int(d.delta(&"budget.line.roads")).is_equal(500)
	assert_int(d.total_delta()).is_equal(500)
	var cmd := d.command()
	assert_that(cmd.kind).is_equal(SimCommand.KIND_BUDGET_PROPOSE)
	assert_dict(cmd.params["lines"]).is_equal({&"budget.line.roads": 40500})
	assert_bool(f.validate_command(cmd).is_rejected()).is_false()


func test_draft_cannot_go_below_zero_and_unknown_lines_do_nothing() -> void:
	var v := BudgetView.new()
	v.lines = [BudgetLineView.make(&"budget.line.parks", 600)]
	var d := BudgetDraft.new()
	d.sync(BudgetModel.build(v))
	UiConfig.set_override(UiPrefs.KEY_BUDGET_STEP, 500)
	assert_bool(d.step(&"budget.line.parks", -1)).is_true()  # 100
	assert_bool(d.can_step_down(&"budget.line.parks")).is_false()
	assert_bool(d.step(&"budget.line.parks", -1)).is_false()
	assert_int(d.amount(&"budget.line.parks")).is_equal(100)
	assert_bool(d.step(&"budget.line.nope", 1)).is_false()


func test_draft_reset_and_resync_on_base_change() -> void:
	var v := BudgetView.new()
	v.lines = [BudgetLineView.make(&"budget.line.roads", 1000)]
	var d := BudgetDraft.new()
	d.sync(BudgetModel.build(v))
	d.step(&"budget.line.roads", 1)
	assert_bool(d.has_changes()).is_true()
	d.sync(BudgetModel.build(v))  # aynı taban: düzenleme korunur
	assert_bool(d.has_changes()).is_true()
	d.reset()
	assert_bool(d.has_changes()).is_false()
	d.step(&"budget.line.roads", 1)
	v.lines = [BudgetLineView.make(&"budget.line.roads", 2000)]  # öneri onaylandı: taban değişti
	d.sync(BudgetModel.build(v))
	assert_bool(d.has_changes()).is_false()
	assert_int(d.amount(&"budget.line.roads")).is_equal(2000)


func test_draft_command_of_a_locked_budget_is_rejected_by_the_sim() -> void:
	var f := _played_council()
	f.advance(1)  # öneri oylamada
	var d := BudgetDraft.new()
	d.sync(BudgetModel.build(f.snapshot().budget))
	d.step(&"budget.line.parks", 1)
	var r := f.validate_command(d.command())
	assert_bool(r.is_rejected()).is_true()
	assert_that(r.reason_key).is_equal(CommandResult.REJECT_PRECONDITION)


# --- AgendaModel ---

func test_agenda_is_derived_from_pending_votes_only_and_has_no_options() -> void:
	var f := _played_council()
	assert_int(AgendaModel.derive(f.snapshot()).size()).is_equal(0)  # henüz oylama yok
	f.advance(1)
	var items := AgendaModel.derive(f.snapshot())
	assert_int(items.size()).is_equal(1)
	assert_that(items[0].id).is_equal(&"vote.1")
	assert_int(items[0].days_left).is_equal(3)
	assert_bool(items[0].answerable()).is_false()  # v1.0: yanıt seçeneği/ertele uydurulmaz
	assert_int(AgendaModel.nearest_days(items)).is_equal(3)
	f.advance(6)
	assert_int(AgendaModel.derive(f.snapshot()).size()).is_equal(0)  # çözülen oylama gündemden çıkar


func test_agenda_source_unbuilt_on_real_sim_and_empty() -> void:
	var f := FlowTestSupport.real()
	assert_bool(AgendaModel.source_built(f.snapshot())).is_false()
	assert_int(AgendaModel.derive(f.snapshot()).size()).is_equal(0)
	assert_int(AgendaModel.nearest_days(AgendaModel.derive(f.snapshot()))).is_equal(-1)


func test_agenda_unseen_tracking() -> void:
	var f := _played_council()
	f.advance(1)
	var items := AgendaModel.derive(f.snapshot())
	assert_int(AgendaModel.unseen(items, {}).size()).is_equal(1)
	assert_int(AgendaModel.unseen(items, {&"vote.1": true}).size()).is_equal(0)


# --- SimSections ---

func test_sections_real_sim_reports_budget_and_council_unbuilt_mock_by_data() -> void:
	var real := FlowTestSupport.real().snapshot()
	assert_bool(SimSections.budget_built(real)).is_false()
	assert_bool(SimSections.council_built(real)).is_false()
	var filled := FlowTestSupport.mock(FlowTestSupport.COUNCIL_BUDGET).snapshot()
	assert_bool(SimSections.budget_built(filled)).is_true()
	assert_bool(SimSections.council_built(filled)).is_true()
	var empty := SimSnapshot.new()  # bayrak yok + veri boş
	assert_bool(SimSections.council_built(empty)).is_false()
	assert_bool(SimSections.budget_built(empty)).is_false()
	assert_bool(SimSections.council_built(null)).is_false()
	# Açık bayrak veriden önceliklidir (T-014 bütçeyi kurunca kalemsiz bile kurulu olur).
	real.extensions[SimSections.PREFIX + "budget"] = true
	assert_bool(SimSections.budget_built(real)).is_true()


func test_prefs_defaults_are_unresolved_open_questions_as_off() -> void:
	assert_bool(UiPrefs.auto_pause_agenda()).is_false()
	assert_bool(UiPrefs.zoning_requires_council()).is_false()
	UiPrefs.set_auto_pause_agenda(true)
	assert_bool(UiPrefs.auto_pause_agenda()).is_true()
	UiText.reset()
	assert_bool(UiPrefs.auto_pause_agenda()).is_false()
