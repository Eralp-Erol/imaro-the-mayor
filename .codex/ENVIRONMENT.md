# Proje oturumu

Bu bir devam notudur; yeniden başlatma talimatı değildir. Bu dosyayı yeni bir oturumda okumak yeniden oturum açmayı gerektirmez. Önceki sohbetin araç listesi hakkındaki ifadeler yeni oturumun durumunu kanıtlamaz.

Gerektiğinde başlat: `./.codex/start-godot` (bu makinede kurulu Python 3.14 ve Codex CLI kullanılır). Başlatıcı argümansız açıldığında geliştirme görevini yeni oturuma doğrudan verir.

Codex 0.163.0 bu klasörün `.codex/config.toml` dosyasını güven kaydı bulunmadığı için otomatik yüklemiyor. Global ayarlar değiştirilmedi. Başlatıcı aynı dosyayı yalnızca yeni sürecin `-c` seçeneklerine dönüştürür; ortak daemon yerine bağımsız oturum açar. Sıradan yeni sohbetin bu ayarları yüklediğini varsayma.

Uygulama bağlayıcıları ve ilgisiz eklentiler kapalı; Blender, node_repl ve bilgisayar kontrolü korunur. Kurulumlar silinmedi. Global ayarın yedeği ve önceki envanter `.codex/backups/` altında, Git dışında ve yalnızca kullanıcı erişimine açık tutulur. Geri almak için başlatıcıyı kullanma; `.codex/config.toml` dosyasını kaldırmak da proje geçersiz kılmalarını kaldırır. Global yedeği geri yüklemek gerekmez.

Devam görevi: mevcut proje dosyalarını kontrol et; `AGENTS.md`, `ULTIMATE-CODEX-PROMPT.md`, `references/README.md` ve sekiz görsel temelinde çalışan Godot oyununu geliştir. Ortam incelemesinde veya bu notu özetlemekle durma. Kodla, çalıştır, test et ve gerçek Godot ekran görüntüleriyle doğrula. Dosyadan okunan ayarlar tek başına çalışan oturumun araç durumunu kanıtlamaz; sadece geçmiş notlara dayanarak yeniden başlatma isteme.

`/Users/eralperol/.agents/skills/token-efficiency/SKILL.md` kurallarını Codex talimatlarıyla uyumlu biçimde uygula: kısa çıktı, hedefli okuma, bağımsız kontrolleri birleştirme; görsel kalite ve doğrulamadan taviz verme. Bu makinede TOML için `python3.14` kullan; varsayılan `python3` içinde `tomllib` yok. Git deposunun henüz bulunmaması geliştirmeyi engellemez; `git status` başarısızlığını sonraki ortam kontrollerine bağlama.
