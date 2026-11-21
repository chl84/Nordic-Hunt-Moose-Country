shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
// Hoof prints and blood on the ground. INSTANCE_CUSTOM.r carries the id of the
// animal that left it so one trail can be lit up; .g scales opacity.

uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
uniform vec3 base_color : source_color = vec3(0.05, 0.035, 0.025);
uniform vec3 glow_color : source_color = vec3(1.0, 0.62, 0.18);
uniform vec3 sense_center = vec3(0.0);
uniform float sense_radius = 0.0;
uniform float sense_strength = 0.0;
uniform float trail_id = -1.0;
uniform float trail_strength = 0.0;
uniform float daylight = 1.0;
uniform vec3 snow_color : source_color = vec3(0.3, 0.33, 0.4);   // how a mark looks in fresh snow
uniform float wash = 0.3;                                          // how much rain takes out of it
global uniform vec4 atmo_weather;

varying float hl;
varying float fade;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float near = 1.0 - smoothstep(sense_radius * 0.7, sense_radius, length(wp - sense_center));
	float same = 1.0 - step(0.002, abs(INSTANCE_CUSTOM.r - trail_id));
	hl = clamp(near * sense_strength + same * trail_strength, 0.0, 1.0);
	fade = INSTANCE_CUSTOM.g;
	// lift highlighted marks slightly so they read through grass
	VERTEX.y += hl * 0.03;
}

void fragment() {
	float a = texture(tex, UV).a;
	float snowy = atmo_weather.y;
	vec3 base = mix(base_color, snow_color, snowy) * daylight;
	ALBEDO = mix(base, glow_color * 1.6, hl);
	float show = (1.0 + 0.9 * snowy) * (1.0 - wash * atmo_weather.x);
	ALPHA = a * clamp(fade * 0.85 * show + hl, 0.0, 1.0);
}
