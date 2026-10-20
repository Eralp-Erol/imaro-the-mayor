# 06 — Daha sonraki geliştirme devri için sınırlar

> **Bu bir harness kurulumu ya da Claude'a gönderilecek görev/prompt değildir.** Gelecekte tasarımın geliştiricilere aktarılırken kaybolmaması için yaratıcı sınırları kaydeder.

## Tasarımın kilitledikleri

- Deneyimin türü ve duygusu: gerçek şehir kurma + belediye yetkisi + siyasi kariyer.
- Yaşayan karma ekonomi, oyuncu dışındaki özel aktörler ve komşu ilçelerin etkinliği.
- Ismeral ve Anderva'nın kimliği, ilk kampanyanın siyasi akışı, oynanabilir başlangıç ilçesi seçimi.
- Tek fiziksel dünyanın farklı kamera seviyelerinde görünmesi.
- T0 ile olgun şehir ayrımı; oyuncunun şehir biçimini başka bir geleceğe yönlendirebilmesi.
- Başlangıç liman/sanayi konumuna ilişkin düzeltme.
- Mimari/atmosfer yönü ve yanlış estetiklere ilişkin reddedilen örnekler.

## Geliştirme liderinin çözmesi gerekenler — buradan seçilip kilitlenmiyor

Oyun motoru, render ve geometri yaklaşımı, simülasyon topolojisi, işbölümü/agentic harness, worker koordinasyonu, asset pipeline, save sistemi, performans optimizasyonu, gerçek zamanlı vs daha soyut alt-sistem seviyeleri, teknik test stratejisi, hedef cihazlar ve üretim takvimi. Teknik seçimlerden hiçbiri bu paketin otoritesiyle varsayılmamalı.

**Özgürlük sınırsız değil:** Her teknik strateji, oyun tasarımının ana vaadini — **oyuncunun gerçekten biçimlendirebildiği, ekonomik aktörlerin tepki verdiği, aynı coğrafyada yaşayan metropol** — göstermeyi başarmalıdır. Sahte görsel kalite raporları, konsept kolajlarla verilmiş '3D hazır' izlenimi ya da sırf test geçti diye oyun hissi onayı kabul edilemez.

## Önceki teknik POC'den öğrenilenler

Geçmişte Godot 4/GDScript ile bir POC hazırlanmıştı. Önceki repo: `https://github.com/Eralp-Erol/imaro-the-mayor`; geçmiş denetimde incelenen commit `0c908b40cf51f297f8c76b3beaebabc42266aece` idi, **güncel HEAD olduğu varsayılamaz**.

- Yaklaşık dört düzenli blok, 32 parsel, tekrar eden bina kütleleri ve sınırları belli olmayan su üzeri test adası **istenen şehir kimliğini kanıtlamadı**.
- Zoning → yatırımcı → inşaat → ekonomi gibi bir temel çekirdek vardı; fakat sahiplik, yaşayan şehir, siyaset ve görsel zenginlik yüzeyseldi.
- İç testlerde geçen senaryolar yalnızca kendi kısıtlı test hedeflerinin sağlandığını gösterdi; **görsel kalite, eğlence veya iPad'de gerçek performans onayı değildi**.
- Geçmiş POC **kanonik ürün veya sanat referansı değildir**. Saat/save-load/kamera/zoning kernel'i gibi bileşenler ancak ayrı bir teknik incelemeyle yeniden kullanılabilir; **hiçbir kod otomatik devralınmaz**. Godot'un kendisinin başarısızlığa sebep olduğu saptanmadı; motor değişikliği zorunlu varsayımı da yanlış olur.

## Kullanıcı onayı açısından dikkat

Yeni sistemin tasarım sözleşmesini bozmadığını anlamanın yolu sık sık yeni illüstrasyonlar üretmek değil, çalışan aynı 3D dünyada sokak-kamera/mesafe, ekonomik faaliyet, imar-bina dönüşümü ve siyasi geri bildirim arasındaki bağı göstermektir. Bu bir yaratıcı kalite ilkesi, burada tanımlanmış görev sıralaması değildir.

**Devralacak ekip, mimaride inisiyatif sahibidir; oyunun kimliğinde, yetki-fiziksel dünya ayrımında, görsel karakterde ve kullanıcı tarafından düzeltmiş coğrafi kurallarda değildir.**
