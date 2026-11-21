shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, fog_disabled, world_vertex_coords;
// Ground cover blades. Lit as if flat on the ground so tufts melt into the terrain.
#include "res://shaders/atmo.gdshaderinc"

varying vec3 wpos;
varying float cloud_v;              // sun let through the clouds (see atmo_cloud_sun)
varying float spec_v;

uniform float fade_start = 30.0;
uniform float fade_end = 50.0;
uniform float wind_strength = 1.0;
uniform sampler2D gust_tex : filter_linear_mipmap, repeat_enable;   // the world noise: same gusts as the open ground

// (world_vertex_coords: VERTEX and NORMAL arrive in world space; the tuft is shrunk
// about its root, the instance's origin, and the wind simply added)
void vertex() {
	vec3 wp = VERTEX;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float d = length(wp - CAMERA_POSITION_WORLD);
	float keep = 1.0 - smoothstep(fade_start, fade_end, d);
	float tip = COLOR.a;
	// with distance the blades get shorter, and at the very edge the whole tuft draws in to a
	// point - flat slivers left lying on the ground would show as specks
	vec3 rel = wp - origin;
	rel.y *= keep;
	rel.xz *= smoothstep(0.0, 0.35, keep);
	float w = sin(TIME * 1.7 + wp.x * 0.7 + wp.z * 0.5) * 0.6 + sin(TIME * 3.9 + wp.x * 1.9 - wp.z * 1.3) * 0.4;
	// a gust leans the whole tuft downwind and sets it shaking harder
	float gust = atmo_gust(gust_tex, origin.xz, TIME) * wind_strength;
	vec3 offs = vec3(atmo_wind.x, 0.0, atmo_wind.y) * atmo_wind.z * (w * 0.06 * (0.6 + gust) + gust * 0.17) * tip * wind_strength * keep;
	offs.y -= gust * 0.06 * tip * keep;
	VERTEX = origin + rel + offs;
	wpos = wp + offs;
	// far blades are thinner than a pixel: let their pale tips sink into the tone of the
	// ground they stand on, or they sparkle as bright dots
	vec3 ground_tone = COLOR.rgb / mix(0.37, 0.92, tip) * 0.56;
	float sink = max(smoothstep(9.0, fade_end * 0.8, d) * 0.85, 1.0 - smoothstep(0.0, 0.5, keep));
	COLOR.rgb = mix(COLOR.rgb, ground_tone, sink);
	// (bent over, the blades show their paler sides: the gust shows as a sheen running through)
	COLOR.rgb *= 1.0 + gust * 0.16 * tip;
	NORMAL = vec3(0.0, 1.0, 0.0);
	cloud_v = atmo_cloud_sun(origin);
}

void fragment() {
	vec4 haze = atmo_fogging(wpos, CAMERA_POSITION_WORLD);
	ALBEDO = COLOR.rgb * atmo_keep(haze.a);
	ROUGHNESS = 0.92;
	SPECULAR = 0.06 * (1.0 - haze.a);
	spec_v = SPECULAR;
	EMISSION = atmo_emit(haze, vec3(0.0));
}

// the engine's own wrapped-Lambert lighting, with the clouds taking their share of the sun
void light() {
	vec3 dl = vec3(0.0);
	vec3 sl = vec3(0.0);
	float cl = LIGHT_IS_DIRECTIONAL ? cloud_v : 1.0;
	atmo_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR * ATTENUATION * cl, ROUGHNESS, METALLIC, spec_v, ALBEDO, SPECULAR_AMOUNT, 2, true, dl, sl);
	DIFFUSE_LIGHT += dl;
	SPECULAR_LIGHT += sl;
}
