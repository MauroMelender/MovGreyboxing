shader_type spatial;
render_mode blend_mix, cull_back, diffuse_toon, specular_toon;

uniform sampler2D textura_base : source_color;
uniform sampler2D textura_detalle : source_color;
uniform bool usar_detalle = true;

uniform vec4 color_sombra : source_color = vec4(0.55, 0.55, 0.68, 1.0);
uniform float umbral_sombra : hint_range(0.0, 1.0) = 0.5;
uniform float suavizado_banda : hint_range(0.001, 0.3) = 0.03;

uniform vec4 color_rim : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float ancho_rim : hint_range(0.0, 1.0) = 0.35;
uniform float intensidad_rim : hint_range(0.0, 3.0) = 0.8;

void fragment() {
	vec4 base = texture(textura_base, UV);
	vec3 color_final = base.rgb;

	if (usar_detalle) {
		vec4 detalle = texture(textura_detalle, UV);
		color_final = mix(base.rgb, detalle.rgb, detalle.a);
	}

	ALBEDO = color_final;

	vec3 vista = normalize(VIEW);
	float fresnel = 1.0 - clamp(dot(NORMAL, vista), 0.0, 1.0);
	EMISSION = color_rim.rgb * intensidad_rim * smoothstep(1.0 - ancho_rim, 1.0, fresnel);
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	float banda = smoothstep(umbral_sombra - suavizado_banda, umbral_sombra + suavizado_banda, ndotl);
	DIFFUSE_LIGHT += mix(color_sombra.rgb, vec3(1.0), banda) * ALBEDO * ATTENUATION * LIGHT_COLOR;
}