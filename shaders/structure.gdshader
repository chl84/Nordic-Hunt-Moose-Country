shader_type spatial;
render_mode cull_back, fog_disabled;
// Buildings: the cabin and its yard, the pier, the hunting towers.
// Vertex colour is the paint or material colour; vertex alpha (x10) picks a
// surface pattern, drawn here in object space (metres):
//   1 painted boards   2 weathered wood   3 stone   4 turf
//   5 bark             6 end grain        7 iron    anything else: plain
#include "res://shaders/atmo.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float fill = 0.5;      // soft light from the sky and the ground, so shaded walls keep their colour

varying vec3 lpos;
varying vec3 lnrm;
varying vec3 wpos;
varying float cloud_v;              // sun let through the clouds (see atmo_cloud_sun)
varying float spec_v;
varying float kind;

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
	kind = COLOR.a * 10.0;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cloud_v = atmo_cloud_sun(wpos);
}

vec3 nz(vec2 p) {
	return texture(noise_tex, p).rgb;
}

void fragment() {
	vec3 col = COLOR.rgb;
	vec3 n = normalize(lnrm);
	vec3 an = abs(n);
	bool flat_up = an.y > 0.75;
	// position across the face and up it, in metres
	vec2 f = flat_up ? lpos.xz : vec2(an.x > an.z ? lpos.z : lpos.x, lpos.y);
	float rough = 0.88;
	float spec = 0.15;
	float metal = 0.0;
	vec3 bend = vec3(0.0);
	int k = int(kind + 0.5);
	if (k == 1) {
		// paint over sawn boards: faint grain showing through, splashed darker near the ground
		float g = nz(vec2(f.x * 2.7, f.y * 0.17)).r;
		float g2 = nz(vec2(f.x * 11.0, f.y * 0.9)).g;
		col *= 0.92 + 0.12 * g + 0.08 * (g2 - 0.5);
		col *= mix(0.84, 1.0, smoothstep(0.1, 0.8, lpos.y));
		rough = 0.8;
		spec = 0.22;
	} else if (k == 2) {
		// weathered wood: grain along the boards (along x on flat faces, upright on the sides), going silver
		vec2 gp = flat_up ? vec2(lpos.x * 0.22, lpos.z * 9.0) : vec2(f.x * 9.0, f.y * 0.22);
		float g = nz(gp).r;
		float g2 = nz(gp * vec2(3.1, 2.7) + 0.37).b;
		col *= 0.78 + 0.34 * g + 0.14 * (g2 - 0.5);
		col = mix(col, vec3(dot(col, vec3(0.333))), 0.15);
		rough = 0.93;
		spec = 0.06;
	} else if (k == 3) {
		// dry stone: blotchy rock, darker joints where the noise crosses its middle, a little lichen
		vec2 p = flat_up ? lpos.xz : f;
		float a = nz(p * 0.9).r;
		float b = nz(p * 2.3 + 0.3).g;
		float joint = 1.0 - smoothstep(0.0, 0.04, abs(a - 0.5));
		col *= 0.78 + 0.4 * b;
		col = mix(col, col * vec3(1.12, 1.14, 0.86), smoothstep(0.6, 0.8, nz(p * 0.5 + 0.7).b) * 0.6);
		col *= 1.0 - joint * 0.5;
		bend.xz = (nz(p * 3.1).rg - 0.5) * 0.35;
		rough = 0.95;
		spec = 0.1;
	} else if (k == 4) {
		// turf: autumn grass, straw and moss in drifts over a lumpy, tufted surface
		vec2 p = lpos.xz;
		float a = nz(p * 0.21).g;
		float b = nz(p * 0.93 + 0.5).r;
		float c = nz(p * 4.3).b;
		vec3 green = vec3(0.15, 0.19, 0.07);
		vec3 straw = vec3(0.37, 0.32, 0.15);
		vec3 rust = vec3(0.30, 0.15, 0.08);
		vec3 moss = vec3(0.11, 0.15, 0.055);
		// broad, soft drifts of colour; the fine noise does the grassy texture
		vec3 g = mix(green, straw, smoothstep(0.2, 0.85, a + (b - 0.5) * 0.35));
		g = mix(g, rust, smoothstep(0.6, 0.9, b) * 0.35);
		g = mix(g, moss, smoothstep(0.6, 0.95, 1.0 - a) * 0.35);
		float blades = nz(p * 13.0 + 0.4).g;
		col = g * (0.7 + 0.32 * c + 0.28 * blades) * COLOR.r;
		bend.xz = (nz(p * 2.9 + 0.2).rg - 0.5) * 0.9;
		rough = 0.97;
		spec = 0.04;
	} else if (k == 5) {
		// bark: rough, in long cracked plates
		float g = nz(vec2(f.x * 5.0, f.y * 1.3)).r;
		col *= 0.7 + 0.55 * g;
		bend.xz = (nz(vec2(f.x * 7.0, f.y * 2.0)).gb - 0.5) * 0.5;
		rough = 0.96;
		spec = 0.05;
	} else if (k == 6) {
		// end grain of cut logs: mottled, a little darker in the cracks
		float g = nz(f * 6.0).g;
		col *= 0.8 + 0.35 * g;
		rough = 0.9;
		spec = 0.08;
	} else if (k == 7) {
		// black iron, a little rusty
		float g = nz(f * 4.0).r;
		col = mix(col, vec3(0.09, 0.05, 0.03), smoothstep(0.62, 0.8, g) * 0.5);
		rough = 0.5;
		spec = 0.4;
		metal = 0.4;
	}
	vec3 n_obj = normalize(n + bend);
	vec3 wn = normalize((MODEL_MATRIX * vec4(n_obj, 0.0)).xyz);
	// the day's weather: snow on the roofs and anything else facing up, wet wood darker
	float cap = atmo_weather.y * smoothstep(0.45, 0.8, wn.y);
	col = mix(col, vec3(0.78, 0.8, 0.85), cap);
	col *= 1.0 - 0.28 * atmo_weather.x * (1.0 - cap);
	rough = mix(rough, 0.5, atmo_weather.x * 0.5 * (1.0 - cap));
	vec4 haze = atmo_fogging(wpos, CAMERA_POSITION_WORLD);
	ALBEDO = col * atmo_keep(haze.a);
	ROUGHNESS = rough;
	SPECULAR = spec * (1.0 - haze.a);
	spec_v = SPECULAR;
	METALLIC = metal;
	// light from the open sky above and the bright ground below, which shaded walls
	// would otherwise lose almost entirely
	vec3 sky = mix(atmo_horizon, atmo_top, 0.25);
	vec3 extra = col * sky * fill * (0.62 + 0.38 * wn.y);
	EMISSION = atmo_emit(haze, extra * extra);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}

// the engine's own Burley and Schlick-GGX lighting, with the clouds taking their share of the sun
void light() {
	vec3 dl = vec3(0.0);
	vec3 sl = vec3(0.0);
	float cl = LIGHT_IS_DIRECTIONAL ? cloud_v : 1.0;
	atmo_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR * ATTENUATION * cl, ROUGHNESS, METALLIC, spec_v, ALBEDO, SPECULAR_AMOUNT, 1, true, dl, sl);
	DIFFUSE_LIGHT += dl;
	SPECULAR_LIGHT += sl;
}
