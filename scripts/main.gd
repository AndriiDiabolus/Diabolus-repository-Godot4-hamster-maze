extends Node2D

# ── Hamster state ─────────────────────────────────────────────────────
var _ham := {"x": 1, "y": 1, "burrowed": false, "burrows": 3}

# ── Fog of war ────────────────────────────────────────────────────────
const FOG_INNER_R: float = 3.8   # cells — fully visible
const FOG_OUTER_R: float = 5.8   # cells — fully fogged
const FOG_ALPHA:   float = 0.40  # max fog darkness

# ── Movement timer ────────────────────────────────────────────────────
const MOVE_INTERVAL: float = 8.0 / 60.0
const WIN_SPIN_DUR: int = 240    # кадров (~4 сек) — танец хомяка
const MENU_INTRO_DUR: int = 285  # кадров — вступительная анимация меню
const LEVEL_TRANS_DUR: int = 150 # кадров (~2.5 сек) — экран перехода уровня
const LEVEL_SPEED_MULT: float = 0.06  # на сколько быстрее лама за уровень
const LEVEL_SPEED_MIN: int = 12       # минимум фреймов/шаг (макс скорость ламы)
var _move_timer: float = 0.0
var _frame: int = 0

# ── Mobile touch controls ─────────────────────────────────────────────
var _show_touch: bool = false
var _touch_dirs: Dictionary = {}   # finger_id -> "up"/"down"/"left"/"right"
var _held_keys: Dictionary = {}    # keycode -> bool, web-compatible held key state
const MB_DPAD_CX:  float = 140.0
const MB_DPAD_CY:  float = 980.0   # bottom of CTRL zone, title takes top portion
const MB_BTN_STEP: float = 76.0
const MB_BTN_R:    float = 38.0
const MB_BURROW_X: float = 820.0
const MB_BURROW_Y: float = 980.0

# ── Game state ────────────────────────────────────────────────────────
# menu → play → level_up → play → ... → lost → won_name → won → menu
var _state: String = "menu"
var _music_on: bool = true
var _menu_selected: int = 0             # 0=play, 1=music, 2=credits
var _menu_btn_rects: Dictionary = {}   # "play","music","credits","back" → Rect2
var _game_start_ms: int = 0
var _game_time_ms: int = 0
var _total_time_ms: int = 0     # суммарное время всех уровней
var _win_anim_t: int = 0
var _level: int = 1
var _level_trans_t: int = 0     # счётчик анимации перехода уровня
var _menu_anim_t: int = 0    # счётчик анимации меню
var _menu_dust: Array = []    # [{x,y,r,life,max_life}]
var _prev_state: String = "" # для сброса анимации при входе в меню
var _particles: Array = []   # [{x,y,vx,vy,life,max_life,color}]
var _bonuses: Array = []     # [{x,y,type,got}] type: "shield"|"speed"|"freeze"
var _shield_until: int = 0   # Time.get_ticks_msec() до которого действует щит
var _speed_until: int = 0    # до которого действует скорость
var _freeze_until: int = 0   # до которого ламы заморожены

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
var _js_get_cb  = null   # JavaScriptObject — web only
var _js_post_cb = null   # JavaScriptObject — web only
var _stone_font: FontFile = null

# ── Leaderboard (local, persistent) ──────────────────────────────────
var _scores: Array = []   # [{name:String, time_ms:int}], sorted asc

# ── Name input UI ─────────────────────────────────────────────────────
var _name_layer: CanvasLayer = null
var _name_edit: LineEdit = null
var _name_label: Label = null


func _ready() -> void:
	_maze_gen = MazeGenerator.new()
	_show_touch = true  # TEST: force touch controls visible
	_stone_font = load("res://assets/fonts/flintstone.ttf")
	_setup_name_input()
	_setup_http()
	_setup_audio()
	_load_scores()
	_maze = _maze_gen.make_maze()
	_fetch_online_scores()
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
		"win":   "res://assets/sounds/win_new.ogg",
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
	_scores.append({"name": nm, "time_ms": _total_time_ms, "level": _level})
	_scores.sort_custom(func(a, b): return a.get("level", 1) > b.get("level", 1) or \
		(a.get("level", 1) == b.get("level", 1) and a.time_ms < b.time_ms))
	if _scores.size() > 10:
		_scores.resize(10)
	_save_scores()
	_post_score(nm, _total_time_ms)
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
	var body_str := JSON.stringify({
		"uid": _player_uid, "name": nm,
		"time": time_ms, "date": Time.get_date_string_from_system()
	})
	if OS.get_name() == "Web":
		_js_post_cb = JavaScriptBridge.create_callback(_on_js_post_done)
		var js := """
fetch('%s', {method:'POST',
  headers:{'apikey':'%s','Authorization':'Bearer %s',
            'Content-Type':'application/json','Prefer':'return=minimal'},
  body:'%s'
}).then(r=>window._gd_post_cb(r.status)).catch(()=>window._gd_post_cb(0));
""" % [SB_URL, SB_KEY, SB_KEY, body_str.replace("'", "\\'")]
		JavaScriptBridge.get_interface("window").set("_gd_post_cb", _js_post_cb)
		JavaScriptBridge.eval(js)
	else:
		var headers := PackedStringArray([
			"apikey: " + SB_KEY, "Authorization: Bearer " + SB_KEY,
			"Content-Type: application/json", "Prefer: return=minimal"
		])
		_http_post.request(SB_URL, headers, HTTPClient.METHOD_POST, body_str)


func _fetch_online_scores() -> void:
	if _fetching:
		return
	_fetching = true
	if OS.get_name() == "Web":
		_js_get_cb = JavaScriptBridge.create_callback(_on_js_get_done)
		var url := SB_URL + "?select=name,time&order=time.asc&limit=10"
		var js := """
fetch('%s', {headers:{'apikey':'%s','Authorization':'Bearer %s'}})
  .then(r=>r.text()).then(t=>window._gd_get_cb(t))
  .catch(()=>window._gd_get_cb('[]'));
""" % [url, SB_KEY, SB_KEY]
		JavaScriptBridge.get_interface("window").set("_gd_get_cb", _js_get_cb)
		JavaScriptBridge.eval(js)
	else:
		var headers := PackedStringArray(["apikey: " + SB_KEY, "Authorization: Bearer " + SB_KEY])
		_http_get.request(SB_URL + "?select=name,time&order=time.asc&limit=10", headers)


func _on_js_get_done(args: Array) -> void:
	_fetching = false
	var raw: String = str(args[0]) if args.size() > 0 else "[]"
	_parse_scores_json(raw)


func _on_js_post_done(args: Array) -> void:
	var code: int = int(str(args[0])) if args.size() > 0 else 0
	if code == 201:
		_fetch_online_scores()


func _on_post_completed(_result: int, response_code: int, _hdrs: PackedStringArray, _body: PackedByteArray) -> void:
	if response_code == 201:
		_fetch_online_scores()


