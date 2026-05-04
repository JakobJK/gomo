extends Control

var edges: PackedVector2Array = []
var gomo_mesh = null  # GomoMesh

var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _panning: bool = false
var _pan_drag_start: Vector2 = Vector2.ZERO

var _selected_uvs: PackedVector2Array = []
var _dragging_uvs: bool = false
var _prev_drag_screen: Vector2

const PICK_RADIUS_PX := 10.0

func reset_view() -> void:
	var fit := minf(size.x, size.y) * 0.85
	_zoom = fit
	_pan = Vector2((size.x - fit) * 0.5, (size.y - fit) * 0.5)
	_selected_uvs = PackedVector2Array()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed: _zoom_at(event.position, 1.15)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed: _zoom_at(event.position, 1.0 / 1.15)
				accept_event()
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
				if _panning:
					_pan_drag_start = event.position - _pan
				accept_event()
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_on_left_press(event.position, event.shift_pressed)
				else:
					_dragging_uvs = false
				accept_event()
	elif event is InputEventMouseMotion:
		if _panning:
			_pan = event.position - _pan_drag_start
			queue_redraw()
			accept_event()
		elif _dragging_uvs and not _selected_uvs.is_empty():
			_on_uv_drag(event.position)
			accept_event()

func _on_left_press(screen_pos: Vector2, shift: bool) -> void:
	var uv := _screen_to_uv(screen_pos)
	var nearest := _nearest_uv_vert(uv)
	if nearest.x != INF:
		if not shift:
			_selected_uvs = PackedVector2Array([nearest])
		else:
			var found := false
			for i in _selected_uvs.size():
				if _selected_uvs[i].distance_squared_to(nearest) < 1e-8:
					var new_sel := PackedVector2Array()
					for j in _selected_uvs.size():
						if j != i: new_sel.append(_selected_uvs[j])
					_selected_uvs = new_sel
					found = true
					break
			if not found:
				_selected_uvs.append(nearest)
		_dragging_uvs = true
		_prev_drag_screen = screen_pos
	elif not shift:
		_selected_uvs = PackedVector2Array()
		_dragging_uvs = false
	queue_redraw()

func _on_uv_drag(screen_pos: Vector2) -> void:
	if gomo_mesh == null:
		return
	var delta_screen := screen_pos - _prev_drag_screen
	var delta_uv := Vector2(delta_screen.x / _zoom, -delta_screen.y / _zoom)
	gomo_mesh.hem.translate_uvs(_selected_uvs, delta_uv, 0.0001)
	for i in _selected_uvs.size():
		_selected_uvs[i] += delta_uv
	edges = gomo_mesh.hem.get_uv_edges()
	_prev_drag_screen = screen_pos
	queue_redraw()
	gomo_mesh.refresh()

func _zoom_at(pos: Vector2, factor: float) -> void:
	_pan = pos + (_pan - pos) * factor
	_zoom *= factor
	queue_redraw()

func _screen_to_uv(screen: Vector2) -> Vector2:
	return Vector2((screen.x - _pan.x) / _zoom, 1.0 - (screen.y - _pan.y) / _zoom)

func _uv_to_screen(uv: Vector2) -> Vector2:
	return Vector2(_pan.x + uv.x * _zoom, _pan.y + (1.0 - uv.y) * _zoom)

func _nearest_uv_vert(uv: Vector2) -> Vector2:
	var thresh_sq := (PICK_RADIUS_PX / _zoom) ** 2
	var best := Vector2(INF, INF)
	var best_d := thresh_sq
	for pt in edges:
		var d := uv.distance_squared_to(pt)
		if d < best_d:
			best_d = d
			best = pt
	return best

func _draw() -> void:
	draw_rect(Rect2(_pan, Vector2(_zoom, _zoom)), Color(0.12, 0.12, 0.12, 1.0))
	if not edges.is_empty():
		var col := Color(0.8, 0.8, 0.8, 1.0)
		var i := 0
		while i + 1 < edges.size():
			draw_line(_uv_to_screen(edges[i]), _uv_to_screen(edges[i + 1]), col, 1.0, true)
			i += 2
	for uv in _selected_uvs:
		var sc := _uv_to_screen(uv)
		draw_circle(sc, 5.0, Color(1.0, 0.55, 0.1, 1.0))
