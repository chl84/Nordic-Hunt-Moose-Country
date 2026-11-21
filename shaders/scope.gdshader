shader_type canvas_item;
// Rifle scope / binocular mask drawn over the zoomed 3D view.

uniform float aspect = 1.7778;
uniform float radius = 0.47;        // lens radius, in screen heights
uniform vec2 shift = vec2(0.0);     // picture offset while the action is worked
uniform vec2 shadow = vec2(0.0);    // eye-relief shadow creeping in from the side
uniform float alpha = 1.0;
uniform float flash = 0.0;
uniform float roll = 0.0;
uniform int mode = 0;               // 0 = scope, 1 = binoculars
uniform float px = 0.001;           // one pixel, in screen heights
uniform float holds[5];             // hold-over marks below centre (screen heights); <= 0 unused

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	vec2 q = p - shift;
	if (mode == 1) {
		float d = min(length(q - vec2(-0.2, 0.0)), length(q - vec2(0.2, 0.0)));
		float vis = smoothstep(radius, radius - 0.018, d);
		float vig = smoothstep(radius * 0.6, radius, d) * 0.4;
		COLOR = vec4(0.0, 0.0, 0.0, (1.0 - vis * (1.0 - vig)) * alpha);
	} else {
		float cr = cos(roll);
		float sr = sin(roll);
		vec2 rq = vec2(q.x * cr - q.y * sr, q.x * sr + q.y * cr);
		float d = length(q);
		float edge = smoothstep(radius, radius - 0.007, d);
		float sh = smoothstep(radius * 1.04, radius * 0.78, length(q - shadow));
		float vis = edge * sh;
		float vig = smoothstep(radius * 0.5, radius, d) * 0.38;
		float a = 1.0 - vis * (1.0 - vig);
		float ax = abs(rq.x);
		float ay = abs(rq.y);
		float fine = px * 0.85;
		float ret = 0.0;
		ret = max(ret, (1.0 - smoothstep(fine, fine + px, ay)) * step(0.006, ax));
		ret = max(ret, (1.0 - smoothstep(fine, fine + px, ax)) * step(0.006, ay));
		float thick = 0.0040;
		float post = radius * 0.40;
		ret = max(ret, (1.0 - smoothstep(thick, thick + px, ay)) * step(post, ax));
		ret = max(ret, (1.0 - smoothstep(thick, thick + px, ax)) * step(post, rq.y));
		for (int i = 0; i < 5; i++) {
			if (holds[i] > 0.0) {
				float w = 0.021 - float(i) * 0.0025;
				ret = max(ret, (1.0 - smoothstep(fine * 1.4, fine * 1.4 + px, abs(rq.y - holds[i]))) * (1.0 - step(w, ax)));
			}
		}
		ret = max(ret, 1.0 - smoothstep(px * 1.5, px * 2.6, length(rq)));
		ret *= vis;
		a = max(a, ret * 0.93);
		float fl = flash * vis * (1.0 - ret) * 0.55;
		COLOR = vec4(vec3(1.0, 0.84, 0.6) * step(0.001, fl), max(a * (1.0 - fl), fl) * alpha);
	}
}