func _on_get_completed(_result: int, response_code: int, _hdrs: PackedStringArray, body: PackedByteArray) -> void:
	_fetching = false
	if response_code != 200:
		return
	_parse_scores_json(body.get_string_from_utf8())


func _parse_scores_json(raw: String) -> void:
	var json := JSON.new()
	if json.parse(raw) != OK:
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
	_level = 1
	_total_time_ms = 0
	_start_level()


func _start_level() -> void:
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
	_init_bonuses(ls)
	_shield_until = 0
	_speed_until = 0
	_freeze_until = 0

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
				if _maze[r][col] == 0 and _nuts.size() < C.NUT_MIN_COUNT:
					var dup := false
					for n in _nuts:
						if n.x == col and n.y == r:
							dup = true
							break
					if not dup:
						_nuts.append({"x": col, "y": r, "got": false, "visible": false})
	_nuts.shuffle()
	if _nuts.size() > C.NUT_MAX_COUNT:
		_nuts.resize(C.NUT_MAX_COUNT)
	var first_wave: int = max(6, int(ceil(_nuts.size() * C.NUT_FIRST_WAVE_PCT)))
	for i in range(first_wave):
		_nuts[i].visible = true
	_next_wave_ms = Time.get_ticks_msec() + C.NUT_WAVE_INTERVAL_MS


# ── Input ─────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_handle_screen_input(event)
		return

	# Mouse click (desktop)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_menu_click(event.position)
		return

	# Track held key state for web-compatible movement (Input.is_key_pressed won't see JS events)
	if event is InputEventKey and not event.echo:
		var _hk: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		_held_keys[_hk] = event.pressed

	if not event is InputEventKey or not event.pressed or event.echo:
		return

	# LineEdit handles its own Enter in won_name state
	if _state == "won_name":
		return

	var kc: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode

	# ── Menu keyboard navigation ──────────────────────────────────────
	if _state == "menu":
		match kc:
			KEY_W, KEY_UP:
				_menu_selected = (_menu_selected - 1 + 3) % 3
				queue_redraw()
			KEY_S, KEY_DOWN:
				_menu_selected = (_menu_selected + 1) % 3
				queue_redraw()
			KEY_ENTER, KEY_KP_ENTER:
				_activate_menu_selection()
		return

	if _state == "credits":
		_state = "menu"
		queue_redraw()
		return

	if kc == KEY_ENTER or kc == KEY_KP_ENTER:
		match _state:
			"splash":
				_start_game()
			"lost":
				_state = "won_name"
				_win_anim_t = WIN_SPIN_DUR  # пропускаем танец
				_show_name_input()
				queue_redraw()
			"won":
				_state = "menu"
				_fetch_online_scores()
				queue_redraw()
		return

	if _state != "play":
		return

	# physical_keycode works reliably in web builds for letter keys (WASD)
	match kc:
		KEY_SPACE:
			_do_burrow()
			return

	var dx: int = 0
	var dy: int = 0
	match kc:
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

	# State transitions: taps on non-play screens
	if event is InputEventScreenTouch and pressed:
		match _state:
			"menu":
				_handle_menu_click(pos)
				return
			"credits":
				_state = "menu"
				queue_redraw()
				return
			"splash":
				_start_game()
				return
			"lost":
				_state = "won_name"
				_win_anim_t = WIN_SPIN_DUR  # пропускаем танец
				_show_name_input()
				queue_redraw()
				return
			"won":
				_state = "menu"
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


func _handle_menu_click(pos: Vector2) -> void:
	# На touch-устройствах canvas сжат — увеличиваем зону нажатия
	var pad: float = 28.0 if _show_touch else 0.0
	if _state == "menu":
		if _menu_btn_rects.has("play") and _menu_btn_rects["play"].grow(pad).has_point(pos):
			_menu_selected = 0
			_activate_menu_selection()
		elif _menu_btn_rects.has("music") and _menu_btn_rects["music"].grow(pad).has_point(pos):
			_menu_selected = 1
			_activate_menu_selection()
		elif _menu_btn_rects.has("credits") and _menu_btn_rects["credits"].grow(pad).has_point(pos):
			_menu_selected = 2
			_activate_menu_selection()
	elif _state == "credits":
		if _menu_btn_rects.has("back") and _menu_btn_rects["back"].grow(pad).has_point(pos):
			_state = "menu"
			queue_redraw()


func _activate_menu_selection() -> void:
	match _menu_selected:
		0:  # play
			_start_game()
		1:  # music
			_music_on = not _music_on
			if _music_on:
				_snd_music.play()
			else:
				_snd_music.stop()
			queue_redraw()
		2:  # credits
			_state = "credits"
			queue_redraw()


# ── Process ───────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_frame += 1

	# Сброс анимации при входе в меню
	if _state != _prev_state:
		if _state == "menu":
			_menu_anim_t = 0
			_menu_dust.clear()
		_prev_state = _state

	if _state == "menu":
		_menu_anim_t += 1
		for i in range(_menu_dust.size() - 1, -1, -1):
			_menu_dust[i].life -= 1
			if _menu_dust[i].life <= 0:
				_menu_dust.remove_at(i)
		_menu_add_dust()

	if _state in ["menu", "credits", "splash"]:
		queue_redraw()
		return

	if _state == "level_up":
		_level_trans_t += 1
		if _level_trans_t >= LEVEL_TRANS_DUR:
			_level += 1
			_start_level()
		queue_redraw()
		return

	if _state == "won_name":
		_win_anim_t += 1
		if _win_anim_t == WIN_SPIN_DUR:
			_show_name_input()
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
		_update_particles()

		var move_int: float = MOVE_INTERVAL * 0.5 if now_ms < _speed_until else MOVE_INTERVAL
		_move_timer += delta
		if _move_timer >= move_int and not _ham.burrowed:
			_move_timer = 0.0
			var dx: int = 0
			var dy: int = 0
			if _held_keys.get(KEY_W, false) or _held_keys.get(KEY_UP, false):
				dy = -1
			elif _held_keys.get(KEY_S, false) or _held_keys.get(KEY_DOWN, false):
				dy =  1
			elif _held_keys.get(KEY_A, false) or _held_keys.get(KEY_LEFT, false):
				dx = -1
			elif _held_keys.get(KEY_D, false) or _held_keys.get(KEY_RIGHT, false):
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
		_update_bonuses(now_ms)

		var level_bonus: int = (_level - 1) * 3  # +3 скорости за каждый уровень
		var shielded: bool = now_ms < _shield_until
		var frozen: bool = now_ms < _freeze_until

		if _llama:
			if not frozen:
				var caught := _llama.update(_ham.x, _ham.y, _ham.burrowed, _llama_bonus + level_bonus)
				if caught and not shielded:
					_state = "lost"
					_game_time_ms = Time.get_ticks_msec() - _game_start_ms
					_total_time_ms += _game_time_ms
					_win_anim_t = 0
					_play(_snd_catch)

		var llama2_delay: int = max(10000, C.LLAMA2_SPAWN_MS - (_level - 1) * 10000)
		if _llama2 == null and _game_time_ms >= llama2_delay:
			var s2 := _random_far_cell(_ham.x, _ham.y, 8)
			_llama2 = LlamaAI.new()
			_llama2.init(s2.x, s2.y, _maze)

		if _llama2:
			if not frozen:
				var caught2 := _llama2.update(_ham.x, _ham.y, _ham.burrowed, _llama_bonus + level_bonus)
				if caught2 and not shielded:
					_state = "lost"
					_game_time_ms = Time.get_ticks_msec() - _game_start_ms
					_total_time_ms += _game_time_ms
					_win_anim_t = 0
					_play(_snd_catch)

	queue_redraw()


