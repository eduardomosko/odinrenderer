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

Color :: image.RGB_Pixel
Image :: struct {
	pixels: []Color,
	width:  int,
	height: int,
}

image_create :: proc(w: int, h: int) -> Image {
	return Image{width = w, height = h, pixels = make([]Color, w * h)}
}

image_set :: proc(img: ^Image, color: Color, x: int, y: int) {
	img.pixels[x + y * img.width] = color
}

image_get :: proc(img: ^image.Image, x, y: int) -> image.RGB_Pixel {
	assert(img.channels == 3)
	assert(img.depth == 8)
	assert(x >= 0 && x < img.width, fmt.tprintf("x: %v, w: %v", x, img.width))
	assert(y >= 0 && y < img.height, fmt.tprintf("y: %v, h: %v", y, img.height))

	pixel := image.RGB_Pixel{}

	n, err := bytes.buffer_read_at(&img.pixels, pixel[:], (x + y * img.width) * 3)
	assert(n == 3)
	assert(err == nil)
	return pixel
}

image_write :: proc(img: ^Image, filepath: string) -> bool {
	img := image.pixels_to_image(img.pixels, int(img.width), int(img.height)) or_return
	return tga.save_to_file(filepath, &img) == nil
}

image_destroy :: proc(img: ^Image) {
	defer delete(img.pixels)
}
