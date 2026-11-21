shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, world_vertex_coords, shadows_disabled;
// Mist lying over the lakes and bogs at dawn (thinner at dusk): soft upright cards that
// turn about their own upright axis to face the camera, drawn from slowly drifting noise.
// The card is the instance's scale (x = width, y = height, in metres) at its origin;
// instance colour r = a seed, a = how thick this bank is. `amount` follows the time of day.
#include "res://shaders/atmo.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float amount = 0.0;

varying vec3 wpos;
varying vec2 size;
varying float seed;
varying float thick;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	vec3 right = normalize(vec3(to_cam.z, 0.0, -to_cam.x) + vec3(0.0001, 0.0, 0.0));
	wpos = origin + right * (UV.x - 0.5) * size.x + vec3(0.0, (0.5 - UV.y) * size.y, 0.0);
	VERTEX = wpos;
	NORMAL = normalize(vec3(to_cam.x, 0.0, to_cam.z) + vec3(0.0001, 0.0, 0.0));
	seed = COLOR.r;
	thick = COLOR.a;
}

void fragment() {
	float t = TIME;
	vec2 p = vec2(UV.x * size.x, (1.0 - UV.y) * size.y);      // metres across and up the card
	// wisps: broad rolls drifting one way, finer curls the other
	float n1 = texture(noise_tex, p * vec2(0.02, 0.045) + vec2(seed * 7.1 + t * 0.011, -t * 0.005)).r;
	float n2 = texture(noise_tex, p * vec2(0.055, 0.1) + vec2(seed * 3.3 - t * 0.018, t * 0.009)).g;
	float wisp = smoothstep(0.28, 0.74, n1 * 0.68 + n2 * 0.45);
	// thickest just above the water, thinning upwards; soft ends
	float v = 1.0 - UV.y;
	float profile = smoothstep(0.0, 0.14, v) * (1.0 - smoothstep(0.22, 1.0, v));
	float sides = smoothstep(0.0, 0.28, UV.x) * smoothstep(1.0, 0.72, UV.x);
	vec3 to_eye = CAMERA_POSITION_WORLD - wpos;
	float dist = length(to_eye);
	vec3 vdir = -to_eye / max(dist, 0.001);
	float near = smoothstep(4.0, 22.0, dist);                 // never a wall in your face
	float edge_on = 1.0 - smoothstep(0.45, 0.85, abs(vdir.y)); // looked down on from a tower
	float a = wisp * profile * sides * near * edge_on * thick * amount;
	// the colour of the air itself, no brighter than its surroundings; only looking towards
	// the low sun does it light up a little
	float sd = max(dot(vdir, atmo_sun_dir), 0.0);
	vec3 col = mix(atmo_haze.rgb, atmo_horizon, 0.3) * 0.96 + atmo_sun_col * (pow(sd, 6.0) * 0.12);
	vec4 haze = atmo_fogging(wpos, CAMERA_POSITION_WORLD);
	ALBEDO = mix(col, haze.rgb, haze.a);
	ALPHA = clamp(a * 0.55 * (1.0 - haze.a * 0.5), 0.0, 1.0);
}
