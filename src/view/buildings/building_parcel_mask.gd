class_name BuildingParcelMask
extends RefCounted
## T-042b · Parsel kimliğiyle yapı SATIRI gizleme (kamulaştırma: alınan parselin T0 yapısı yıkılır, geri alınca döner).
## Sütunlar (`BuildingColumns`) DEĞİŞMEZ ve sim'e yazılmaz; gizleme yalnız görünümün chunk planındaki hücre satır
## listelerini süzer. Böylece tüm plan/özet yeniden hesaplanmaz (T0'da plan + hücre özetleri ~91 ms, çatı dizini
## ~324 ms: dilime sığmaz): yalnız satırı gizlenen/geri gelen parsellerin hücreleri etkilenir.
## Saf: Node/Mesh yok. `BuildingView.set_parcels_hidden` kullanır.

## Gizli parsel kimlikleri (yalnız en az bir satırı olanlar).
var hidden: Dictionary = {}
## Gizli satır sayısı.
var rows_hidden: int = 0

var _rows_of: Dictionary = {}
var _indexed_count: int = -1
var _full: Dictionary = {}


## Sütunlar yeniden verildi: dizinler düşer (gizli küme korunur).
func reset() -> void:
	_rows_of.clear()
	_full.clear()
	_indexed_count = -1


## parsel kimliği -> satır dizinleri (bir kez; ~10 ms / 32 bin satır).
func index(cols: BuildingColumns) -> void:
	if _indexed_count == cols.count and not _rows_of.is_empty():
		return
	var tmp: Dictionary = {}
	for i in cols.count:
		var pid := cols.parcel_id[i]
		if not tmp.has(pid):
			tmp[pid] = []
		(tmp[pid] as Array).append(i)
	_rows_of = {}
	for pid: int in tmp:
		_rows_of[pid] = PackedInt32Array(tmp[pid] as Array)
	_indexed_count = cols.count


func rows_of(pid: int) -> PackedInt32Array:
	return _rows_of.get(pid, PackedInt32Array())


## Parselleri gizler/geri koyar ve planı yerinde süzer. Dönüş: {rows: durumu değişen satırlar, cells: satır listesi
## değişen hücre anahtarları (Array[Vector2i])}.
func set_hidden(plan: BuildingChunkPlan, cols: BuildingColumns, ids: PackedInt32Array, hide: bool) -> Dictionary:
	index(cols)
	var rows := PackedInt32Array()
	var cells: Dictionary = {}
	for pid in ids:
		var pr := rows_of(pid)
		if pr.is_empty() or hidden.has(pid) == hide:
			continue
		if hide:
			hidden[pid] = true
			rows_hidden += pr.size()
		else:
			hidden.erase(pid)
			rows_hidden -= pr.size()
		for r in pr:
			rows.append(r)
			cells[plan.cell_of(cols.x[r], cols.z[r])] = true
	var keys: Array[Vector2i] = []
	for key: Vector2i in cells:
		_refilter(plan, cols, key)
		keys.append(key)
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return {"rows": rows, "cells": keys}


## Yeni plan (sütunlar yeniden verildi): gizli kümeyi yeni plana uygular.
func apply_all(plan: BuildingChunkPlan, cols: BuildingColumns) -> void:
	reset()
	if hidden.is_empty():
		return
	index(cols)
	var cells: Dictionary = {}
	rows_hidden = 0
	for pid: int in hidden:
		for r in rows_of(pid):
			rows_hidden += 1
			cells[plan.cell_of(cols.x[r], cols.z[r])] = true
	for key: Vector2i in cells:
		_refilter(plan, cols, key)


func _refilter(plan: BuildingChunkPlan, cols: BuildingColumns, key: Vector2i) -> void:
	if not _full.has(key):
		_full[key] = plan.cells.get(key, PackedInt32Array())
	var out := PackedInt32Array()
	for r in _full[key] as PackedInt32Array:
		if not hidden.has(cols.parcel_id[r]):
			out.append(r)
	if out.is_empty():
		plan.cells.erase(key)
	else:
		plan.cells[key] = out
