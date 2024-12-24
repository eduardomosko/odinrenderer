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

GouraudShader :: struct {
	light:     [3]f64,

	// written by vertex shader, read by fragment shader
	intensity: [3]f64,
}

gouraud_shader :: proc(this: ^GouraudShader) -> Shader {
	return Shader {
		vertex = auto_cast (gouraud_vertex),
		fragment = auto_cast (gouraud_fragment),
		data = this,
	}
}

gouraud_vertex :: proc(this: ^GouraudShader, model: Model, iface, nverth: int) -> [4]f64 {
	vdata := model.f[iface][nverth]
	normal := model.vn[vdata.vn]
	vert := model.v[vdata.v]

	this.intensity[nverth] = max(0., linalg.vector_dot(normal, this.light))

	output: [4]f64 = 1
	output.xyz = vert
	output = Viewport * Projection * ModelView * output
	return output
}

gouraud_fragment :: proc(this: ^GouraudShader, barycenter: [3]f64) -> (Color, bool) {
	intensity := linalg.vector_dot(this.intensity, barycenter)
	color: Color = u8(255 * intensity)
	return color, false
}

ToonShader :: struct {
	light:     [3]f64,
	color:     Color,

	// written by vertex shader, read by fragment shader
	intensity: [3]f64,
}

toon_shader :: proc(this: ^ToonShader) -> Shader {
	return Shader {
		vertex = auto_cast (toon_vertex),
		fragment = auto_cast (toon_fragment),
		data = this,
	}
}

toon_vertex :: proc(this: ^ToonShader, model: Model, iface, nverth: int) -> [4]f64 {
	vdata := model.f[iface][nverth]
	normal := model.vn[vdata.vn]
	vert := model.v[vdata.v]

	this.intensity[nverth] = max(0., linalg.vector_dot(normal, this.light))

	output: [4]f64 = 1
	output.xyz = vert
	output = Viewport * Projection * ModelView * output
	return output
}

toon_fragment :: proc(this: ^ToonShader, barycenter: [3]f64) -> (Color, bool) {
	intensity := linalg.vector_dot(this.intensity, barycenter)
	if intensity > 0.8 do intensity = 1
	else if intensity > 0.4 do intensity = .6
	else if intensity > 0.0 do intensity = .2

	color := vec_to(Color, vec_to([3]f64, this.color) * intensity)
	return color, false
}

TextureShader :: struct {
	light:     [3]f64,
	texture:   ^image.Image,

	// written by vertex shader, read by fragment shader
	intensity: [3]f64,
	uvs:       matrix[3, 3]f64,
}

texture_shader :: proc(this: ^TextureShader) -> Shader {
	return Shader {
		vertex = auto_cast (texture_vertex),
		fragment = auto_cast (texture_fragment),
		data = this,
	}
}

texture_vertex :: proc(this: ^TextureShader, model: Model, iface, nverth: int) -> [4]f64 {
	vdata := model.f[iface][nverth]
	normal := model.vn[vdata.vn]
	uvs := model.vt[vdata.vt]
	vert := model.v[vdata.v]

	this.intensity[nverth] = max(0., linalg.vector_dot(normal, this.light))
	this.uvs[nverth] = uvs

	output: [4]f64 = 1
	output.xyz = vert
	output = Viewport * Projection * ModelView * output
	return output
}

texture_fragment :: proc(this: ^TextureShader, barycenter: [3]f64) -> (Color, bool) {
	intensity := linalg.vector_dot(this.intensity, barycenter)
	//intensity := (this.intensity[0] + this.intensity[1] + this.intensity[2]) / 3

	uvs := this.uvs * barycenter
	uvs.y = 1 - uvs.y // invert y
	uvs.x *= f64(this.texture.width)
	uvs.y *= f64(this.texture.height)
	color := image_get(this.texture, int(uvs.x), int(uvs.y))

	//if intensity > 0.8 do intensity = 1
	//else if intensity > 0.4 do intensity = .6
	//else if intensity > 0.0 do intensity = .2

	color = vec_to(Color, vec_to([3]f64, color) * intensity)
	return color, false
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

	img := image_create(600, 600)
	defer image_destroy(&img)

	//slice.fill(img.pixels[:], Color{127, 127, 127})

	zbuffer := make([]f64, img.width * img.height)
	slice.fill(zbuffer, -math.F64_MAX)

	light := [3]f64{1, 1, 1}
	light = linalg.vector_normalize(light)

	{
		scale := 2. / 3.
		size := [2]f64{f64(img.width), f64(img.height)}
		center := size / 2
		size *= scale

		viewport(center.x - size.x / 2, center.y - size.y / 2., size.x, -size.y)
	}

	{
		eye := [3]f64{1, 1, 3}
		center := [3]f64{0, 0, 0}
		up := [3]f64{0, 1, 0}

		lookat(eye, center, up)
		projection(-1. / 3.)
	}


	gouraud := GouraudShader {
		light = light,
	}
	//shader := gouraud_shader(&gouraud)

	toon := ToonShader {
		light = light,
		color = Color{100, 20, 200},
		//color = Color{255, 155, 0},
	}
	//shader := toon_shader(&toon)

	textures := TextureShader {
		light   = light,
		texture = texture,
		//color = Color{255, 155, 0},
	}
	shader := texture_shader(&textures)

	for _, i in model.f {
		coords := [3][4]f64{}
		for &coord, j in coords {
			coord = shader.vertex(shader.data, model, i, j)
		}
		triangle(&img, coords, zbuffer, shader)
	}

	image_write(&img, "output.tga")

	zmax := slice.max(zbuffer)

	zmin := math.F64_MAX
	for z in zbuffer {
		if z != -math.F64_MAX && z < zmin {
			zmin = z
		}
	}

	slice.fill(img.pixels[:], 0)
	for y in 0 ..< img.height {
		for x in 0 ..< img.width {
			c := zbuffer[x + y * img.height]
			if c == -math.F64_MAX do continue
			c = ((c - zmin) / (zmax - zmin)) * 255
			image_set(&img, u8(c), x, y)
		}
	}

	image_write(&img, "zbuffer.tga")
}
