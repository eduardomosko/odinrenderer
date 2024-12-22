package renderer

import "core:bytes"
import "core:fmt"
import "core:image"
import "core:image/tga"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"
import "core:strconv"
import "core:strings"

image_draw_line :: proc(img: ^Image, color: Color, p1: [2]int, p2: [2]int) {
	p1 := p1
	p2 := p2
	steep := abs(p2.x - p1.x) < abs(p2.y - p1.y)

	if (steep) {
		p1.xy = p1.yx
		p2.xy = p2.yx
	}

	if (p1.x > p2.x) {
		p1, p2 = p2, p1
	}

	dx := p2.x - p1.x
	dy := p2.y - p1.y

	derr2 := abs(dy) * 2
	ydir := 1 if p2.y > p1.y else -1
	dx2 := dx * 2

	y := p1.y
	err2 := 0

	for x in p1.x ..= p2.x {
		err2 += derr2
		if (err2 > dx) {
			y += ydir
			err2 -= dx2
		}

		if (steep) {
			image_set(img, color, y, x)
		} else {
			image_set(img, color, x, y)
		}
	}
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

image_draw_triangle :: proc(img: ^Image, t: [3][3]f64, zbuf: []f64, color: Color) {
	aa := [2]f64{math.F64_MAX, math.F64_MAX}
	bb := [2]f64{-math.F64_MAX, -math.F64_MAX}
	clamp := [2]f64{f64(img.width - 1), f64(img.height - 1)}
	for i in 0 ..< 3 {
		for j in 0 ..< 2 {
			aa[j] = max(0, min(aa[j], t[i][j]))
			bb[j] = min(clamp[j], max(bb[j], t[i][j]))
		}
	}

	for y in int(aa.y) ..= int(bb.y) {
		for x in int(aa.x) ..= int(bb.x) {
			uv := triangle_uv({t[0].xy, t[1].xy, t[2].xy}, {f64(x), f64(y)})
			bar := [3]f64{1 - uv.x - uv.y, uv.x, uv.y}

			if bar.x < 0 || bar.y < 0 || bar.z < 0 {
				continue // skip outside triangle
			}

			z := t[0].z * bar[0] + t[1].z * bar[1] + t[2].z * bar[2]
			zindex := x + y * img.width

			if zbuf[zindex] > z {
				continue // skip if something in front
			}

			zbuf[zindex] = z
			image_set(img, color, x, y)
		}
	}
}

image_draw_triangle_texture :: proc(
	img: ^Image,
	t: [3][3]f64,
	zbuf: []f64,
	texture: ^image.Image,
	texture_uvs: [3][3]f64,
	brightness: f64,
) {
	aa := [2]f64{math.F64_MAX, math.F64_MAX}
	bb := [2]f64{math.F64_MIN, math.F64_MIN}
	clamp := [2]f64{f64(img.width - 1), f64(img.height - 1)}
	for i in 0 ..< 3 {
		for j in 0 ..< 2 {
			aa[j] = max(0, min(aa[j], t[i][j]))
			bb[j] = min(clamp[j], max(bb[j], t[i][j]))
		}
	}

	for y in int(aa.y) ..= int(bb.y) {
		for x in int(aa.x) ..= int(bb.x) {
			uv := triangle_uv({t[0].xy, t[1].xy, t[2].xy}, {f64(x), f64(y)})
			bar := [3]f64{1 - uv.x - uv.y, uv.x, uv.y}

			if bar.x < 0 || bar.y < 0 || bar.z < 0 {
				continue // skip outside triangle
			}

			z := t[0].z * bar[0] + t[1].z * bar[1] + t[2].z * bar[2]
			zindex := x + y * img.width

			if zbuf[zindex] > z {
				continue // skip if something in front
			}

			zbuf[zindex] = z

			texture_uv :=
				texture_uvs[0] * bar[0] + texture_uvs[1] * bar[1] + texture_uvs[2] * bar[2]
			texture_uv.y = 1 - texture_uv.y
			texture_coord := [2]f64{f64(texture.width), f64(texture.height)} * texture_uv.xy

			color := image_get(texture, int(texture_coord.x), int(texture_coord.y))
			color.r = u8(f64(color.r) * brightness)
			color.g = u8(f64(color.g) * brightness)
			color.b = u8(f64(color.b) * brightness)

			image_set(img, color, x, y)
		}
	}
}

mat_lookat :: proc(eye, center, up: [3]f64) -> matrix[4, 4]f64 {
	z := linalg.normalize(eye - center)
	x := linalg.normalize(linalg.vector_cross(up, z))
	y := linalg.normalize(linalg.vector_cross(z, x))

	minv := (matrix[4, 4]f64)(1)
	translate := (matrix[4, 4]f64)(1)
	for i in 0 ..< 3 {
		minv[0, i] = x[i]
		minv[1, i] = y[i]
		minv[2, i] = z[i]
		translate[i, 3] = -eye[i]
	}

	return minv * translate
}

mat_viewport :: proc(x, y, w, h: int) -> matrix[4, 4]f64 {
	depth :: 255
	x, y, w, h := f64(x), f64(y), f64(w), f64(h)
	m := (matrix[4, 4]f64)(1)
	// translation
	m[0, 3] = x + w / 2
	m[1, 3] = y + w / 2
	m[2, 3] = depth / 2

	// scale
	m[0, 0] = w / 2
	m[1, 1] = h / 2
	m[2, 2] = depth / 2

	return m
}


main :: proc() {
	model, ok := model_load_from_file("models/african_head.obj")
	if !ok {
		return
	}
	defer destroy(&model)

	texture, err := tga.load_from_file("models/african_head_diffuse.tga")
	assert(err == nil)
	defer image.destroy(texture)

	img := image_create(2000, 2000)
	defer image_destroy(&img)

	slice.fill(img.pixels[:], Color{127, 127, 127})

	zbuffer := make([]f64, img.width * img.height)
	for &v in zbuffer do v = -math.F64_MAX

	image_draw_line(&img, {255, 255, 255}, {10, 10}, {20, 20})
	image_draw_line(&img, {255, 0, 255}, {20, 20}, {60, 50})

	light := [3]f64{0, 0, 1}

	viewport := mat_viewport(
		img.width / 2. - (img.width * 2. / 3.) / 2,
		img.height / 2. - (img.height * 2. / 3.) / 2,
		img.width * 2. / 3.,
		-img.height * 2. / 3.,
	)
	lookat := mat_lookat({-0.5, 0.1, 0.5}, {0, 0, 0}, {0, 1, 0})

	for face in model.f {
		screen_coords := [3][3]f64{}
		world_coords := [3][3]f64{}
		texture_uvs := [3][3]f64{}
		normals := [3][3]f64{}

		for vertex, i in face {
			world_coords[i] = model.v[vertex.v]
			texture_uvs[i] = model.vt[vertex.vt]
			normals[i] = model.vn[vertex.vn]

			transform := (matrix[4, 4]f64)(1)
			transform[3, 2] = -1. / 3. // perspective transformation

			vert := ([4]f64)(1)
			vert.xyz = world_coords[i].xyz

			vert = lookat * vert
			vert = transform * vert
			vert = viewport * vert
			sc := vert.xyz / vert.w

			//sc.x = (sc.x + 1) / 2 * f64(img.width)
			//sc.y = (-sc.y + 1) / 2 * f64(img.height)
			//sc.z += 0

			screen_coords[i] = sc
		}

		face_normal := linalg.vector_cross(
			world_coords[2] - world_coords[0],
			world_coords[1] - world_coords[0],
		)
		face_normal = linalg.normalize(face_normal) * -1
		b := abs(linalg.vector_dot(face_normal, light))

		if b > 0 {
			image_draw_triangle_texture(&img, screen_coords, zbuffer, texture, texture_uvs, b)
		}
	}

	image_write(&img, "output.tga")
}