# ── Nuts update ───────────────────────────────────────────────────────
func _update_nuts(now_ms: int) -> void:
	for n in _nuts:
		if not n.got and n.visible and n.x == _ham.x and n.y == _ham.y:
			n.got = true
			_play(_snd_eat)
			_spawn_particles(n.x * C.CELL + C.CELL * 0.5, n.y * C.CELL + C.CELL * 0.5)

	var vis_left: int = 0
	var hid_left: int = 0
	for n in _nuts:
		if not n.got:
			if n.visible:
				vis_left += 1
			else:
				hid_left += 1

	if vis_left == 0 and hid_left == 0:
		_game_time_ms = Time.get_ticks_msec() - _game_start_ms
		_total_time_ms += _game_time_ms
		_state = "level_up"
		_level_trans_t = 0
		_play(_snd_win)
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


func _init_bonuses(llama_start: Vector2i) -> void:
	_bonuses = []
	var types: Array = ["shield", "speed", "freeze"]
	var count: int = 2 + min(_level, 3)  # 3 на ур.1, 4 на ур.2, max 5
	var candidates: Array = []
	for r in range(1, C.ROWS - 1):
		for col in range(1, C.COLS - 1):
			if _maze[r][col] == 0 \
					and not (col == 1 and r == 1) \
					and not (col == llama_start.x and r == llama_start.y):
				# Не ставим на орехи
				var on_nut := false
				for n in _nuts:
					if n.x == col and n.y == r:
						on_nut = true
						break
				if not on_nut:
					candidates.append(Vector2i(col, r))
	candidates.shuffle()
	for i in range(min(count, candidates.size())):
		var pos: Vector2i = candidates[i]
		_bonuses.append({x = pos.x, y = pos.y, type = types[i % types.size()], got = false})


func _spawn_particles(px: float, py: float) -> void:
	for i in range(7):
		var angle: float = randf() * TAU
		var spd: float = 1.5 + randf() * 2.5
		var colors: Array = [Color("#ffd700"), Color("#ffaa00"), Color("#ffe066"), Color("#ff8800")]
		_particles.append({
			x = px, y = py,
			vx = cos(angle) * spd, vy = sin(angle) * spd - 1.0,
			life = 20 + randi() % 10, max_life = 30,
			color = colors[i % colors.size()]
		})


func _update_bonuses(now_ms: int) -> void:
	for b in _bonuses:
		if not b.got and b.x == _ham.x and b.y == _ham.y:
			b.got = true
			_spawn_particles(b.x * C.CELL + C.CELL * 0.5, b.y * C.CELL + C.CELL * 0.5)
			match b.type:
				"shield":
					_shield_until = now_ms + 5000
				"speed":
					_speed_until = now_ms + 4000
				"freeze":
					_freeze_until = now_ms + 4000


func _update_particles() -> void:
	for i in range(_particles.size() - 1, -1, -1):
		var p: Dictionary = _particles[i]
		p.x += p.vx
		p.y += p.vy
		p.vy += 0.12  # gravity
		p.life -= 1
		if p.life <= 0:
			_particles.remove_at(i)


func _draw_bonus(bx: int, by: int, btype: String) -> void:
	var cx: float = bx * C.CELL + C.CELL * 0.5
	var cy: float = by * C.CELL + C.CELL * 0.5
	var bob: float = sin(float(_frame) * 0.1 + float(bx * 7 + by * 13)) * 2.0
	cy += bob
	# Glow
	var glow_a: float = 0.15 + 0.10 * sin(float(_frame) * 0.08)
	match btype:
		"shield":
			_ell(Vector2(cx, cy), 12, 12, Color(0.2, 0.5, 1.0, glow_a))
			_ell(Vector2(cx, cy), 7, 8, Color(0.3, 0.6, 1.0, 0.9))
			_ell(Vector2(cx, cy - 1), 5, 6, Color(0.5, 0.8, 1.0, 0.7))
			draw_circle(Vector2(cx, cy + 1), 2.0, Color(1.0, 1.0, 1.0, 0.5))
		"speed":
			_ell(Vector2(cx, cy), 12, 12, Color(1.0, 0.8, 0.0, glow_a))
			_ell(Vector2(cx, cy), 7, 7, Color(1.0, 0.7, 0.0, 0.9))
			# Молния
			var pts := PackedVector2Array([
				Vector2(cx - 2, cy - 7), Vector2(cx + 2, cy - 2),
				Vector2(cx - 1, cy - 2), Vector2(cx + 3, cy + 7),
				Vector2(cx, cy + 1), Vector2(cx - 3, cy + 1),
			])
			draw_colored_polygon(pts, Color(1.0, 1.0, 0.3, 0.95))
		"freeze":
			_ell(Vector2(cx, cy), 14, 14, Color(0.3, 0.9, 1.0, glow_a + 0.10))
			_ell(Vector2(cx, cy), 9, 9, Color(0.3, 0.85, 1.0, 0.9))
			_ell(Vector2(cx, cy), 5, 5, Color(0.7, 1.0, 1.0, 0.8))
			# Снежинка — 3 линии крестом, вращающаяся
			var lc := Color(1.0, 1.0, 1.0, 0.9)
			var rot_off: float = float(_frame) * 0.03
			for i in range(3):
				var ang: float = float(i) / 3.0 * PI + rot_off
				var ddx: float = cos(ang) * 7.0
				var ddy: float = sin(ang) * 7.0
				draw_line(Vector2(cx - ddx, cy - ddy), Vector2(cx + ddx, cy + ddy), lc, 2.0)


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
	if _state == "menu":
		_draw_menu()
		return

	if _state == "credits":
		_draw_credits()
		return

	if _state == "splash":
		_draw_splash()
		return

	draw_rect(Rect2(0, 0, C.W, C.H + C.HUD + C.CTRL_H), Color("#0d0d1a"))
	_draw_maze()

	for n in _nuts:
		if n.visible and not n.got:
			_draw_nut(n.x, n.y)

	for b in _bonuses:
		if not b.got:
			_draw_bonus(b.x, b.y, b.type)

	var now_ms: int = Time.get_ticks_msec()
	var pairs: Array = _rh.get_pairs()
	for i in range(pairs.size()):
		var pair: Dictionary = pairs[i]
		for h in pair.holes:
			_draw_rabbit_hole(h.x, h.y, i)
		if pair.holes.is_empty() and not pair.next_pos.is_empty():
			for h in pair.next_pos:
				_draw_rabbit(h.x, h.y, pair.open_at, now_ms)

	var hcx: float = _ham.x * C.CELL + C.CELL * 0.5
	var hcy: float = _ham.y * C.CELL + C.CELL * 0.5
	var now_eff: int = Time.get_ticks_msec()
	# Shield aura (behind hamster)
	if now_eff < _shield_until:
		var sa: float = 0.2 + 0.15 * sin(float(_frame) * 0.15)
		_ell(Vector2(hcx, hcy), 18, 16, Color(0.2, 0.5, 1.0, sa))
		_ell(Vector2(hcx, hcy), 14, 12, Color(0.3, 0.6, 1.0, sa * 0.7))
	# Speed trail (behind hamster)
	if now_eff < _speed_until:
		var sa2: float = 0.3 + 0.2 * sin(float(_frame) * 0.2)
		_ell(Vector2(hcx, hcy), 16, 14, Color(1.0, 0.8, 0.0, sa2 * 0.4))
	_draw_hamster(hcx, hcy, _ham.burrowed)
	# Shield ring (on top of hamster)
	if now_eff < _shield_until:
		var ring_a: float = 0.5 + 0.3 * sin(float(_frame) * 0.12)
		draw_arc(Vector2(hcx, hcy), 15.0, 0, TAU, 24, Color(0.3, 0.6, 1.0, ring_a), 1.5)
	if _llama:
		var lcx: float = _llama.x * C.CELL + C.CELL * 0.5
		var lcy: float = _llama.y * C.CELL + C.CELL * 0.5
		_draw_llama(lcx, lcy, _llama.state, false)
		if now_eff < _freeze_until:
			var fa: float = 0.4 + 0.2 * sin(float(_frame) * 0.15)
			_ell(Vector2(lcx, lcy), 16, 14, Color(0.2, 0.7, 1.0, fa))
			draw_arc(Vector2(lcx, lcy), 14.0, 0, TAU, 16, Color(0.5, 0.95, 1.0, fa + 0.1), 1.5)
	if _llama2:
		var lcx2: float = _llama2.x * C.CELL + C.CELL * 0.5
		var lcy2: float = _llama2.y * C.CELL + C.CELL * 0.5
		_draw_llama(lcx2, lcy2, _llama2.state, true)
		if now_eff < _freeze_until:
			var fa2: float = 0.4 + 0.2 * sin(float(_frame) * 0.15)
			_ell(Vector2(lcx2, lcy2), 16, 14, Color(0.2, 0.7, 1.0, fa2))
			draw_arc(Vector2(lcx2, lcy2), 14.0, 0, TAU, 16, Color(0.5, 0.95, 1.0, fa2 + 0.1), 1.5)

	# Частицы (перед туманом, чтобы fog тоже их скрывал на расстоянии)
	for p in _particles:
		var a: float = float(p.life) / float(p.max_life)
		var c: Color = p.color
		c.a = a
		draw_circle(Vector2(p.x, p.y), 3.0 * a + 1.0, c)

	if _state == "play":
		_draw_fog()

	_draw_hud()

	if _state == "level_up":
		_draw_level_up()
	elif _state == "lost":
		_draw_lost_overlay()
	elif _state == "won" or _state == "won_name":
		_draw_win_overlay()



