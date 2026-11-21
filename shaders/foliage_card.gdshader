shader_type spatial;
render_mode cull_disabled, fog_disabled, world_vertex_coords;
// Foliage cards: boughs, needle clusters and leaf sprays cut out of a painted
// texture. Vertex colour is the hue (times the instance colour), vertex alpha the
// wind sway. The mesh normal is a soft "crown" normal rather than the card's own,
// so a tree is lit as one rounded mass instead of a stack of flat boards.
// Colour, haze and cut-off are worked out per corner: about half of every card is
// cut away, so anything done per pixel is mostly wasted.
#include "res://shaders/atmo.gdshaderinc"

uniform sampler2D card_tex : filter_linear_mipmap, repeat_disable;
uniform float wind_strength = 1.0;

varying vec3 crown_n;
varying vec3 tone;
varying vec3 glow;
varying float cloud_v;              // sun let through the clouds (see atmo_cloud_sun)

// (world_vertex_coords: VERTEX and NORMAL arrive in world space, so the wind is
// simply added; no per-vertex matrix inverse to take it back into the model)
void vertex() {
	float sway = COLOR.a;
	vec3 wp = VERTEX;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float my = (wp.y - origin.y) / max(length(MODEL_MATRIX[1].xyz), 0.001);   // height in the model
	float phase = origin.x * 0.31 + origin.z * 0.27;
	float gust = sin(TIME * 0.9 + phase) * 0.6 + sin(TIME * 2.3 + phase * 1.7 + wp.y * 0.4) * 0.4;
	float flutter = sin(TIME * 5.1 + wp.x * 2.1 + wp.z * 1.7) * 0.25;
	vec3 offs = vec3(0.8, 0.0, 0.6) * (gust + flutter * sway) * 0.07 * sway * wind_strength * (0.4 + my * 0.09);
	wp += offs;
	VERTEX = wp;
	cloud_v = atmo_cloud_sun(MODEL_MATRIX[3].xyz);
	vec3 wn = normalize(NORMAL);
	crown_n = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	vec3 to_eye = CAMERA_POSITION_WORLD - wp;
	float dist = length(to_eye);
	vec3 alb = pow(COLOR.rgb, vec3(1.3)) * 0.62;
	alb = mix(vec3(dot(alb, vec3(0.3, 0.59, 0.11))), alb, 0.88);
	// foliage seen from the inside of the crown sits in its shade
	alb *= mix(0.74, 1.0, smoothstep(-0.3, 0.2, dot(wn, to_eye / max(dist, 0.001))));
	vec4 haze = atmo_fogging(wp, CAMERA_POSITION_WORLD);
	tone = alb * atmo_keep(haze.a);
	glow = atmo_emit(haze, vec3(0.0));
}

void fragment() {
	vec4 t = texture(card_tex, UV);
	// the atlas's smaller copies keep the share of solid pixels, so one cut-off serves every distance
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// blue is each leaf's own tint: towards orange one way, towards lime the other
	float hv = t.b * 2.0 - 1.0;
	ALBEDO = tone * (0.28 + t.r * 0.86) * (vec3(1.0) + vec3(0.22, -0.03, -0.3) * hv);
	ROUGHNESS = 0.9;
	SPECULAR = 0.0;
	EMISSION = glow;
	NORMAL = normalize(crown_n);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp((ndl + 0.45) / 1.45, 0.0, 1.0);
	float through = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * clamp(0.6 - ndl * 0.5, 0.0, 1.0) * 0.7;
	float cl = LIGHT_IS_DIRECTIONAL ? cloud_v : 1.0;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * cl * (wrap + through) / PI;
}
