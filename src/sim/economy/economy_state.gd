class_name EconomyState
extends RefCounted
## Ekonomi çekirdeği durum düzeni (T-013): `state.systems["economy"]` içindeki sütunlar, sabitler ve salt okunur
## yardımcılar.
## Tüm kalıcı veri burada; kayda ve hash'e GameState üzerinden girer. Bu sınıf durum TUTMAZ. Düzen: design/specs/
## economy-core-v0.md §2.
##
## Parsel sütunları (indeks = `parcel_ids` içindeki konum; `parcel_ids` artan sıralı): stage (byte), use (byte),
## units (int32), owner_id (int32), land_value (int64), days_left (int32), reason_id (int64), last_code (byte),
## last_reason_tick (int32, -1 = hiç). Seyrek sözlükler (yalnız dokunulan parseller; anahtar = indeks):
## zone_seen, attention, attention_cmd, active. Bölge ve yatırımcı verisi iç sözlüklerde Packed*Array sütunlarıdır.

const KEY := "economy"
## Kayıt sürümü: durum kurulurken yazılan (`VERSION`) ve T-043B öncelik kuyruğu İLK KEZ yaratılınca yükselen
## (`VERSION_PRIORITY`). Kuyruksuz koşular 1'de kalır (t0/altın hash'ler değişmez); 1 ve 2 ikisi de geçerli okunur.
const VERSION := 1
const VERSION_PRIORITY := 2

const STAGE_VACANT := 0
const STAGE_PLANNED := 1
const STAGE_UNDER_CONSTRUCTION := 2
const STAGE_BUILT := 3
const STAGE_STALLED := 4
## T-042b (D-011): parsel bir yol tarafından ALINDI (bina yıkıldı). YALNIZ kamulaştırmada yazılır (yolsuz koşuların
## durumu/hash'i değişmez); kimlik silinmez. Boş sayılmaz: yatırımcı bakışı, imar ve kira bu parsele işlemez.
const STAGE_TAKEN := 5

## Karar sonuç kodu (`last_code` baytı ve gerekçe `code` alanı).
const CODE_NONE := 0
const CODE_APPROVED := 1
const CODE_ZONING := 2
const CODE_INFRASTRUCTURE := 3
const CODE_FINANCING := 4
const CODE_DEMAND := 5
const CODE_RETURN := 6
## T-043A (D-010): yürürlükte oyuncu planı olmayan boş parsel (`unplanned_land_enabled`). Engel kodu: imar sırasında
## `CODE_ZONING`un yerine geçer (plan yok ≠ imar yapılanmaya kapalı).
const CODE_UNPLANNED := 7
## Yatırım kararı gerekçesinin karar anahtarı (`EconomySystem._record`); durma/devam gerekçeleri
## `decision.investor.continue`.
const DEVELOP_DECISION := &"decision.investor.develop"
const CODE_NAMES: Array[StringName] = [
	&"", &"approved", &"zoning_not_buildable", &"infrastructure_exhausted", &"insufficient_financing",
	&"demand_too_low", &"return_too_low", &"zoning_unplanned",
]

const PARCEL_COLUMNS: Array[String] = [
	"parcel_ids", "stage", "use", "units", "owner_id", "land_value", "days_left", "reason_id", "last_code",
	"last_reason_tick", "next_review",
]
const REGION_COLUMNS: Array[String] = [
	"latent_hh", "growth_frac", "income_pm", "access_pm", "service_pm", "infra_cap", "res_built", "res_pipe",
	"com_built", "com_pipe",
]
const SPARSE_KEYS: Array[String] = ["zone_seen", "attention", "attention_cmd", "active"]
## T-043B: öncelik kuyruğu (parsel indeksi -> vade günü / tetikleyici komut). Yalnız ilk tetikte yaratılır; v1 kayıtta
## yok.
const PRIORITY_KEYS: Array[String] = ["priority", "priority_cmd"]
const TOTAL_KEYS: Array[String] = [
	"evaluations", "approvals", "declines", "declines_recorded", "completions", "stalls", "land_sales",
	"construction_spend", "rent_income", "capital_inflow",
]


## Ekonomi durumu (DOĞRUDAN durumun parçası: değiştirmeyin); kurulu/ilk tick geçmediyse boş sözlük.
static func data(state: GameState) -> Dictionary:
	var d: Variant = state.systems.get(KEY, null)
	return d if d is Dictionary and d.has("parcel_ids") else {}


static func is_ready(state: GameState) -> bool:
	return not data(state).is_empty()


## Parselin sütun indeksi; yoksa -1.
static func index_of(d: Dictionary, parcel_id: int) -> int:
	var ids: PackedInt64Array = d["parcel_ids"]
	var i := ids.bsearch(parcel_id)
	return i if i < ids.size() and ids[i] == parcel_id else -1