# ── Main menu ─────────────────────────────────────────────────────────
func _draw_menu() -> void:
	var font := ThemeDB.fallback_font
	var cx: float = C.W * 0.5
	var total_h: float = C.H + C.HUD + C.CTRL_H

	draw_rect(Rect2(0, 0, C.W, total_h), Color("#050510"))
	for i in range(10):
		var r: float = (10 - i) * 52.0
		var a: float = 0.032 * (i / 10.0)
		_ell(Vector2(cx, 300.0), r, r * 0.55, Color(0.15, 0.25, 0.85, a))

	# Мерцающие звёзды
	for i in 28:
		var sx: float = float((i * 137 + 43) % C.W)
		var sy: float = float((i * 89  + 31) % (C.H + C.HUD))
		var speed: float = 0.028 + float(i % 7) * 0.006
		var phase: float = float(i) * 0.71
		var bright: float = 0.4 + 0.6 * (0.5 + 0.5 * sin(float(_frame) * speed + phase))
		var sr: float = 1.0 + float(i % 3) * 0.65
		draw_circle(Vector2(sx, sy), sr, Color(0.85, 0.90, 1.0, bright))
		if i % 5 == 0:
			var cl: float = bright * 0.5
			draw_line(Vector2(sx - sr * 2.5, sy), Vector2(sx + sr * 2.5, sy), Color(0.9, 0.95, 1.0, cl), 1.0)
			draw_line(Vector2(sx, sy - sr * 2.5), Vector2(sx, sy + sr * 2.5), Color(0.9, 0.95, 1.0, cl), 1.0)

	# HAMSTER MAZE title — пульсирующий (bob + scale)
	var title_bob: float = sin(float(_frame) * 0.045) * 5.0
	var title_sc: float  = 1.0 + sin(float(_frame) * 0.045) * 0.05
	var y_offs: Array = [0.0, -8.0, 5.0, -9.0, 7.0, -4.0, 9.0, -6.0, 4.0, -7.0, 5.0, -5.0]
	_draw_rocky_word("HAMSTER", 0.0, float(C.W), 155.0 + title_bob, int(105.0 * title_sc), y_offs)
	_draw_rocky_word("MAZE",    0.0, float(C.W), 265.0 + title_bob, int(115.0 * title_sc), y_offs)

	draw_string(font, Vector2(cx - 90, 300.0), "Собери все орехи!",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.55, 0.75, 1.0, 0.55))

	# ── Buttons ────────────────────────────────────────────────────────
	var bw: float = 290.0
	var bh: float = 54.0
	var bx: float = cx - bw * 0.5
	var pulse: float = 1.0 + 0.03 * sin(_frame * 0.05)

	# Helper: draw selection cursor (triangle) to the left of selected button
	var sel_ys: Array = [348.0, 427.0, 506.0]
	var sel_y: float = sel_ys[_menu_selected] + bh * 0.5
	var sel_x: float = bx - 28.0
	var tri: PackedVector2Array = PackedVector2Array([
		Vector2(sel_x, sel_y - 10),
		Vector2(sel_x + 16, sel_y),
		Vector2(sel_x, sel_y + 10),
	])
	draw_colored_polygon(tri, Color("#ffd700"))

	# PLAY
	var py: float = 348.0
	var pw: float = bw * (pulse if _menu_selected == 0 else 1.0)
	_menu_btn_rects["play"] = Rect2(bx, py, bw, bh)
	var play_sel: bool = _menu_selected == 0
	draw_rect(Rect2(cx - pw * 0.5, py, pw, bh), Color("#0d2040") if not play_sel else Color("#1a3860"))
	draw_rect(Rect2(cx - pw * 0.5, py, pw, bh),
		Color("#ffd700", 1.0) if play_sel else Color("#ffd700", 0.6), false, 2.5 if play_sel else 1.5)
	draw_string(font, Vector2(cx - 68, py + 36), "▶   ИГРАТЬ",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("#ffd700") if play_sel else Color("#ffd700", 0.75))

	# MUSIC
	var my: float = 427.0
	_menu_btn_rects["music"] = Rect2(bx, my, bw, bh)
	var music_sel: bool = _menu_selected == 1
	var mbg: Color = Color("#0a1e3a") if _music_on else Color("#1a0808")
	if music_sel:
		mbg = mbg.lightened(0.12)
	var mbr: Color = Color(0.35, 0.7, 1.0, 1.0 if music_sel else 0.7) if _music_on \
		else Color(0.5, 0.2, 0.2, 1.0 if music_sel else 0.65)
	draw_rect(Rect2(bx, my, bw, bh), mbg)
	draw_rect(Rect2(bx, my, bw, bh), mbr, false, 2.5 if music_sel else 1.5)
	var mlabel: String = "♪   МУЗЫКА   ON" if _music_on else "♪   МУЗЫКА   OFF"
	var mcol: Color = Color(0.4, 0.8, 1.0) if _music_on else Color(0.65, 0.3, 0.3)
	draw_string(font, Vector2(cx - 90, my + 36), mlabel,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 23, mcol)

	# CREDITS
	var cy2: float = 506.0
	_menu_btn_rects["credits"] = Rect2(bx, cy2, bw, bh)
	var cred_sel: bool = _menu_selected == 2
	draw_rect(Rect2(bx, cy2, bw, bh), Color(0.05, 0.07, 0.16) if not cred_sel else Color(0.1, 0.12, 0.28))
	draw_rect(Rect2(bx, cy2, bw, bh),
		Color(0.65, 0.7, 1.0, 1.0) if cred_sel else Color(0.45, 0.5, 0.72, 0.5), false, 2.5 if cred_sel else 1.5)
	draw_string(font, Vector2(cx - 55, cy2 + 36), "CREDITS",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
		Color(0.8, 0.85, 1.0) if cred_sel else Color(0.62, 0.68, 0.88, 0.85))

	# Online leaderboard (compact, bottom of game area)
	if not _online_scores.is_empty():
		var lby: float = 590.0
		draw_string(font, Vector2(cx - 80, lby), "Онлайн рекорды",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#ffd700", 0.7))
		draw_rect(Rect2(cx - 130, lby + 4, 260, 1), Color("#1a3060"))
		lby += 20
		for i in range(min(_online_scores.size(), 5)):
			var sc: Dictionary = _online_scores[i]
			var rc: Color = Color("#ffd700") if i == 0 else Color(0.7, 0.85, 1.0, 0.75)
			draw_string(font, Vector2(cx - 130, lby), "%d. %s" % [i + 1, sc.name],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, rc)
			draw_string(font, Vector2(cx + 60, lby), _fmt_time(sc.time_ms),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, rc)
			lby += 20
	elif _fetching:
		draw_string(font, Vector2(cx - 40, 600), "Загрузка...",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.25))

	# Анимация меню — рисуется ПОВЕРХ кнопок
	_draw_menu_anim()


