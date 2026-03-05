extends Node2D

# ── Hamster state ─────────────────────────────────────────────────────
var _ham := {"x": 1, "y": 1, "burrowed": false, "burrows": 3}

# ── Fog of war ────────────────────────────────────────────────────────
const FOG_INNER_R: float = 3.8   # cells — fully visible
const FOG_OUTER_R: float = 5.8   # cells — fully fogged
const FOG_ALPHA:   float = 0.55  # max fog darkness

# ── Movement timer ────────────────────────────────────────────────────
const MOVE_INTERVAL: float = 8.0 / 60.0
var _move_timer: float = 0.0
var _frame: int = 0

# ── Game state ────────────────────────────────────────────────────────
var _state: String = "play"   # play | lost | won
var _game_start_ms: int = 0
var _game_time_ms: int = 0
var _win_anim_t: int = 0

# ── Maze ──────────────────────────────────────────────────────────────
var _maze: Array = []
var _maze_gen: MazeGenerator

# ── Llamas ────────────────────────────────────────────────────────────
var _llama: LlamaAI = null
var _llama2: LlamaAI = null
var _llama_bonus: int = 0     # speed bonus, +1 every 30s, max 8

# ── Nuts ──────────────────────────────────────────────────────────────
# Each nut: {x, y, got, visible}
var _nuts: Array = []
var _next_wave_ms: int = 0   # absolute ticks when next wave appears

# ── Rabbit holes (portals) ────────────────────────────────────────────
var _rh: RHManager = null


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
	_win_anim_t = 0
	_game_start_ms = Time.get_ticks_msec()
	_game_time_ms = 0

	# Blue llama starts at bottom-right
	var ls := _find_llama_start()
	_llama = LlamaAI.new()
	_llama.init(ls.x, ls.y, _maze)

	# Red llama spawns after 60s — not yet
	_llama2 = null

	# Nuts
	_init_nuts(ls)

	# Rabbit holes
	_rh = RHManager.new()
	_rh.init(_maze)


func _find_llama_start() -> Vector2i:
	for r in range(C.ROWS - 2, 0, -1):
		for col in range(C.COLS - 2, 0, -1):
			if _maze[r][col] == 0:
				return Vector2i(col, r)
	return Vector2i(3, 3)


# ── Nuts init ─────────────────────────────────────────────────────────
# Port of init() nuts section — hamster_maze.html lines 511-529
func _init_nuts(llama_start: Vector2i) -> void:
	_nuts = []
	for r in range(1, C.ROWS - 1):
		for col in range(1, C.COLS - 1):
			if _maze[r][col] == 0 \
					and not (col == 1 and r == 1) \
					and not (col == llama_start.x and r == llama_start.y):
				if randf() < C.NUT_SPAWN_CHANCE:
					_nuts.append({"x": col, "y": r, "got": false, "visible": false})

	# Guarantee minimum
	while _nuts.size() < C.NUT_MIN_COUNT:
		for r in range(1, C.ROWS - 1):
			for col in range(1, C.COLS - 1):
				if _maze[r][col] == 0 and _nuts.size() < 30:
					var dup := false
					for n in _nuts:
						if n.x == col and n.y == r:
							dup = true
							break
					if not dup:
						_nuts.append({"x": col, "y": r, "got": false, "visible": false})

	# Shuffle
	_nuts.shuffle()

	# First wave: ~35%
	var first_wave: int = max(6, int(ceil(_nuts.size() * C.NUT_FIRST_WAVE_PCT)))
	for i in range(first_wave):
		_nuts[i].visible = true

	_next_wave_ms = Time.get_ticks_msec() + C.NUT_WAVE_INTERVAL_MS


# ── Input ─────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_start_game()
		return
	if _state != "play":
		return
	match event.keycode:
		KEY_SPACE:
			_do_burrow()
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


# ── Burrow toggle ─────────────────────────────────────────────────────
# Port of doBurrow() — hamster_maze.html lines 539-553
func _do_burrow() -> void:
	if not _ham.burrowed and _ham.burrows > 0:
		_ham.burrowed = true
		_ham.burrows -= 1
	elif _ham.burrowed:
		_ham.burrowed = false
		# Push llama away if she's on the same cell
		var dirs := [[0,1],[1,0],[0,-1],[-1,0]]
		for lm in [_llama, _llama2]:
			if lm and lm.x == _ham.x and lm.y == _ham.y:
				var esc: Array = []
				for d in dirs:
					var nx: int = lm.x + d[0]
					var ny: int = lm.y + d[1]
					if nx >= 0 and nx < C.COLS and ny >= 0 and ny < C.ROWS and _maze[ny][nx] == 0:
						esc.append(d)
				if esc.size() > 0:
					var chosen: Array = esc[randi() % esc.size()]
					lm.x += chosen[0]
					lm.y += chosen[1]


