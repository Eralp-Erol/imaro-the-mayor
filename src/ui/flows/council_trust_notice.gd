class_name CouncilTrustNotice
extends RefCounted
## B-081 (D-021, SIM-12): yıkım sonrası meclis güveni düştüyse NEDENİNİ tek satırda gösterir. Veri: meclis üyeleri
## `facade.snapshot().council.blocs` (üye ActorRef), her üyenin `facade.reasons_for(üye)` kaydından son
## `decision.council.displacement_trust` kaydı; `outcome == positive` = güven kesintisi yürürlükte, `negative` =
## toparlandı. Kayıt yoksa ya da hepsi toparlandıysa metin boştur (satır gösterilmez). Sayı uydurulmaz; saf, UI durum
## tutmaz. Sim ve sözleşmeye dokunmaz.

const DECISION := &"decision.council.displacement_trust"


## Kesintisi yürürlükte olan üye sayısı (son kayıt positive).
static func affected_members(facade: SimFacade) -> int:
	var council: CouncilView = facade.snapshot().council
	var count := 0
	for bloc in council.blocs:
		if bloc.bloc == null or not bloc.bloc.is_valid():
			continue
		var latest: ReasonRecord = null
		for rec in facade.reasons_for(bloc.bloc.ref()):
			if rec.decision_key == DECISION and (latest == null or rec.id > latest.id):
				latest = rec
		if latest != null and latest.outcome == ReasonRecord.OUTCOME_POSITIVE:
			count += 1
	return count


## Şerit metni; etkilenen üye yoksa "".
static func strip_text(members: int) -> String:
	return UiText.t(&"strip.council_trust_drop", {"n": members}) if members > 0 else ""