# ── Menu animation: dust spawner ──────────────────────────────────────
func _menu_add_dust() -> void:
	if _frame % 3 != 0:
		return
	var t := _menu_anim_t
	if t >= 95 and t < 140:
		# Хомяк убегает вправо (sc=2.2, cy=455, ноги на 455+26=481)
		var hx: float = 450.0 + float(t - 95) * 9.5
		_menu_dust.append({x=hx - 28.0, y=480.0, r=6.0 + randf() * 3.0, life=16, max_life=16})
	elif t >= 242 and t < 286:
		# Лама убегает влево (sc=2.0, cy=459, ноги на 459+32=491)
		var lx: float = 450.0 - float(t - 242) * 10.5
		_menu_dust.append({x=lx + 28.0, y=488.0, r=6.0 + randf() * 3.0, life=16, max_life=16})
	elif t >= MENU_INTRO_DUR:
		var lt: int = t - MENU_INTRO_DUR
		var p1: int = 340
		var p2: int = 260
		var cycle: int = p1 + p2
		var phase: int = lt % cycle
		if phase < p1:
			# Большая дорожка (sc=2.2, cy=455, ноги на ~481)
			if phase > 0 and phase < p1 - 5:
				var hx1: float = -80.0 + float(phase) / float(p1) * float(C.W + 160)
				_menu_dust.append({x=hx1 - 30.0, y=480.0, r=7.0 + randf() * 3.0, life=18, max_life=18})
		else:
			# Малая дорожка (sc=1.2, cy=425, ноги на ~439)
			var t2: int = phase - p1
			if t2 > 0 and t2 < p2 - 5:
				var hx2: float = float(C.W) + 80.0 - float(t2) / float(p2) * float(C.W + 160.0)
				_menu_dust.append({x=hx2 + 20.0, y=437.0, r=4.0 + randf() * 2.0, life=12, max_life=12})


# ── Menu animation: main dispatcher ───────────────────────────────────
func _draw_menu_anim() -> void:
	# Пыль (рисуется первой — позади персонажей)
	for d in _menu_dust:
		var a: float = float(d.life) / float(d.max_life) * 0.40
		draw_circle(Vector2(d.x, d.y), d.r, Color(0.72, 0.68, 0.52, a))
		draw_circle(Vector2(d.x, d.y), d.r * 0.55, Color(0.82, 0.78, 0.62, a * 0.6))

	var t := _menu_anim_t
	if t < MENU_INTRO_DUR:
		_draw_menu_intro_anim(t)
	else:
		_draw_menu_chase(t - MENU_INTRO_DUR)