# ── Process ───────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_frame += 1

	if _state == "won":
		_win_anim_t += 1
		queue_redraw()
		return

	if _state == "play":
		var now_ms: int = Time.get_ticks_msec()
		_game_time_ms = now_ms - _game_start_ms

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

		# Rabbit hole teleport
		var tp := _rh.update(_ham.x, _ham.y, _ham.burrowed, now_ms)
		if tp != Vector2i(-1, -1):
			_ham.x = tp.x
			_ham.y = tp.y

		# Collect nuts
		_update_nuts(now_ms)

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


# ── Nuts update ───────────────────────────────────────────────────────
# Port of nuts section in update() — hamster_maze.html lines 921-948
func _update_nuts(now_ms: int) -> void:
	# Collect visible nuts the hamster is standing on
	for n in _nuts:
		if not n.got and n.visible and n.x == _ham.x and n.y == _ham.y:
			n.got = true

	var vis_left: int = 0
	var hid_left: int = 0
	for n in _nuts:
		if not n.got:
			if n.visible:
				vis_left += 1
			else:
				hid_left += 1

	# Win condition: all nuts collected
	if vis_left == 0 and hid_left == 0:
		_state = "won"
		_game_time_ms = Time.get_ticks_msec() - _game_start_ms
		_win_anim_t = 0
		return

	# Trigger next wave immediately if all visible collected
	if vis_left == 0 and hid_left > 0:
		_next_wave_ms = 0

	# Wave: reveal next batch every 25s
	if now_ms >= _next_wave_ms:
		var hidden: Array = []
		for n in _nuts:
			if not n.visible:
				hidden.append(n)
		if hidden.size() > 0:
			var batch_count: int = max(4, int(ceil(hidden.size() * C.NUT_NEXT_WAVE_PCT)))
			for i in range(min(batch_count, hidden.size())):
				hidden[i].visible = true
			# Alert llama toward a random nut in the batch
			var target: Dictionary = hidden[randi() % min(batch_count, hidden.size())]
			if _llama and _llama.state == "patrol":
				_llama.state = "alert"
				_llama.state_timer = 0
				_llama.dest = Vector2i(target.x, target.y)
		_next_wave_ms = now_ms + C.NUT_WAVE_INTERVAL_MS


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

	# Nuts
	for n in _nuts:
		if n.visible and not n.got:
			_draw_nut(n.x, n.y)

	# Rabbit holes and rabbits
	var now_ms: int = Time.get_ticks_msec()
	var pairs: Array = _rh.get_pairs()
	for i in range(pairs.size()):
		var pair: Dictionary = pairs[i]
		for h in pair.holes:
			_draw_rabbit_hole(h.x, h.y, i)
		# Draw rabbit if hole is cooldown and positions are being dug
		if pair.holes.is_empty() and not pair.next_pos.is_empty():
			for h in pair.next_pos:
				_draw_rabbit(h.x, h.y, pair.open_at, now_ms)

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

	# Fog of war (drawn after all game objects, before HUD)
	if _state == "play":
		_draw_fog()

	_draw_hud()

	if _state == "lost":
		_draw_lost_overlay()
	elif _state == "won":
		_draw_win_overlay()


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


# Port of drawNut() — hamster_maze.html lines 1051-1058
func _draw_nut(x: int, y: int) -> void:
	var cx: float = x * C.CELL + C.CELL * 0.5
	var cy: float = y * C.CELL + C.CELL * 0.5
	_ell(Vector2(cx + 1, cy + 3), 7.0, 5.0, Color(0, 0, 0, 0.3))
	_ell(Vector2(cx,     cy),     7.0, 9.0, Color("#7a2e0a"), 0.1)
	_ell(Vector2(cx - 2, cy - 2), 4.0, 6.0, Color("#a04520"), 0.1)
	_ell(Vector2(cx - 3, cy - 4), 2.0, 3.0, Color(1.0, 0.78, 0.39, 0.35), 0.1)
	_ell(Vector2(cx,     cy - 8), 4.0, 2.5, Color("#4a6020"))


