# Kullanıcı kararı bekleyen sorular

Yalnızca kanondan çözülemeyen, gerçekten yaratıcı/ürün kararları. Gruplanmış tutulur; her biri için stüdyonun beklerken ne yaptığı yazılıdır. Cevaplar `design/decisions/` altına kullanıcının sözleriyle kaydedilir.

### Q-001 · Eski 8 POC referans görselinin statüsü  (status: answered → D-001)
- Kullanıcı eski POC'yi referans görselleriyle birlikte sildi; kullanılmaz.

### Q-002 · İlk geliştirilecek (dikey dilim) ilçe  (status: open)
- Context: CAN-08 — oyuncu yalnızca gerçekten geliştirilmiş ilçeleri seçer; Orven seçilebilir ama zorunlu başlangıç değil. M2 dikey dilimi bir ilçeyi sokak ölçeğine kadar geliştirmeyi gerektirir. Metro iskeleti (M1/T-001) bu karara bağlı değil.
- Options: A) Orven (D2, doğu kıyısı karma ilçe: konut, gündelik ticaret, atölye, marina servisi; büyüme alanı var) · B) D1 Merkez (tarihî çekirdek, saat kulesi, çarşı — görsel/tarihî yük en yüksek) · C) D6 karşı yaka çekirdeği
- Recommendation: A — tek kesin adlı ilçe, karma ve büyümeye açık olduğu için imar→yatırım→inşaat döngüsü en net burada görünür; D1'in miras yükünü erken almaz. Mimari ilçe-bağımsız (veri odaklı) kurulur; sürüm öncesinde en az ikinci bir ilçe geliştirilmeden Orven fiilen zorunlu başlangıç hâline getirilmez.
- Meanwhile: M1 metro ölçeğinde tüm bölgeleri kaba düzeyde kurar; ilçe ayrıntısı bu cevabı bekler.

### Q-003 · Anderva'nın para birimi ve arayüz dili  (status: open)
- Context: POC brifi Türkçe arayüz ve ₺ istiyordu; Anderva ise Türkiye olmayan kurgusal bir ülke ve foundation para birimini belirtmiyor (ülke görselindeki ₺ etiketi UI olduğu için kanon değil).
- Options: A) Türkçe arayüz + ₺ · B) Türkçe arayüz + kurgusal Anderva para birimi (ad/simge sizden) · C) Çok dilli (Türkçe + İngilizce), para birimi A veya B
- Recommendation: Türkçe varsayılan arayüz kesin; para birimi sizin kararınız — kurgusal ülke tutarlılığı için B'ye yakınım ama A da tutarlı bir tercih.
- Meanwhile: tüm metinler ve para biçimlendirme tek yerden; geçici olarak ₺ gösterilir ve "geçici" olarak işaretlidir.

### Q-004 · Hedef platform önceliği  (status: open)
- Context: Foundation platformu açık bırakıyor; önceki belgeler iPad yatay, dokunmatik öncelikli hedef öngörüyordu. Geliştirme makinesi 2019 Intel MacBook Pro. Gerçek iPad testi fiziksel cihaz + Apple geliştirici hesabı/imzalama gerektirir.
- Options: A) iPad (yatay, dokunmatik) birincil + macOS ikincil · B) Masaüstü (macOS/Windows) birincil, iPad sonra · C) İkisi eşit
- Recommendation: A — tasarım geçmişi ve dokunmatik öncelikli UX bu yönde; mimari zaten platform-bağımsız. Hangi iPad modeline sahip olduğunuzu ve bir Apple Developer hesabınız olup olmadığını da yazarsanız performans bütçesini cihaza göre sabitleriz.
- Meanwhile: dokunmatik + fare/trackpad birlikte; performans bütçesi düşük güçlü GPU varsayımıyla (ADR-0001); "iPad'de çalışır" denmez.
