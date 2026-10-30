class_name PlayableBudget
extends RefCounted
## Oynanabilir sahnenin gösterge bütçe bağlaması (T-043C): ekonomili facade kurulduktan, yol komutları bağlandıktan
## sonra ve İLK tick'ten önce `attach_budget` çağrılır. Takılamazsa bölüm "henüz kurulmadı" kalır (UI dürüst durum).


## `roads_attached`: yol komutları bağlandı mı (bağlanmadıysa yalnız vergi geliri görünür). Dönüş: bütçe takıldı mı.
static func attach(facade: SimFacade, roads_attached: bool) -> bool:
	var impl := facade as SimFacadeImpl
	if impl == null:
		return false
	if not roads_attached:
		push_warning("playable: yol komutları yok; bütçede yol gideri oluşmayacak")
	var ok := impl.attach_budget(BudgetConfig.load_default())
	if not ok:
		push_error("playable: gösterge bütçe takılamadı; bütçe bölümü 'henüz kurulmadı' kalır")
	return ok
