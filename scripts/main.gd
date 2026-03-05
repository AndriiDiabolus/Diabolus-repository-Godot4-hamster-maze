extends Node2D

# ── Hamster state ─────────────────────────────────────────────────────
var _ham := {"x": 1, "y": 1, "burrowed": false, "burrows": 3}

# ── Movement timer ────────────────────────────────────────────────────
const MOVE_INTERVAL: float = 8.0 / 60.0
var _move_timer: float = 0.0
var _frame: int = 0

# ── Game state ────────────────────────────────────────────────────────
var _state: String = "play"   # play | lost
var _game_start_ms: int = 0
var _game_time_ms: int = 0

# ── Maze ──────────────────────────────────────────────────────────────
var _maze: Array = []
var _maze_gen: MazeGenerator

# ── Llamas ────────────────────────────────────────────────────────────
var _llama: LlamaAI = null
var _llama2: LlamaAI = null
var _llama_bonus: int = 0     # speed bonus, +1 every 30s, max 8


func _ready() -> void:
	_maze_gen = MazeGenerator.new()
	_start_game()


func _start_game() -> void:
	_maze = _maze_gen.make_maze()
	_ham = {"x": 1, "y": 1, "burrowed": false, "burrows": 3}
	_state = "play"
	_frame = 0
	_move_timer = 0.0
	_llama_bonus = 0
	_game_start_ms = Time.get_ticks_msec()
	_game_time_ms = 0

	# Blue llama starts at bottom-right
	var ls := _find_llama_start()
	_llama = LlamaAI.new()
	_llama.init(ls.x, ls.y, _maze)

	# Red llama spawns after 60s — not yet
	_llama2 = null


func _find_llama_start() -> Vector2i:
	for r in range(C.ROWS - 2, 0, -1):
		for col in range(C.COLS - 2, 0, -1):
			if _maze[r][col] == 0:
				return Vector2i(col, r)
	return Vector2i(3, 3)


# ── Input ─────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_start_game()
		return
	if _state != "play":
		return
	var dx: int = 0
	var dy: int = 0
	match event.keycode:
		KEY_W, KEY_UP:    dy = -1
		KEY_S, KEY_DOWN:  dy =  1
		KEY_A, KEY_LEFT:  dx = -1
		KEY_D, KEY_RIGHT: dx =  1
	if dx != 0 or dy != 0:
		_try_move(dx, dy)
		_move_timer = 0.0


# ── Process ───────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_frame += 1

	if _state == "play":
		_game_time_ms = Time.get_ticks_msec() - _game_start_ms

		# Llama speed bonus: +1 every 30s, max 8
		_llama_bonus = min(C.LLAMA_BONUS_MAX, _game_time_ms / C.LLAMA_BONUS_INTERVAL_MS)

		# Held-key movement
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

		# Update blue llama
		if _llama:
			var caught := _llama.update(_ham.x, _ham.y, _ham.burrowed, _llama_bonus)
			if caught:
				_state = "lost"
				_game_time_ms = Time.get_ticks_msec() - _game_start_ms

		# Spawn red llama after 60s
		if _llama2 == null and _game_time_ms >= C.LLAMA2_SPAWN_MS:
			var s2 := _random_far_cell(_ham.x, _ham.y, 8)
			_llama2 = LlamaAI.new()
			_llama2.init(s2.x, s2.y, _maze)

		# Update red llama
		if _llama2:
			var caught2 := _llama2.update(_ham.x, _ham.y, _ham.burrowed, _llama_bonus)
			if caught2:
				_state = "lost"
				_game_time_ms = Time.get_ticks_msec() - _game_start_ms

	queue_redraw()


func _try_move(dx: int, dy: int) -> void:
	var nx: int = _ham.x + dx
	var ny: int = _ham.y + dy
	if nx >= 0 and nx < C.COLS and ny >= 0 and ny < C.ROWS and _maze[ny][nx] == 0:
		_ham.x = nx
		_ham.y = ny


func _random_far_cell(from_x: int, from_y: int, min_dist: int) -> Vector2i:
	var attempts: int = 0
	while attempts < 200:
		var px: int = 1 + randi() % (C.COLS - 2)
		var py: int = 1 + randi() % (C.ROWS - 2)
		if _maze[py][px] == 0 and abs(px - from_x) + abs(py - from_y) >= min_dist:
			return Vector2i(px, py)
		attempts += 1
	return Vector2i(C.COLS - 2, C.ROWS - 2)


