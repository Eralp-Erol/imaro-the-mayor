# D-020 · Oyun hep D2'den başlar, meclis "hayır" nadir kalır

- Tarih: 2026-11-04 · Kaynak: bu oturumdaki B-026 (başlangıç ilçesi) ve meclis RED görünürlüğü soruları.
- Not: Kullanıcı iki soruyu seçenekli kartla yanıtladı; aşağıdaki sözler seçtiği kart etiketleridir (serbest metin yazmadı).

## Kullanıcının kendi sözleri

> Başlangıç ilçesi: “Hep D2'den başlasın”
> Meclis RED: “Nadir kalsın (Önerilen)”

## Yanıtların bağlamı

- Başlangıç ilçesi: Oyun şimdilik oyuncunun ilçe seçmesi olmadan, D2'den başlar. Yol yetkisi veride yalnız D2'ye bağlı (`network.json jurisdiction_regions`); bu, şimdiki hâlin kararlaştırılmış olması demektir.
- Meclis RED: Meclis "hayır"ı yalnız yeşil imar + dolu altyapı + en az 10 parsellik plan gibi koşullarda ve gürültüyle (~%5-8) çıkar. Ağırlıklara/eşiğe dokunulmaz (Q-014 D-014 ile kapandı; Q-028 açık kalır).

## Uygulama notu (ajan açıklaması; kullanıcı alıntısı değildir)

- B-026: karar gereği kapatıldı (düzeltilmez). M2 ölçüt 7 ("örnek ilçe zorunlu başlangıç yeri olmaz") bu kararla D2 başlangıcı için KISMEN kalır; sim yarısı 6 ilçede kanıtlı (`tests/game/m2_start_district_test.gd`). Oyuncunun ilçe seçmesi sonradan istenirse T-043 yeniden açılır ve bu karar güncellenir.
- Meclis RED: kod/veri değişikliği yok. Gösterim için test tohumu kullanılır (`tests/game/council_red_scenario_test.gd`: tohum 1020 RED 2-3). Rastgele oyunda RED görülmemesi hata değildir.
