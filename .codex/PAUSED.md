# Kullanıcı isteğiyle güvenli duraklatma

Kullanıcı: “safe pause. usage limit reached”. Açık devam talimatı gelmeden çalışmaya devam etme.

- Başlatıcı ve ENVIRONMENT.md içindeki yeniden oturum açma döngüsü düzeltildi. Global ayarlara dokunulmadı.
- Godot 4.7.2 proje içinde `.tools/Godot.app`; arşivin resmî SHA512 değeri doğrulandı.
- Gerçek 3D mahalle, kamera, Türkçe HUD, ayrı deterministik simülasyon ve kayıt/yükleme kodu eklendi.
- Son doğrulanmış simülasyon testi: 28/28 başarılı (`artifacts/tests/simulation.json`).
- Son incelenen oyun içi test: 10/15 başarılı. Ekran koordinatlı tıklama/parsel seçimi ve buna bağlı teklif/inşaat testleri başarısız. Prototip tamamlanmış veya tüm kontroller doğrulanmış DEĞİL.
- En son `tests/gameplay_capture.gd` içine INPUT_PROBE eklendi; viewport/canvas koordinat dönüşümü ile doğrudan ray sonucunu karşılaştırıyor. Son denemenin çıktısı `artifacts/logs/gameplay.log`; yeniden başlamadan önce bunu incele.
- `artifacts/screenshots/` gerçek Godot viewport görüntüleri içeriyor; başarısız oyun içi testin construction/completed isimli görüntüleri başarılı inşaat kanıtı SAYILMAZ. Düzeltme sonrası yeniden üret.
- Son ölçüm: yaklaşık 77 FPS, 682 draw call; masaüstü Radeon Pro 560X. iPad testi yapılmadı. Draw call azaltma ve UI/kamera doğrulaması henüz bitmedi.
- README teslim sürümüne güncellenmedi; Git deposu/commit henüz oluşturulmadı. Remote push yapılmadı.

Devam: önce tıklama testini düzelt, gerçek oynanış görüntülerini kontrol et; ardından dokunmatik giriş, uygun testler, performans ve teslim README’sini tamamla. Geçmiş ortam notlarından yeniden başlatma zorunluluğu çıkarma.
