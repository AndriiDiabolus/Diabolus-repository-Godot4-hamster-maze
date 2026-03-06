extends Node2D

# ── Hamster state ─────────────────────────────────────────────────────
var _ham := {"x": 1, "y": 1, "burrowed": false, "burrows": 3}

# ── Fog of war ────────────────────────────────────────────────────────
const FOG_INNER_R: float = 3.8   # cells — fully visible
const FOG_OUTER_R: float = 5.8   # cells — fully fogged
const FOG_ALPHA:   float = 0.40  # max fog darkness

# ── Movement timer ────────────────────────────────────────────────────
const MOVE_INTERVAL: float = 8.0 / 60.0
var _move_timer: float = 0.0
var _frame: int = 0

# ── Mobile touch controls ─────────────────────────────────────────────
var _show_touch: bool = false
var _touch_dirs: Dictionary = {}   # finger_id -> "up"/"down"/"left"/"right"
const MB_DPAD_CX:  float = 140.0
const MB_DPAD_CY:  float = 862.0   # center of CTRL zone (742+120)
const MB_BTN_STEP: float = 76.0
const MB_BTN_R:    float = 38.0
const MB_BURROW_X: float = 820.0
const MB_BURROW_Y: float = 862.0

# ── Game state ────────────────────────────────────────────────────────
# splash → play → (lost | won_name) → (splash | won) → splash
var _state: String = "splash"
var _game_start_ms: int = 0
var _game_time_ms: int = 0
var _win_anim_t: int = 0

# ── Maze ──────────────────────────────────────────────────────────────
var _maze: Array = []
var _maze_gen: MazeGenerator

# ── Llamas ────────────────────────────────────────────────────────────
var _llama: LlamaAI = null
var _llama2: LlamaAI = null
var _llama_bonus: int = 0

# ── Nuts ──────────────────────────────────────────────────────────────
var _nuts: Array = []
var _next_wave_ms: int = 0

# ── Rabbit holes (portals) ────────────────────────────────────────────
var _rh: RHManager = null

# ── Audio ─────────────────────────────────────────────────────────────
var _snd_eat:   AudioStreamPlayer = null
var _snd_burrow: AudioStreamPlayer = null
var _snd_tp:    AudioStreamPlayer = null
var _snd_catch: AudioStreamPlayer = null
var _snd_win:     AudioStreamPlayer = null
var _snd_music:   AudioStreamPlayer = null
var _snd_rh_laugh: AudioStreamPlayer = null

# ── Supabase ──────────────────────────────────────────────────────────
const SB_URL: String = "https://ytipfibgtnrvtsygetnb.supabase.co/rest/v1/scores"
const SB_KEY: String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl0aXBmaWJndG5ydnRzeWdldG5iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI1NDU5OTgsImV4cCI6MjA4ODEyMTk5OH0.8lbB7UJymEZppz0RI8xnoo1EeKpSo1XMoSIC1Jy73s0"
var _http_post: HTTPRequest = null
var _http_get: HTTPRequest = null
var _online_scores: Array = []
var _fetching: bool = false
var _player_uid: String = ""

# ── Leaderboard (local, persistent) ──────────────────────────────────
var _scores: Array = []   # [{name:String, time_ms:int}], sorted asc

# ── Name input UI ─────────────────────────────────────────────────────
var _name_layer: CanvasLayer = null
var _name_edit: LineEdit = null
var _name_label: Label = null


func _ready() -> void:
	_maze_gen = MazeGenerator.new()
	_show_touch = true  # TEST: force touch controls visible
	_setup_name_input()
	_setup_http()
	_setup_audio()
	_load_scores()
	_maze = _maze_gen.make_maze()
	queue_redraw()


# ── Name input setup ──────────────────────────────────────────────────
func _setup_name_input() -> void:
	_name_layer = CanvasLayer.new()
	_name_layer.layer = 10
	add_child(_name_layer)

	_name_label = Label.new()
	_name_label.position = Vector2(C.W * 0.5 - 160, C.H * 0.5 - 10)
	_name_label.size = Vector2(320, 30)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.text = "Введи своё имя и нажми Enter:"
	_name_label.add_theme_color_override("font_color", Color("#ffd700"))
	_name_label.visible = false
	_name_layer.add_child(_name_label)

	_name_edit = LineEdit.new()
	_name_edit.position = Vector2(C.W * 0.5 - 120, C.H * 0.5 + 22)
	_name_edit.size = Vector2(240, 34)
	_name_edit.placeholder_text = "Хомяк Победитель"
	_name_edit.max_length = 20
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.visible = false
	_name_layer.add_child(_name_edit)
	_name_edit.text_submitted.connect(_on_name_submitted)


