class_name WorldRegion
extends RefCounted
## Çalışma bölgesi (D1–D6, WLD-02): çapa + kaba eliptik kapsam. Kodlar resmî ilçe DEĞİLDİR; sınırlar ve statü AÇIK.
## Yalnız D2 "Orven" adını taşır (CAN-01); diğerlerinde `display_name` boştur.

## Raster'daki sayısal kimlik (1..n); 0 = bölge yok (WorldData.REGION_NONE).
var id: int = 0
## Çalışma kodu: &"D1" … &"D6".
var code: StringName = &""
var display_name: String = ""
## Çapa ve eliptik kapsam yarıçapı (dünya metresi), dönüş (derece).
var anchor: Vector2 = Vector2.ZERO
var radius: Vector2 = Vector2.ZERO
var rotation_deg: float = 0.0
## Üretimden sonra hesaplanır: atanan kara hücre sayısı ve ağırlık merkezi (dünya metresi).
var cell_count: int = 0
var centroid: Vector2 = Vector2.ZERO
## Veri dosyasındaki serbest not (ÇIKARIM işaretleri burada).
var basis: String = ""


func state_dict() -> Dictionary:
	return {
		"id": id, "code": code, "name": display_name, "anchor": [anchor.x, anchor.y],
		"radius": [radius.x, radius.y], "rotation": rotation_deg, "cells": cell_count,
		"centroid": [centroid.x, centroid.y],
	}
