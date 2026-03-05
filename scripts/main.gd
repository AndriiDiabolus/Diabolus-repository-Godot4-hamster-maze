extends Node2D

# ── Hamster state ─────────────────────────────────────────────────────
var _ham := {"x": 1, "y": 1, "burrowed": false, "burrows": 3}

# ── Movement timer (same logic as mTimer in HTML: move every 8 frames) ─
const MOVE_INTERVAL: float = 8.0 / 60.0
var _move_timer: float = 0.0
var _frame: int = 0

# ── Maze ──────────────────────────────────────────────────────────────
var _maze: Array = []
var _maze_gen: MazeGenerator


func _ready() -> void:
	_maze_gen = MazeGenerator.new()
	_maze = _maze_gen.make_maze()


# ── Input: immediate response on first keypress ────────────────────────
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var dx: int = 0
	var dy: int = 0
	match event.keycode:
		KEY_W, KEY_UP:    dy = -1
		KEY_S, KEY_DOWN:  dy =  1
		KEY_A, KEY_LEFT:  dx = -1
		KEY_D, KEY_RIGHT: dx =  1
		KEY_ENTER, KEY_KP_ENTER:
			_ham = {"x": 1, "y": 1, "burrowed": false, "burrows": 3}
			_maze = _maze_gen.make_maze()
			queue_redraw()
			return
	if dx != 0 or dy != 0:
		_try_move(dx, dy)
		_move_timer = 0.0


# ── Process: held-key repeat ───────────────────────────────────────────
func _process(delta: float) -> void:
	_frame += 1
	_move_timer += delta
	if _move_timer >= MOVE_INTERVAL and not _ham.burrowed:
		_move_timer = 0.0
		var dx: int = 0
		var dy: int = 0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			dy = -1
		elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			dy =  1
		elif Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			dx = -1
		elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			dx =  1
		if dx != 0 or dy != 0:
			_try_move(dx, dy)
	queue_redraw()


func _try_move(dx: int, dy: int) -> void:
	var nx: int = _ham.x + dx
	var ny: int = _ham.y + dy
	if nx >= 0 and nx < C.COLS and ny >= 0 and ny < C.ROWS and _maze[ny][nx] == 0:
		_ham.x = nx
		_ham.y = ny


# ── Draw ──────────────────────────────────────────────────────────────
func _draw() -> void:
	draw_rect(Rect2(0, 0, C.W, C.H + C.HUD), Color("#0d0d1a"))
	_draw_maze()
	_draw_hamster(
		_ham.x * C.CELL + C.CELL * 0.5,
		_ham.y * C.CELL + C.CELL * 0.5,
		_ham.burrowed
	)
	_draw_hud()


func _draw_maze() -> void:
	for r in range(C.ROWS):
		for col in range(C.COLS):
			var px: float = col * C.CELL
			var py: float = r * C.CELL
			if _maze[r][col] == 1:
				draw_rect(Rect2(px, py, C.CELL, C.CELL),           Color("#1a3358"))
				draw_rect(Rect2(px, py, C.CELL, 2),                Color("#25487a"))
				draw_rect(Rect2(px, py, 2,       C.CELL),          Color("#25487a"))
				draw_rect(Rect2(px + C.CELL - 2, py, 2,    C.CELL), Color("#0e1f3a"))
				draw_rect(Rect2(px, py + C.CELL - 2, C.CELL, 2),   Color("#0e1f3a"))
			else:
				var tc: Color = Color("#d4a85a") if (r + col) % 2 == 0 else Color("#ca9e50")
				draw_rect(Rect2(px, py, C.CELL, C.CELL), tc)