func _show_name_input() -> void:
	_name_label.visible = true
	_name_edit.visible = true
	_name_edit.text = ""
	_name_edit.grab_focus()


func _hide_name_input() -> void:
	_name_label.visible = false
	_name_edit.visible = false


func _setup_audio() -> void:
	var sfx := {
		"eat":   "res://assets/sounds/eat_nut.mp3",
		"burrow":"res://assets/sounds/burrow.wav",
		"tp":    "res://assets/sounds/teleport.wav",
		"catch": "res://assets/sounds/llama_catch.wav",
		"win":   "res://assets/sounds/win.wav",
		"music":    "res://assets/sounds/bg_music.ogg",
		"rh_laugh": "res://assets/sounds/rabbit_laugh.ogg",
	}
	for key in sfx:
		var p := AudioStreamPlayer.new()
		p.stream = load(sfx[key])
		add_child(p)
		match key:
			"eat":    _snd_eat    = p
			"burrow": _snd_burrow = p
			"tp":     _snd_tp     = p
			"catch":  _snd_catch  = p
			"win":    _snd_win    = p
			"music":
				p.stream.loop = true
				_snd_music = p
				p.play()
			"rh_laugh": _snd_rh_laugh = p


func _play(p: AudioStreamPlayer) -> void:
	if p:
		p.stop()
		p.play()


func _on_name_submitted(text: String) -> void:
	var nm: String = text.strip_edges()
	if nm.is_empty():
		nm = "Хомяк"
	_scores.append({"name": nm, "time_ms": _game_time_ms})
	_scores.sort_custom(func(a, b): return a.time_ms < b.time_ms)
	if _scores.size() > 10:
		_scores.resize(10)
	_save_scores()
	_post_score(nm, _game_time_ms)
	_hide_name_input()
	_state = "won"
	queue_redraw()


func _load_scores() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://scores.cfg") != OK:
		return
	var count: int = cfg.get_value("scores", "count", 0)
	for i in range(count):
		var nm: String = cfg.get_value("scores", "name_%d" % i, "")
		var ms: int    = cfg.get_value("scores", "time_%d" % i, 0)
		if nm != "":
			_scores.append({"name": nm, "time_ms": ms})


func _save_scores() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://scores.cfg")  # preserve player/uid section
	cfg.set_value("scores", "count", _scores.size())
	for i in range(_scores.size()):
		cfg.set_value("scores", "name_%d" % i, _scores[i].name)
		cfg.set_value("scores", "time_%d" % i, _scores[i].time_ms)
	cfg.save("user://scores.cfg")


# ── Supabase HTTP ─────────────────────────────────────────────────────
func _setup_http() -> void:
	_http_post = HTTPRequest.new()
	add_child(_http_post)
	_http_post.request_completed.connect(_on_post_completed)
	_http_get = HTTPRequest.new()
	add_child(_http_get)
	_http_get.request_completed.connect(_on_get_completed)
	_load_uid()
	_fetch_online_scores()


func _load_uid() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://scores.cfg")
	_player_uid = cfg.get_value("player", "uid", "")
	if _player_uid.is_empty():
		_player_uid = "%x%x%x%x" % [randi(), randi(), randi(), randi()]
		cfg.set_value("player", "uid", _player_uid)
		cfg.save("user://scores.cfg")


func _post_score(nm: String, time_ms: int) -> void:
	var headers := PackedStringArray([
		"apikey: " + SB_KEY,
		"Authorization: Bearer " + SB_KEY,
		"Content-Type: application/json",
		"Prefer: return=minimal"
	])
	var body := JSON.stringify({
		"uid": _player_uid,
		"name": nm,
		"time": time_ms,
		"date": Time.get_date_string_from_system()
	})
	_http_post.request(SB_URL, headers, HTTPClient.METHOD_POST, body)


func _fetch_online_scores() -> void:
	if _fetching:
		return
	_fetching = true
	var headers := PackedStringArray([
		"apikey: " + SB_KEY,
		"Authorization: Bearer " + SB_KEY
	])
	_http_get.request(SB_URL + "?select=name,time&order=time.asc&limit=10", headers)


func _on_post_completed(_result: int, response_code: int, _hdrs: PackedStringArray, _body: PackedByteArray) -> void:
	if response_code == 201:
		_fetch_online_scores()


