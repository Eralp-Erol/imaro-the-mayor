extends SimTestBase
## T-045 · `ReasonLog.peek`: kopyasız O(1) okuma (parsel başına karar özeti binlerce kez çağırır). `by_id` ile aynı
## içerik; budanmış/yok kimlik boş; durumu değiştirmez.

const A1 := &"actor.investor.1"


func test_peek_reads_without_copying_and_returns_empty_for_pruned_or_unknown_ids() -> void:
	var rlog := ReasonLog.new(3)
	var ids: Array[int] = []
	for k in 5:
		ids.append(rlog.record(k, A1, &"d", [], 0, &"c%d" % k))
	assert_int(rlog.first_id()).is_equal(3)
	assert_bool(rlog.peek(ids[0]).is_empty()).override_failure_message("budanmış").is_true()
	assert_bool(rlog.peek(ids[1]).is_empty()).is_true()
	assert_bool(rlog.peek(0).is_empty()).is_true()
	assert_bool(rlog.peek(99).is_empty()).override_failure_message("henüz yok").is_true()
	for k in range(2, 5):
		var rec := rlog.peek(ids[k])
		assert_int(rec["id"]).is_equal(ids[k])
		assert_int(rec["tick"]).is_equal(k)
		assert_str(str(rec["code"])).is_equal("c%d" % k)
		assert_dict(rec).is_equal(rlog.by_id(ids[k]))  # by_id ile aynı içerik


func test_peek_is_read_only_for_the_state_hash() -> void:
	var state := new_state()
	var id := state.record_reason(A1, &"d", [{"name": &"yield", "value": 7000, "weight": 3000}], 100)
	var before := state_hash_of(state)
	for _i in 3:
		state.reasons.peek(id)
		state.reasons.peek(id + 5)
	assert_str(state_hash_of(state)).is_equal(before)
