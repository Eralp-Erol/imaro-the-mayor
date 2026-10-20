shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// mat_kit (T-004, design/specs/art/building-kit-v0.md section 6): one shared material for every kit mesh.
// UV0.x = (part_id + 0.5) / 16, UV0.y = constant shade multiplier. INSTANCE_CUSTOM (MultiMesh custom data) =
// (wall row, roof row, accent row, brightness) / 32. Palette and part table are filled from kit_palette.json by
// assets/kit/kit_material.gd (single source). Flat shading comes from the glTF per-face normals.

uniform vec3 palette[32] : source_color;   // sRGB as authored; the renderer converts exactly like StandardMaterial3D albedo
uniform float part_row[16];   // >= 0: fixed palette row; -1 / -2 / -3: instance wall / roof / accent row
uniform float part_mul[16];   // per-part constant multiplier (trim = 0.85)
uniform float instance_scale = 32.0;

varying flat vec4 v_inst;

void vertex() {
	v_inst = INSTANCE_CUSTOM;
}

void fragment() {
	int pid = clamp(int(floor(UV.x * 16.0)), 0, 15);
	float src = part_row[pid];
	float row = src;
	if (src < -2.5) {
		row = floor(v_inst.z * instance_scale + 0.5);
	} else if (src < -1.5) {
		row = floor(v_inst.y * instance_scale + 0.5);
	} else if (src < -0.5) {
		row = floor(v_inst.x * instance_scale + 0.5);
	}
	int ri = clamp(int(row), 0, 31);
	float bright = v_inst.w > 0.0 ? v_inst.w * instance_scale : 1.0;
	ALBEDO = palette[ri] * (UV.y * part_mul[pid] * bright);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