func _on_get_completed(_result: int, response_code: int, _hdrs: PackedStringArray, body: PackedByteArray) -> void:
	_fetching = false
	if response_code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	var data = json.get_data()
	if not data is Array:
		return
	_online_scores = []
	for item in data:
		if item is Dictionary and item.has("name") and item.has("time"):
			_online_scores.append({"name": str(item["name"]), "time_ms": int(item["time"])})
	queue_redraw()


# ── Start game ────────────────────────────────────────────────────────
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

	var ls := _find_llama_start()
	_llama = LlamaAI.new()
	_llama.init(ls.x, ls.y, _maze)
	_llama2 = null

	_init_nuts(ls)

	_rh = RHManager.new()
	_rh.init(_maze)


func _find_llama_start() -> Vector2i:
	for r in range(C.ROWS - 2, 0, -1):
		for col in range(C.COLS - 2, 0, -1):
			if _maze[r][col] == 0:
				return Vector2i(col, r)
	return Vector2i(3, 3)


# ── Nuts init ─────────────────────────────────────────────────────────
func _init_nuts(llama_start: Vector2i) -> void:
	_nuts = []
	for r in range(1, C.ROWS - 1):
		for col in range(1, C.COLS - 1):
			if _maze[r][col] == 0 \
					and not (col == 1 and r == 1) \
					and not (col == llama_start.x and r == llama_start.y):
				if randf() < C.NUT_SPAWN_CHANCE:
					_nuts.append({"x": col, "y": r, "got": false, "visible": false})
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
	_nuts.shuffle()
	var first_wave: int = max(6, int(ceil(_nuts.size() * C.NUT_FIRST_WAVE_PCT)))
	for i in range(first_wave):
		_nuts[i].visible = true
	_next_wave_ms = Time.get_ticks_msec() + C.NUT_WAVE_INTERVAL_MS


# ── Input ─────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_handle_screen_input(event)
		return

	if not event is InputEventKey or not event.pressed or event.echo:
		return

	# LineEdit handles its own Enter in won_name state
	if _state == "won_name":
		return

	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		match _state:
			"splash":
				_start_game()
			"lost", "won":
				_state = "splash"
				_fetch_online_scores()
				queue_redraw()
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
func _do_burrow() -> void:
	if not _ham.burrowed and _ham.burrows > 0:
		_ham.burrowed = true
		_ham.burrows -= 1
		_play(_snd_burrow)
	elif _ham.burrowed:
		_ham.burrowed = false
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


# ── Touch input ───────────────────────────────────────────────────────
func _handle_screen_input(event: InputEvent) -> void:
	var pos: Vector2
	var finger: int
	var pressed: bool
	if event is InputEventScreenTouch:
		pos = event.position; finger = event.index; pressed = event.pressed
	else:
		pos = event.position; finger = event.index; pressed = true

	# State transitions: any tap on non-play screens
	if event is InputEventScreenTouch and pressed:
		match _state:
			"splash":
				_start_game()
				return
			"lost", "won":
				_state = "splash"
				_fetch_online_scores()
				queue_redraw()
				return

	if _state != "play":
		return

	if not pressed:
		_touch_dirs.erase(finger)
		return

	var action := _mb_action_at(pos)
	if action == "burrow":
		if event is InputEventScreenTouch:
			_do_burrow()
	elif action != "":
		_touch_dirs[finger] = action


func _mb_action_at(pos: Vector2) -> String:
	if pos.distance_to(Vector2(MB_BURROW_X, MB_BURROW_Y)) <= MB_BTN_R + 20:
		return "burrow"
	var dpad_centers: Dictionary = {
		"up":    Vector2(MB_DPAD_CX, MB_DPAD_CY - MB_BTN_STEP),
		"down":  Vector2(MB_DPAD_CX, MB_DPAD_CY + MB_BTN_STEP),
		"left":  Vector2(MB_DPAD_CX - MB_BTN_STEP, MB_DPAD_CY),
		"right": Vector2(MB_DPAD_CX + MB_BTN_STEP, MB_DPAD_CY),
	}
	for dir in dpad_centers:
		if pos.distance_to(dpad_centers[dir]) <= MB_BTN_R + 16:
			return dir
	return ""