# ── Draw ──────────────────────────────────────────────────────────────
func _draw() -> void:
	draw_rect(Rect2(0, 0, C.W, C.H + C.HUD), Color("#0d0d1a"))
	_draw_maze()

	# Rabbit holes placeholder (Etap 4)

	# Characters
	_draw_hamster(
		_ham.x * C.CELL + C.CELL * 0.5,
		_ham.y * C.CELL + C.CELL * 0.5,
		_ham.burrowed
	)
	if _llama:
		_draw_llama(
			_llama.x * C.CELL + C.CELL * 0.5,
			_llama.y * C.CELL + C.CELL * 0.5,
			_llama.state, false
		)
	if _llama2:
		_draw_llama(
			_llama2.x * C.CELL + C.CELL * 0.5,
			_llama2.y * C.CELL + C.CELL * 0.5,
			_llama2.state, true
		)

	_draw_hud()

	if _state == "lost":
		_draw_overlay()


func _draw_maze() -> void:
	for r in range(C.ROWS):
		for col in range(C.COLS):
			var px: float = col * C.CELL
			var py: float = r * C.CELL
			if _maze[r][col] == 1:
				draw_rect(Rect2(px, py, C.CELL, C.CELL),            Color("#1a3358"))
				draw_rect(Rect2(px, py, C.CELL, 2),                 Color("#25487a"))
				draw_rect(Rect2(px, py, 2,       C.CELL),           Color("#25487a"))
				draw_rect(Rect2(px + C.CELL - 2, py, 2,    C.CELL), Color("#0e1f3a"))
				draw_rect(Rect2(px, py + C.CELL - 2, C.CELL, 2),   Color("#0e1f3a"))
			else:
				var tc: Color = Color("#d4a85a") if (r + col) % 2 == 0 else Color("#ca9e50")
				draw_rect(Rect2(px, py, C.CELL, C.CELL), tc)


# Transliterated from drawHamster() — hamster_maze.html lines 1061-1116
func _draw_hamster(cx: float, cy: float, burrowed: bool) -> void:
	if burrowed:
		for i in range(6):
			var a: float = i / 6.0 * TAU
			draw_circle(Vector2(cx + cos(a) * 18.0, cy + 4.0 + sin(a) * 9.0), 4.0, Color("#7a5018"))
		_ell(Vector2(cx, cy + 5), 14, 9,   Color("#2a0e00"))
		_ell(Vector2(cx, cy + 4), 9,  5.5, Color("#3e1800"))

	var m: float = 0.38 if burrowed else 1.0
	_ell(Vector2(cx + 1, cy + 4), 13, 6, Color(0, 0, 0, 0.3 * m))
	_ell(Vector2(cx,      cy + 2), 13, 11, _ca("#c07840", m))
	_ell(Vector2(cx,      cy + 4),  7,  7, _ca("#e8c080", m))
	_ell(Vector2(cx - 12, cy + 2),  8,  7, _ca("#d89050", m), -0.2)
	_ell(Vector2(cx + 12, cy + 2),  8,  7, _ca("#d89050", m),  0.2)
	_ell(Vector2(cx,      cy - 7), 11, 10, _ca("#c07840", m))
	_ell(Vector2(cx -  8, cy - 17), 5, 6,   _ca("#a05530", m), -0.3)
	_ell(Vector2(cx +  8, cy - 17), 5, 6,   _ca("#a05530", m),  0.3)
	_ell(Vector2(cx -  8, cy - 17), 2.5, 3.5, _ca("#ffaaaa", m), -0.3)
	_ell(Vector2(cx +  8, cy - 17), 2.5, 3.5, _ca("#ffaaaa", m),  0.3)
	draw_circle(Vector2(cx - 4, cy - 10), 3.0, _ca("#1a0800", m))
	draw_circle(Vector2(cx + 4, cy - 10), 3.0, _ca("#1a0800", m))
	draw_circle(Vector2(cx - 3, cy - 11), 1.2, _ca("#ffffff", m))
	draw_circle(Vector2(cx + 5, cy - 11), 1.2, _ca("#ffffff", m))
	draw_circle(Vector2(cx, cy - 6), 2.0, _ca("#ff8888", m))
	var wc := Color(1.0, 1.0, 1.0, 0.55 * m)
	draw_line(Vector2(cx - 2, cy - 5), Vector2(cx - 15, cy - 7), wc, 1.0)
	draw_line(Vector2(cx - 2, cy - 5), Vector2(cx - 15, cy - 4), wc, 1.0)
	draw_line(Vector2(cx + 2, cy - 5), Vector2(cx + 15, cy - 7), wc, 1.0)
	draw_line(Vector2(cx + 2, cy - 5), Vector2(cx + 15, cy - 4), wc, 1.0)
	_ell(Vector2(cx - 8, cy + 12), 4, 3, _ca("#a06030", m))
	_ell(Vector2(cx + 8, cy + 12), 4, 3, _ca("#a06030", m))


