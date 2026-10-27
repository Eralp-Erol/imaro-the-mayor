shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;

// Shared asset policy: relightable volume normals, no received card self-shadow.
// Shadow casting remains enabled on the imported MeshInstance3D.
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 canopy_center = vec3(0.0);
uniform vec3 canopy_extent = vec3(1.0);
varying vec3 local_position;

void vertex() {
    local_position = VERTEX;
}

void fragment() {
    vec4 texel = texture(atlas, UV);
    ALBEDO = texel.rgb;
    ALPHA = texel.a;
    ALPHA_SCISSOR_THRESHOLD = 0.45;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    // Average unresolved foliage occlusion, independent of sun/camera.
    AO = 0.55;
    AO_LIGHT_AFFECT = 0.75;
    // A position field shared by all three cards, independent of face orientation.
    vec3 volume_normal = normalize((local_position - canopy_center) / canopy_extent + vec3(0.0, 0.25, 0.0));
    NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(volume_normal, 0.0)).xyz);
}
