package renderer

import "core:bytes"
import "core:c"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:image/tga"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

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
	//intensity := (this.intensity[0] + this.intensity[1] + this.intensity[2]) / 3

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

	uvs := this.uvs * barycenter
	uvs.y = 1 - uvs.y // invert y
	uvs.x *= f64(this.texture.width)
	uvs.y *= f64(this.texture.height)
	color := image_get(this.texture, int(uvs.x), int(uvs.y))

	color = vec_to(Color, vec_to([3]f64, color) * intensity)
	return color, false
}

TexNormalShader :: struct {
	light:   [3]f64,
	texture: ^image.Image,
	normals: ^image.Image,
	index:   int,

	// written by vertex shader, read by fragment shader
	uvs:     matrix[3, 3]f64,
}

texnormal_shader :: proc(this: ^TexNormalShader) -> Shader {
	return Shader {
		vertex = auto_cast (texnormal_vertex),
		fragment = auto_cast (texnormal_fragment),
		data = this,
	}
}

texnormal_vertex :: proc(this: ^TexNormalShader, model: Model, iface, nverth: int) -> [4]f64 {
	vdata := model.f[iface][nverth]
	normal := model.vn[vdata.vn]
	uvs := model.vt[vdata.vt]
	vert := model.v[vdata.v]

	this.uvs[nverth] = uvs

	output: [4]f64 = 1
	output.xyz = vert
	output = Viewport * Projection * ModelView * output
	return output
}

texnormal_fragment :: proc(this: ^TexNormalShader, barycenter: [3]f64) -> (Color, bool) {
	this.index += 1
	uvs := this.uvs * barycenter
	uvs.y = 1 - uvs.y // invert y

	color := image_get(
		this.texture,
		int(uvs.x * f64(this.texture.width)),
		int(uvs.y * f64(this.texture.height)),
	)

	u8normal := image_get(
		this.normals,
		int(uvs.x * f64(this.normals.width)),
		int(uvs.y * f64(this.normals.height)),
	)
	u8normal.zyx = u8normal
	normal := [3]f64{cast(f64)u8normal.x, cast(f64)u8normal.y, cast(f64)u8normal.z}
	normal = (normal / 255.) * 2. - 1.
	normal = linalg.vector_normalize(normal)
	intensity := max(0., linalg.vector_dot(normal, this.light))

	color = vec_to(Color, vec_to([3]f64, color) * intensity)
	return color, false
}


main :: proc() {
	model, ok := model_load_from_file("models/african_head.obj")
	if !ok {
		return
	}
	defer destroy(&model)

	err: image.Error
	texture: ^image.Image
	normalsTexture: ^image.Image

	texture, err = tga.load_from_file("models/african_head_diffuse.tga")
	assert(err == nil)
	defer image.destroy(texture)

	normalsTexture, err = tga.load_from_file("models/african_head_nm.tga")
	assert(err == nil)
	defer image.destroy(normalsTexture)

	img := image_create(800, 800)
	defer image_destroy(&img)

	//slice.fill(img.pixels[:], Color{127, 127, 127})

	zbuffer := make([]f64, img.width * img.height)
	slice.fill(zbuffer, -math.F64_MAX)

	light := [3]f64{1, 1, 1}
	light = linalg.vector_normalize(light)

	scale := 2. / 3.
	size := [2]f64{f64(img.width), f64(img.height)}
	imgcenter := size / 2
	size *= scale

	eye := [3]f64{1, 0.3, 1}
	center := [3]f64{0, 0, 0}
	up := [3]f64{0, 1, 0}

	lookat(eye, center, up)
	projection(-1. / 3.)
	viewport(imgcenter.x - size.x / 2, imgcenter.y - size.y / 2., size.x, -size.y)


	gouraud := GouraudShader {
		light = light,
	}
	shader := gouraud_shader(&gouraud)

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
	//shader := texture_shader(&textures)

	texnormal := TexNormalShader {
		light   = light,
		texture = texture,
		normals = normalsTexture,
	}
	//shader := texnormal_shader(&texnormal)

	rl.SetConfigFlags(rl.ConfigFlags{.WINDOW_UNFOCUSED})
	rl.InitWindow(cast(c.int)img.width * 2, cast(c.int)img.height, "Renderer")
	defer rl.CloseWindow()

	angle := 45.
	for !rl.WindowShouldClose() {
		if rl.IsKeyPressed(rl.KeyboardKey.N) {
			shader = texnormal_shader(&texnormal)
		}
		if rl.IsKeyPressed(rl.KeyboardKey.T) {
			shader = texture_shader(&textures)
		}
		if rl.IsKeyPressed(rl.KeyboardKey.O) {
			shader = toon_shader(&toon)
		}
		if rl.IsKeyPressed(rl.KeyboardKey.G) {
			shader = gouraud_shader(&gouraud)
		}

		angle += 20 * f64(rl.GetFrameTime())
		angle := linalg.to_radians(angle)
		eye.x = math.cos(angle)
		eye.z = math.sin(angle)

		light.y = 1
		light.x = math.cos(-angle) * 4
		light.z = math.sin(-angle) * 4
		gouraud.light = linalg.vector_normalize(light)

		fmt.printfln("eye: %v", eye)

		lookat(eye, center, up)
		slice.fill(zbuffer, -math.F64_MAX)

		// Render image
		texnormal.index = 0
		for _, i in model.f {
			coords := [3][4]f64{}
			for &coord, j in coords {
				coord = shader.vertex(shader.data, model, i, j)
			}
			triangle(&img, coords, zbuffer, shader)
		}

		//image_write(&img, "output.tga")

		// Draw zbuffer
		zmax := slice.max(zbuffer)
		zmin := math.F64_MAX
		for z in zbuffer {
			if z != -math.F64_MAX && z < zmin {
				zmin = z
			}
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		for y in 0 ..< img.height {
			for x in 0 ..< img.width {
				i := x + y * img.height
				z := zbuffer[i]
				if z == -math.F64_MAX do continue
				z = ((z - zmin) / (zmax - zmin)) * 255

				color: rl.Color = 255
				color.rgb = u8(z)
				rl.DrawPixel(cast(c.int)x, cast(c.int)y, color)

				color.rgb = img.pixels[i]
				rl.DrawPixel(cast(c.int)(x + img.width), cast(c.int)y, color)
			}
		}

		rl.DrawFPS(5, 5)
		rl.EndDrawing()

		//image_write(&img, "zbuffer.tga")
	}

}
