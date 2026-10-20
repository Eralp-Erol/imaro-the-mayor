# IMARO: THE MAYOR
## Oyun tasarımı başlangıç paketi · 20 Ekim 2026

**Belge niteliği:** Yaratıcı vizyon, dünya/oynanış yönü ve karar devri. **Kod, agentic harness, implementation prompt, teknik mimari veya üretim planı değildir.**

> **Tek cümlede oyun:** Oyuncunun Anderva'nın bir ilçesinde belediye başkanı olarak başlayıp yaşayan bir 3D şehri imar, kamu yatırımları, ekonomi ve siyasi mücadeleyle dönüştürdüğü; daha sonra aynı şehrin metropol yönetimine ve ulusal siyasete yükseldiği bir **city-builder + siyasi kariyer simülasyonu**.

### Okuma sırası

1. **[`docs/01_CREATIVE_BIBLE.md`](docs/01_CREATIVE_BIBLE.md)** — oyunun kimliği, vaat ettiği deneyim, kurgu dünyası ve karakterin siyasi hikâyesi.
2. **[`docs/02_ISMERAL_WORLD_AND_GROWTH.md`](docs/02_ISMERAL_WORLD_AND_GROWTH.md)** — Ismeral'in coğrafyası, altı çalışma bölgesi, T0 ve açık uçlu büyüme.
3. **[`docs/03_GAMEPLAY_AND_SIMULATION.md`](docs/03_GAMEPLAY_AND_SIMULATION.md)** — şehir inşa etme, özerk ekonomik aktörler, siyaset ve oyun döngüsü.
4. **[`docs/04_VISUAL_DIRECTION_AND_ASSETS.md`](docs/04_VISUAL_DIRECTION_AND_ASSETS.md)** — onaylı görsellerin rolleri; uyarlanacak görsel ilkeler, reddedilen yaklaşımlar.
5. **[`docs/05_DECISIONS_OPEN_AND_REJECTED.md`](docs/05_DECISIONS_OPEN_AND_REJECTED.md)** — bağlayıcı kararlar / kabul edilen yönler / taslaklar / açık sorular.
6. **[`docs/06_TECH_HANDOFF_BOUNDARIES.md`](docs/06_TECH_HANDOFF_BOUNDARIES.md)** — gelecekteki geliştirme ekibinin neyi koruması, neyi özgürce tasarlaması gerektiği; geçmiş POC dersleri.

### Görseller ve onay statüleri

| Görsel | Statü | Ne için kaynak? |
|---|---|---|
| [`01_anderva_approved_country.png`](visual-references/01_anderva_approved_country.png) | **Onaylı ülke görsel referansı** | Anderva'nın genel coğrafi kompozisyonu, 7 kentli dünya, sanat yönü. Üzerindeki UI/istatistik/hatalı kampanya sıralaması **onaylı değil**. |
| [`01b_anderva_country_crop.png`](visual-references/01b_anderva_country_crop.png) | Onaylı görselden **türetilmiş crop** | Aynı ülke referansının güncel olmayan alt kampanya şeridi hariç hâli; **yeni, bağımsız onay değil**. |
| [`02_ismeral_t0_vs_mature_SELECTED.jpg`](visual-references/02_ismeral_t0_vs_mature_SELECTED.jpg) | **Kullanıcının seçtiği Ismeral karşılaştırması** | T0 ile olgun şehir farkı, körfez ve altı bölge ilişkileri, yaşanan/kentleşen dünya, büyüme yönü. **Birebir topografya, nihai ada/liman geometrisi, sabit gelecek ve oyun UI'ı değildir.** |
| [`03_ismeral_mature_architecture_DIRECTION.png`](visual-references/03_ismeral_mature_architecture_DIRECTION.png) | **Beğenilmiş olgun metropol sanat/atmosfer yönü; ikincil** | Kentsel ölçek, katmanlı mimari, İzmir esintili yoğunluk, kamusal odaklar, sanayi varlığı. **Eski yerleşim hataları bağlayıcı değildir**; seçilen karşılaştırma ve yazılı coğrafi kararların gerisindedir. |

### Belgeleri nasıl yorumlamalı?

**KANONİK** = kullanıcı tarafından kesinleştirilmiş oyun/dünya kuralı.  
**ONAYLANMIŞ YÖN** = görsel veya konsept karakteri benimsendi; içindeki her objenin/koordinatın aynısı zorunlu değil.  
**ÇALIŞMA MODELİ** = tartışmak ve prototiple doğrulamak için kullanılabilir; keskin idari, sayısal veya mimari karara dönüşmez.  
**AÇIK** = kullanıcı karar vermedi; yeni gerçek gibi anlatma.  
**REDDEDİLDİ** = daha önce hata olduğu açıkça saptandı; tekrar etme.

**Önemli:** Eski `IMARO_DESIGN_HANDOFF_V3_CORRECTED` belgeleri bu paketin tarihsel kaynağıydı. O eski belgede “yalnızca Anderva görseli onaylı” yazması, **sonradan seçilen Ismeral karşılaştırmasını** hesaba katmadığı içindir. Bu paket yeni onayları bütünleştirir; önceki reddedilmiş Ismeral ve Orven renderlarını geri getirmez.

**Kaynak tarihi:** 20 Ekim 2026'ya kadarki kullanıcı kararları. **Statü:** tasarım devri; gelecekte başka bir agent'ın teknoloji/mimari kararları almasına yönelik bağlam. **Bu paket tek başına geliştirme yetkisi vermez.**
