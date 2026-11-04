class_name ParcelPlanning
extends RefCounted
## T-043A · Parselin PLAN DURUMU (D-010, core-loop-v0 §2): SAF, durumsuz türetme. Yeni sütun/anahtar YOKTUR; durum
## `parcels.overlay` kaydından (`ParcelZoningSystem`) ve parselin boş/yapılı olmasından çıkar. UI "Plansız / Teklif
## verildi (yürürlük gün N) / Planlı / Plan reddedildi" etiketini ve gerekçe metnini buradan (sim sorgusu:
## `EconomySystem.plan_state`) okur; durumu kendisi uydurmaz.
##
## Durumlar:
##   untracked      `decision.unplanned_land_enabled` = 0: plan kavramı kapalı (eski davranış; kaynak
##     şablon imarı geçerli)
##   unplanned      boş parsel, yürürlükte plan yok, bekleyen teklif yok: yatırımcı `zoning_unplanned` ile reddeder
##   proposed       teklif verildi (`pending_zone`), yürürlük `due_tick`'te (ya da meclis oylaması
##     sürüyor: `due_tick` -1)
##   planned        plan yürürlükte (`zone`); normal yatırımcı kararı
##   plan_rejected  meclis yolu açıkken oylama reddetti; parsel plansız kalır, yeniden teklif edilebilir
##   existing       T0 stoğundan yapılı parsel (bindirme yok): mevcut imarını korur, plan akışından etkilenmez (Q-017)

const STATE_UNTRACKED := &"untracked"
const STATE_UNPLANNED := &"unplanned"
const STATE_PROPOSED := &"proposed"
const STATE_PLANNED := &"planned"
const STATE_REJECTED := &"plan_rejected"
const STATE_EXISTING := &"existing"
const NO_TICK := -1


## `entry`: parselin bindirme kaydı ({} = yok). `vacant`: parsel boş mu (T0 stoğu/yatırımcı yapısı yok). B-022: yıkılmış
## yolun boş belediye arazisi (`STAGE_TAKEN`) da boştur ve `vacant = true` ile gelir (`EconomySystem._is_vacant` yalnız
## `STAGE_VACANT` bilir; yolun yıkıldığı bilgisi kamu işleri tarafında, `MunicipalLandFlow.is_freed`).
## `pending_vote_id` > 0: parsel için meclis oylaması sürüyor (çağıran
## `CouncilEngine.pending_vote_for_parcel` ile bulur;
## ekonomi siyaseti bilmez) => `proposed`, `due_tick` -1 (yürürlük oylamadan sonra), `vote_ref` "vote.N".
## Dönüş (hepsi düz değer): {state, zone, pending_zone, due_tick, command_id, source_ref, density, max_height_m,
## rejected_command_id, rejected_tick}. `command_id` / `source_ref` durumu doğuran komuttur (teklif ya da yürürlükteki
## plan ya da reddedilen teklif); yoksa 0 / &"". `density`/`max_height_m`: durumun plan içeriği (-1 = imar varsayılanı).
static func describe(entry: Dictionary, vacant: bool, enabled: bool, pending_vote_id: int = 0) -> Dictionary:
	var zone: StringName = entry.get("zone", &"")
	var pending: StringName = entry.get("pending_zone", &"")
	var out := {
		"state": STATE_UNTRACKED, "zone": zone, "pending_zone": pending, "due_tick": NO_TICK, "command_id": 0,
		"source_ref": &"", "density": ParcelZoningSystem.NO_VALUE, "max_height_m": ParcelZoningSystem.NO_VALUE,
		"rejected_command_id": int(entry.get("rejected_command", 0)),
		"rejected_tick": int(entry.get("rejected_tick", NO_TICK)),
		"vote_ref": &"",
	}
	if not enabled:
		return out
	if pending != &"":
		out["state"] = STATE_PROPOSED
		out["due_tick"] = int(entry.get("due_tick", NO_TICK))
		out["command_id"] = int(entry.get("command_id", 0))
		out["density"] = int(entry.get("pending_density", ParcelZoningSystem.NO_VALUE))
		out["max_height_m"] = int(entry.get("pending_max_height_m", ParcelZoningSystem.NO_VALUE))
	elif pending_vote_id > 0:
		out["state"] = STATE_PROPOSED
		out["vote_ref"] = SimContract.ref(SimContract.REF_VOTE, pending_vote_id)
	elif zone != &"":
		out["state"] = STATE_PLANNED
		out["command_id"] = int(entry.get("command_id", 0))
		out["density"] = int(entry.get("density", ParcelZoningSystem.NO_VALUE))
		out["max_height_m"] = int(entry.get("max_height_m", ParcelZoningSystem.NO_VALUE))
	elif int(entry.get("rejected_command", 0)) > 0:
		out["state"] = STATE_REJECTED
		out["command_id"] = int(entry["rejected_command"])
	elif vacant:
		out["state"] = STATE_UNPLANNED
	else:
		out["state"] = STATE_EXISTING
	if int(out["command_id"]) > 0:
		out["source_ref"] = SimContract.ref(SimContract.REF_COMMAND, int(out["command_id"]))
	return out
