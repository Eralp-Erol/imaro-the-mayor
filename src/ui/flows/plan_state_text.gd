class_name PlanStateText
extends RefCounted
## Parselin imar PLANI durumunun düz Türkçe etiketi (T-043A/D-010). SAF: `PlanStateView` (sim türetmesi,
## `SimFacade.plan_state`) -> metin. Yürürlük günü ve yoğunluk sim'den okunur; UI hiçbir şey uydurmaz.
## `untracked` (plan kavramı kapalı ya da kaynak sunmuyor: mock dahil) için metin YOKTUR ("" döner; satır gizlenir).
## "Meclis/oylama" sözcüğü yalnız sim bir oylama kaydettiğinde (`vote_ref` dolu) görünür.

## Durum etiketi; gösterilecek bir şey yoksa "". `short`: dar satırlar için ("Plansız"; açıklama ayrı satırda).
static func label(plan: PlanStateView, short: bool = false) -> String:
	if plan == null:
		return ""
	match plan.state:
		PlanStateView.STATE_UNPLANNED:
			return UiText.t(&"plan.state.unplanned_short" if short else &"plan.state.unplanned")
		PlanStateView.STATE_PROPOSED:
			if plan.vote_ref != &"" and plan.due_tick < 0:
				return UiText.t(&"plan.state.proposed_vote")
			return UiText.t(&"plan.state.proposed", {"day": plan.due_tick})
		PlanStateView.STATE_PLANNED:
			return UiText.t(&"plan.state.planned", {"zone": zone_text(plan.zone), "density": density_text(plan.density)})
		PlanStateView.STATE_REJECTED:
			if plan.rejected_tick >= 0:
				return UiText.t(&"plan.state.rejected", {"day": plan.rejected_tick})
			return UiText.t(&"plan.state.rejected_noday")
		PlanStateView.STATE_EXISTING:
			return UiText.t(&"plan.state.existing")
	return ""


static func zone_text(zone: StringName) -> String:
	if zone == &"":
		return UiText.t(&"common.unknown")
	return UiText.t(zone) if UiText.has(zone) else UiText.humanize(String(zone))


## Yoğunluk binde (‰) olarak gelir; -1 = imar varsayılanı.
static func density_text(density_pm: int) -> String:
	if density_pm < 0:
		return UiText.t(&"plan.density.default")
	return UiText.t(&"plan.density.value", {"pct": UiText.number(density_pm / 10)})


## Plansız ya da reddedilmiş (plan teklif edilebilir ve yatırımcı bu parselde inşa etmez) mi?
static func needs_plan(plan: PlanStateView) -> bool:
	return plan != null and (plan.state == PlanStateView.STATE_UNPLANNED or plan.state == PlanStateView.STATE_REJECTED)
