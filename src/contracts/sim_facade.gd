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
