shader_type spatial;
render_mode cull_disabled, fog_disabled, world_vertex_coords;
// Distant trees: one upright card per tree that turns to face the viewer and
// shows a picture of the full model (see Impostors). Each kind has two pictures;
// a tree picks one, and whether to mirror it, from where it stands.
#include "res://shaders/atmo.gdshaderinc"

uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform float tile_u = 0.0;       // left edge of this kind's first picture
uniform float tile_w = 0.1667;    // width of one picture
uniform float lod_cut[12];        // alpha cut-off per mip level, keeping the crown as full as up close
uniform float wind_strength = 1.0;

varying vec3 tint;
varying vec3 glow;
varying vec3 right_w;
varying vec3 fwd_w;
varying float across;
varying float cloud_v;              // sun let through the clouds (see atmo_cloud_sun)

// (world_vertex_coords: VERTEX arrives in world space; the card's own x and y are
// read back off the instance's axes, and the turned card is written out directly)
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 bx = MODEL_MATRIX[0].xyz;
	vec3 up = MODEL_MATRIX[1].xyz;
	float sx = length(bx);
	vec3 rel = VERTEX - origin;
	float mx = dot(rel, bx) / max(sx * sx, 1e-6);
	float my = dot(rel, up) / max(dot(up, up), 1e-6);
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	fwd_w = normalize(to_cam + vec3(0.0001, 0.0, 0.0));
	right_w = cross(vec3(0.0, 1.0, 0.0), fwd_w);
	float h1 = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float h2 = fract(h1 * 7.31 + 0.137);
	vec3 wp = origin + right_w * (mx * sx) + up * my;
	float phase = origin.x * 0.31 + origin.z * 0.27;
	float gust = sin(TIME * 0.9 + phase) * 0.6 + sin(TIME * 2.3 + phase * 1.7) * 0.4;
	float top = 1.0 - UV.y;
	wp += vec3(0.8, 0.0, 0.6) * gust * 0.07 * wind_strength * top * top * (0.4 + my * 0.09);
	VERTEX = wp;
	cloud_v = atmo_cloud_sun(MODEL_MATRIX[3].xyz);
	vec4 haze = atmo_fogging(wp, CAMERA_POSITION_WORLD);
	tint = pow(COLOR.rgb, vec3(1.3)) * atmo_keep(haze.a);
	glow = atmo_emit(haze, vec3(0.0));
	across = UV.x * 2.0 - 1.0;
	float u = h2 < 0.5 ? UV.x : 1.0 - UV.x;
	UV = vec2(tile_u + (h1 < 0.5 ? 0.0 : tile_w) + u * tile_w, UV.y);
}

void fragment() {
	vec4 t = texture(atlas, UV);
	ALPHA = t.a;
	// which copy of the picture is being read, to pick its cut-off
	vec2 texel = UV * vec2(textureSize(atlas, 0));
	vec2 dx = dFdx(texel);
	vec2 dy = dFdy(texel);
	float lod = clamp(0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1e-6)), 0.0, 10.999);
	int l0 = int(lod);
	ALPHA_SCISSOR_THRESHOLD = mix(lod_cut[l0], lod_cut[l0 + 1], fract(lod));
	// the pictures blend towards transparent black at their edges: undo that
	ALBEDO = t.rgb / max(t.a, 0.08) * tint;
	ROUGHNESS = 0.9;
	SPECULAR = 0.0;
	EMISSION = glow;
	// lit as a rounded column, so the sunny side and the shaded side read at a distance
	vec3 nw = normalize(right_w * across * 0.85 + fwd_w * sqrt(max(1.0 - across * across * 0.72, 0.0)) + vec3(0.0, 0.3, 0.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp((ndl + 0.45) / 1.45, 0.0, 1.0);
	float through = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * clamp(0.6 - ndl * 0.5, 0.0, 1.0) * 0.5;
	float cl = LIGHT_IS_DIRECTIONAL ? cloud_v : 1.0;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * cl * (wrap + through) / PI;
}
