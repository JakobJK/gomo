extends Control

var edges:         PackedVector2Array = []
var seam_edges:    PackedVector2Array = []
var face_polygons: Array             = []
var gomo_mesh = null

var _background: ImageTexture = null
var last_baked_image: Image   = null

var _zoom: float  = 1.0
var _pan: Vector2 = Vector2.ZERO

var _panning: bool      = false
var _pan_start: Vector2 = Vector2.ZERO

var _zoom_dragging: bool   = false
var _zoom_anchor: Vector2  = Vector2.ZERO

var _marquee_active: bool   = false
var _marquee_start: Vector2 = Vector2.ZERO
var _marquee_end: Vector2   = Vector2.ZERO

# Index-based UV vert data
var _he_indices: PackedInt32Array   = []
var _he_uvs:     PackedVector2Array = []

var _selected_he: PackedInt32Array  = []

# Gizmo
enum GizmoPart { NONE, FREE, AXIS_U, AXIS_V }
var _hovered_part: int = GizmoPart.NONE
var _active_part:  int = GizmoPart.NONE

# Transform drag
var _dragging: bool = false
var _left_held: bool = false
var _left_press_pos: Vector2 = Vector2.ZERO
var _drag_initial_uvs: PackedVector2Array = []

const ARROW_LEN  := 70.0
const CENTER_SZ  := 10.0
const ROTATE_R   := 55.0
const HIT_R      := 10.0

const COL_U      := Color(0.9,  0.18, 0.18)
const COL_V      := Color(0.18, 0.85, 0.18)
const COL_CENTER := Color(0.9,  0.9,  0.9)
const COL_HOVER  := Color(1.0,  0.9,  0.1)

const PICK_RADIUS_PX := 10.0

func reset_view() -> void:
	var fit := minf(size.x, size.y) * 0.85
	_zoom = fit
	_pan  = Vector2((size.x - fit) * 0.5, (size.y - fit) * 0.5)
	_selected_he = PackedInt32Array()
	queue_redraw()

func set_uv_vert_data(verts: Array) -> void:
	_he_indices = verts[0]
	_he_uvs     = verts[1]

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
				if _panning: _pan_start = event.position - _pan
				accept_event()
			MOUSE_BUTTON_RIGHT:
				_zoom_dragging = event.pressed
				if _zoom_dragging: _zoom_anchor = event.position
				accept_event()
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_left_held      = true
					_left_press_pos = event.position
					_on_left_press(event.position, event.shift_pressed)
				else:
					_left_held = false
					if _marquee_active:
						_finish_marquee(event.shift_pressed)
						_marquee_active = false
					_dragging    = false
					_active_part = GizmoPart.NONE
				accept_event()

	elif event is InputEventMouseMotion:
		if _zoom_dragging:
			_zoom_at(_zoom_anchor, 1.0 + event.relative.x * 0.005)
			accept_event()
		elif _panning:
			_pan = event.position - _pan_start
			queue_redraw()
			accept_event()
		elif _marquee_active:
			_marquee_end = event.position
			queue_redraw()
			accept_event()
		elif _dragging:
			_on_transform_drag(event.position)
			accept_event()
		elif _left_held and event.position.distance_to(_left_press_pos) > 3.0:
			# threshold crossed — begin drag if gizmo was hit
			if _active_part != GizmoPart.NONE:
				_dragging = true
				_on_transform_drag(event.position)
				accept_event()
		else:
			# hover
			var prev := _hovered_part
			_hovered_part = _gizmo_hit(event.position)
			if _hovered_part != prev: queue_redraw()

