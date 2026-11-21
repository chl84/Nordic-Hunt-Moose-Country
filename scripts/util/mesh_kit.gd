class_name MeshKit
extends RefCounted
## Tiny procedural mesh builder. Every model in the game is built with this.
##
## Convention: callers describe faces counter-clockwise as seen from outside
## (right-hand-rule normals); the kit emits Godot's clockwise winding.

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()        ## optional: exported only when filled for every vertex
var idx := PackedInt32Array()
var bones := PackedInt32Array()
var weights := PackedFloat32Array()

var skinned := false
var xf := Transform3D.IDENTITY          ## applied to everything added
var cur_bones := PackedInt32Array([0, 0, 0, 0])
var cur_weights := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])

func _init(p_skinned := false) -> void:
	skinned = p_skinned

func count() -> int:
	return v.size()

func set_bone(b0: int, w0 := 1.0, b1 := 0, w1 := 0.0, b2 := 0, w2 := 0.0) -> void:
	var s := w0 + w1 + w2
	cur_bones = PackedInt32Array([b0, b1, b2, 0])
	cur_weights = PackedFloat32Array([w0 / s, w1 / s, w2 / s, 0.0])

func vert(p: Vector3, normal: Vector3, color: Color, tex := Vector2.ZERO) -> int:
	v.append(xf * p)
	n.append((xf.basis * normal).normalized() if normal != Vector3.ZERO else Vector3.UP)
	c.append(color)
	uv.append(tex)
	if skinned:
		bones.append_array(cur_bones)
		weights.append_array(cur_weights)
	return v.size() - 1

func tri(a: int, b: int, c2: int) -> void:
	idx.append(a)
	idx.append(c2)
	idx.append(b)

func quad(a: int, b: int, c2: int, d: int) -> void:
	tri(a, b, c2)
	tri(a, c2, d)

## Flat-shaded triangle / quad from points (CCW from outside).
func face3(p0: Vector3, p1: Vector3, p2: Vector3, color: Color) -> void:
	var nn := (p1 - p0).cross(p2 - p0).normalized()
	var a := vert(p0, nn, color)
	var b := vert(p1, nn, color)
	var d := vert(p2, nn, color)
	tri(a, b, d)

func face4(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, color: Color) -> void:
	var nn := (p1 - p0).cross(p2 - p0).normalized()
	if nn == Vector3.ZERO:
		nn = (p2 - p0).cross(p3 - p0).normalized()
	var a := vert(p0, nn, color, Vector2(0, 1))
	var b := vert(p1, nn, color, Vector2(1, 1))
	var d := vert(p2, nn, color, Vector2(1, 0))
	var e := vert(p3, nn, color, Vector2(0, 0))
	quad(a, b, d, e)

## Axis-aligned box in the local frame `t` (size = full extents).
func box(size: Vector3, t: Transform3D, color: Color) -> void:
	var h := size * 0.5
	var p := [
		t * Vector3(-h.x, -h.y, -h.z), t * Vector3(h.x, -h.y, -h.z),
		t * Vector3(h.x, h.y, -h.z), t * Vector3(-h.x, h.y, -h.z),
		t * Vector3(-h.x, -h.y, h.z), t * Vector3(h.x, -h.y, h.z),
		t * Vector3(h.x, h.y, h.z), t * Vector3(-h.x, h.y, h.z),
	]
	face4(p[4], p[5], p[6], p[7], color)   # +z
	face4(p[1], p[0], p[3], p[2], color)   # -z
	face4(p[5], p[1], p[2], p[6], color)   # +x
	face4(p[0], p[4], p[7], p[3], color)   # -x
	face4(p[7], p[6], p[2], p[3], color)   # +y
	face4(p[0], p[1], p[5], p[4], color)   # -y

