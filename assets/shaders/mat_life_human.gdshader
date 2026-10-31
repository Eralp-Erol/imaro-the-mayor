shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// T-050: onaylı B blok figür (D-013) için ortak düz-karo atlası (human_atlas.png) + yol boyunca hareket.
#include "res://assets/shaders/life_motion.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;

void vertex() {
	VERTEX = life_move(INSTANCE_CUSTOM, MODEL_MATRIX, VERTEX);
}

void fragment() {
	ALBEDO = texture(atlas, UV).rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
