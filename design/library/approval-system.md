# Varlık onay sistemi (kullanıcı kararı toplama)

Kapsam: kullanıcı (Creative Director) kimlik bazında onay/red/bekle kararını bir sayfada verir; karar sohbette yapıştırılınca uygulanır. **Ajan onay yazamaz.** Onaylı/reddedilmiş statünün **oyunda hiçbir etkisi yoktur** (oyuna bağlama bu sistemin dışındadır; CAN-03 ve kütüphane kuralları aynen geçerli).

## Akış
1. Sayfayı üret: `python3 tools/library/build_approval_page.py` → `artifacts/library/approval.html` (tek dosya, çevrimdışı, CDN yok; repoya konmaz). Görseller `../../design/library/sheets/...` ile `file://` altında açılır; bulunamayan görsel "gorsel yok" gösterir.
2. Tarayıcıda aç (`open artifacts/library/approval.html`). Kartta Onayla / Reddet / Bekle + kısa not; filtre (kategori, karar) ve sayaçlar üstte. Durum tarayıcının localStorage'ında tutulur (yoksa sayfa yine çalışır). Sayfa kataloğa **hiçbir şey yazmaz**.
3. "Kararları kopyala" veya "JSON indir" → sohbete yapıştır / dosya yolunu ver. Biçim: `{"schema":"imaro-approval-decisions/1","decided_by":"user","decided_at":ISO,"catalog_version":1,"decisions":[{"id","decision":"approved|rejected|hold","sha256":{...},"note"}]}`.
4. Uygulama (Studio Director, kullanıcının yapıştırdığı karar üzerine): önce `python3 tools/library/apply_approvals.py karar.json` (DRY-RUN, değişecek kayıtları yazar), sonra `--write`. Stdin için `-`.

## Reddedilen girdiler (çıkış kodu 1, hiçbir şey yazılmaz)
`schema` yanlış · `decided_by != "user"` · bilinmeyen/yinelenen id · geçersiz `decision` · gönderilen `sha256` kataloğun güncel içerik hash'iyle eşleşmiyor (dosya değişmiş, yeniden incele) · zaten `approved` kayıt farklı hash'le yeniden onaylanıyor · `rejected` kayıt yeniden onaylanıyor (kimlik yeniden kullanılmaz). Çoklu kararda hepsi ya da hiçbiri. Yazımdan önce `validate_catalog` bellekte çalışır; geçmezse dosya değişmez. Yazma geçici dosya + `os.replace` ile atomiktir.

## Hash bağlama
İçerik hash'i = kayıttaki tüm dosya özetleri: `glb`/`png` ve `lod_chain` altındaki her `sha256` (LOD0/LOD1/PROXY, atlas...). Onayda `user_approved_sha256` (bu sözlük) yazılır; `user_` öneki sayesinde bütün katalog üreteçleri alanı korur. Üreteç sonradan dosyayı değiştirirse hash uyuşmaz: yeniden onay ancak yeni içerikle ve yeniden bakılarak yapılır (onaylı kayıt için şimdilik sessiz yeniden onay yoktur; sıfırlama kullanıcı kararı gerektirir).

## Yazılan alanlar
Yalnız hedef kaydın `approval`, `approval_by: "user"`, `approval_date` (`decided_at` günü), `user_note` (not doluysa) ve `user_approved_sha256` alanları. `hold` yalnız notu günceller; statü değişmez. Başka alan/kayıt değişmez.

## Açık sınırlar
`approved` statüsünü oyun kapısının okuyup okumayacağı (`godot-engineer`) bu sistemin parçası değildir. Q-018 açık kategoriler sayfada uyarıyla işaretlenir; onay yalnız o görünümü kapsar.
