package renderer

Shader :: struct {
	vertex: proc(model: ^Model) -> [4]f64,
	fragment: proc() -> bool,
	data:   rawptr,
}