# Transliterated from drawLlama() — hamster_maze.html lines 1140-1180
func _draw_llama(cx: float, cy: float, s: String, is_red: bool) -> void:
	# Palette
	var body  := Color("#4a9eff") if not is_red else Color("#ff4a4a")
	var dark  := Color("#3880dd") if not is_red else Color("#cc2020")
	var light := Color("#90ccff") if not is_red else Color("#ff9999")
	var head  := Color("#5aafff") if not is_red else Color("#ff6060")
	var snout := Color("#7ac8ff") if not is_red else Color("#ffaaaa")
	var ear_in := Color("#b0dcff") if not is_red else Color("#ffdddd")
	var hoof  := Color("#1a50aa") if not is_red else Color("#991010")
	var nostr := Color("#2060cc") if not is_red else Color("#cc1010")

	# State aura
	if s != "patrol":
		var ac: Color
		match s:
			"chase":  ac = Color(1.0, 0.16, 0.16, 0.0)
			"alert":  ac = Color(1.0, 0.78, 0.0,  0.0)
			"search": ac = Color(1.0, 0.51, 0.0,  0.0)
		var pulse := 0.55 + 0.45 * sin(_frame * 0.22)
		ac.a = 0.38 * pulse
		_ell(Vector2(cx, cy + 5), 22, 14, ac)

	# Shadow
	_ell(Vector2(cx, cy + 8), 13, 5, Color(0, 0, 0, 0.25))
	# Legs
	draw_rect(Rect2(cx - 9, cy + 3, 6, 13), dark)
	draw_rect(Rect2(cx + 3, cy + 3, 6, 13), dark)
	# Hooves
	_ell(Vector2(cx - 6, cy + 16), 4, 2.5, hoof)
	_ell(Vector2(cx + 6, cy + 16), 4, 2.5, hoof)
	# Body
	_ell(Vector2(cx, cy + 1), 14, 11, body)
	_ell(Vector2(cx, cy + 3),  9,  7, light)
	# Tail
	_ell(Vector2(cx + 13, cy), 4, 6, body, 0.4)
	# Neck
	var neck_pts := PackedVector2Array([
		Vector2(cx - 5, cy - 7), Vector2(cx + 5, cy - 7),
		Vector2(cx + 4, cy - 20), Vector2(cx - 4, cy - 20)
	])
	draw_colored_polygon(neck_pts, body)
	# Head
	_ell(Vector2(cx, cy - 24), 10, 9, head)
	# Snout
	_ell(Vector2(cx + 1, cy - 20), 6, 4, snout, 0.15)
	# Ears
	var ear_l := PackedVector2Array([Vector2(cx-7,cy-30),Vector2(cx-10,cy-43),Vector2(cx-3,cy-30)])
	var ear_r := PackedVector2Array([Vector2(cx+3,cy-30),Vector2(cx+10,cy-43),Vector2(cx+7,cy-30)])
	draw_colored_polygon(ear_l, dark)
	draw_colored_polygon(ear_r, dark)
	var ear_li := PackedVector2Array([Vector2(cx-6.5,cy-31),Vector2(cx-9,cy-40),Vector2(cx-4,cy-31)])
	var ear_ri := PackedVector2Array([Vector2(cx+4,cy-31),Vector2(cx+9,cy-40),Vector2(cx+6.5,cy-31)])
	draw_colored_polygon(ear_li, ear_in)
	draw_colored_polygon(ear_ri, ear_in)
	# Eyes
	draw_circle(Vector2(cx - 4, cy - 26), 2.5, Color("#1a1a3a"))
	draw_circle(Vector2(cx + 4, cy - 26), 2.5, Color("#1a1a3a"))
	draw_circle(Vector2(cx - 3, cy - 27), 1.0, Color("white"))
	draw_circle(Vector2(cx + 5, cy - 27), 1.0, Color("white"))
	# Nostrils
	_ell(Vector2(cx - 1, cy - 19), 1.5, 1.0, nostr)
	_ell(Vector2(cx + 3, cy - 19), 1.5, 1.0, nostr)

	# State bubble
	_draw_llama_bubble(cx, cy, s)