func _on_left_press(screen_pos: Vector2, shift: bool) -> void:
	var tool := State.active_tool
	# Check gizmo first if selection exists and tool active
	if not _selected_he.is_empty() and tool != null:
		var part := _gizmo_hit(screen_pos)
		if part != GizmoPart.NONE:
			_active_part      = part
			_drag_initial_uvs = _current_selected_uvs()
			return

	# Check UV vert hit
	var hits := _he_indices_at_screen(screen_pos)
	if not hits.is_empty():
		if not shift:
			_selected_he = hits
		else:
			var first := hits[0]
			var already := false
			for s in _selected_he:
				if s == first: already = true; break
			if already:
				var new_sel := PackedInt32Array()
				for s in _selected_he:
					var matched := false
					for h in hits:
						if s == h: matched = true; break
					if not matched: new_sel.append(s)
				_selected_he = new_sel
			else:
				for h in hits: _selected_he.append(h)
		if tool != null:
			_active_part      = GizmoPart.FREE
			_drag_initial_uvs = _current_selected_uvs()
	else:
		if not shift: _selected_he = PackedInt32Array()
		_marquee_active = true
		_marquee_start  = screen_pos
		_marquee_end    = screen_pos
	queue_redraw()

func _on_transform_drag(screen_pos: Vector2) -> void:
	if gomo_mesh == null or _selected_he.is_empty() or _drag_initial_uvs.is_empty(): return
	var tool     := State.active_tool
	var new_uvs  := PackedVector2Array()
	var centroid := _uv_centroid(_drag_initial_uvs)
	var start_uv := _screen_to_uv(_left_press_pos)
	var cur_uv   := _screen_to_uv(screen_pos)

	if tool is RotateTool:
		var angle := (start_uv - centroid).angle_to(cur_uv - centroid)
		for uv in _drag_initial_uvs:
			new_uvs.append(centroid + (uv - centroid).rotated(angle))

	elif tool is ScaleTool:
		match _active_part:
			GizmoPart.AXIS_U:
				var s := absf(start_uv.x - centroid.x)
				var c := cur_uv.x - centroid.x
				var f := maxf(c / s, 0.001) if s > 0.0001 else 1.0
				for uv in _drag_initial_uvs:
					new_uvs.append(centroid + Vector2((uv.x - centroid.x) * f, uv.y - centroid.y))
			GizmoPart.AXIS_V:
				var s := absf(start_uv.y - centroid.y)
				var c := cur_uv.y - centroid.y
				var f := maxf(c / s, 0.001) if s > 0.0001 else 1.0
				for uv in _drag_initial_uvs:
					new_uvs.append(centroid + Vector2(uv.x - centroid.x, (uv.y - centroid.y) * f))
			_:
				var s := start_uv.distance_to(centroid)
				var f := maxf(cur_uv.distance_to(centroid) / s, 0.001) if s > 0.0001 else 1.0
				for uv in _drag_initial_uvs:
					new_uvs.append(centroid + (uv - centroid) * f)

	else: # MoveTool or FREE
		var delta := cur_uv - start_uv
		match _active_part:
			GizmoPart.AXIS_U: delta.y = 0.0
			GizmoPart.AXIS_V: delta.x = 0.0
		for uv in _drag_initial_uvs:
			new_uvs.append(uv + delta)

	gomo_mesh.hem.set_uvs(_selected_he, new_uvs)
	for i in _selected_he.size():
		var he := _selected_he[i]
		for j in _he_indices.size():
			if _he_indices[j] == he:
				_he_uvs[j] = new_uvs[i]
				break
	edges         = gomo_mesh.hem.get_uv_edges()
	seam_edges    = gomo_mesh.hem.get_uv_seam_edges()
	face_polygons = gomo_mesh.hem.get_uv_face_polygons()
	queue_redraw()
	gomo_mesh.refresh()

func _finish_marquee(shift: bool) -> void:
	var rect := Rect2(_marquee_start, _marquee_end - _marquee_start).abs()
	if rect.size.length_squared() < 4.0: return
	var new_sel := _selected_he if shift else PackedInt32Array()
	var seen: Array[Vector2] = []
	for i in _he_indices.size():
		var sc := _uv_to_screen(_he_uvs[i])
		if not rect.has_point(sc): continue
		var uv  := _he_uvs[i]
		var dup := false
		for s in seen:
			if s.distance_squared_to(uv) < 1e-8: dup = true; break
		if dup: continue
		seen.append(uv)
		for h in _all_he_at_uv(uv):
			var exists := false
			for s in new_sel:
				if s == h: exists = true; break
			if not exists: new_sel.append(h)
	_selected_he = new_sel
	queue_redraw()

