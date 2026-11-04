# D-019 · Evsiz aileler sıraya girer, yıkım yapımın yarısı, Politikalar yerinde kalır

- Tarih: 2026-11-04 · Kaynak: bu oturumdaki Q-032 / Kart E1, Q-033 / Kart K1, Q-034 / Kart P1 soruları.
- Not: Kullanıcı üç soruyu seçenekli kartla yanıtladı; aşağıdaki sözler seçtiği kart etiketleridir (kullanıcı ayrıca serbest metin yazmadı).

## Kullanıcının kendi sözleri

> E1 (evsiz aileler): “Sıraya girsinler (Önerilen)”
> K1 (yıkım bedeli): “Yapımın yarısı”
> P1 (Politikalar düğmesi): “Böyle kalsın (Önerilen)”

## Yanıtların bağlamı

- E1: Yeniden iskân politikası açıkken ev bulunamayan aileler bekleme listesine girer; yatırımcıların bitirdiği yeni evler önce onlara verilir, belediye bina yapmaz (CAN-03). Ev verilene dek tepki sürer, verilince “biraz kalır” (D-014 §3, D-016 §2).
- K1: “Yolu yıkmak yapmaktan ucuz olsun, oyuncu hatasını rahat düzeltsin.” Yer tutucu değer metre başına 15 idi (134 m yol: yapmak 1.300, yıkmak 1.995).
- P1: Alt çubuk [İnşa | İmar | Yönetim]; Yönetim > Politikalar bugünkü gibi.

## Uygulama notu (ajan açıklaması; kullanıcı alıntısı değildir)

- K1: `data/sim/budget/budget_config.json road.demolish_cost_per_m` 15 → 5. Yapım ~9,7 birim/m olduğundan tam yarısı (~4,85) tamsayıya yuvarlandı; 134 m için yıkım 670, yapım 1.300. Değer veridir; sahip başka oran isterse yalnız bu sayı değişir.
- E1: yeni sim durumu (bekleme listesi) gerektirir; kaydedilir, hash'lenir, determinizm ve kayıt testleri ister. T-067'de ayrıldı; henüz uygulanmadı. GOLDEN yenilemesi gerekirse teknik direktör kapısı ve sahip bilgisi şart.
- P1: değişiklik yok.