static func stage_name(stage: int) -> StringName:
	match stage:
		STAGE_PLANNED:
			return ParcelView.DEVELOPMENT_PLANNED
		STAGE_UNDER_CONSTRUCTION:
			return ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION
		STAGE_BUILT:
			return ParcelView.DEVELOPMENT_BUILT
		STAGE_STALLED:
			return ParcelView.DEVELOPMENT_STALLED
		STAGE_TAKEN:
			return ParcelView.DEVELOPMENT_TAKEN
	return ParcelView.DEVELOPMENT_VACANT


static func use_name(use: int) -> StringName:
	match use:
		EconomyConfig.USE_RESIDENTIAL:
			return &"residential"
		EconomyConfig.USE_COMMERCIAL:
			return &"commercial"
	return &""


static func use_id(use_text: StringName) -> int:
	match use_text:
		&"residential":
			return EconomyConfig.USE_RESIDENTIAL
		&"commercial":
			return EconomyConfig.USE_COMMERCIAL
	return EconomyConfig.USE_NONE


## Yatırımcı kimliği (1..n) -> aktör referansı (`actor.investor.<n>`), ad anahtarı yer tutucu.
static func investor_ref(investor_id: int) -> ActorRef:
	return ActorRef.make(&"investor", investor_id, StringName("actor.investor.%d.name" % investor_id))


## `ParcelView`'a ekonomi alanlarını yazar (facade `parcel_views` çağırır). Ekonomi kurulu değilse ya da parsel
## yoksa şablonu bırakır. Yalnız ekonomi durumunu OKUR. Sözleşme v1.1: `use/units` (proje/yapı), `progress_pm`
## (inşaat ilerlemesi ‰: `cfg` yoksa yolda olan projeler için 0), `developed_by_sim` (son karar `approved` ise: T0
## stoku karar kaydı taşımaz, `last_code` 0 kalır).
static func decorate_view(state: GameState, view: ParcelView, cfg: EconomyConfig = null) -> void:
	var d := data(state)
	if d.is_empty():
		return
	var i := index_of(d, view.id)
	if i < 0:
		return
	view.development = stage_name((d["stage"] as PackedByteArray)[i])
	if view.development == ParcelView.DEVELOPMENT_TAKEN:  # v1.5: parseli alan yol (gerekçe/iş kaydına çözülür)
		view.taken_by_command = PublicWorksState.taken_command(state, view.id)
	view.land_value = (d["land_value"] as PackedInt64Array)[i]
	var owner_id: int = (d["owner_id"] as PackedInt32Array)[i]
	if owner_id > 0:
		view.owner = investor_ref(owner_id)
	var stage: int = (d["stage"] as PackedByteArray)[i]
	var use: int = (d["use"] as PackedByteArray)[i]
	var units: int = (d["units"] as PackedInt32Array)[i]
	view.use = use_name(use)
	view.units = units
	view.developed_by_sim = stage != STAGE_VACANT and (d["last_code"] as PackedByteArray)[i] == CODE_APPROVED
	view.progress_pm = progress_pm(stage, use, units, (d["days_left"] as PackedInt32Array)[i], cfg)
	# (T-043A/T-043B: plansız boş parselde placeholder imarın gizlenmesi `EconomySystem.hides_template_zone` ile
	# facade'ta yapılır: ekonomi durumu kurulmadan önce de geçerli olmalı.)
	_decorate_decision(state, d, i, view)


## v1.2 kalıcı karar özeti (`ParcelView.decision*`): MEVCUT sütunlardan (`last_code`, `last_reason_tick`, `reason_id`)
## türer; gerekçe günlüğünün budanmasına bağlı DEĞİLDİR (yalnız `decision_reason_id` budanınca 0 olur). `last_code`
## yalnız karar KAYDEDİLİNCE değişir (ret taramalarının hepsi kaydedilmez), dolayısıyla `decision_tick` son KAYDEDİLEN
## kararın tick'idir. İmar yürürlüğe girince boş parselde sıfırlanır (`last_code = none`) => `decision` boş.
static func _decorate_decision(state: GameState, d: Dictionary, i: int, view: ParcelView) -> void:
	var code: int = (d["last_code"] as PackedByteArray)[i]
	if code == CODE_NONE or code >= CODE_NAMES.size():
		return
	view.decision = ParcelView.DECISION_APPROVED if code == CODE_APPROVED else ParcelView.DECISION_DECLINED
	view.decision_code = CODE_NAMES[code]
	view.decision_tick = (d["last_reason_tick"] as PackedInt32Array)[i]
	view.decision_reason_id = _develop_reason_id(state.reasons, (d["reason_id"] as PackedInt64Array)[i])


