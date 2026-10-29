class_name EdgeFog
extends MeshInstance3D
## Dünya-uzayı kenar pusu (T-064, ADR-0007 §Karar 3): tam ekran tek dörtgen, kenar payı (`edge_margin_m`) boyunca
## dünya kutusu kenarına doğru artan pus. Yalnız sokak bandında (kamera < `fog_full_below_m`) görünür;
## K1 bandında kutu kenarı zaten kadraja girmez (`strength` 0 -> düğüm gizli, çizilmez).
## Görünüm katmanıdır: simülasyon bilmez.
## Compatibility'de derinlik dokusu okuması çalışma zamanında DENENİR (engine-reference'ta yok);
## çalışmazsa pus görünmez.

const SHADER: Shader = preload("res://src/view/camera/edge_fog.gdshader")
## Kutu dışı boşluğun rengi ile aynı olmalı (sahne arka plan rengi): kenarda pus boşluğa karışır.
const DEFAULT_COLOR := Color(0.045, 0.06, 0.085)
const VISIBLE_EPS := 0.002

var _material: ShaderMaterial = ShaderMaterial.new()
var _bounds: Rect2 = Rect2()


func _init() -> void:
	name = "EdgeFog"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	_material.shader = SHADER
	material_override = _material
	# Köşeler vertex() içinde ekrana yerleşir; kuyruklama (frustum culling) devre dışı kalsın.
	custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0e6), Vector3(2.0e6, 2.0e6, 2.0e6))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## `bounds`: dünya sınırı (dünya metresi); `margin_m`: kenar payı; `color`: arka plan rengi.
func setup(bounds: Rect2, margin_m: float, color: Color = DEFAULT_COLOR) -> void:
	_bounds = bounds
	_material.set_shader_parameter("margin_m", margin_m)
	_material.set_shader_parameter("fog_color", color)


## Rebasing: kutu, rebase edilmiş kök koordinatına çevrilir (kök = dünya - origin).
func set_origin(origin: Vector2) -> void:
	var b := _bounds
	_material.set_shader_parameter("box", Vector4(b.position.x - origin.x, b.position.y - origin.y,
			b.end.x - origin.x, b.end.y - origin.y))


func set_strength(strength: float) -> void:
	_material.set_shader_parameter("strength", strength)
	visible = strength > VISIBLE_EPS
