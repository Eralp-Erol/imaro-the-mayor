class_name SimSections
extends RefCounted
## Sim bölümlerinin KURULU olup olmadığı (T-022). Gerçek `SimFacadeImpl`, kurulmamış bölümü
## `snapshot.extensions["x.sim.available.<bölüm>"] = false` ile bildirir (v1.1'de tipli alan istenir).
## Mock'ta bu anahtar yoktur: bölüm, veri doluysa kurulu sayılır. UI kurulmamış bölümde "Henüz kurulmadı"
## durumu gösterir (sahte içerik/sekme yok).

enum Flag { UNKNOWN, NO, YES }

const PREFIX := "x.sim.available."
const BUDGET := &"budget"
const COUNCIL := &"council"
const GROUPS := &"groups"


static func flag(snapshot: SimSnapshot, section: StringName) -> Flag:
	var key := PREFIX + String(section)
	if snapshot == null or not snapshot.extensions.has(key):
		return Flag.UNKNOWN
	return Flag.YES if bool(snapshot.extensions[key]) else Flag.NO


static func budget_built(snapshot: SimSnapshot) -> bool:
	match flag(snapshot, BUDGET):
		Flag.NO:
			return false
		Flag.YES:
			return true
	return snapshot != null and (snapshot.budget.period > 0 or not snapshot.budget.lines.is_empty())


static func council_built(snapshot: SimSnapshot) -> bool:
	match flag(snapshot, COUNCIL):
		Flag.NO:
			return false
		Flag.YES:
			return true
	return snapshot != null and (snapshot.council.seats_total > 0 or not snapshot.council.blocs.is_empty())