# --- Gizmo ---

func _gizmo_centroid_screen() -> Vector2:
	return _uv_to_screen(_uv_centroid(_current_selected_uvs()))

func _gizmo_hit(screen_pos: Vector2) -> int:
	if _selected_he.is_empty() or State.active_tool == null:
		return GizmoPart.NONE
	var c    := _gizmo_centroid_screen()
	var tool := State.active_tool

	if tool is RotateTool:
		if absf(screen_pos.distance_to(c) - ROTATE_R) < HIT_R:
			return GizmoPart.FREE
		return GizmoPart.NONE

	# Move and Scale share axis layout
	var tip_u := c + Vector2(ARROW_LEN, 0)
	var tip_v := c + Vector2(0, -ARROW_LEN)
	if screen_pos.distance_to(tip_u) < HIT_R: return GizmoPart.AXIS_U
	if screen_pos.distance_to(tip_v) < HIT_R: return GizmoPart.AXIS_V
	if screen_pos.distance_to(c)     < HIT_R: return GizmoPart.FREE
	return GizmoPart.NONE

func _draw_gizmo(c: Vector2) -> void:
	var tool := State.active_tool
	if tool == null: return

	if tool is RotateTool:
		var col := COL_HOVER if _hovered_part == GizmoPart.FREE else COL_CENTER
		draw_arc(c, ROTATE_R, 0.0, TAU, 48, col, 2.0)
		return

	var col_u := COL_HOVER if _hovered_part == GizmoPart.AXIS_U else COL_U
	var col_v := COL_HOVER if _hovered_part == GizmoPart.AXIS_V else COL_V
	var col_c := COL_HOVER if _hovered_part == GizmoPart.FREE   else COL_CENTER

	if tool is ScaleTool:
		var tip_u := c + Vector2(ARROW_LEN, 0)
		var tip_v := c + Vector2(0, -ARROW_LEN)
		draw_line(c, tip_u, col_u, 2.0)
		draw_rect(Rect2(tip_u - Vector2(5, 5), Vector2(10, 10)), col_u)
		draw_line(c, tip_v, col_v, 2.0)
		draw_rect(Rect2(tip_v - Vector2(5, 5), Vector2(10, 10)), col_v)
		draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), col_c)
	else: # MoveTool
		var tip_u := c + Vector2(ARROW_LEN, 0)
		var tip_v := c + Vector2(0, -ARROW_LEN)
		draw_line(c, tip_u, col_u, 2.0)
		draw_colored_polygon(_arrowhead(tip_u, Vector2(1, 0)), col_u)
		draw_line(c, tip_v, col_v, 2.0)
		draw_colored_polygon(_arrowhead(tip_v, Vector2(0, -1)), col_v)
		draw_rect(Rect2(c - Vector2(CENTER_SZ * 0.5, CENTER_SZ * 0.5), Vector2(CENTER_SZ, CENTER_SZ)), col_c)

func _arrowhead(tip: Vector2, dir: Vector2) -> PackedVector2Array:
	var right := Vector2(-dir.y, dir.x) * 5.0
	var base  := tip - dir * 12.0
	var pts   := PackedVector2Array()
	pts.append(tip)
	pts.append(base + right)
	pts.append(base - right)
	return pts

# --- Helpers ---

func _he_indices_at_screen(screen_pos: Vector2) -> PackedInt32Array:
	var uv        := _screen_to_uv(screen_pos)
	var thresh_sq := (PICK_RADIUS_PX / _zoom) ** 2
	var best_d    := thresh_sq
	var best_uv   := Vector2(INF, INF)
	for i in _he_uvs.size():
		var d := uv.distance_squared_to(_he_uvs[i])
		if d < best_d:
			best_d  = d
			best_uv = _he_uvs[i]
	if best_uv.x == INF: return PackedInt32Array()
	return _all_he_at_uv(best_uv)

