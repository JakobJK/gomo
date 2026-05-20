shader_type spatial;

uniform vec4 albedo : source_color = vec4(0.78, 0.47, 0.18, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.35;
uniform float specular : hint_range(0.0, 1.0) = 0.65;
uniform sampler2D normal_map_tex : filter_linear_mipmap, repeat_disable;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	vec3 n_obj = texture(normal_map_tex, UV).rgb * 2.0 - 1.0;
	NORMAL = normalize(mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * n_obj);
}
