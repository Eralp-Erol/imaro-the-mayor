# gdlint:disable=max-public-methods
@abstract
class_name SimFacade
extends RefCounted
## View/UI'nin simülasyona TEK kapısı (ADR-0005, ADR-0002 §1). Soyut: gerçek uygulama `SimFacadeImpl` (T-027, sim
## hattı), geliştirme/test uygulaması `MockSimFacade`. Bir uygulama metodu atlarsa `@abstract` ayrıştırma hatası verir.
##
## Kurallar (tüm uygulamalar):
## - Okuma metodları DEĞER kopyası döner (DTO); çağıranın değiştirmesi sim durumunu etkilemez.
## - Okumalar tick SINIRINDAKİ tutarlı durumu gösterir (sim iş parçacığında koşsa da yarım tick görünmez).
## - Yazma yalnız komutla (`submit_command`); komut sonraki tick sınırında uygulanır. Doğrudan durum yazma yok.
## - Ana iş parçacığından çağrılır. Sinyal yok: tüketici `current_tick()`/`last_event_seq()` değişimini yoklar.
## - Metin yok: tüm görünen metinler anahtardır. Para birimsiz tamsayıdır (Q-003).
## - `provenance() != SimContract.PROVENANCE_SIM` ise UI her yüzeyi "MOCK" olarak işaretler.

const SPEED_PAUSED := 0
const SPEED_NORMAL := 1
const SPEED_FAST := 2
const SPEED_FASTEST := 3

## `sim_developed_parcel_ids()` varsayılan yolunun tek okumada aldığı parsel sayısı.
const DEVELOPED_SCAN_CHUNK := 400


## Bu uygulamanın konuştuğu sözleşme sürümü (`SimContract.VERSION`).
func contract_version() -> String:
	return SimContract.VERSION


func is_mock() -> bool:
	return provenance() != SimContract.PROVENANCE_SIM


## `SimContract.PROVENANCE_SIM` ya da `SimContract.PROVENANCE_MOCK`.
@abstract func provenance() -> StringName


@abstract func current_tick() -> int


## Hız seviyesi (SPEED_*). Hız sim durumu değildir; tick sürücüsü (src/app) okur.
@abstract func speed() -> int


## Bu oturumda/platform profilinde izin verilen seviyeler, artan (her zaman SPEED_PAUSED içerir).
@abstract func available_speeds() -> PackedInt32Array


## İzinli değilse false döner ve hızı değiştirmez.
@abstract func set_speed(level: int) -> bool


## `ticks` tick ilerletir, ilerletilen tick sayısını döner. YALNIZ tick sürücüsü (src/app) ve testler çağırır;
## UI çağırmaz. Gerçek uygulama iş parçacığı/kare dilimleme kullanıyorsa bu senkron yol testler içindir.
@abstract func advance(ticks: int) -> int


## Kuru doğrulama: durum değişmez, kuyruğa girmez. `valid` ya da gerekçeli `rejected` (UI ön izleme/onay düğmesi).
@abstract func validate_command(command: SimCommand) -> CommandResult


## `queued` (command_id > 0, apply_tick = current_tick + 1) ya da gerekçeli `rejected` (command_id = 0).
@abstract func submit_command(command: SimCommand) -> CommandResult


@abstract func snapshot() -> SimSnapshot


## Parsel kimlikleri, artan; `region_code` boşsa tümü. Ölçekte bölge filtresi kullanılır.
@abstract func parcel_ids(region_code: StringName = &"") -> PackedInt64Array


## Bilinmeyen kimlikler atlanır; sonuç istenen sırada.
@abstract func parcel_views(ids: PackedInt64Array) -> Array[ParcelView]


## `seq > after_seq` olaylar, artan; `max_count > 0` ise en fazla o kadar (en eskiler). Saklama sınırlı olabilir:
## `after_seq < first_retained_event_seq() - 1` ise arada kayıp vardır (tüketici tam snapshot ile yeniden eşitlenir).
@abstract func events_since(after_seq: int, max_count: int = 0) -> Array[SimEvent]


## Yayımlanmış son olay sırası (hiç yoksa 0).
@abstract func last_event_seq() -> int


## Hâlâ saklanan en eski olay sırası (hiç olay yoksa last_event_seq() + 1).
@abstract func first_retained_event_seq() -> int


## Bir varlıkla ilgili gerekçeler (aktör ya da `subjects` eşleşmesi), id artan (= kronolojik).
## `subject_ref` örnekleri: `parcel.12`, `actor.investor.3`, `vote.1`, `command.7`.
@abstract func reasons_for(subject_ref: StringName) -> Array[ReasonRecord]


## Kimlikle gerekçe; yoksa null.
@abstract func reason(reason_id: int) -> ReasonRecord


## v1.1 (M2) · Ölçülebilir ekonomik sonuç özeti (bölge kohortları, yeni tamamlanan birimler, kümülatif sayaçlar).
## Varsayılan: kaynak ekonomi sunmuyorsa `available == false` (mock dahil); uygulama geçersiz kılar. Okuma değer
## kopyasıdır ve sim durumunu DEĞİŞTİRMEZ; önce/sonra farkı için iki okumanın `delta_since`'ı.
func economy_outcome() -> EconomyOutcomeView:
	return EconomyOutcomeView.unavailable(provenance(), current_tick())


## v1.2 (T-045) · `tick`ten SONRA değişen parsellerin kimlikleri (O(değişen)); olay/gerekçe saklama ufkundan BAĞIMSIZ.
## Semantik, tüketici protokolü ve kapsam: `ParcelChangeFeed`. Varsayılan (kaynak değişimi izlemiyorsa): `complete ==
## false` + boş `ids` -> tüketici her seferinde tam eşitler. Değer kopyası; sim durumunu DEĞİŞTİRMEZ.
func parcel_changes_since(_tick: int) -> ParcelChangeFeed:
	return ParcelChangeFeed.incomplete(provenance(), current_tick())


