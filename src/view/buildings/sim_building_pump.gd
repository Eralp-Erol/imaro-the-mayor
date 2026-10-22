class_name SimBuildingPump
extends RefCounted
## Kare başına iş dağıtıcısı: SimBuildingProjector'ın bütçeli dilimi ile BuildingView kurulumu (`set_columns`) arasında
## karar verir. `playable.gd` ve testler AYNI kuralı kullanır (düşük kare hızı davranışı test edilebilsin).
##
## Kurallar (T-040 ölçüt 10, B-002):
##  - Tick'li karede (sim zaten ağır) iş yapılmaz; yalnız projector `MAX_BEHIND_DAYS`ten fazla geride kalırsa.
##  - Diğer karelerde önce projector bütçeli dilim yürütür; pencere bu karede biterse (yeni sütunlar) görünüm AYNI
##    karede kurulur (`apply_view`): ek bir kare beklenmez. Geride kalındıkça (`backlog_ticks`) bütçe büyür (en çok
##    `MAX_SCALE`x): kuyruk bütçe sabit kalıp birikemez.

const BUDGET_US := 1200
const MAX_BEHIND_DAYS := 2
const MAX_SCALE := 6
## Tam eşitleme (yükleme sonrası tek seferlik, ~12 bin parsel okuma) kare başına bütçesi.
const FULL_SYNC_BUDGET_US := 3000

var projector: SimBuildingProjector = null
var stats: Dictionary = {"frames": 0, "view_builds": 0, "steps": 0, "behind_frames": 0}

var _seen_version: int = 0


static func create(p_projector: SimBuildingProjector) -> SimBuildingPump:
	var pump := SimBuildingPump.new()
	pump.projector = p_projector
	pump._seen_version = p_projector.version() if p_projector != null else 0
	return pump


## Görünüme verilen son sürüm (dev tam senkron yolu aynı sayaçla işaretler).
func mark_view_version(version: int) -> void:
	_seen_version = version


func view_pending() -> bool:
	return projector != null and projector.version() != _seen_version


## Bir kare. `had_tick`: bu karede sim tick'i işledi mi. `apply_view`: Callable(columns, version) görünümü kurar.
## Dönüş: {worked, view_built, stepped}.
func frame(had_tick: bool, apply_view: Callable) -> Dictionary:
	var out := {"worked": false, "view_built": false, "stepped": false}
	if projector == null:
		return out
	var full := projector.full_sync_active()
	var backlog := projector.backlog_ticks()
	var behind := backlog > MAX_BEHIND_DAYS and not full
	if had_tick and not behind:
		return out
	stats["frames"] += 1
	if behind:
		stats["behind_frames"] += 1
	var budget := FULL_SYNC_BUDGET_US if full else BUDGET_US * clampi(backlog, 1, MAX_SCALE)
	var res := projector.step(budget)
	out["stepped"] = bool(res.get("worked", false))
	if out["stepped"]:
		stats["steps"] += 1
	if view_pending():
		_seen_version = projector.version()
		apply_view.call(projector.columns(), _seen_version)
		stats["view_builds"] += 1
		out["view_built"] = true
	out["worked"] = bool(out["stepped"]) or bool(out["view_built"])
	return out
