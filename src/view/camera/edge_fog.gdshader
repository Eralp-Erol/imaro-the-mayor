shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled;
// T-064 (ADR-0007 §Karar 3): dünya-uzayı KENAR PUSU. Yüzeyin dünya konumu derinlikten yeniden kurulur ve pus, dünya
// kutusunun kenarına YATAY uzaklıkla artar (kameraya uzaklıkla DEĞİL): sokak bandında kutu kenarı görünmesin.
// Compatibility (GL) derinlik dönüşümü: ndc = vec3(SCREEN_UV, depth) * 2 - 1 (Forward+ biçimi farklıdır).
// Compatibility'de `hint_depth_texture` desteği çalıştırılarak denenir (docs/engine-reference'ta yok): bkz T-064 raporu.
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 box = vec4(0.0, 0.0, 1.0, 1.0); // x0, z0, x1, z1 (sahne = rebase edilmiş kök koordinatı)
uniform float margin_m = 1500.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fog_color : source_color = vec4(0.045, 0.06, 0.085, 1.0);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	float inside = min(min(world.x - box.x, box.z - world.x), min(world.z - box.y, box.w - world.z));
	float amount = 1.0 - smoothstep(0.0, margin_m, inside);
	ALBEDO = fog_color.rgb;
	ALPHA = amount * strength;
}