# ── Process ───────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_frame += 1

	if _state == "splash" or _state == "won_name":
		queue_redraw()
		return

	if _state == "won":
		_win_anim_t += 1
		queue_redraw()
		return

	if _state == "play":
		var now_ms: int = Time.get_ticks_msec()
		_game_time_ms = now_ms - _game_start_ms
		_llama_bonus = min(C.LLAMA_BONUS_MAX, _game_time_ms / C.LLAMA_BONUS_INTERVAL_MS)

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
			elif not _touch_dirs.is_empty():
				for td in _touch_dirs.values():
					match td:
						"up":    dy = -1
						"down":  dy =  1
						"left":  dx = -1
						"right": dx =  1
					if dx != 0 or dy != 0:
						break
			if dx != 0 or dy != 0:
				_try_move(dx, dy)

		# Check if rabbit just started digging (next_pos newly populated)
		var pairs_before: Array = []
		for _p in _rh.get_pairs():
			pairs_before.append(_p.next_pos.is_empty())

		var tp := _rh.update(_ham.x, _ham.y, _ham.burrowed, now_ms)
		if tp != Vector2i(-1, -1):
			_ham.x = tp.x
			_ham.y = tp.y
			_play(_snd_tp)

		var pairs_after: Array = _rh.get_pairs()
		for i in range(pairs_after.size()):
			if pairs_before[i] and not pairs_after[i].next_pos.is_empty():
				_play(_snd_rh_laugh)
				break

		_update_nuts(now_ms)

		if _llama:
			var caught := _llama.update(_ham.x, _ham.y, _ham.burrowed, _llama_bonus)
			if caught:
				_state = "lost"
				_game_time_ms = Time.get_ticks_msec() - _game_start_ms
				_play(_snd_catch)

		if _llama2 == null and _game_time_ms >= C.LLAMA2_SPAWN_MS:
			var s2 := _random_far_cell(_ham.x, _ham.y, 8)
			_llama2 = LlamaAI.new()
			_llama2.init(s2.x, s2.y, _maze)

		if _llama2:
			var caught2 := _llama2.update(_ham.x, _ham.y, _ham.burrowed, _llama_bonus)
			if caught2:
				_state = "lost"
				_game_time_ms = Time.get_ticks_msec() - _game_start_ms
				_play(_snd_catch)

	queue_redraw()


# ── Nuts update ───────────────────────────────────────────────────────
func _update_nuts(now_ms: int) -> void:
	for n in _nuts:
		if not n.got and n.visible and n.x == _ham.x and n.y == _ham.y:
			n.got = true
			_play(_snd_eat)

	var vis_left: int = 0
	var hid_left: int = 0
	for n in _nuts:
		if not n.got:
			if n.visible:
				vis_left += 1
			else:
				hid_left += 1

	if vis_left == 0 and hid_left == 0:
		_state = "won_name"
		_game_time_ms = Time.get_ticks_msec() - _game_start_ms
		_win_anim_t = 0
		_play(_snd_win)
		_show_name_input()
		return

	if vis_left == 0 and hid_left > 0:
		_next_wave_ms = 0

	if now_ms >= _next_wave_ms:
		var hidden: Array = []
		for n in _nuts:
			if not n.visible:
				hidden.append(n)
		if hidden.size() > 0:
			var batch_count: int = max(4, int(ceil(hidden.size() * C.NUT_NEXT_WAVE_PCT)))
			for i in range(min(batch_count, hidden.size())):
				hidden[i].visible = true
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
	if _state == "splash":
		_draw_splash()
		if _show_touch:
			_draw_mobile_controls()
		return

	draw_rect(Rect2(0, 0, C.W, C.H + C.HUD + C.CTRL_H), Color("#0d0d1a"))
	_draw_maze()

	for n in _nuts:
		if n.visible and not n.got:
			_draw_nut(n.x, n.y)

	var now_ms: int = Time.get_ticks_msec()
	var pairs: Array = _rh.get_pairs()
	for i in range(pairs.size()):
		var pair: Dictionary = pairs[i]
		for h in pair.holes:
			_draw_rabbit_hole(h.x, h.y, i)
		if pair.holes.is_empty() and not pair.next_pos.is_empty():
			for h in pair.next_pos:
				_draw_rabbit(h.x, h.y, pair.open_at, now_ms)

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

	if _state == "play":
		_draw_fog()

	_draw_hud()

	if _state == "lost":
		_draw_lost_overlay()
	elif _state == "won" or _state == "won_name":
		_draw_win_overlay()

	if _show_touch:
		_draw_mobile_controls()