func _draw_llama_bubble(cx: float, cy: float, s: String) -> void:
	if s == "patrol":
		return
	var txt: String
	var col: Color
	match s:
		"alert":  txt = "?";   col = Color("#ffcc00")
		"chase":  txt = "!!";  col = Color("#ff2020")
		"search": txt = "?.."; col = Color("#ff8800")
	var font := ThemeDB.fallback_font
	var by: float = cy - 58
	var scale := 1.0 + 0.2 * sin(_frame * 0.45) if s == "chase" else 1.0
	var bw: float = 36.0 * scale
	var bh: float = 22.0 * scale
	draw_rect(Rect2(cx - bw * 0.5, by - bh * 0.5, bw, bh), Color("#fffbe0"))
	draw_rect(Rect2(cx - bw * 0.5, by - bh * 0.5, bw, bh), col, false, 2.0)
	draw_string(font, Vector2(cx - 8, by + 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


func _draw_hud() -> void:
	var Y: float = C.H
	var font: Font = ThemeDB.fallback_font

	draw_rect(Rect2(0, Y, C.W, C.HUD), Color("#08080f"))
	draw_rect(Rect2(0, Y, C.W, 2),     Color("#1a3060"))

	# Burrows
	draw_string(font, Vector2(162, Y + 20), "Норки:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("white"))
	for i in range(3):
		var bx: float = 223.0 + i * 32.0
		var by: float = Y + 5.0
		if i < _ham.burrows:
			_ell(Vector2(bx,     by + 11), 13, 8, Color("#7a5010"))
			_ell(Vector2(bx,     by + 12),  9, 5, Color("#2a0e00"))
			_ell(Vector2(bx - 1, by +  9),  5, 3, Color("#c07840"))
		else:
			_ell(Vector2(bx, by + 11), 13, 8, Color("#1e1e1e"))

	# Burrowed status
	if _ham.burrowed:
		draw_string(font, Vector2(318, Y + 23), "Хомяк под землёй!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#44ff88"))
	else:
		# Llama state
		if _llama and _llama.state != "patrol":
			var info := {"alert": ["Лама: слышит шаги!", Color("#ffcc00")],
						 "chase": ["Лама: ПОГОНЯ!",      Color("#ff4040")],
						 "search":["Лама: ищет...",      Color("#ff9900")]}
			var d: Array = info.get(_llama.state, [])
			if d.size() > 0:
				draw_string(font, Vector2(318, Y + 28), d[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, d[1])

	# Timer
	var elapsed := _game_time_ms if _state == "play" else _game_time_ms
	draw_string(font, Vector2(C.W * 0.5 - 30, Y + 22), "⏱ %s" % _fmt_time(elapsed),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#7799cc"))

	# Llama speed indicator
	if _llama_bonus > 0:
		var fire := "🔥".repeat(min(4, int(ceil(float(_llama_bonus) / 2.0))))
		draw_string(font, Vector2(C.W * 0.5 - 30, Y + 40), "Лама %s" % fire,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffcc44"))

	# Controls hint
	draw_string(font, Vector2(8, Y + C.HUD - 8),
		"WASD/←↑→↓ — движение   Enter — рестарт",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#3a3a5a"))


func _draw_overlay() -> void:
	draw_rect(Rect2(0, 0, C.W, C.H + C.HUD), Color(0, 0, 0, 0.78))
	var font := ThemeDB.fallback_font
	var cx: float = C.W * 0.5
	var cy: float = C.H * 0.5
	draw_rect(Rect2(cx - 230, cy - 100, 460, 200), Color("#501a1a"))
	draw_string(font, Vector2(cx - 60, cy - 10), "💀 КОНЕЦ",   HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color("white"))
	draw_string(font, Vector2(cx - 120, cy + 40), "Лама поймала хомяка!", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1,1,1,0.85))
	draw_string(font, Vector2(cx - 130, cy + 80), "Enter — играть снова", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1,1,1,0.45))


# ── Helpers ───────────────────────────────────────────────────────────
func _fmt_time(ms: int) -> String:
	var s := ms / 1000
	var m := s / 60
	var dec := (ms % 1000) / 100
	return "%d:%02d.%d" % [m, s % 60, dec]


func _ca(hex: String, alpha: float) -> Color:
	var c := Color(hex)
	c.a = alpha
	return c


func _ell(center: Vector2, rx: float, ry: float, color: Color, rot: float = 0.0, seg: int = 24) -> void:
	var pts := PackedVector2Array()
	var cr := cos(rot)
	var sr := sin(rot)
	for i in range(seg):
		var a := i * TAU / seg
		var ex := cos(a) * rx
		var ey := sin(a) * ry
		if rot != 0.0:
			pts.append(center + Vector2(ex * cr - ey * sr, ex * sr + ey * cr))
		else:
			pts.append(center + Vector2(ex, ey))
	draw_colored_polygon(pts, color)
