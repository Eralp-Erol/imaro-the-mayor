class_name EventSpec
extends RefCounted
## Olay şablonu sözlüğü (T-017, political-events §2-§3): şablon verisinin kullanabileceği KAPALI kümeler. Şablon
## yalnız bu kaynakları okur (olay -> sim bağımlılığı tek yönlü okuma + etki), yeni "sihirli" gösterge yoktur.
## Kümeler kod, sayılar ve şablonlar veridir (`data/politics/events/*.json`).

## Okunan durum kaynakları (hepsi tamsayı; EventEngine.sources üretir).
const SOURCES: Array[String] = [
	"bloc.react_tier", "bloc.G", "bloc.amp", "bloc.organizer",
	"investor.declines_recent",
	"politics.council_instability", "politics.reversals_180d", "politics.unrest", "politics.permit_delay_days",
	"council.budget_vote_failed", "council.dissent", "council.trust_gap",
	"media.published_recent", "media.newsworthiness", "media.lean_abs", "media.fact_abs",
	"service.overload_days", "service.growth_pm", "service.stress_pm",
]
const OPS: Array[String] = [">=", ">", "<=", "<", "=="]
## Etki hedefleri: yalnız mevcut sistem durumları. Desteklenmeyenler (budget.line, world.cue, council.stance_shift)
## T-014/UI/ayrı görev bağımlıdır ve yükleme hatasıdır (sessizce yok sayılmaz).
const TARGETS: Array[String] = [
	"bloc.grievance", "bloc.satisfaction", "relation.trust", "investor.political_risk", "media.tone", "council.friction",
]
const SCOPES: Array[String] = ["trigger_bloc", "trigger_topic", "beneficiary_blocs", "district", "all"]
const CURVES: Array[String] = ["step", "linear", "decay"]
const DELIVERIES: Array[String] = ["ambient", "agenda", "decision"]
## Olayın nedeni (parent_ids) kaynağı.
const CAUSES: Array[String] = ["bloc_react", "investor_decline", "council_vote", "media_story", "none"]
## Etkilenen seçici türleri.
const AFFECTED: Array[String] = ["bloc", "region", "council", "investor"]
## relation.* etkileri tek seferliktir (hafıza kuralından geçer, §4.2).
const STEP_ONLY: Array[String] = ["relation.trust"]