# ── Menu animation: intro (однократная, ~285 кадров) ──────────────────
func _draw_menu_intro_anim(t: int) -> void:
	var cx: float = 450.0
	var cy: float = 455.0   # центр хомяка — гарантированно в видимой зоне
	var font := ThemeDB.fallback_font
	const HSC: float = 2.2  # масштаб хомяка в интро
	const LSC: float = 2.0  # масштаб ламы в интро

	# ── Хомяк (t = 0..139) ──────────────────────────────────────────
	if t < 140:
		var hx: float = cx
		var hy: float = cy
		var sc: float = HSC
		var flip: float = 1.0  # 1 = лицом влево (default), -1 = лицом вправо

		if t < 22:
			# Появление: выезжает снизу
			hy = cy + 50.0 * (1.0 - float(t) / 22.0)
		elif t < 45:
			# Смотрит влево (по умолчанию)
			hy = cy + sin(float(t) * 0.35) * 5.0
		elif t < 68:
			# Смотрит вправо
			flip = -1.0
			hy = cy + sin(float(t) * 0.35) * 5.0
		elif t < 80:
			# Заметил что-то — быстрый bob, смотрит вправо
			flip = -1.0
			hy = cy + sin(float(t) * 0.9) * 8.0
		elif t < 95:
			# Прыжок от испуга
			var jt: float = float(t - 80) / 15.0
			hy = cy - sin(jt * PI) * 70.0
			sc = HSC * (1.0 + sin(jt * PI) * 0.14)
			flip = -1.0
		else:
			# Убегает вправо
			var rt: float = float(t - 95)
			hx = cx + rt * 9.5
			flip = -1.0
			hy = cy + sin(rt * 0.75) * 10.0
			sc = HSC * (0.95 + sin(rt * 0.75 + 0.5) * 0.08)

		if hx > -120.0 and hx < C.W + 120.0:
			draw_set_transform(Vector2(hx, hy), 0.0, Vector2(flip * sc, sc))
			_draw_hamster(0, 0, false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# "!" при испуге
		if t >= 80 and t < 95:
			var excl_a: float = 1.0 - float(t - 80) / 15.0
			draw_string(font, Vector2(hx + 40, hy - 95), "!",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(1.0, 0.95, 0.2, excl_a))

	# ── Лама (t = 162..284) ─────────────────────────────────────────
	if t >= 162:
		var lt: float = float(t - 162)
		var lx: float = cx
		var ly: float = cy + 4.0
		var lsc: float = LSC
		var lflip: float = 1.0  # лицом влево (идёт влево)
		var is_red: bool = false

		if t < 208:
			# Входит справа
			var frac: float = lt / 46.0
			lx = C.W + 65.0 - frac * (C.W + 65.0 - cx)
			lflip = 1.0
			ly = cy + 4.0 + sin(lt * 0.5) * 7.0
		elif t < 224:
			# Осматривается
			var at: float = float(t - 208)
			lflip = 1.0 if at < 8.0 else -1.0
			ly = cy + 4.0 + sin(at * 0.45) * 5.0
		elif t < 242:
			# Прыжок + краснеет
			var jt2: float = float(t - 224) / 18.0
			ly = cy + 4.0 - sin(jt2 * PI) * 60.0
			lsc = LSC * (1.0 + sin(jt2 * PI) * 0.13)
			is_red = t >= 232
			lflip = -1.0  # смотрит вправо (куда убежал хомяк)
		else:
			# Мчится влево в погоню
			var rt2: float = float(t - 242)
			lx = cx - rt2 * 10.5
			lflip = 1.0
			ly = cy + 4.0 + sin(rt2 * 0.7) * 9.0
			is_red = true

		if lx > -120.0 and lx < C.W + 120.0:
			draw_set_transform(Vector2(lx, ly), 0.0, Vector2(lflip * lsc, lsc))
			_draw_llama(0, 0, "patrol", is_red)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# "!!" когда лама видит следы хомяка
		if t >= 224 and t < 242:
			var excl_a2: float = 1.0 - float(t - 224) / 18.0
			draw_string(font, Vector2(lx + 45, ly - 110), "!!",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1.0, 0.3, 0.3, excl_a2))


# ── Menu animation: looping chase ─────────────────────────────────────
func _draw_menu_chase(lt: int) -> void:
	# Чередование: сначала большая пара, потом маленькая
	var p1: int = 340  # кадров — большая дорожка
	var p2: int = 260  # кадров — малая дорожка
	var cycle: int = p1 + p2
	var phase: int = lt % cycle

	if phase < p1:
		# Большая дорожка: лево→право, красная лама, sc=2.2
		var hx1: float = -80.0 + float(phase) / float(p1) * float(C.W + 160.0)
		var cy1: float = 455.0
		var sc1: float = 2.2
		var bob1: float = sin(float(lt) * 0.22) * 8.0
		# Лама сзади (gap = ширина хомяка при sc=2.2: 40*2.2=88px)
		draw_set_transform(Vector2(hx1 - 88.0, cy1 - 5.0 + bob1), 0.0, Vector2(-sc1, sc1))
		_draw_llama(0, 0, "chase", true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_set_transform(Vector2(hx1, cy1 + bob1), 0.0, Vector2(-sc1, sc1))
		_draw_hamster(0, 0, false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		# Малая дорожка: право→лево, синяя лама, sc=1.2
		var t2: int = phase - p1
		var hx2: float = float(C.W) + 80.0 - float(t2) / float(p2) * float(C.W + 160.0)
		var cy2: float = 425.0
		var sc2: float = 1.2
		var bob2: float = sin(float(lt) * 0.18) * 4.0
		# Лама сзади (gap = ширина хомяка при sc=1.2: 40*1.2=48px)
		draw_set_transform(Vector2(hx2 + 48.0, cy2 + bob2), 0.0, Vector2(sc2, sc2))
		_draw_llama(0, 0, "chase", false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_set_transform(Vector2(hx2, cy2 + bob2), 0.0, Vector2(sc2, sc2))
		_draw_hamster(0, 0, false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ── Credits screen ─────────────────────────────────────────────────────
func _draw_credits() -> void:
	var font := ThemeDB.fallback_font
	var cx: float = C.W * 0.5
	draw_rect(Rect2(0, 0, C.W, C.H + C.HUD + C.CTRL_H), Color("#050510"))

	# Ambient red glow behind heart
	for i in range(7):
		var r: float = 55.0 + i * 30.0
		var a: float = 0.07 * (1.0 - i / 7.0) * (0.65 + 0.35 * sin(_frame * 0.07))
		_ell(Vector2(cx, 270.0), r, r * 0.8, Color(1.0, 0.08, 0.2, a))

	# Big pulsing heart — scale 120..160px
	var hp: float = 0.82 + 0.18 * sin(_frame * 0.07)
	var hs: int = int(150.0 * hp)
	var hw: float = font.get_string_size("♥", HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
	# Dark shadow
	draw_string(font, Vector2(cx - hw * 0.5 + 5, 315.0 + 6), "♥",
		HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(0.3, 0.0, 0.05, 0.6))
	# Red heart
	draw_string(font, Vector2(cx - hw * 0.5, 315.0), "♥",
		HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(1.0, 0.06, 0.18, 1.0))

	# Dedication text — centred
	var name_sz: int = 30
	var name_str: String = "Andrew & Lucy"
	var name_w: float = font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, name_sz).x
	draw_string(font, Vector2(cx - name_w * 0.5, 395.0), name_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, name_sz, Color(1.0, 0.86, 0.91, 0.97))

	var mem_sz: int = 21
	var mem_str: String = "in memory of Beloved Moty..."
	var mem_w: float = font.get_string_size(mem_str, HORIZONTAL_ALIGNMENT_LEFT, -1, mem_sz).x
	draw_string(font, Vector2(cx - mem_w * 0.5, 432.0), mem_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, mem_sz, Color(0.88, 0.72, 0.78, 0.85))

	# Back button
	var br := Rect2(cx - 130, 610, 260, 46)
	_menu_btn_rects["back"] = br
	draw_rect(br, Color("#0d1e38"))
	draw_rect(br, Color(0.45, 0.5, 0.8, 0.65), false, 2.0)
	draw_string(font, Vector2(cx - 70, 642), "←  НАЗАД",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.65, 0.72, 1.0))
	draw_string(font, Vector2(cx - 110, 672), "Любая клавиша — назад",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.2))


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

	# Level
	var lvl_str: String = "Ур. %d" % _level
	draw_string(font, Vector2(C.W - 75, Y + 20), lvl_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#ffd700"))

	# Active bonus indicators
	var bx_pos: float = C.W - 75
	var now_hud: int = Time.get_ticks_msec()
	if now_hud < _shield_until:
		var secs: float = float(_shield_until - now_hud) / 1000.0
		draw_string(font, Vector2(bx_pos, Y + 40), "🛡️%.1f" % secs,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.7, 1.0))
	if now_hud < _speed_until:
		var secs2: float = float(_speed_until - now_hud) / 1000.0
		draw_string(font, Vector2(bx_pos - 55, Y + 40), "⚡%.1f" % secs2,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.8, 0.0))
	if now_hud < _freeze_until:
		var secs3: float = float(_freeze_until - now_hud) / 1000.0
		draw_string(font, Vector2(bx_pos - 110, Y + 40), "❄️%.1f" % secs3,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.9, 1.0))

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