# Port of drawRabbitHole() — hamster_maze.html lines 835-858
func _draw_rabbit_hole(x: int, y: int, pair_idx: int) -> void:
	var cx: float = x * C.CELL + C.CELL * 0.5
	var cy: float = y * C.CELL + C.CELL * 0.5
	var pulse: float = 0.72 + 0.28 * sin(_frame * 0.1 + pair_idx * PI)

	var styles: Array = RHManager.RH_STYLES
	var ring_c: Color = styles[pair_idx][0]
	var glow_c: Color = styles[pair_idx][1]

	# Outer glow layers
	_ell(Vector2(cx, cy), C.CELL * 0.75, C.CELL * 0.52,
		Color(glow_c.r, glow_c.g, glow_c.b, 0.13 * pulse))
	_ell(Vector2(cx, cy), C.CELL * 0.55, C.CELL * 0.38,
		Color(glow_c.r, glow_c.g, glow_c.b, 0.18 * pulse))

	# Colored ring
	_ell(Vector2(cx, cy), C.CELL * 0.43, C.CELL * 0.30,
		Color(ring_c.r, ring_c.g, ring_c.b, 0.65 + 0.35 * pulse))

	# Portal interior: dark edge → golden centre
	_ell(Vector2(cx, cy), C.CELL * 0.40, C.CELL * 0.27, Color(0.31, 0.12, 0.0, 0.92))
	_ell(Vector2(cx, cy), C.CELL * 0.28, C.CELL * 0.18, Color(1.0, 0.7, 0.0, 0.80 * pulse))
	_ell(Vector2(cx, cy), C.CELL * 0.16, C.CELL * 0.10, Color(1.0, 0.94, 0.24, pulse))
	_ell(Vector2(cx, cy), C.CELL * 0.06, C.CELL * 0.04, Color(0.02, 0.01, 0.0, 0.9))