# Transliterated from drawHamster() — hamster_maze.html lines 1061-1116
func _draw_hamster(cx: float, cy: float, burrowed: bool) -> void:
	if burrowed:
		# Dirt mounds
		for i in range(6):
			var a: float = i / 6.0 * TAU
			draw_circle(Vector2(cx + cos(a) * 18.0, cy + 4.0 + sin(a) * 9.0), 4.0, Color("#7a5018"))
		# Entrance hole
		_ell(Vector2(cx, cy + 5), 14, 9,   Color("#2a0e00"))
		_ell(Vector2(cx, cy + 4), 9,  5.5, Color("#3e1800"))

	var m: float = 0.38 if burrowed else 1.0   # alpha modulation

	# Shadow
	_ell(Vector2(cx + 1, cy + 4), 13, 6, Color(0, 0, 0, 0.3 * m))
	# Body
	_ell(Vector2(cx,      cy + 2), 13, 11, _ca("#c07840", m))
	# Belly
	_ell(Vector2(cx,      cy + 4),  7,  7, _ca("#e8c080", m))
	# Cheek pouches
	_ell(Vector2(cx - 12, cy + 2),  8,  7, _ca("#d89050", m), -0.2)
	_ell(Vector2(cx + 12, cy + 2),  8,  7, _ca("#d89050", m),  0.2)
	# Head
	_ell(Vector2(cx,      cy - 7), 11, 10, _ca("#c07840", m))
	# Ears outer
	_ell(Vector2(cx -  8, cy - 17), 5, 6,   _ca("#a05530", m), -0.3)
	_ell(Vector2(cx +  8, cy - 17), 5, 6,   _ca("#a05530", m),  0.3)
	# Ears inner
	_ell(Vector2(cx -  8, cy - 17), 2.5, 3.5, _ca("#ffaaaa", m), -0.3)
	_ell(Vector2(cx +  8, cy - 17), 2.5, 3.5, _ca("#ffaaaa", m),  0.3)
	# Eyes
	draw_circle(Vector2(cx - 4, cy - 10), 3.0, _ca("#1a0800", m))
	draw_circle(Vector2(cx + 4, cy - 10), 3.0, _ca("#1a0800", m))
	draw_circle(Vector2(cx - 3, cy - 11), 1.2, _ca("#ffffff", m))
	draw_circle(Vector2(cx + 5, cy - 11), 1.2, _ca("#ffffff", m))
	# Nose
	draw_circle(Vector2(cx, cy - 6), 2.0, _ca("#ff8888", m))
	# Whiskers
	var wc := Color(1.0, 1.0, 1.0, 0.55 * m)
	draw_line(Vector2(cx - 2, cy - 5), Vector2(cx - 15, cy - 7), wc, 1.0)
	draw_line(Vector2(cx - 2, cy - 5), Vector2(cx - 15, cy - 4), wc, 1.0)
	draw_line(Vector2(cx + 2, cy - 5), Vector2(cx + 15, cy - 7), wc, 1.0)
	draw_line(Vector2(cx + 2, cy - 5), Vector2(cx + 15, cy - 4), wc, 1.0)
	# Feet
	_ell(Vector2(cx - 8, cy + 12), 4, 3, _ca("#a06030", m))
	_ell(Vector2(cx + 8, cy + 12), 4, 3, _ca("#a06030", m))


func _draw_hud() -> void:
	var Y: float = C.H
	var font: Font = ThemeDB.fallback_font

	draw_rect(Rect2(0, Y, C.W, C.HUD), Color("#08080f"))
	draw_rect(Rect2(0, Y, C.W, 2),     Color("#1a3060"))

	# Burrow label + icons
	draw_string(font, Vector2(162, Y + 20), "Норки:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("white"))
	for i in range(3):
		var bx: float = 223.0 + i * 32.0
		var by: float = Y + 5.0
		if i < _ham.burrows:
			_ell(Vector2(bx,      by + 11), 13, 8, Color("#7a5010"))
			_ell(Vector2(bx,      by + 12),  9, 5, Color("#2a0e00"))
			_ell(Vector2(bx - 1,  by +  9),  5, 3, Color("#c07840"))
		else:
			_ell(Vector2(bx, by + 11), 13, 8, Color("#1e1e1e"))

	# State indicator
	if _ham.burrowed:
		draw_string(font, Vector2(318, Y + 23), "Хомяк под землёй!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#44ff88"))

	# Position debug (temp)
	draw_string(font, Vector2(10, Y + 22), "Позиция: %d, %d" % [_ham.x, _ham.y],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffd700"))

	# Controls hint
	draw_string(font, Vector2(8, Y + C.HUD - 8),
		"WASD / ←↑→↓ — движение   Enter — рестарт",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#3a3a5a"))


# ── Helpers ───────────────────────────────────────────────────────────

# Color from hex string with alpha override
func _ca(hex: String, alpha: float) -> Color:
	var c := Color(hex)
	c.a = alpha
	return c


# Draw filled ellipse with optional rotation (radians)
func _ell(center: Vector2, rx: float, ry: float, color: Color, rot: float = 0.0, seg: int = 24) -> void:
	var pts := PackedVector2Array()
	var cr := cos(rot)
	var sr := sin(rot)
	for i in range(seg):
		var a := i * TAU / seg
		var x := cos(a) * rx
		var y := sin(a) * ry
		if rot != 0.0:
			pts.append(center + Vector2(x * cr - y * sr, x * sr + y * cr))
		else:
			pts.append(center + Vector2(x, y))
	draw_colored_polygon(pts, color)
