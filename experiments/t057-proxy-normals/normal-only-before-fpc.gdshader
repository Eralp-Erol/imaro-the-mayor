shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
// Raw object-space XYZ, no source_color or hint_normal (no blue reconstruction).
uniform sampler2D object_normals : filter_linear_mipmap_anisotropic;
void fragment() {
    vec4 color = texture(atlas, UV);
    ALBEDO = color.rgb;
    ALPHA = color.a;
    ALPHA_SCISSOR_THRESHOLD = 0.45;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    vec2 data_uv = (UV * 1024.0 - vec2(0.0, 640.0)) / vec2(1024.0, 384.0);
    vec3 object_normal = texture(object_normals, data_uv).rgb * 2.0 - 1.0;
    if (dot(object_normal, object_normal) < 0.0025) {
        object_normal = vec3(0.0, 1.0, 0.0);
    }
    NORMAL = normalize((VIEW_MATRIX * vec4(MODEL_NORMAL_MATRIX * normalize(object_normal), 0.0)).xyz);
}
