# 2026-11-05 · B-052 yükleme sonrası senkron okuma + T0 süpürmesi: önce/sonra ölçümü

Dal `work/b052` (taban `34eae42` + ADR-0011). Prob: `tools/godot/b050_load_probe.gd` (gerçek `playable.tscn`, başsız, `nice 19`, makine yükü 5-6, **Intel Mac, iPad DEĞİL**, tek koşu). Ayrıntı ve tablo: `production/bugs/B-052.md` "UYGULAMA VE ÖLÇÜM".

ÖNCE (bu oturumda yeniden ölçüldü): `PLAYABLE_LOAD_RESYNC ms=1477.8 parcel_reads=17348` (aynı süreç), `ms=1554.1 parcel_reads=16205` (yeni süreç); `B050_SETTLE same frames=783 ms_sum=2915.0 ms_max=7.5`, `fresh frames=659 ms_sum=2615.1 ms_max=70.9`; yeni süreç yükleme anı `MISSING_sim=9`.
SONRA: `ms=15.2 parcel_reads=1171` / `ms=21.2 parcel_reads=28`; `same frames=20 ms_sum=3.7 ms_max=0.4`, `fresh frames=39 ms_sum=110.2 ms_max=60.7`; `MISSING_sim=0` her aşamada.