# ── Splash screen ─────────────────────────────────────────────────────
func _draw_splash() -> void:
	# Background gradient (approximated)
	draw_rect(Rect2(0, 0, C.W, C.H + C.HUD + C.CTRL_H), Color("#050510"))
	# Subtle center glow
	for i in range(8):
		var r: float = (8 - i) * 60.0
		var a: float = 0.04 * (i / 8.0)
		_ell(Vector2(C.W * 0.5, (C.H + C.HUD) * 0.44), r, r * 0.6, Color(0.2, 0.3, 0.8, a))

	var font := ThemeDB.fallback_font
	var cx: float = C.W * 0.5
	var pulse: float = 1.0 + 0.04 * sin(_frame * 0.04)

	# Title
	var title_y: float = 58.0
	draw_string(font, Vector2(cx - 215, title_y), "ХОМЯК В ЛАБИРИНТЕ",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 42, Color("#ffd700"))
	draw_string(font, Vector2(cx - 130, title_y + 36), "Собери все орехи!",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.55, 0.75, 1.0, 0.75))

	# Divider
	draw_rect(Rect2(30, title_y + 50, C.W - 60, 1), Color("#1a3060"))

	# ── Two columns ──────────────────────────────────────────────────
	var col1_x: float = 30.0
	var col2_x: float = C.W * 0.5 + 10.0
	var row_y: float = title_y + 70.0

	# Column 1 — Rules
	draw_string(font, Vector2(col1_x, row_y), "Правила",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#ffd700"))
	row_y += 6
	draw_rect(Rect2(col1_x, row_y, C.W * 0.5 - 50.0, 1), Color("#1a3060"))
	row_y += 14

	var rules: Array = [
		["Хомяк", "WASD / стрелки"],
		["Нора", "Пробел (3 попытки)"],
		["Цель", "Собери все орехи"],
		["Орехи", "Появляются волнами"],
		["Синяя лама", "Слышит на 8 клеток"],
		["Красная лама", "Через 1 минуту"],
		["Порталы", "2 пары, +1 мин кулдаун"],
		["Туман", "Видимость ~4 клетки"],
	]
	for rule in rules:
		draw_string(font, Vector2(col1_x, row_y), rule[0] + ":",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.55))
		draw_string(font, Vector2(col1_x + 110, row_y), rule[1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.85, 1.0, 0.9))
		row_y += 22

	# Column 2 — Leaderboard
	var lb_y: float = title_y + 70.0
	var show_online: bool = not _online_scores.is_empty()
	var lb_title: String = "Онлайн рекорды" if show_online else "Рекорды"
	draw_string(font, Vector2(col2_x, lb_y), lb_title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#ffd700"))
	lb_y += 6
	draw_rect(Rect2(col2_x, lb_y, C.W * 0.5 - 50.0, 1), Color("#1a3060"))
	lb_y += 14

	var scores_to_show: Array = _online_scores if show_online else _scores
	if scores_to_show.is_empty():
		var hint: String = "Загрузка..." if _fetching else "Пока нет рекордов"
		draw_string(font, Vector2(col2_x, lb_y + 10), hint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.3))
	else:
		var medals_arr := ["1.", "2.", "3.", "4.", "5.", "6.", "7.", "8."]
		for i in range(min(scores_to_show.size(), 8)):
			var sc: Dictionary = scores_to_show[i]
			var rank_c: Color = Color("#ffd700") if i == 0 else Color(0.7, 0.85, 1.0, 0.8)
			var medal: String = medals_arr[i] if i < medals_arr.size() else "%d." % (i + 1)
			draw_string(font, Vector2(col2_x, lb_y), medal,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, rank_c)
			draw_string(font, Vector2(col2_x + 30, lb_y), sc.name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, rank_c)
			draw_string(font, Vector2(col2_x + 170, lb_y), _fmt_time(sc.time_ms),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, rank_c)
			lb_y += 22

	# Start button hint
	var btn_y: float = C.H + C.HUD - 70.0
	var bw: float = 260.0 * pulse
	draw_rect(Rect2(cx - bw * 0.5, btn_y, bw, 42), Color("#1a2a50"))
	draw_rect(Rect2(cx - bw * 0.5, btn_y, bw, 42), Color("#ffd700", 0.7), false, 2.0)
	draw_string(font, Vector2(cx - 100, btn_y + 28), "Enter — Начать игру",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#ffd700"))

	# Version hint
	draw_string(font, Vector2(cx - 60, C.H + C.HUD - 12), "Godot 4  •  Etap 8",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.2))


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
	_ell(Vector2(cx, cy), C.CELL * 0.75, C.CELL * 0.52,
		Color(glow_c.r, glow_c.g, glow_c.b, 0.13 * pulse))
	_ell(Vector2(cx, cy), C.CELL * 0.55, C.CELL * 0.38,
		Color(glow_c.r, glow_c.g, glow_c.b, 0.18 * pulse))
	_ell(Vector2(cx, cy), C.CELL * 0.43, C.CELL * 0.30,
		Color(ring_c.r, ring_c.g, ring_c.b, 0.65 + 0.35 * pulse))
	_ell(Vector2(cx, cy), C.CELL * 0.40, C.CELL * 0.27, Color(0.31, 0.12, 0.0, 0.92))
	_ell(Vector2(cx, cy), C.CELL * 0.28, C.CELL * 0.18, Color(1.0, 0.7, 0.0, 0.80 * pulse))
	_ell(Vector2(cx, cy), C.CELL * 0.16, C.CELL * 0.10, Color(1.0, 0.94, 0.24, pulse))
	_ell(Vector2(cx, cy), C.CELL * 0.06, C.CELL * 0.04, Color(0.02, 0.01, 0.0, 0.9))


