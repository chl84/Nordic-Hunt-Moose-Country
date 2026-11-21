shader_type spatial;
render_mode cull_back, fog_disabled;
// Boulders: grey granite with a coarse grain, pale lichen rosettes and the odd
// rusty-orange crust, moss settled on the faces that look up, and a damp, darker
// foot where the stone meets the ground. Everything is drawn in the stone's own
// space (scaled to metres), so the pattern rides with each boulder; vertex colour
// darkens the hollows and carries the MultiMesh instance tint.
#include "res://shaders/atmo.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float fill = 0.45;     // soft light from the sky, so the shaded side keeps its colour

varying vec3 lpos;             // position in the stone, in metres
varying vec3 lnrm;
varying vec3 wpos;
varying float cloud_v;              // sun let through the clouds (see atmo_cloud_sun)
varying float spec_v;
varying float above;           // metres above the ground line (the instance is sunk 25 % of its size)

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lpos = VERTEX * sc;
	lnrm = NORMAL;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cloud_v = atmo_cloud_sun(wpos);
	above = (VERTEX.y - 0.25) * sc.y;
}

// noise projected along the three axes, blended by the surface direction
vec3 tri(vec3 p, vec3 w) {
	return texture(noise_tex, p.yz).rgb * w.x + texture(noise_tex, p.xz).rgb * w.y + texture(noise_tex, p.xy).rgb * w.z;
}

void fragment() {
	vec3 n = normalize(lnrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec3 big = tri(lpos * 0.11, w);           // blotches a metre or so across
	vec3 fine = tri(lpos * 1.15 + 0.31, w);   // grain and lichen, a few centimetres
	vec3 wn = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);

	// granite: a slow drift between cooler and warmer grey, finely speckled
	vec3 col = mix(vec3(0.23, 0.23, 0.225), vec3(0.31, 0.30, 0.28), smoothstep(0.3, 0.7, big.r));
	col *= 0.76 + 0.48 * fine.g;
	// lichen: scattered pale grey-green rosettes, and here and there a crust of rusty orange
	float lichen = smoothstep(0.66, 0.71, fine.r * 0.7 + big.b * 0.45);
	col = mix(col, vec3(0.40, 0.42, 0.36) * (0.9 + 0.2 * fine.b), lichen * 0.65);
	float crust = smoothstep(0.71, 0.75, fine.b) * smoothstep(0.55, 0.72, big.g);
	col = mix(col, vec3(0.45, 0.29, 0.09), crust * 0.7);
	// moss settles on what faces up, with a ragged edge
	float moss = smoothstep(0.45, 0.8, wn.y + (big.g - 0.5) * 0.9 + (fine.r - 0.5) * 0.3);
	col = mix(col, mix(vec3(0.085, 0.12, 0.04), vec3(0.17, 0.19, 0.07), fine.g), moss * 0.92);
	// the damp foot
	col *= mix(0.6, 1.0, smoothstep(-0.05, 0.4, above + (fine.b - 0.5) * 0.25));
	col *= COLOR.rgb;
	// the day's weather: snow on what faces up, rain darkening the stone
	float cap = atmo_weather.y * smoothstep(0.25, 0.65, wn.y + (big.g - 0.5) * 0.5 + (fine.r - 0.5) * 0.2);
	col = mix(col, vec3(0.78, 0.8, 0.85) * (0.92 + 0.1 * fine.g), cap);
	float soaked = atmo_weather.x * (1.0 - cap);
	col *= 1.0 - 0.35 * soaked;

	// a rough, pitted surface: the grain tilts the light a little (less under the moss)
	vec3 bend = (fine - 0.5) * (0.55 - 0.3 * moss) * (1.0 - 0.7 * cap);
	vec3 wb = normalize((MODEL_MATRIX * vec4(normalize(n + bend), 0.0)).xyz);

	vec4 haze = atmo_fogging(wpos, CAMERA_POSITION_WORLD);
	ALBEDO = col * atmo_keep(haze.a);
	ROUGHNESS = mix(mix(0.82, 0.97, moss), 0.42, soaked * 0.6);
	SPECULAR = (0.18 - 0.12 * moss + 0.15 * soaked) * (1.0 - haze.a);
	spec_v = SPECULAR;
	vec3 sky = mix(atmo_horizon, atmo_top, 0.25);
	vec3 extra = col * sky * fill * (0.62 + 0.38 * wb.y);
	EMISSION = atmo_emit(haze, extra * extra);
	NORMAL = normalize((VIEW_MATRIX * vec4(wb, 0.0)).xyz);
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