func box_at(center: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	box(size, Transform3D(Basis.from_euler(rot), center), color)

static func _perp_frame(axis: Vector3) -> Array:
	var a := axis.normalized()
	var ref := Vector3.UP if absf(a.y) < 0.92 else Vector3.RIGHT
	var u := ref.cross(a).normalized()
	var w := a.cross(u).normalized()
	return [u, w, a]   # u x w = a

## Ring of `sides` points around `center`, perpendicular to `axis`.
static func ring(center: Vector3, axis: Vector3, rx: float, ry: float, sides: int, phase := 0.0) -> PackedVector3Array:
	var f := _perp_frame(axis)
	var out := PackedVector3Array()
	out.resize(sides)
	for i in sides:
		var a := TAU * float(i) / float(sides) + phase
		out[i] = center + f[0] * (cos(a) * rx) + f[1] * (sin(a) * ry)
	return out

## Ring from an explicit frame. For lofting, u x w must equal the travel direction.
static func ring_uw(center: Vector3, u: Vector3, w: Vector3, rx: float, ry: float, sides: int, phase := 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(sides)
	for i in sides:
		var a := TAU * float(i) / float(sides) + phase
		out[i] = center + u * (cos(a) * rx) + w * (sin(a) * ry)
	return out

## Tapered cylinder / cone from p0 to p1.
func cyl(p0: Vector3, p1: Vector3, r0: float, r1: float, sides: int, color0: Color, color1 = null, cap0 := false, cap1 := false) -> void:
	var col1: Color = color0 if color1 == null else color1
	var f := _perp_frame(p1 - p0)
	var length := (p1 - p0).length()
	var slope := (r0 - r1) / maxf(length, 0.0001)
	var base := v.size()
	for i in sides + 1:
		var a := TAU * float(i) / float(sides)
		var radial: Vector3 = f[0] * cos(a) + f[1] * sin(a)
		var nn: Vector3 = (radial + f[2] * slope).normalized()
		var u := float(i) / float(sides)
		vert(p0 + radial * r0, nn, color0, Vector2(u, 1))
		vert(p1 + radial * r1, nn, col1, Vector2(u, 0))
	for i in sides:
		var a0 := base + i * 2
		quad(a0, a0 + 2, a0 + 3, a0 + 1)
	if cap0 and r0 > 0.0:
		_cap(p0, f, r0, sides, color0, false)
	if cap1 and r1 > 0.0:
		_cap(p1, f, r1, sides, col1, true)

## Reverse the winding (and normals) of everything added since `i_start`/`v_start`.
func flip_from(v_start: int, i_start: int) -> void:
	for t in range(i_start, idx.size(), 3):
		var tmp := idx[t + 1]
		idx[t + 1] = idx[t + 2]
		idx[t + 2] = tmp
	for i in range(v_start, n.size()):
		n[i] = -n[i]

## Hollow pipe: outer wall, inner wall and ring-shaped end faces.
func tube(p0: Vector3, p1: Vector3, r_out: float, r_in: float, sides: int, color: Color, inner_color = null) -> void:
	var ic: Color = color if inner_color == null else inner_color
	cyl(p0, p1, r_out, r_out, sides, color)
	var vs := v.size()
	var ist := idx.size()
	cyl(p0, p1, r_in, r_in, sides, ic)
	flip_from(vs, ist)
	var f := _perp_frame(p1 - p0)
	for e in 2:
		var c0: Vector3 = p0 if e == 0 else p1
		var nn: Vector3 = -f[2] if e == 0 else f[2]
		var base := v.size()
		for i in sides + 1:
			var a := TAU * float(i) / float(sides)
			var radial: Vector3 = f[0] * cos(a) + f[1] * sin(a)
			vert(c0 + radial * r_out, nn, color)
			vert(c0 + radial * r_in, nn, color)
		for i in sides:
			var a0 := base + i * 2
			if e == 0:
				quad(a0, a0 + 1, a0 + 3, a0 + 2)
			else:
				quad(a0, a0 + 2, a0 + 3, a0 + 1)

func _cap(center: Vector3, f: Array, r: float, sides: int, color: Color, top: bool) -> void:
	var nn: Vector3 = f[2] if top else -f[2]
	var ci := vert(center, nn, color, Vector2(0.5, 0.5))
	var base := v.size()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		vert(center + (f[0] * cos(a) + f[1] * sin(a)) * r, nn, color)
	for i in sides:
		var a0 := base + i
		var a1 := base + (i + 1) % sides
		if top:
			tri(ci, a0, a1)
		else:
			tri(ci, a1, a0)

## Ellipsoid. `basis` orients/stretches it further; `jitter` roughens the surface.
func sphere(center: Vector3, radii: Vector3, lon: int, lat: int, color_top: Color, color_bottom = null, basis := Basis.IDENTITY, jitter := 0.0, seed_v := 0) -> void:
	var cb: Color = color_top if color_bottom == null else color_bottom
	var base := v.size()
	for j in lat + 1:
		var th := PI * float(j) / float(lat)
		for i in lon + 1:
			var ph := TAU * float(i) / float(lon)
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var k := 1.0
			if jitter > 0.0 and j > 0 and j < lat:
				k += (G.hash2(i % lon, j, seed_v) - 0.5) * 2.0 * jitter
			var p := Vector3(d.x * radii.x, d.y * radii.y, d.z * radii.z) * k
			var nn := Vector3(d.x / radii.x, d.y / radii.y, d.z / radii.z).normalized()
			vert(center + basis * p, basis * nn, cb.lerp(color_top, d.y * 0.5 + 0.5), Vector2(float(i) / lon, float(j) / lat))
	for j in lat:
		for i in lon:
			var a := base + j * (lon + 1) + i
			var b := a + lon + 1
			# top row (j) to next row (j+1): CCW from outside
			quad(a, a + 1, b + 1, b)

## Skin a sequence of rings (equal point counts) into a tube with smooth normals.
## Rings must wind CCW when looking back along the direction of travel.
## `colors` is one Color per ring, or per ring an Array of Colors per point.
func loft(rings: Array, colors: Array, cap_start := false, cap_end := false, ring_bones: Array = []) -> void:
	var m: int = rings[0].size()
	var base := v.size()
	var i_start := idx.size()
	for r in rings.size():
		if skinned and ring_bones.size() > r:
			var rb: Array = ring_bones[r]
			set_bone(rb[0], rb[1], rb[2] if rb.size() > 2 else 0, rb[3] if rb.size() > 3 else 0.0)
		var ring_pts: PackedVector3Array = rings[r]
		for i in m:
			var col: Color = colors[r][i] if typeof(colors[r]) == TYPE_ARRAY else colors[r]
			vert(ring_pts[i], Vector3.UP, col, Vector2(float(i) / m, float(r) / maxi(rings.size() - 1, 1)))
	for r in rings.size() - 1:
		for i in m:
			var a := base + r * m + i
			var b := base + r * m + (i + 1) % m
			quad(a, b, b + m, a + m)
	smooth_normals(base, i_start)
	if cap_start:
		_loft_cap(rings[0], colors[0], true, ring_bones[0] if ring_bones.size() > 0 else [])
	if cap_end:
		_loft_cap(rings[-1], colors[-1], false, ring_bones[-1] if ring_bones.size() > 0 else [])

func _loft_cap(pts: PackedVector3Array, col, start: bool, rb: Array) -> void:
	if skinned and rb.size() >= 2:
		set_bone(rb[0], rb[1], rb[2] if rb.size() > 2 else 0, rb[3] if rb.size() > 3 else 0.0)
	var center := Vector3.ZERO
	for p in pts:
		center += p
	center /= pts.size()
	var nn := (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	if start:
		nn = -nn
	var color: Color = col[0] if typeof(col) == TYPE_ARRAY else col
	var ci := vert(center, nn, color)
	var base := v.size()
	for p in pts:
		vert(p, nn, color)
	for i in pts.size():
		var a := base + i
		var b := base + (i + 1) % pts.size()
		if start:
			tri(ci, b, a)
		else:
			tri(ci, a, b)

## Extrude a 2D outline (in the local ZY plane: x = along -Z... see `to3`) to a
## symmetric slab of half-thickness `half_w`, with a rounded edge of `bevel`.
## `outline` points are (forward, up); forward maps to -Z.
func slab(outline: PackedVector2Array, half_w: float, bevel: float, color: Color) -> void:
	var pts := outline
	if Geometry2D.is_polygon_clockwise(pts):
		pts = pts.duplicate()
		pts.reverse()
	var inner := pts
	if bevel > 0.0:
		var off := Geometry2D.offset_polygon(pts, -bevel, Geometry2D.JOIN_ROUND)
		if off.size() == 1 and off[0].size() >= 3:
			inner = _resample_like(off[0], pts)
	var m := pts.size()
	var base := v.size()
	var i_start := idx.size()
	# rings across the thickness: right face (inner), right edge, left edge, left face (inner)
	var layers := [[inner, half_w], [pts, half_w - bevel], [pts, -(half_w - bevel)], [inner, -half_w]]
	for layer in layers:
		var lp: PackedVector2Array = layer[0]
		for i in m:
			vert(Vector3(layer[1], lp[i].y, -lp[i].x), Vector3.UP, color)
	for l in layers.size() - 1:
		for i in m:
			var a := base + l * m + i
			var b := base + l * m + (i + 1) % m
			quad(b, a, a + m, b + m)
	smooth_normals(base, i_start)
	# flat side faces
	var tris := Geometry2D.triangulate_polygon(inner)
	for side in 2:
		var x := half_w if side == 0 else -half_w
		var nn := Vector3(1 if side == 0 else -1, 0, 0)
		var sb := v.size()
		for i in m:
			vert(Vector3(x, inner[i].y, -inner[i].x), nn, color)
		for t in range(0, tris.size(), 3):
			var q0 := inner[tris[t]]
			var q1 := inner[tris[t + 1]]
			var q2 := inner[tris[t + 2]]
			var ccw := (q1 - q0).cross(q2 - q0) > 0.0   # CCW as seen from +X
			if ccw == (side == 0):
				tri(sb + tris[t], sb + tris[t + 1], sb + tris[t + 2])
			else:
				tri(sb + tris[t], sb + tris[t + 2], sb + tris[t + 1])

static func _resample_like(poly: PackedVector2Array, like: PackedVector2Array) -> PackedVector2Array:
	# For each point of `like`, take the closest point on `poly` (keeps counts equal).
	var out := PackedVector2Array()
	out.resize(like.size())
	for i in like.size():
		var best := poly[0]
		var bd := INF
		for j in poly.size():
			var a := poly[j]
			var b := poly[(j + 1) % poly.size()]
			var q := Geometry2D.get_closest_point_to_segment(like[i], a, b)
			var d := q.distance_squared_to(like[i])
			if d < bd:
				bd = d
				best = q
		out[i] = best
	return out

## Recompute smooth normals for vertices >= v_start using triangles from i_start.
func smooth_normals(v_start: int, i_start: int) -> void:
	for i in range(v_start, v.size()):
		n[i] = Vector3.ZERO
	for t in range(i_start, idx.size(), 3):
		var i0 := idx[t]
		var i1 := idx[t + 1]
		var i2 := idx[t + 2]
		var fn := (v[i2] - v[i0]).cross(v[i1] - v[i0])   # stored order is clockwise
		n[i0] += fn
		n[i1] += fn
		n[i2] += fn
	for i in range(v_start, v.size()):
		n[i] = n[i].normalized() if n[i].length_squared() > 1e-12 else Vector3.UP

## Weld normals of coincident vertices (after lofting seams etc).
## Give every triangle from index `i_start` on its own vertices and one flat
## normal: a chiselled look for rock. Returns the first of the new vertices.
func facet(i_start: int) -> int:
	var tris := idx.slice(i_start)
	idx.resize(i_start)
	var first := v.size()
	for t in range(0, tris.size(), 3):
		var ia := tris[t]
		var ib := tris[t + 1]
		var ic := tris[t + 2]
		var nn := (v[ib] - v[ia]).cross(v[ic] - v[ia])
		if nn.length_squared() < 1e-12:
			continue
		nn = nn.normalized()
		if nn.dot(n[ia] + n[ib] + n[ic]) < 0.0:
			nn = -nn
		var base := v.size()
		for src in [ia, ib, ic]:
			v.append(v[src])
			n.append(nn)
			c.append(c[src])
			uv.append(uv[src])
		idx.append(base)
		idx.append(base + 1)
		idx.append(base + 2)
	return first

func recolor(v_start: int, fn: Callable) -> void:
	for i in range(v_start, v.size()):
		c[i] = fn.call(v[i], n[i], c[i])

func append_kit(other: MeshKit, t := Transform3D.IDENTITY) -> void:
	var base := v.size()
	for i in other.v.size():
		v.append(t * other.v[i])
		n.append((t.basis * other.n[i]).normalized())
		c.append(other.c[i])
		uv.append(other.uv[i])
	for i in other.idx:
		idx.append(base + i)

## Vertex colours are authored in sRGB; `linear` converts them for materials
## that use them directly as albedo.
func arrays(linear := false) -> Array:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = n
	if linear:
		var lc := PackedColorArray()
		lc.resize(c.size())
		for i in c.size():
			var col := c[i].srgb_to_linear()
			lc[i] = Color(col.r, col.g, col.b, c[i].a)
		a[Mesh.ARRAY_COLOR] = lc
	else:
		a[Mesh.ARRAY_COLOR] = c
	a[Mesh.ARRAY_TEX_UV] = uv
	if uv2.size() == v.size() and v.size() > 0:
		a[Mesh.ARRAY_TEX_UV2] = uv2
	a[Mesh.ARRAY_INDEX] = idx
	if skinned:
		a[Mesh.ARRAY_BONES] = bones
		a[Mesh.ARRAY_WEIGHTS] = weights
	return a

## Add this kit as a surface on `mesh` (created if null) and return the mesh.
func commit(material: Material = null, mesh: ArrayMesh = null, linear := false) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if v.size() == 0:
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays(linear))
	if material:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh

func tri_count() -> int:
	return idx.size() / 3
