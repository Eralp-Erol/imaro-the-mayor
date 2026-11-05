class_name ZoningParcelText
extends RefCounted
## İmar akışı parsel etiketleri (sanat direktörü düzeltmesi, M2): ham parsel numarası yerine oyuncunun anlayacağı
## özet. YALNIZ sim'in `ParcelView` alanları okunur: `area_m2` ve `region_code`. Yola uzaklık / komşu yol adı
## `ParcelView`/`SimFacade` sözleşmesinde YOK; uydurulmaz (gerçek veri gelirse buraya eklenir). Alan 0 ise (kaynak
## bilmiyor) alan yazılmaz, sıfır gösterilmez. Metinler `data/ui/strings.tr.json`dadır.

## Bu sayıdan çok parselde liste katlanır, özet satırı görünür.
const FOLD_MIN := 4
## Özette en çok bu kadar bölge kodu adı yazılır; fazlası "N bölge" olur.
const MAX_REGION_NAMES := 3


## Satır başlığı: "3. parsel · 420 m² · Bölge R3" (bilinmeyen parça atlanır). `view` null olabilir.
static func row_head(ordinal: int, view: ParcelView) -> String:
	var parts := PackedStringArray([UiText.t(&"zoning.parcel_ordinal", {"n": UiText.number(ordinal)})])
	if view != null:
		if view.area_m2 > 0:
			parts.append(UiText.t(&"format.area_m2", {"value": UiText.number(view.area_m2)}))
		if view.region_code != &"":
			parts.append(UiText.t(&"zoning.parcel_region", {"code": String(view.region_code)}))
	return " · ".join(parts)


## Özet: "15 parsel · toplam 1.800 m² · Bölge R1, R2". Alan/bölge bilinmiyorsa o parça düşer.
static func summary(count: int, views: Array[ParcelView]) -> String:
	var parts := PackedStringArray([UiText.t(&"zoning.municipal.summary", {"n": UiText.number(count)})])
	var total := 0
	var regions: Array[String] = []
	for v in views:
		total += v.area_m2
		var code := String(v.region_code)
		if code != "" and not regions.has(code):
			regions.append(code)
	if total > 0:
		parts.append(UiText.t(&"zoning.area_total", {"m2": UiText.number(total)}))
	regions.sort()
	if regions.size() > MAX_REGION_NAMES:
		parts.append(UiText.t(&"zoning.region_count", {"n": UiText.number(regions.size())}))
	elif not regions.is_empty():
		parts.append(UiText.t(&"zoning.region_names", {"codes": ", ".join(regions)}))
	return " · ".join(parts)


## Teklif özet cümlesindeki alan adı: az parselde "1. parsel · 420 m²" listesi, çokta `summary`.
static func area_phrase(count: int, views: Array[ParcelView]) -> String:
	if count > MAX_REGION_NAMES or views.size() != count:
		return summary(count, views)
	var parts := PackedStringArray()
	for i in views.size():
		parts.append(row_head(i + 1, views[i]))
	return ", ".join(parts)


static func folds(count: int) -> bool:
	return count >= FOLD_MIN
