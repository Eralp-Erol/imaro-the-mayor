@abstract
class_name ExistingStockSource
extends RefCounted
## T0 mevcut yapı stoğu arayüzü (T-013 ölçüt 2). Ekonomi çekirdeği başlangıçta bu parselleri `built` doğurur: stok
## "başlangıç durumudur", bir aktör kararı ya da belediye komutu değildir (CAN-03 atlatılmaz: kayıtta gerekçe yoktur,
## yeni gelişme yine yalnız yatırımcı kararıyla olur). Gerçek kaynak T-005 `BuildingColumns` teslimiyle bir alt sınıf
## (adaptör) olarak takılır: parcel_id -> parsel, `floors`/`module_idx` -> birim, `flags` -> kullanım. Şimdilik
## `EmptyStockSource` ve fixture/test için `ListStockSource`.
## Kaynak STATİKTİR (kayda girmez); yükleyen aynı dünyayı veren kaynağı yeniden sağlar. Değer kopyası verir.

## Stoklu parsellerin kimlikleri, artan.
@abstract func parcel_ids() -> PackedInt64Array


## &"residential" | &"commercial"; stokta olmayan parselde &"".
@abstract func use_of(parcel_id: int) -> StringName


## Mevcut birim sayısı (konutta hane kapasitesi, ticarette dükkân birimi); stokta olmayan parselde 0.
@abstract func units_of(parcel_id: int) -> int


## Sahip yatırımcı kimliği (1..yatırımcı sayısı); 0 = ilk arsa sahibi.
@abstract func owner_of(parcel_id: int) -> int
