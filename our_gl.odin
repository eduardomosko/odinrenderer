package renderer

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"

Shader :: struct {
	vertex:   proc(data: rawptr, model: Model, iface, nthvert: int) -> [4]f64,
	fragment: proc(data: rawptr, barycenter: [3]f64) -> (color: Color, discard: bool),
	data:     rawptr,
}

Projection: matrix[4, 4]f64 = 1 // perspective transformation
ModelView: matrix[4, 4]f64 = 1 // lookat transformation
Viewport: matrix[4, 4]f64 = 1 // viewport bounds

projection :: proc(coeff: f64) {
	// https://github.com/ssloy/tinyrenderer/wiki/Lesson-4:-Perspective-projection#let-us-sum-up-the-main-formula-for-today
	p: matrix[4, 4]f64 = 1
	p[3, 2] = coeff
	Projection = p
}

lookat :: proc(eye, center, up: [3]f64) {
	z := linalg.normalize(eye - center)
	x := linalg.normalize(linalg.vector_cross(up, z))
	y := linalg.normalize(linalg.vector_cross(z, x))

	mv: matrix[4, 4]f64 = 1
	for i in 0 ..< 3 {
		mv[0, i] = x[i]
		mv[1, i] = y[i]
		mv[2, i] = z[i]
		mv[i, 3] = -center[i]
	}

	ModelView = mv
}

viewportf :: proc(x, y, w, h: f64) {
	depth :: 255 // how many z indexes to consider
	v: matrix[4, 4]f64 = 1

	// translation
	v[0, 3] = x + w / 2
	v[1, 3] = y + w / 2
	v[2, 3] = depth / 2.

	// scale
	v[0, 0] = w / 2
	v[1, 1] = h / 2
	v[2, 2] = depth / 2.

	Viewport = v
}

viewporti :: proc(x, y, w, h: int) {
	viewportf(f64(x), f64(y), f64(w), f64(h))
}

viewport :: proc {
	viewportf,
	viewporti,
}

triangle_uv :: proc(t: [3][2]f64, p: [2]f64) -> [2]f64 {
	a := t[0]
	b := t[1]
	c := t[2]
	swapped := false

	if c.y == a.y {
		b, c = c, b
		swapped = true
	}

	u_nume := a.x * (c.y - a.y) + (p.y - a.y) * (c.x - a.x) - p.x * (c.y - a.y)
	u_deno := (b.y - a.y) * (c.x - a.x) - (b.x - a.x) * (c.y - a.y)

	v_nume := p.y * u_deno - a.y * u_deno - u_nume * (b.y - a.y)
	v_deno := (c.y - a.y) * u_deno

	u := u_nume / u_deno
	v := v_nume / v_deno

	if swapped {
		return {v, u}
	}
	return {u, v}
}

barycentric :: proc(t: [3][2]f64, p: [2]f64) -> [3]f64 {
	uv := triangle_uv(t, p)
	return [3]f64{1 - uv.x - uv.y, uv.x, uv.y}
}

vec_to_type :: #force_inline proc "contextless" ($Target: typeid/[$Nr]$R, input: [$N]$T) -> Target {
	output: Target = 0
    less := len(output) if len(output) < len(input) else len(input)
	for i in 0 ..< less {
		output[i] = cast(R)input[i]
	}
	return output
}

vec_to_ptr :: #force_inline proc "contextless" (output: ^[$Nr]$R, input: [$N]$T) {
    less := len(output) if len(output) < len(input) else len(input)
	for i in 0 ..< less {
		output[i] = cast(R)input[i]
	}
}

vec_to_override :: #force_inline proc "contextless" (base: [$Nr]$R, input: [$N]$T) -> [Nr]R {
    output := base
    less := len(base) if len(base) < len(input) else len(input)
	for i in 0 ..< less {
		output[i] = cast(R)input[i]
	}
    return output
}

vec_to :: proc {
	vec_to_type,
	vec_to_ptr,
	vec_to_override,
}

// weird version
_triangle :: proc(img: ^Image, triangle: [3][4]f64, zbuf: []f64, shader: Shader) {
	aa, bb: [2]int
	{
		aaf := [2]f64{math.F64_MAX, math.F64_MAX}
		bbf := [2]f64{-math.F64_MAX, -math.F64_MAX}
		clamp := [2]f64{f64(img.width - 1), f64(img.height - 1)}
		for i in 0 ..< 3 {
			for j in 0 ..< 2 {
				aaf[j] = max(0, min(aaf[j], triangle[i][j]/triangle[i].w))
				bbf[j] = min(clamp[j], max(bbf[j], triangle[i][j]/triangle[i].w))
			}
		}
		aa = vec_to([2]int, aaf)
		bb = vec_to([2]int, bbf)
	}


	for y in aa.y ..= bb.y {
		for x in aa.x ..= bb.x {
			triangle2D := [3][2]f64 {
				triangle[0].xy / triangle[0].w,
				triangle[1].xy / triangle[1].w,
				triangle[2].xy / triangle[2].w,
			}
			point: [2]f64 = {f64(x), f64(y)}
			barycenter := barycentric(triangle2D, point)

			if barycenter.x < 0 || barycenter.y < 0 || barycenter.z < 0 {
				continue // skip outside triangle
			}

			z :=
				triangle[0].z * barycenter[0] +
				triangle[1].z * barycenter[1] +
				triangle[2].z * barycenter[2]
			w :=
				triangle[0].w * barycenter[0] +
				triangle[1].w * barycenter[1] +
				triangle[2].w * barycenter[2]

			depth := z / w + 0.5
			zindex := x + y * img.width

			if zbuf[zindex] > depth {
				continue // skip if something in front
			}

			color, discard := shader.fragment(shader.data, barycenter)
			if !discard {
				zbuf[zindex] = depth
				image_set(img, color, x, y)
			}
		}
	}
}

triangle :: proc(img: ^Image, triangle: [3][4]f64, zbuf: []f64, shader: Shader) {
	for &point in triangle {
		point /= point.w
	}

	aa, bb: [2]int
	{
		aaf := [2]f64{math.F64_MAX, math.F64_MAX}
		bbf := [2]f64{-math.F64_MAX, -math.F64_MAX}
		clamp := [2]f64{f64(img.width - 1), f64(img.height - 1)}
		for i in 0 ..< 3 {
			for j in 0 ..< 2 {
				aaf[j] = max(0, min(aaf[j], triangle[i][j]/triangle[i].w))
				bbf[j] = min(clamp[j], max(bbf[j], triangle[i][j]/triangle[i].w))
			}
		}
		aa = vec_to([2]int, aaf)
		bb = vec_to([2]int, bbf)
	}


	for y in aa.y ..= bb.y {
		for x in aa.x ..= bb.x {
			triangle2D := [3][2]f64 {
				triangle[0].xy,
				triangle[1].xy,
				triangle[2].xy,
			}
			point: [2]f64 = {f64(x), f64(y)}
			barycenter := barycentric(triangle2D, point)

			if barycenter.x < 0 || barycenter.y < 0 || barycenter.z < 0 {
				continue // skip outside triangle
			}

			z :=
				triangle[0].z * barycenter[0] +
				triangle[1].z * barycenter[1] +
				triangle[2].z * barycenter[2]
			zindex := x + y * img.width

			if zbuf[zindex] > z {
				continue // skip if something in front
			}

			color, discard := shader.fragment(shader.data, barycenter)
			if !discard {
				zbuf[zindex] = z
				image_set(img, color, x, y)
			}
		}
	}
}
