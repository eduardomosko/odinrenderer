package renderer

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

Face :: [3]struct {
	v:  uint,
	vt: uint,
	vn: uint,
}

Model :: struct {
	v:  [dynamic][3]f64,
	vt: [dynamic][3]f64,
	vn: [dynamic][3]f64,
	f:  [dynamic]Face,
}

destroy :: proc(m: ^Model) {
	delete(m.v)
	delete(m.vt)
	delete(m.vn)
	delete(m.f)
}

model_load_from_file :: proc(filepath: string) -> (m: Model, ok: bool) {
	data: []u8
	data, ok = os.read_entire_file(filepath)
	if !ok {
		fmt.printfln("unable to read file")
		return {}, false
	}
	defer delete(data)
	it := string(data)

	lineno := 0

	defer if !ok {
		fmt.printfln("model load error. line %v", lineno)
		destroy(&m)
		m = {}
	}

	for line in strings.split_lines_iterator(&it) {
		lineno += 1

		if strings.starts_with(line, "f ") {
			line := line[1:]

			face := Face{}
			for &vertex in face {
				for line[0] == ' ' {
					line = line[1:]
				}
				n := 0

				vertex.v, ok = strconv.parse_uint(line, 10, &n)
				if !ok && n == 0 {return}
				line = line[n + 1:]

				vertex.vt, ok = strconv.parse_uint(line, 10, &n)
				if !ok && n == 0 {return}
				line = line[n + 1:]

				vertex.vn, ok = strconv.parse_uint(line, 10, &n)
				if !ok && n == 0 {return}
				line = line[n:]

				// obj indexes start at 1
				vertex.v -= 1
				vertex.vt -= 1
				vertex.vn -= 1
			}

			_, err := append(&m.f, face)
			assert(err == nil)

		} else if strings.starts_with(line, "v ") {
			line := line[1:]

			vec := [3]f64{}
			for &val in vec {
				for line[0] == ' ' {
					line = line[1:]
				}

				value, n := strconv.parse_f64_prefix(line) or_return
				val = value
				line = line[n:]
			}

			_, err := append(&m.v, vec)
			assert(err == nil)
		} else if strings.starts_with(line, "vt ") {
			line := line[2:]

			vec := [3]f64{}
			for &val in vec {
				for line[0] == ' ' {
					line = line[1:]
				}

				value, n := strconv.parse_f64_prefix(line) or_return
				val = value
				line = line[n:]
			}

			_, err := append(&m.vt, vec)
			assert(err == nil)
		} else if strings.starts_with(line, "vn ") {
			line := line[2:]

			vec := [3]f64{}
			for &val in vec {
				for line[0] == ' ' {
					line = line[1:]
				}

				value, n := strconv.parse_f64_prefix(line) or_return
				val = value
				line = line[n:]
			}

			_, err := append(&m.vn, vec)
			assert(err == nil)
		}
	}

	return m, true
}
