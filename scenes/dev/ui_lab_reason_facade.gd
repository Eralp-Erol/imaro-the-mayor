class_name UiLabReasonFacade
extends MockSimFacade
## DEV/TEST: senaryo durumunu `MockSimFacade`den alır, gerekçe okumalarını elle kurulmuş kayıtlarla değiştirir
## (zincir gezinmesi ve TUTARSIZ kayıt gibi mock senaryolarında bulunmayan durumlar için). Sayılar SAHTEDİR;
## `provenance()` mock kalır (MOCK rozeti çıkar). Oyuncu UI'ında kullanılmaz.

## Dev/test: kayıtlar olduğu gibi döner (kopya yok; v1.1 uzantı alt sınıfları korunur).
var records: Array[ReasonRecord] = []


static func with_records(scenario_path: String, records_in: Array[ReasonRecord]) -> UiLabReasonFacade:
	var f := UiLabReasonFacade.new(MockScenario.load_file(scenario_path))
	f.records = records_in
	return f


## Üç halkalı zincir: grup tepkisi (1) -> yatırımcı vazgeçti (2, ebeveyn 1) -> meclis grubu tutumu (3, ebeveyn 2).
## Hepsi `parcel.1` ile ilgili; tutarlı kayıtlar (`finalize`).
static func chain_records() -> Array[ReasonRecord]:
	var out: Array[ReasonRecord] = []
	out.append(_rec(1, 4, ActorRef.make(&"group", 2, &"mock.actor.group.2"), &"decision.group.protest", 500, [
		_f(&"reason.factor.traffic_noise", 800, 500), _f(&"reason.factor.rent_pressure", 600, 500, true)],
		PackedStringArray(["parcel.1"]), []))
	out.append(_rec(2, 6, ActorRef.make(&"investor", 1, &"mock.actor.investor.1"), &"decision.investor.develop", 500, [
		_f(&"reason.factor.demand", 300, 400), _f(&"reason.factor.expected_return", 400, 300),
		_f(&"reason.factor.infrastructure_capacity", 100, 200, false, &"parcel.1"),
		_f(&"reason.factor.construction_cost", -600, 100, true)], PackedStringArray(["parcel.1"]), [1]))
	out.append(_rec(3, 9, ActorRef.make(&"council_bloc", 2, &"mock.actor.council_bloc.2"),
		&"decision.council_bloc.vote_yes", 500, [
		_f(&"reason.factor.alignment_with_mayor", -300, 500), _f(&"reason.factor.fiscal_concern", 200, 500)],
		PackedStringArray(["parcel.1", "vote.1"]), [2]))
	return out


## `base` kaydının TUTARSIZ kopyası: kayıtlı toplam etkenlerden hesaplananla uyuşmuyor ve sonuç eşikle çelişiyor.
static func corrupt(base: ReasonRecord, score_shift: int, flip_outcome: bool) -> ReasonRecord:
	var r := ReasonRecord.from_dict(base.to_dict())
	r.score += score_shift
	if flip_outcome:
		r.outcome = ReasonRecord.OUTCOME_POSITIVE if r.outcome == ReasonRecord.OUTCOME_NEGATIVE \
			else ReasonRecord.OUTCOME_NEGATIVE
	return r


func provenance() -> StringName:
	return SimContract.PROVENANCE_MOCK


func reasons_for(subject_ref: StringName) -> Array[ReasonRecord]:
	var out: Array[ReasonRecord] = []
	for r in records:
		if r.is_about(subject_ref):
			out.append(r)
	return out


func reason(reason_id: int) -> ReasonRecord:
	for r in records:
		if r.id == reason_id:
			return r
	return null


static func _rec(id: int, tick: int, actor: ActorRef, decision: StringName, threshold: int,
		factors: Array[ReasonFactor], subjects: PackedStringArray, parents: Array) -> ReasonRecord:
	var r := ReasonRecord.new()
	r.id = id
	r.tick = tick
	r.actor = actor
	r.decision_key = decision
	r.threshold = threshold
	r.factors = factors
	r.subjects = subjects
	r.parent_ids = SimContract.to_int64_array(parents)
	r.provenance = SimContract.PROVENANCE_MOCK
	return r.finalize()


static func _f(key: StringName, value: int, weight: int, estimate: bool = false,
		source: StringName = &"") -> ReasonFactor:
	var f := ReasonFactor.make(key, value, weight)
	f.is_estimate = estimate
	f.source_ref = source
	return f