# Port of drawRabbit() — hamster_maze.html lines 860-894
func _draw_rabbit(x: int, y: int, open_at_ms: int, now_ms: int) -> void:
	var px: float = x * C.CELL + C.CELL * 0.5
	var bob: float = sin(_frame * 0.13) * 2.5
	var py: float = y * C.CELL + C.CELL * 0.5 + bob

	# Shadow
	_ell(Vector2(px, y * C.CELL + C.CELL - 5.0), 8.0, 3.0, Color(0, 0, 0, 0.2))
	# Body
	_ell(Vector2(px, py + 5.0), 9.0, 11.0, Color("#e8e0cc"))
	# Head
	_ell(Vector2(px, py - 7.0), 7.0, 6.5, Color("#e8e0cc"))
	# Ears (outer)
	_ell(Vector2(px - 4.0, py - 18.0), 2.8, 7.5, Color("#e8e0cc"), -0.15)
	_ell(Vector2(px + 4.0, py - 18.0), 2.8, 7.5, Color("#e8e0cc"),  0.15)
	# Ears (inner)
	_ell(Vector2(px - 4.0, py - 18.0), 1.3, 5.5, Color("#ffb0b8"), -0.15)
	_ell(Vector2(px + 4.0, py - 18.0), 1.3, 5.5, Color("#ffb0b8"),  0.15)
	# Eye
	draw_circle(Vector2(px + 2.5, py - 8.0), 1.6, Color("#cc2244"))
	# Nose
	draw_circle(Vector2(px, py - 2.0), 1.1, Color("#ffaaaa"))
	# Countdown timer
	if open_at_ms > 0:
		var secs: int = int(ceil((open_at_ms - now_ms) / 1000.0))
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(px - 10.0, py - 27.0 + bob),
			"%dс" % secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.92, 0.31, 0.95))


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
	var body  := Color("#4a9eff") if not is_red else Color("#ff4a4a")
	var dark  := Color("#3880dd") if not is_red else Color("#cc2020")
	var light := Color("#90ccff") if not is_red else Color("#ff9999")
	var head  := Color("#5aafff") if not is_red else Color("#ff6060")
	var snout := Color("#7ac8ff") if not is_red else Color("#ffaaaa")
	var ear_in := Color("#b0dcff") if not is_red else Color("#ffdddd")
	var hoof  := Color("#1a50aa") if not is_red else Color("#991010")
	var nostr := Color("#2060cc") if not is_red else Color("#cc1010")

	if s != "patrol":
		var ac: Color
		match s:
			"chase":  ac = Color(1.0, 0.16, 0.16, 0.0)
			"alert":  ac = Color(1.0, 0.78, 0.0,  0.0)
			"search": ac = Color(1.0, 0.51, 0.0,  0.0)
		var pulse := 0.55 + 0.45 * sin(_frame * 0.22)
		ac.a = 0.38 * pulse
		_ell(Vector2(cx, cy + 5), 22, 14, ac)

	_ell(Vector2(cx, cy + 8), 13, 5, Color(0, 0, 0, 0.25))
	draw_rect(Rect2(cx - 9, cy + 3, 6, 13), dark)
	draw_rect(Rect2(cx + 3, cy + 3, 6, 13), dark)
	_ell(Vector2(cx - 6, cy + 16), 4, 2.5, hoof)
	_ell(Vector2(cx + 6, cy + 16), 4, 2.5, hoof)
	_ell(Vector2(cx, cy + 1), 14, 11, body)
	_ell(Vector2(cx, cy + 3),  9,  7, light)
	_ell(Vector2(cx + 13, cy), 4, 6, body, 0.4)
	var neck_pts := PackedVector2Array([
		Vector2(cx - 5, cy - 7), Vector2(cx + 5, cy - 7),
		Vector2(cx + 4, cy - 20), Vector2(cx - 4, cy - 20)
	])
	draw_colored_polygon(neck_pts, body)
	_ell(Vector2(cx, cy - 24), 10, 9, head)
	_ell(Vector2(cx + 1, cy - 20), 6, 4, snout, 0.15)
	var ear_l := PackedVector2Array([Vector2(cx-7,cy-30),Vector2(cx-10,cy-43),Vector2(cx-3,cy-30)])
	var ear_r := PackedVector2Array([Vector2(cx+3,cy-30),Vector2(cx+10,cy-43),Vector2(cx+7,cy-30)])
	draw_colored_polygon(ear_l, dark)
	draw_colored_polygon(ear_r, dark)
	var ear_li := PackedVector2Array([Vector2(cx-6.5,cy-31),Vector2(cx-9,cy-40),Vector2(cx-4,cy-31)])
	var ear_ri := PackedVector2Array([Vector2(cx+4,cy-31),Vector2(cx+9,cy-40),Vector2(cx+6.5,cy-31)])
	draw_colored_polygon(ear_li, ear_in)
	draw_colored_polygon(ear_ri, ear_in)
	draw_circle(Vector2(cx - 4, cy - 26), 2.5, Color("#1a1a3a"))
	draw_circle(Vector2(cx + 4, cy - 26), 2.5, Color("#1a1a3a"))
	draw_circle(Vector2(cx - 3, cy - 27), 1.0, Color("white"))
	draw_circle(Vector2(cx + 5, cy - 27), 1.0, Color("white"))
	_ell(Vector2(cx - 1, cy - 19), 1.5, 1.0, nostr)
	_ell(Vector2(cx + 3, cy - 19), 1.5, 1.0, nostr)
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

	# Nut counter
	var total_nuts: int = _nuts.size()
	var collected: int = 0
	var vis_not_got: int = 0
	for n in _nuts:
		if n.got:
			collected += 1
		elif n.visible:
			vis_not_got += 1
	draw_string(font, Vector2(8, Y + 20), "Орехи:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("white"))
	draw_string(font, Vector2(72, Y + 20), "%d / %d" % [collected, total_nuts],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffd700"))
	# Mini progress bar
	var bar_w: float = 140.0
	draw_rect(Rect2(8, Y + 25, bar_w, 6), Color("#1a1a2a"))
	if total_nuts > 0:
		draw_rect(Rect2(8, Y + 25, bar_w * collected / total_nuts, 6), Color("#ffd700"))

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

	# Burrowed status / llama state
	if _ham.burrowed:
		draw_string(font, Vector2(318, Y + 23), "Хомяк под землёй!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#44ff88"))
	else:
		if _llama and _llama.state != "patrol":
			var info := {"alert": ["Лама: слышит шаги!", Color("#ffcc00")],
						 "chase": ["Лама: ПОГОНЯ!",      Color("#ff4040")],
						 "search":["Лама: ищет...",      Color("#ff9900")]}
			var d: Array = info.get(_llama.state, [])
			if d.size() > 0:
				draw_string(font, Vector2(318, Y + 28), d[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, d[1])

	# Timer
	draw_string(font, Vector2(C.W * 0.5 - 30, Y + 22), "⏱ %s" % _fmt_time(_game_time_ms),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#7799cc"))

	# Llama speed indicator
	if _llama_bonus > 0:
		var fire := "🔥".repeat(min(4, int(ceil(float(_llama_bonus) / 2.0))))
		draw_string(font, Vector2(C.W * 0.5 - 30, Y + 40), "Лама %s" % fire,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffcc44"))

	# Controls hint
	draw_string(font, Vector2(8, Y + C.HUD - 8),
		"WASD/←↑→↓ — движение   Пробел — нора   Enter — рестарт",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#3a3a5a"))


func _draw_lost_overlay() -> void:
	draw_rect(Rect2(0, 0, C.W, C.H + C.HUD), Color(0, 0, 0, 0.78))
	var font := ThemeDB.fallback_font
	var cx: float = C.W * 0.5
	var cy: float = C.H * 0.5
	draw_rect(Rect2(cx - 230, cy - 100, 460, 200), Color("#501a1a"))
	draw_string(font, Vector2(cx - 60, cy - 10), "КОНЕЦ",   HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color("white"))
	draw_string(font, Vector2(cx - 120, cy + 40), "Лама поймала хомяка!", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1,1,1,0.85))
	draw_string(font, Vector2(cx - 130, cy + 80), "Enter — играть снова", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1,1,1,0.45))


func _draw_win_overlay() -> void:
	draw_rect(Rect2(0, 0, C.W, C.H + C.HUD), Color(0, 0, 0, 0.78))
	var font := ThemeDB.fallback_font
	var cx: float = C.W * 0.5
	var cy: float = C.H * 0.5
	var pulse: float = 1.0 + 0.06 * sin(_win_anim_t * 0.05)
	var bw: float = 460.0 * pulse
	draw_rect(Rect2(cx - bw * 0.5, cy - 110, bw, 230), Color("#0d2a0d"))
	draw_rect(Rect2(cx - bw * 0.5, cy - 110, bw, 230), Color("#ffd700"), false, 3.0)
	draw_string(font, Vector2(cx - 95, cy - 25), "ПОБЕДА!", HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color("#ffd700"))
	draw_string(font, Vector2(cx - 150, cy + 38), "Все орехи собраны!", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1,1,1,0.9))
	var total := _nuts.size()
	draw_string(font, Vector2(cx - 115, cy + 72),
		"Орехов: %d/%d   Время: %s" % [total, total, _fmt_time(_game_time_ms)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#c8e878"))
	draw_string(font, Vector2(cx - 100, cy + 108), "Enter — играть снова", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1,1,1,0.5))


# Port of drawFog() — hamster_maze.html lines 1439-1460
# Per-cell radial gradient: inside innerR fully visible, outside outerR fully dark.
func _draw_fog() -> void:
	var ham_cx: float = _ham.x * C.CELL + C.CELL * 0.5
	var ham_cy: float = _ham.y * C.CELL + C.CELL * 0.5
	var inner_px: float = FOG_INNER_R * C.CELL
	var outer_px: float = FOG_OUTER_R * C.CELL
	var fog_color := Color(0.0, 0.0, 0.04)   # rgba(0,0,10) ≈ #00000a

	for r in range(C.ROWS):
		for col in range(C.COLS):
			var cell_cx: float = col * C.CELL + C.CELL * 0.5
			var cell_cy: float = r * C.CELL + C.CELL * 0.5
			var dist: float = sqrt(
				(cell_cx - ham_cx) * (cell_cx - ham_cx) +
				(cell_cy - ham_cy) * (cell_cy - ham_cy)
			)
			var alpha: float
			if dist <= inner_px:
				alpha = 0.0
			elif dist >= outer_px:
				alpha = FOG_ALPHA
			else:
				alpha = FOG_ALPHA * (dist - inner_px) / (outer_px - inner_px)
			if alpha > 0.01:
				draw_rect(Rect2(col * C.CELL, r * C.CELL, C.CELL, C.CELL),
					Color(fog_color.r, fog_color.g, fog_color.b, alpha))


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
