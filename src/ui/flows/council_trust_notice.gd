class_name CouncilTrustNotice
extends RefCounted
## B-081 (D-021, SIM-12): yıkım sonrası meclis güveni düştüyse NEDENİNİ tek satırda gösterir. Veri: meclis üyeleri
## `facade.snapshot().council.blocs` (üye ActorRef), her üyenin `facade.reasons_for(üye)` kaydından son
## `decision.council.displacement_trust` kaydı; `outcome == positive` = güven kesintisi yürürlükte, `negative` =
## toparlandı. Kayıt yoksa ya da hepsi toparlandıysa metin boştur (satır gösterilmez). Sayı uydurulmaz; saf, UI durum
## tutmaz. Sim ve sözleşmeye dokunmaz.

const DECISION := &"decision.council.displacement_trust"


## Kesintisi yürürlükte olan üye sayısı (son kayıt positive). `snap` verilirse yeniden `snapshot()` alınmaz.
## B-042: facade hızlı yolu (`latest_reason_by_subject`, sözleşme dışı) varsa artımlı önbellekten (~0 ms), yoksa tam
## tarama; sonuç ikisinde de AYNI (`affected_members_scan` referans).
static func affected_members(facade: SimFacade, snap: SimSnapshot = null) -> int:
	if not facade.has_method(&"latest_reason_by_subject"):
		return affected_members_scan(facade, snap)
	var council: CouncilView = (snap if snap != null else facade.snapshot()).council
	var subjects := PackedStringArray()
	for bloc in council.blocs:
		if bloc.bloc != null and bloc.bloc.is_valid():
			subjects.append(String(bloc.bloc.ref()))
	var latest: Dictionary = facade.call(&"latest_reason_by_subject", DECISION, subjects)
	var count := 0
	for subject in subjects:
		var rec: ReasonRecord = latest.get(subject, null)
		if rec != null and rec.outcome == ReasonRecord.OUTCOME_POSITIVE:
			count += 1
	return count


## Tam tarama (eski yol; mock facade ve test referansı): her üyenin tüm neden kaydı.
static func affected_members_scan(facade: SimFacade, snap: SimSnapshot = null) -> int:
	var council: CouncilView = (snap if snap != null else facade.snapshot()).council
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
