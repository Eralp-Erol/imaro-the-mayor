# D-012 · Varlık kütüphanesi: araç onayı (ve onay sayfasının yeniden gönderdiği kararlar)

- Tarih: 2026-10-31 · Kaynak: kullanıcının onay sayfasından (`artifacts/library/approval.html`) kopyalayıp sohbete yapıştırdığı karar JSON'u; karar zamanı sayfada `2026-10-31T15:57:48.926Z` damgalı. Kullanıcının sözü: "Ben az önce sadece bir de araç onayını verdim."
- Karar (kullanıcının): **`veh_car` approved** (içerik hash'i `c6162a31…`; D-005'te aynı hash'li kayıt rejected idi, kullanıcı şimdi onayladı). Kullanıcı insan kararlarını D-005'te zaten verdiğini de belirtti.
- Sayfa aynı JSON'da 39 kaydı daha yeniden gönderdi; hepsi katalogdaki mevcut durumla aynı: 16 eski kit bina + `prop_chimney` rejected (D-005'te zaten rejected), 21 bitki/donatı/insan kaydı approved (D-005'te zaten approved). Yeni karar sayılmaz; kataloga yalnız `approval_date` 2026-10-31 olarak işlendi.
- Ham karar listesi: `D-012-kutuphane-onaylari-arac-2026-10-31.json` (kimlik, karar, içerik hash'i).
- Araç notu (karar değil, teknik): `tools/library/apply_approvals.py` daha önce rejected bir kimliğin yeniden onayını reddediyordu; kullanıcının açık kararı olduğu için `--allow-reverse veh_car` bayrağıyla uygulandı (bayrak yalnız komut satırından, karar dosyası tek başına kimliği yeniden açamaz). Tekrarlanan red artık hata değil, değişiklik yok sayılır. İki yeni test eklendi.
- Önemli: Onay kayıt/şablon durumudur; oyuna bağlama kararı değildir. Araç şablonunun görünümü, kaç araç türü olacağı ve insan stili (A/B/C) hâlâ Q-018 altında açık.