func _all_he_at_uv(target: Vector2) -> PackedInt32Array:
	var result := PackedInt32Array()
	for i in _he_indices.size():
		if _he_uvs[i].distance_squared_to(target) < 1e-8:
			result.append(_he_indices[i])
	return result

func _current_selected_uvs() -> PackedVector2Array:
	var result := PackedVector2Array()
	for he in _selected_he:
		for i in _he_indices.size():
			if _he_indices[i] == he:
				result.append(_he_uvs[i])
				break
	return result

func _uv_centroid(uvs: PackedVector2Array) -> Vector2:
	if uvs.is_empty(): return Vector2.ZERO
	var c := Vector2.ZERO
	for uv in uvs: c += uv
	return c / uvs.size()

func _zoom_at(pos: Vector2, factor: float) -> void:
	_pan   = pos + (_pan - pos) * factor
	_zoom *= factor
	queue_redraw()

func _screen_to_uv(screen: Vector2) -> Vector2:
	return Vector2((screen.x - _pan.x) / _zoom, 1.0 - (screen.y - _pan.y) / _zoom)

func _uv_to_screen(uv: Vector2) -> Vector2:
	return Vector2(_pan.x + uv.x * _zoom, _pan.y + (1.0 - uv.y) * _zoom)

func _ready() -> void:
	EventBus.instance.tool_changed.connect(func(_t): queue_redraw())
	EventBus.instance.normal_map_baked.connect(func(image: Image):
		last_baked_image = image
		var display := image.duplicate()
		display.flip_y()
		_background = ImageTexture.create_from_image(display)
		queue_redraw()
	)

static func _signed_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	var n    := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	return area * 0.5

func _draw() -> void:
	draw_rect(Rect2(_pan, Vector2(_zoom, _zoom)), Color(0.12, 0.12, 0.12, 1.0))
	if _background != null:
		draw_texture_rect(_background, Rect2(_pan, Vector2(_zoom, _zoom)), false)
	for poly in face_polygons:
		var screen_poly := PackedVector2Array()
		for uv in poly: screen_poly.append(_uv_to_screen(uv))
		var col := Color(0.25, 0.45, 1.0, 0.18) if _signed_area(poly) > 0.0 \
				else Color(1.0, 0.25, 0.25, 0.18)
		draw_colored_polygon(screen_poly, col)
	if not edges.is_empty():
		var i := 0
		while i + 1 < edges.size():
			draw_line(_uv_to_screen(edges[i]), _uv_to_screen(edges[i + 1]), Color(0.8, 0.8, 0.8, 1.0), 0.5, true)
			i += 2
	if not seam_edges.is_empty():
		var i := 0
		while i + 1 < seam_edges.size():
			draw_line(_uv_to_screen(seam_edges[i]), _uv_to_screen(seam_edges[i + 1]), Color(0.8, 0.8, 0.8, 1.0), 1.0, true)
			i += 2
	# Selected UV verts
	var drawn: Array[Vector2] = []
	for he in _selected_he:
		for i in _he_indices.size():
			if _he_indices[i] == he:
				var uv := _he_uvs[i]
				var dup := false
				for d in drawn:
					if d.distance_squared_to(uv) < 1e-8: dup = true; break
				if not dup:
					drawn.append(uv)
					draw_circle(_uv_to_screen(uv), 5.0, Color(1.0, 0.55, 0.1, 1.0))
				break
	# Gizmo
	if not _selected_he.is_empty():
		_draw_gizmo(_gizmo_centroid_screen())
	# Marquee
	if _marquee_active:
		var rect := Rect2(_marquee_start, _marquee_end - _marquee_start)
		draw_rect(rect, Color(0.3, 0.6, 1.0, 0.12), true)
		draw_rect(rect, Color(0.3, 0.6, 1.0, 0.8), false)
