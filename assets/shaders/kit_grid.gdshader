shader_type spatial;
render_mode unshaded, cull_disabled;

// kit_lab ölçek ızgarası (dev). Dünya konumundan 1 m ince / 5 m orta / 10 m kalın çizgi. Yüzeyin düzlemi `plane_axis`
// ile seçilir: 0 = zemin (x,z), 1 = arka perde (x,y).

uniform vec3 base_color : source_color = vec3(0.80, 0.79, 0.75);
uniform vec3 line_color : source_color = vec3(0.55, 0.55, 0.52);
uniform int plane_axis = 0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 p, float step_m, float width_px) {
	vec2 g = abs(fract(p / step_m - 0.5) - 0.5) / fwidth(p / step_m);
	return 1.0 - clamp(min(g.x, g.y) - width_px + 1.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = plane_axis == 0 ? v_world.xz : v_world.xy;
	float thin = grid_line(p, 1.0, 0.5) * 0.25;
	float mid = grid_line(p, 5.0, 0.7) * 0.5;
	float thick = grid_line(p, 10.0, 1.0) * 0.9;
	float l = max(thin, max(mid, thick));
	ALBEDO = mix(base_color, line_color, l);
}