## v1.10 (B-052, ADR-0011; ADR-0005 Ek M) · `ParcelView.developed_by_sim == true` olan TÜM parsellerin kimlikleri,
## artan ve tekrarsız (T0 olan/olmayan ayrımı yok; planlı/inşaatta/yapıldı/durmuş hepsi). Görünümün "sim yapısı" satır
## kümesidir: yükleme sonrası tam eşitleme tüm parselleri değil yalnız bunları okur. Değer kopyası; sim durumunu
## DEĞİŞTİRMEZ. Varsayılan DOĞRUDUR ama yavaştır (`parcel_ids` + dilimli `parcel_views` süzgeci): mock ve eski
## uygulamalar doğru sonuç verir; `SimFacadeImpl` hızlı yolu ezer.
func sim_developed_parcel_ids() -> PackedInt64Array:
	var out := PackedInt64Array()
	var all := parcel_ids()
	var pos := 0
	while pos < all.size():
		var chunk := all.slice(pos, mini(pos + DEVELOPED_SCAN_CHUNK, all.size()))
		pos += chunk.size()
		for v in parcel_views(chunk):
			if v.developed_by_sim:
				out.append(v.id)
	return out


## v1.3 (T-042) · Ağa eklenmiş oyuncu yolları, eskiden yeniye (son eleman = geri alınabilecek yol). Değer kopyası; sim
## durumunu DEĞİŞTİRMEZ. Gerekçedeki `source_ref = command.N` bu listedeki `command_id`ye çözülür (T-041 denetçisi
## "Altyapı kapasitesi <- Yol (gün N)" yazar). Varsayılan: kaynak yol sunmuyorsa boş.
func public_works() -> Array[PublicWorkView]:
	return []


## v1.8 (T-066, D-018): yeni imar kararı için belediye arazileri ve gerçek dünya uygunluğu.
## Salt okunur değer kopyaları. Bu kaynağı sunmayan facade (mock dahil) boş döner.
func municipal_lands() -> Array[MunicipalLandView]:
	return []


## v1.6 (T-042c, D-014 §1) · KLASİK GERİ AL açık mı? Başka bir yol/yıkım yapılana, geri alınana ya da
## o yolun halk tepkisi siyaset taramasına girene kadar en son yol geri alınabilir (`public_work.undo_last`). Ret nedeni
## ve ön izleme için `validate_command(SimCommand.public_work_undo_last())`
## (`public_work.reject.undo_window_closed`, `args.cause`). Salt okunur.
## Varsayılan: false (kaynak geri alma sunmuyorsa).
func undo_available() -> bool:
	return false


## v1.6 (T-042c, D-014 §1) · Yolu YIKMA maliyeti (gösterge, bütçe kısıtı yok; değer veri/config'te):
## `command_id` = `PublicWorkView.command_id`. Dönüş: maliyet birimi (>= 0) ya da -1 (yol yok/yıkılamaz/maliyet henüz
## kurulu değil). Ayrıntı ve ret nedeni için `validate_command(SimCommand.public_work_demolish(command_id))`.
## Salt okunur. Varsayılan: -1.
func demolish_cost(_command_id: int) -> int:
	return -1


## v1.7 (T-065, D-016) · Belediyenin kalıcı politikaları ve güncel durumları (şimdilik yalnız `resettlement`), kimlik
## sıralı. Politika `policy.set` komutuyla değişir; hiç değiştirilmediyse kapalıdır (`changed_tick == -1`). Salt okunur,
## değer kopyası. Varsayılan (kaynak politika sunmuyorsa): boş (uydurma satır yok). Uygulama geçersiz kılar.
func policies() -> Array[PolicyView]:
	return []


## v1.5 (T-042b, isteğe bağlı ek) · Sim'in açtığı AÇIK gündem öğeleri (olay motoru; PE-01 yerinden edilme dahil), kimlik
## artan. Meclis oylamaları burada değil, `snapshot().council` içindedir. Değer kopyası; sim durumunu DEĞİŞTİRMEZ.
## Varsayılan (kaynak olay sistemi sunmuyorsa): boş (uydurma öğe yok). Uygulama geçersiz kılar.
func agenda_items() -> Array[AgendaItemView]:
	return []


## v1.4 (T-043A, D-010) · Parselin imar PLANI durumu (Plansız / Teklif verildi / Planlı / ...). Salt okunur, değer
## kopyası. Varsayılan (kaynak plan kavramı sunmuyorsa, mock dahil): `untracked`. Uygulama geçersiz kılar.
func plan_state(parcel_id: int) -> PlanStateView:
	var v := PlanStateView.new()
	v.provenance = provenance()
	v.parcel_id = parcel_id
	return v


## v1.4 (T-043A, D-010) · İmar planı önizlemesi: seçili parsellere `land_use` teklif edilirse yatırımcının kullanacağı
## aynı formülle potansiyel birim ve altyapı yükü. `density`/`max_height_m` < 0: imar varsayılanı / sınır yok. Salt
## okunur. Varsayılan: `ok == false`, `reason == plan.not_built` (uydurma sayı yok).
func plan_preview(_parcel_ids: PackedInt64Array, land_use: StringName, _density: int = -1,
		_max_height_m: int = -1, _municipal_reuse: bool = false) -> PlanPreviewView:
	var v := PlanPreviewView.new()
	v.provenance = provenance()
	v.land_use = land_use
	return v