## `reason_id` sütunu durma/devam kararından sonra o kararın gerekçesini gösterir (ebeveyni onay gerekçesidir). Karar
## özeti HER ZAMAN yatırım kararının (`decision.investor.develop`) gerekçesini verir: ebeveyn zinciri o kayda kadar
## yürünür. Kayıt ya da zincir budanmışsa 0. Kopyasız (`ReasonLog.peek`): zincir kısadır (durma/devam sayısı kadar).
static func _develop_reason_id(reasons: ReasonLog, reason_id: int) -> int:
	var rid := reason_id
	for _step in 64:
		var rec := reasons.peek(rid)
		if rec.is_empty():
			return 0
		if rec["decision"] == DEVELOP_DECISION:
			return rid
		var parents: PackedInt64Array = rec["parent_ids"]
		if parents.is_empty():
			return 0
		rid = parents[0]
	return 0


## Aşama + kalan günden inşaat ilerlemesi ‰ (ParcelView.progress_pm): built 1000; under_construction/stalled geçen
## inşaat süresi oranı (stalled iken `days_left` donar); vacant/planned 0.
static func progress_pm(stage: int, use: int, units: int, days_left: int, cfg: EconomyConfig) -> int:
	if stage == STAGE_BUILT:
		return ParcelView.PROGRESS_FULL
	if (stage == STAGE_UNDER_CONSTRUCTION or stage == STAGE_STALLED) and cfg != null:
		return EconomyMath.construction_progress_pm(EconomyMath.construction_days(cfg, use, units), days_left)
	return 0


## Kayıtlı ekonomi verisinin biçim hatası (Türkçe metin); yoksa/geçerliyse "". `d` = `systems["economy"]`;
## `expected_parcels` >= 0 ise parsel sayısı dünyayla karşılaştırılır.
static func validate_data(d: Variant, expected_parcels: int = -1) -> String:
	if d == null:
		return ""
	if not (d is Dictionary) or not (d as Dictionary).has("parcel_ids"):
		return "durum.systems.economy sözlük değil ya da parsel sütunları yok"
	if typeof(d.get("version", null)) != TYPE_INT or int(d["version"]) < VERSION or int(d["version"]) > VERSION_PRIORITY:
		return "durum.systems.economy.version desteklenmiyor"
	var n: int = (d["parcel_ids"] as PackedInt64Array).size() if d["parcel_ids"] is PackedInt64Array else -1
	if n < 0:
		return "durum.systems.economy.parcel_ids PackedInt64Array değil"
	if expected_parcels >= 0 and n != expected_parcels:
		return "durum.systems.economy %d parsel taşıyor, dünya %d parsel (farklı dünya?)" % [n, expected_parcels]
	for column in PARCEL_COLUMNS:
		var col: Variant = d.get(column, null)
		if col == null or not (typeof(col) >= TYPE_PACKED_BYTE_ARRAY and typeof(col) <= TYPE_PACKED_STRING_ARRAY) \
				or col.size() != n:
			return "durum.systems.economy.%s eksik ya da %d uzunlukta değil" % [column, n]
	if typeof(d.get("review_cursor", null)) != TYPE_INT or int(d["review_cursor"]) < 0:
		return "durum.systems.economy.review_cursor int değil"
	for key in SPARSE_KEYS:
		if not (d.get(key, null) is Dictionary):
			return "durum.systems.economy.%s sözlük değil" % key
	for key in PRIORITY_KEYS:
		if d.has(key) and (int(d["version"]) < VERSION_PRIORITY or not (d[key] is Dictionary)):
			return "durum.systems.economy.%s sözlük değil ya da sürüm 2'den eski kayıtta" % key
	if d.has("priority") != d.has("priority_cmd"):
		return "durum.systems.economy.priority ve priority_cmd birlikte olmalı"
	var regions: Variant = d.get("regions", null)
	if not (regions is Dictionary) or not (regions.get("codes", null) is PackedStringArray):
		return "durum.systems.economy.regions.codes yok"
	var rn: int = (regions["codes"] as PackedStringArray).size()
	for column in REGION_COLUMNS:
		var col: Variant = regions.get(column, null)
		if not (col is PackedInt64Array) or col.size() != rn:
			return "durum.systems.economy.regions.%s eksik ya da %d uzunlukta değil" % [column, rn]
	var investors: Variant = d.get("investors", null)
	if not (investors is Dictionary) or not (investors.get("capital", null) is PackedInt64Array) \
			or not (investors.get("monthly_inflow", null) is PackedInt64Array):
		return "durum.systems.economy.investors.capital/monthly_inflow yok"
	if not (d.get("totals", null) is Dictionary):
		return "durum.systems.economy.totals sözlük değil"
	return ""
