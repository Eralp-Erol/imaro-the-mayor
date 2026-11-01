class_name ReactionRehousing
extends RefCounted
## D-014 §3 (2026-11-01): "yeni ev sunulmadığı sürece tepki sürer; sunulursa hiç olmaz."
## Sim'de bunun karşılığı YOKTUR: haneler yalnız bölge toplamıdır (`latent_hh`, barınan = min(talep, biten konut));
## yerinden edilen hane `household_fate = return_to_latent` ile bölge talebinde kalır; ne hanenin "yeni ev bulması"
## ne de belediyenin "yeni ev sunması" modellenmiştir (tepki hattı `ExpropriationFlow.apply` ->
## `PublicWorksState.note_reactions` yalnız bölge başına hane sayısı yazar). Sahip yeniden iskân özelliğini ayrıca
## karara bağlayacaktır (D-015, design/specs/resettlement-social-security-v0.md).
##
## TEK GİRİŞ NOKTASI: tepkinin "bu hane yeniden yerleşti mi" kararı YALNIZ `still_unhoused`dan geçer (yerel okuma ve
## ilçe şikâyeti dahil). ŞİMDİLİK her zaman "hayır" döner (hiç kimse yeniden yerleşmiş sayılmaz): davranış değişmez.
## Gelecekte yeniden iskân politikası bayrağı/çarpanı (hanenin varlığı, ekonomik ve sosyo-politik durumu) YALNIZ
## buraya takılır. SAF ve durumsuz; rastgelelik yok.


## (Bölge, komut) satırındaki `households` yerinden edilen haneden kaçı HÂLÂ barınamıyor (tepki sayar). Şimdilik tümü.
static func still_unhoused(_region_code: String, _command_id: int, households: int) -> int:
	return households
