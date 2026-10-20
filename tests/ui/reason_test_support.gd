class_name ReasonTestSupport
extends RefCounted
## T-021 test yardımcıları (test paketi değildir): v1.1 uzantı alanlarını taklit eden kayıt/etken sınıfları.
## Sözleşme v1.0'da `summary_key/args`, `cause_refs`, `direction`, `trend` YOK; ReasonModel bunları `Object.get`
## ile okur, yoksa zarifçe düşer.


class ExtRecord:
	extends ReasonRecord
	var summary_key: StringName = &"decision.investor.develop.negative"
	var summary_args: Dictionary = {}
	var cause_refs: PackedStringArray = PackedStringArray(["parcel.7"])


class ExtFactor:
	extends ReasonFactor
	var direction: int = 1
	var trend: int = -1


## Bir düğümün altındaki tüm etiket metinleri.
static func labels_of(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for child in node.find_children("*", "Label", true, false):
		out.append((child as Label).text)
	return out