func _draw_level_up() -> void:
	var t: int = _level_trans_t
	var font := ThemeDB.fallback_font
	var cx: float = C.W * 0.5
	var cy: float = C.H * 0.5

	# Фон затемняется
	var bg_a: float = min(float(t) / 30.0, 1.0) * 0.85
	draw_rect(Rect2(0, 0, C.W, C.H + C.HUD), Color(0, 0, 0, bg_a))

	# Следующий уровень
	var next_lvl: int = _level + 1
	var title: String = "УРОВЕНЬ %d" % next_lvl

	# Масштаб: вырастает из 0 до 1 за первые 30 кадров
	var sc: float = min(float(t) / 30.0, 1.0)
	# Пульсация
	if t > 30:
		sc += sin(float(t - 30) * 0.08) * 0.08

	var sz: int = int(52.0 * sc)
	if sz < 4:
		sz = 4
	var tw: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(font, Vector2(cx - tw * 0.5, cy - 10), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color("#ffd700"))

	# Время за уровень
	if t > 20:
		var time_a: float = min(float(t - 20) / 20.0, 1.0)
		var time_str: String = "Время: %s" % _fmt_time(_game_time_ms)
		var tsz: int = 18
		var ttw: float = font.get_string_size(time_str, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x
		draw_string(font, Vector2(cx - ttw * 0.5, cy + 35), time_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, tsz, Color(0.7, 0.85, 1.0, time_a))

	# Хомяк танцует (маленький bounce)
	if t > 15:
		var bounce: float = abs(sin(float(t) * 0.15)) * 15.0
		var hsc: float = 3.5 * sc
		draw_set_transform(Vector2(cx, cy + 75 - bounce), 0.0, Vector2(hsc, hsc))
		_draw_hamster(0, 0, false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 8 звёздочек по кругу
	if t > 40:
		for i in range(8):
			var angle: float = float(i) / 8.0 * TAU + float(t) * 0.04
			var r: float = 120.0 + sin(float(t) * 0.1 + float(i)) * 20.0
			var sx: float = cx + cos(angle) * r
			var sy: float = cy + sin(angle) * r
			var star_a: float = min(float(t - 40) / 20.0, 1.0) * (0.5 + 0.5 * sin(float(t) * 0.15 + float(i) * 0.8))
			draw_circle(Vector2(sx, sy), 4.0, Color(1.0, 0.85, 0.2, star_a))


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
	draw_string(font, Vector2(cx - 100, cy + 65),
		"Уровень: %d   Орехи: %d / %d" % [_level, collected, _nuts.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#c8b060", 0.85))
	draw_string(font, Vector2(cx - 80, cy + 88),
		"Общее время: %s" % _fmt_time(_total_time_ms),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.85, 1.0, 0.85))
	draw_string(font, Vector2(cx - 130, cy + 112), "Enter — сохранить результат", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1,1,1,0.45))


func _draw_win_anim() -> void:
	var t: int = _win_anim_t
	var cx: float = C.W * 0.5
	var cy: float = C.H * 0.5 - 10.0
	var font := ThemeDB.fallback_font

	# Фон затемняется в первые 40 кадров
	draw_rect(Rect2(0, 0, C.W, C.H + C.HUD), Color(0, 0, 0, min(float(t) / 40.0, 1.0) * 0.82))

	# Базовый масштаб: хомяк вырастает до размера 5x за 25 кадров
	var base_sc: float = min(float(t) / 25.0, 1.0) * 5.0

	var sc_x: float = base_sc
	var sc_y: float = base_sc
	var rot: float  = 0.0
	var ox:  float  = 0.0
	var oy:  float  = 0.0

	if t < 60:
		# Фаза 1: Прыжки (3 раза) — squish при приземлении
		var bounce: float = abs(sin(float(t) / 60.0 * PI * 3.0))
		oy = -bounce * 30.0
		var sq: float = lerp(1.0, 0.78, 1.0 - bounce)
		sc_x = base_sc / sq
		sc_y = base_sc * sq
	elif t < 120:
		# Фаза 2: Раскачка влево-вправо (2 волны)
		var st: float = float(t - 60) / 60.0
		rot = sin(st * TAU * 2.0) * 0.35
		ox  = sin(st * TAU * 2.0) * 20.0
		oy  = -abs(sin(st * TAU * 2.0)) * 8.0
	elif t < 165:
		# Фаза 3: Один полный оборот + масштаб пульсирует
		var sp: float = float(t - 120) / 45.0
		rot  = sp * TAU
		sc_x = base_sc * (1.0 + sin(sp * TAU) * 0.15)
		sc_y = base_sc * (1.0 - sin(sp * TAU) * 0.15)
	else:
		# Фаза 4: Финал — лёгкое покачивание
		var fp: float = float(t - 165)
		rot = sin(fp * 0.10) * 0.15
		oy  = -abs(sin(fp * 0.13)) * 8.0

	# Рисуем хомяка
	draw_set_transform(Vector2(cx + ox, cy + oy), rot, Vector2(sc_x, sc_y))
	_draw_hamster(0.0, 0.0, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Искры вращаются вокруг хомяка (начиная с фазы 3)
	if t >= 110:
		var sp_p: float = min(float(t - 110) / 25.0, 1.0)
		var sr: float = base_sc * 25.0 + 18.0
		for i in 8:
			var angle: float = float(i) / 8.0 * TAU + float(t) * 0.045
			var sx: float = cx + cos(angle) * sr
			var sy: float = cy + sin(angle) * sr * 0.55
			var flicker: float = 0.5 + 0.5 * sin(float(t) * 0.28 + float(i) * 1.1)
			draw_circle(Vector2(sx, sy), 5.0 * sp_p, Color(1.0, 0.9, 0.1, sp_p * flicker))
			draw_circle(Vector2(sx, sy), 2.5 * sp_p, Color(1.0, 1.0, 1.0, sp_p * flicker))

	# Плавающие нотки ♪ (фаза 2+)
	if t >= 60:
		for i in 3:
			var nt: float = float(t - 60 + i * 55)
			var note_cycle: float = fmod(nt, 75.0) / 75.0
			if note_cycle > 0.88:
				continue
			var nx: float = cx + (i - 1) * 55.0 + sin(nt * 0.07) * 12.0
			var ny: float = cy - base_sc * 20.0 - note_cycle * 65.0
			var nalpha: float = (1.0 - note_cycle) * min(float(t - 60) / 20.0, 1.0)
			draw_string(font, Vector2(nx, ny), "♪", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.85, 0.3, nalpha))

	# "ПОБЕДА!" — появляется в фазе 2
	if t >= 70:
		var tp: float  = min(float(t - 70) / 35.0, 1.0)
		var text: String = "ПОБЕДА!"
		var fs: int = 48
		if t >= 165:
			fs = int(48.0 * (1.0 + 0.04 * sin(float(t - 165) * 0.12)))
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(cx - tw * 0.5, cy - base_sc * 28.0 - 25.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.84, 0.0, tp))


func _draw_win_overlay() -> void:
	draw_rect(Rect2(0, 0, C.W, C.H + C.HUD + C.CTRL_H), Color(0, 0, 0, 0.82))
	var font := ThemeDB.fallback_font
	var cx: float = C.W * 0.5
	var cy: float = C.H * 0.5

	if _state == "won_name":
		if _win_anim_t < WIN_SPIN_DUR:
			_draw_win_anim()
			return
		# Waiting for player to type name
		draw_rect(Rect2(cx - 240, cy - 130, 480, 240), Color("#0d2a0d"))
		draw_rect(Rect2(cx - 240, cy - 130, 480, 240), Color("#ffd700"), false, 2.0)
		draw_string(font, Vector2(cx - 80, cy - 90), "РЕЗУЛЬТАТ", HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color("#ffd700"))
		draw_string(font, Vector2(cx - 120, cy - 45),
			"Уровень: %d   Время: %s" % [_level, _fmt_time(_total_time_ms)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#c8e878"))
		draw_string(font, Vector2(cx - 75, cy - 20), "Введи имя:",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.85, 1.0, 0.85))
		# Name input area highlighted (LineEdit node renders on top)
		draw_rect(Rect2(cx - 125, cy + 17, 250, 40), Color("#1a1a3a"))
		draw_rect(Rect2(cx - 125, cy + 17, 250, 40), Color("#ffd700", 0.5), false, 1.5)
		return

	# "won" state — show result + leaderboard
	var pulse: float = 1.0 + 0.05 * sin(_win_anim_t * 0.05)
	var bw: float = 480.0 * pulse
	draw_rect(Rect2(cx - bw * 0.5, cy - 170, bw, 360), Color("#0d2a0d"))
	draw_rect(Rect2(cx - bw * 0.5, cy - 170, bw, 360), Color("#ffd700"), false, 2.5)
	draw_string(font, Vector2(cx - 80, cy - 125), "РЕЗУЛЬТАТ", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("#ffd700"))
	draw_string(font, Vector2(cx - 130, cy - 75),
		"Уровень: %d   Время: %s" % [_level, _fmt_time(_total_time_ms)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#c8e878"))

	# Leaderboard inside overlay
	draw_rect(Rect2(cx - 200, cy - 50, 400, 1), Color("#1a3060"))
	draw_string(font, Vector2(cx - 80, cy - 32), "Таблица рекордов",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#ffd700", 0.8))

	var lb_y: float = cy - 8.0
	for i in range(min(_scores.size(), 6)):
		var sc: Dictionary = _scores[i]
		var rank_c: Color = Color("#ffd700") if i == 0 else Color(0.75, 0.9, 1.0, 0.85)
		var medals := ["1.", "2.", "3.", "4.", "5.", "6."]
		draw_string(font, Vector2(cx - 190, lb_y), medals[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, rank_c)
		var lvl_str: String = "Ур.%d" % sc.get("level", 1)
		draw_string(font, Vector2(cx - 165, lb_y), "%s  %s" % [sc.name, lvl_str],
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

	# Flintstones-style title — always visible
	_draw_ctrl_title()

	if _state != "play":
		# Show "Tap to continue" only on end screens, not on menu/credits
		if _state in ["lost", "won", "splash"]:
			var tap_y := zone_y + float(C.CTRL_H) - 22.0
			draw_rect(Rect2(C.W * 0.5 - 82.0, tap_y - 19.0, 164.0, 24.0), Color(0, 0, 0, 0.55))
			draw_string(font, Vector2(C.W * 0.5 - 62.0, tap_y),
				"Tap — продолжить", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.55))
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


func _draw_ctrl_title() -> void:
	var zone_y: float = C.H + C.HUD
	# Stone font has built-in rocky shape; small y_offs for stacked-stone height variation
	var y_offs: Array = [0.0, -8.0, 5.0, -9.0, 7.0, -4.0, 9.0, -6.0, 4.0, -7.0, 5.0, -5.0]
	_draw_rocky_word("HAMSTER", 0.0, float(C.W), zone_y + 155.0, 130, y_offs)
	_draw_rocky_word("MAZE",    0.0, float(C.W), zone_y + 310.0, 145, y_offs)


func _draw_rocky_word(text: String, zone_x: float, zone_w: float, baseline_y: float, sz: int, y_offs: Array) -> void:
	var font: Font = _stone_font if _stone_font else ThemeDB.fallback_font
	var fill    := Color(1.00, 0.88, 0.10, 1.0)   # warm yellow
	var outline := Color(0.82, 0.20, 0.02, 1.0)   # red-orange contour
	var shadow  := Color(0.00, 0.00, 0.00, 0.65)  # dark drop shadow
	var glow    := Color(1.00, 0.50, 0.05, 0.40)  # orange inner glow

	var n      := text.length()
	var slot_w := zone_w / float(n)

	for i in range(n):
		var ch   := text[i]
		var dy   := y_offs[i % y_offs.size()] as float
		var ch_w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var x    := zone_x + float(i) * slot_w + (slot_w - ch_w) * 0.5
		var pos  := Vector2(x, baseline_y + dy)

		# Layer 1 — deep drop shadow
		for ox in [-5, 0, 5]:
			for oy in [-5, 0, 5]:
				if ox != 0 or oy != 0:
					draw_string(font, pos + Vector2(ox, oy + 4), ch,
						HORIZONTAL_ALIGNMENT_LEFT, -1, sz, shadow)

		# Layer 2 — thick red-orange outline (4px)
		for ox in [-4, -2, 0, 2, 4]:
			for oy in [-4, -2, 0, 2, 4]:
				if ox != 0 or oy != 0:
					draw_string(font, pos + Vector2(ox, oy), ch,
						HORIZONTAL_ALIGNMENT_LEFT, -1, sz, outline)

		# Layer 3 — orange inner glow
		for ox in [-2, 0, 2]:
			for oy in [-2, 0, 2]:
				if ox != 0 or oy != 0:
					draw_string(font, pos + Vector2(ox, oy), ch,
						HORIZONTAL_ALIGNMENT_LEFT, -1, sz, glow)

		# Layer 4 — yellow fill
		draw_string(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, fill)


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
