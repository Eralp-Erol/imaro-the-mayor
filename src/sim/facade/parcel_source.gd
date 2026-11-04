@abstract
class_name ParcelSource
extends RefCounted
## Facade'ın parsel kaynağı (T-027 ölçüt 5). Sim dünya verisini (parsel kimliği, bölge, konum, alan) BURADAN okur;
## koordinat/bölge kodu gömmez (ADR-0005 §7, LANES kural 8). Gerçek kaynak T-011 `WorldNetwork` teslimiyle bir
## `ParcelSource` alt sınıfı olarak takılır; o gelene dek `ListParcelSource` (WorldFixture'dan beslenen liste)
## kullanılır.
##
## Kaynak STATİK şablon verir (konum, alan, bölge, başlangıç imarı/değeri). Dinamik durum (yürürlükteki imar, bekleyen
## öneri, gelişme) sim durumundadır (`ParcelZoningSystem` bindirmesi) ve kayda girer; kaynak kayda GİRMEZ — yükleyen,
## aynı dünyayı veren kaynağı yeniden sağlar (`SimFacadeImpl.import_save` dünya kimliğini/parsel sayısını denetler).
## Kaynak değer kopyası verir (çağıranın değiştirmesi kaynağı etkilemez).


## Kaynak/dünya tanımlayıcısı (kayıtla karşılaştırılır).
@abstract func world_id() -> StringName


@abstract func parcel_count() -> int


## Parsel kimlikleri, artan; `region_code` boş değilse yalnız o bölge.
@abstract func parcel_ids(region_code: StringName = &"") -> PackedInt64Array


@abstract func has_parcel(id: int) -> bool


## Statik şablon (yeni kopya) ya da bilinmeyen kimlikte null.
@abstract func template(id: int) -> ParcelView