# Port of drawRabbit() — hamster_maze.html lines 860-894
func _draw_rabbit(x: int, y: int, open_at_ms: int, now_ms: int) -> void:
	var px: float = x * C.CELL + C.CELL * 0.5
	var bob: float = sin(_frame * 0.13) * 2.5
	var py: float = y * C.CELL + C.CELL * 0.5 + bob
	_ell(Vector2(px, y * C.CELL + C.CELL - 5.0), 8.0, 3.0, Color(0, 0, 0, 0.2))
	_ell(Vector2(px, py + 5.0), 9.0, 11.0, Color("#e8e0cc"))
	_ell(Vector2(px, py - 7.0), 7.0, 6.5, Color("#e8e0cc"))
	_ell(Vector2(px - 4.0, py - 18.0), 2.8, 7.5, Color("#e8e0cc"), -0.15)
	_ell(Vector2(px + 4.0, py - 18.0), 2.8, 7.5, Color("#e8e0cc"),  0.15)
	_ell(Vector2(px - 4.0, py - 18.0), 1.3, 5.5, Color("#ffb0b8"), -0.15)
	_ell(Vector2(px + 4.0, py - 18.0), 1.3, 5.5, Color("#ffb0b8"),  0.15)
	draw_circle(Vector2(px + 2.5, py - 8.0), 1.6, Color("#cc2244"))
	draw_circle(Vector2(px, py - 2.0), 1.1, Color("#ffaaaa"))
	if open_at_ms > 0:
		var secs: int = int(ceil((open_at_ms - now_ms) / 1000.0))
		draw_string(ThemeDB.fallback_font, Vector2(px - 10.0, py - 27.0 + bob),
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

	# Nut counter + progress bar
	var total_nuts: int = _nuts.size()
	var collected: int = 0
	var vis_not_got: int = 0
	var hidden_count: int = 0
	for n in _nuts:
		if n.got:
			collected += 1
		elif n.visible:
			vis_not_got += 1
		else:
			hidden_count += 1

	draw_string(font, Vector2(8, Y + 20), "Орехи:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ffd700"))
	draw_string(font, Vector2(70, Y + 20), "%d / %d" % [collected, total_nuts],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("white"))
	var bar_w: float = 140.0
	var pct: float = float(collected) / max(total_nuts, 1)
	draw_rect(Rect2(8, Y + 25, bar_w, 7), Color("#111"))
	var bar_c: Color = Color("#88ff44") if pct >= 0.5 else Color("#ffd700")
	draw_rect(Rect2(8, Y + 25, bar_w * pct, 7), bar_c)
	draw_rect(Rect2(8, Y + 25, bar_w, 7), Color("#3a3a3a"), false, 1.0)
	if hidden_count > 0:
		var wave_secs: int = max(0, int(ceil((_next_wave_ms - Time.get_ticks_msec()) / 1000.0)))
		draw_string(font, Vector2(8, Y + 42), "+%d через %dс" % [hidden_count, wave_secs],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.5, 0.5, 0.9))

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

	# Status
	if _ham.burrowed:
		var pulse: float = 0.55 + 0.45 * sin(_frame * 0.18)
		draw_rect(Rect2(0, Y, C.W, C.HUD), Color(0.27, 0.86, 0.43, pulse * 0.10))
		draw_string(font, Vector2(318, Y + 23), "Хомяк под землёй!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#44ff88"))
		draw_string(font, Vector2(318, Y + 40), "Лама потеряла след...", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.27, 1.0, 0.53, 0.7))
	else:
		if _llama and _llama.state != "patrol":
			var info := {"alert": ["Лама: слышит шаги!", Color("#ffcc00")],
						 "chase": ["Лама: ПОГОНЯ!",      Color("#ff4040")],
						 "search":["Лама: ищет...",      Color("#ff9900")]}
			var d: Array = info.get(_llama.state, [])
			if d.size() > 0:
				var alpha: float = 0.7 + 0.3 * sin(_frame * 0.2)
				var sc: Color = d[1]
				if _llama.state == "chase":
					sc.a = alpha
				draw_string(font, Vector2(318, Y + 28), d[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, sc)

	# Timer
	draw_string(font, Vector2(C.W * 0.5 - 30, Y + 22), "⏱ %s" % _fmt_time(_game_time_ms),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#7799cc"))

	if _llama_bonus > 0:
		var fire := "🔥".repeat(min(4, int(ceil(float(_llama_bonus) / 2.0))))
		draw_string(font, Vector2(C.W * 0.5 - 30, Y + 40), "Лама %s" % fire,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffcc44"))

	var hint: String = "WASD/←↑→↓ — движение   Пробел — нора   Enter — рестарт" if not _show_touch \
		else "D-pad — движение   [нора] — закопаться"
	draw_string(font, Vector2(8, Y + C.HUD - 8),
		hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#3a3a5a"))


func _draw_lost_overlay() -> void:
	draw_rect(Rect2(0, 0, C.W, C.H + C.HUD + C.CTRL_H), Color(0, 0, 0, 0.78))
	var font := ThemeDB.fallback_font
	var cx: float = C.W * 0.5
	var cy: float = C.H * 0.5
	draw_rect(Rect2(cx - 230, cy - 100, 460, 210), Color("#501a1a"))
	draw_rect(Rect2(cx - 230, cy - 100, 460, 210), Color("#aa2020"), false, 2.0)
	draw_string(font, Vector2(cx - 60, cy - 15), "КОНЕЦ", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color("white"))
	draw_string(font, Vector2(cx - 120, cy + 38), "Лама поймала хомяка!", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1,1,1,0.85))
	var collected: int = 0
	for n in _nuts:
		if n.got:
			collected += 1
	draw_string(font, Vector2(cx - 100, cy + 72),
		"Собрано орехов: %d / %d" % [collected, _nuts.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#c8b060", 0.85))
	draw_string(font, Vector2(cx - 130, cy + 98), "Enter — в главное меню", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1,1,1,0.45))


func _draw_win_overlay() -> void:
	draw_rect(Rect2(0, 0, C.W, C.H + C.HUD + C.CTRL_H), Color(0, 0, 0, 0.82))
	var font := ThemeDB.fallback_font
	var cx: float = C.W * 0.5
	var cy: float = C.H * 0.5

	if _state == "won_name":
		# Waiting for player to type name
		draw_rect(Rect2(cx - 240, cy - 120, 480, 220), Color("#0d2a0d"))
		draw_rect(Rect2(cx - 240, cy - 120, 480, 220), Color("#ffd700"), false, 2.0)
		draw_string(font, Vector2(cx - 95, cy - 78), "ПОБЕДА!", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color("#ffd700"))
		draw_string(font, Vector2(cx - 140, cy - 28), "Все орехи собраны! Время: %s" % _fmt_time(_game_time_ms),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#c8e878"))
		# Name input area highlighted (LineEdit node renders on top)
		draw_rect(Rect2(cx - 125, cy + 17, 250, 40), Color("#1a1a3a"))
		draw_rect(Rect2(cx - 125, cy + 17, 250, 40), Color("#ffd700", 0.5), false, 1.5)
		return

	# "won" state — show result + leaderboard
	var pulse: float = 1.0 + 0.05 * sin(_win_anim_t * 0.05)
	var bw: float = 480.0 * pulse
	draw_rect(Rect2(cx - bw * 0.5, cy - 170, bw, 360), Color("#0d2a0d"))
	draw_rect(Rect2(cx - bw * 0.5, cy - 170, bw, 360), Color("#ffd700"), false, 2.5)
	draw_string(font, Vector2(cx - 95, cy - 125), "ПОБЕДА!", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color("#ffd700"))
	draw_string(font, Vector2(cx - 130, cy - 75), "Все орехи собраны! Время: %s" % _fmt_time(_game_time_ms),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#c8e878"))

	# Leaderboard inside win overlay
	draw_rect(Rect2(cx - 200, cy - 50, 400, 1), Color("#1a3060"))
	draw_string(font, Vector2(cx - 80, cy - 32), "Таблица рекордов",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#ffd700", 0.8))

	var lb_y: float = cy - 8.0
	for i in range(min(_scores.size(), 6)):
		var sc: Dictionary = _scores[i]
		var is_last: bool = (sc.time_ms == _game_time_ms and i == _scores.size() - 1) or \
							(sc.time_ms == _game_time_ms)
		var rank_c: Color = Color("#ffd700") if i == 0 else Color(0.75, 0.9, 1.0, 0.85)
		if is_last and i == 0:
			rank_c = Color("#ffd700")
		var medals := ["1.", "2.", "3.", "4.", "5.", "6."]
		draw_string(font, Vector2(cx - 190, lb_y), medals[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, rank_c)
		draw_string(font, Vector2(cx - 165, lb_y), sc.name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, rank_c)
		draw_string(font, Vector2(cx + 80, lb_y), _fmt_time(sc.time_ms),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, rank_c)
		lb_y += 22.0

	draw_string(font, Vector2(cx - 110, cy + 165), "Enter — в главное меню",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1,1,1,0.45))


# Port of drawFog() — hamster_maze.html lines 1439-1460
func _draw_fog() -> void:
	var ham_cx: float = _ham.x * C.CELL + C.CELL * 0.5
	var ham_cy: float = _ham.y * C.CELL + C.CELL * 0.5
	var inner_px: float = FOG_INNER_R * C.CELL
	var outer_px: float = FOG_OUTER_R * C.CELL
	var fog_color := Color(0.05, 0.05, 0.10)

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


# ── Mobile controls rendering ──────────────────────────────────────────
func _draw_mobile_controls() -> void:
	var font := ThemeDB.fallback_font
	var zone_y: float = C.H + C.HUD

	# Blue background for controls zone
	draw_rect(Rect2(0, zone_y, C.W, C.CTRL_H), Color("#0a1535"))
	draw_rect(Rect2(0, zone_y, C.W, 2), Color("#1a3060"))  # top border line

	if _state != "play":
		draw_string(font, Vector2(C.W * 0.5 - 60, zone_y + C.CTRL_H * 0.5 + 8),
			"Tap — продолжить", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.35))
		return

	var active: Array = _touch_dirs.values()

	# D-pad: 4 direction buttons
	var dpad_pos: Dictionary = {
		"up":    Vector2(MB_DPAD_CX,               MB_DPAD_CY - MB_BTN_STEP),
		"down":  Vector2(MB_DPAD_CX,               MB_DPAD_CY + MB_BTN_STEP),
		"left":  Vector2(MB_DPAD_CX - MB_BTN_STEP, MB_DPAD_CY),
		"right": Vector2(MB_DPAD_CX + MB_BTN_STEP, MB_DPAD_CY),
	}
	# Center disc
	_ell(Vector2(MB_DPAD_CX, MB_DPAD_CY), 26, 26, Color(0, 0, 0, 0.25))

	for dir in dpad_pos:
		var center: Vector2 = dpad_pos[dir]
		var is_pressed: bool = active.has(dir)
		var bg_a: float = 0.60 if is_pressed else 0.28
		_ell(center, MB_BTN_R, MB_BTN_R, Color(0.15, 0.22, 0.50, bg_a))
		draw_colored_polygon(_mb_arrow(center, dir), Color(1, 1, 1, 0.75 if is_pressed else 0.45))

	# Burrow button
	var bur_r: float = MB_BTN_R + 10
	_ell(Vector2(MB_BURROW_X, MB_BURROW_Y), bur_r, bur_r, Color(0.05, 0.28, 0.08, 0.45))
	_ell(Vector2(MB_BURROW_X, MB_BURROW_Y), bur_r - 4, bur_r - 4, Color(0.05, 0.18, 0.06, 0.30))
	draw_string(font, Vector2(MB_BURROW_X - 18, MB_BURROW_Y + 7),
		"НОРА", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.4, 1.0, 0.4, 0.65))
	draw_string(font, Vector2(MB_BURROW_X - 13, MB_BURROW_Y - 14),
		"[SP]", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.28))


func _mb_arrow(center: Vector2, dir: String) -> PackedVector2Array:
	var s: float = MB_BTN_R * 0.52
	var pts := PackedVector2Array()
	match dir:
		"up":
			pts.append(Vector2(center.x,       center.y - s))
			pts.append(Vector2(center.x + s,   center.y + s * 0.55))
			pts.append(Vector2(center.x - s,   center.y + s * 0.55))
		"down":
			pts.append(Vector2(center.x,       center.y + s))
			pts.append(Vector2(center.x - s,   center.y - s * 0.55))
			pts.append(Vector2(center.x + s,   center.y - s * 0.55))
		"left":
			pts.append(Vector2(center.x - s,   center.y))
			pts.append(Vector2(center.x + s * 0.55, center.y - s))
			pts.append(Vector2(center.x + s * 0.55, center.y + s))
		"right":
			pts.append(Vector2(center.x + s,   center.y))
			pts.append(Vector2(center.x - s * 0.55, center.y - s))
			pts.append(Vector2(center.x - s * 0.55, center.y + s))
	return pts


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
