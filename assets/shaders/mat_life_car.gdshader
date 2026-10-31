shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// T-050: onaylı araç (veh_car, D-012) için kit paleti + yol boyunca hareket. Fragman mat_kit ile AYNI (palet tek kaynak:
// assets/kit/kit_palette.json, KitMaterial). Gövde rengi satırı örnek verisinden (packed bit 14..18); çatı/aksan satırı sabit.
#include "res://assets/shaders/life_motion.gdshaderinc"

uniform vec3 palette[32] : source_color;
uniform float part_row[16];
uniform float part_mul[16];
uniform float roof_row = 0.0;
uniform float accent_row = 0.0;

varying flat float v_wall;

void vertex() {
	uint pk = uint(INSTANCE_CUSTOM.w + 0.5);
	v_wall = float((pk >> 14u) & 31u);
	VERTEX = life_move(INSTANCE_CUSTOM, MODEL_MATRIX, VERTEX);
}

void fragment() {
	int pid = clamp(int(floor(UV.x * 16.0)), 0, 15);
	float src = part_row[pid];
	float row = src;
	if (src < -2.5) {
		row = accent_row;
	} else if (src < -1.5) {
		row = roof_row;
	} else if (src < -0.5) {
		row = v_wall;
	}
	int ri = clamp(int(row + 0.5), 0, 31);
	ALBEDO = palette[ri] * (UV.y * part_mul[pid]);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
