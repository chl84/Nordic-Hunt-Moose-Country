shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
// Window glass, painted rather than lit: the sky (and the dark yard below it)
// mirrored by angle, and behind the pane a dim room with chequered curtains,
// which glows warm when the lamps are lit at dusk.
// UV is the position on the window in metres (u to the right, v down from the
// top); COLOR.rg carries the window's width and height / 4, COLOR.b some variety.
#include "res://shaders/atmo.gdshaderinc"

uniform float glow = 0.0;      // 0 by day .. 1 with the lamps lit
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wnrm;
varying vec2 size;
varying float seed;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	size = COLOR.rg * 4.0;
	seed = COLOR.b;
}

void fragment() {
	vec3 to_eye = CAMERA_POSITION_WORLD - wpos;
	float dist = length(to_eye);
	vec3 v = to_eye / max(dist, 0.001);
	vec3 n = normalize(wnrm);
	vec3 t = normalize(cross(vec3(0.0, 1.0, 0.0), n));     // along the window, to the right
	vec3 up = cross(n, t);
	// old glass is never quite flat
	vec2 wob = (texture(noise_tex, UV * vec2(0.7, 0.5) + seed * 3.7).rg - 0.5) * 0.07;
	vec3 nn = normalize(n + t * wob.x + up * wob.y);
	float ndv = clamp(dot(nn, v), 0.0, 1.0);
	float fres = 0.17 + 0.83 * pow(1.0 - ndv, 3.0);
	vec3 r = reflect(-v, nn);
	vec3 sky = atmo_sky(normalize(vec3(r.x, max(r.y, 0.02), r.z)));
	vec3 ground = mix(vec3(0.07, 0.08, 0.05), atmo_horizon * 0.4, 0.25);
	vec3 refl = mix(ground, sky, smoothstep(-0.05, 0.1, r.y));

	// the room behind the pane, seen along the view ray in the window's own frame
	vec3 d = -v;
	vec3 dl = vec3(dot(d, t), -dot(d, up), -dot(d, n));    // x right, y down, z into the room
	float into = max(dl.z, 0.08);
	vec2 at_c = UV + dl.xy / into * 0.06;                  // the curtains hang 6 cm in
	vec2 at_b = UV + dl.xy / into * 2.4;                   // the far wall
	// curtains gathered at both sides, a valance across the top; red and white check
	float cw = size.x * 0.21;
	float sides = max(1.0 - smoothstep(cw - 0.015, cw, at_c.x), smoothstep(size.x - cw, size.x - cw + 0.015, at_c.x));
	sides *= 1.0 - smoothstep(size.y * 0.9, size.y * 0.93, at_c.y);
	float valance = 1.0 - smoothstep(size.y * 0.15, size.y * 0.15 + 0.015, at_c.y);
	float curtain = max(sides, valance);
	vec2 cp = at_c * 24.0;
	float check = (step(0.5, fract(cp.x)) + step(0.5, fract(cp.y))) * 0.5;
	vec3 cloth = mix(vec3(0.86, 0.83, 0.77), vec3(0.62, 0.10, 0.08), check * 0.8);
	float folds = 0.72 + 0.28 * sin(at_c.x * 75.0 + seed * 6.0);
	float day = clamp(dot(atmo_sun_col, vec3(0.3, 0.5, 0.2)), 0.0, 1.4);
	vec3 lamp = vec3(1.0, 0.6, 0.27);
	// the room: dark by day; at dusk a warm pool of lamplight
	float pool = exp(-length((at_b - vec2(size.x * 0.5, size.y * 0.35)) / vec2(1.4, 1.0)));
	// (by day the far wall catches a little light from the other windows; the floor is darker)
	float back = smoothstep(size.y * 1.3, size.y * 0.4, at_b.y);
	vec3 room = vec3(0.075, 0.062, 0.05) * (0.3 + 0.7 * day) * mix(0.55, 1.0, back) + lamp * glow * (0.22 + 0.95 * pool);
	vec3 cur = cloth * folds * (0.36 * day + lamp * glow * 0.85);
	vec3 inside = mix(room, cur, curtain);
	// dust and the odd smear catch the light
	float dust = smoothstep(0.55, 0.85, texture(noise_tex, UV * 1.6 + seed).b) * 0.12;
	vec3 col = mix(inside, refl, fres * (1.0 - glow * 0.45)) + refl * dust;
	vec4 haze = atmo_fogging(wpos, CAMERA_POSITION_WORLD);
	ALBEDO = sqrt(col * col * (1.0 - haze.a) + haze.rgb * haze.rgb * haze.a);
}
