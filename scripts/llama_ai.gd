class_name LlamaAI
extends RefCounted

# Transliterated from hamster_maze.html updateLlama() — lines 975-1031
# States: patrol | alert | chase | search

var x: int = 1
var y: int = 1
var state: String = "patrol"
var last_known: Vector2i = Vector2i(-1, -1)
var dest: Vector2i = Vector2i(-1, -1)
var search_pts: Array = []
var search_idx: int = 0
var state_timer: int = 0
var move_timer: int = 0

var _bfs: BFSPathfinder
var _maze: Array = []


func init(start_x: int, start_y: int, maze: Array) -> void:
	x = start_x
	y = start_y
	_maze = maze
	_bfs = BFSPathfinder.new()
	state = "patrol"
	last_known = Vector2i(-1, -1)
	dest = Vector2i(-1, -1)
	search_pts = []
	search_idx = 0
	state_timer = 0
	move_timer = 0


# Called every frame from main. Returns true if llama caught hamster.
func update(ham_x: int, ham_y: int, ham_burrowed: bool, llama_bonus: int) -> bool:
	var ham_dist: int = abs(ham_x - x) + abs(ham_y - y)
	state_timer += 1
	var prev_state: String = state

	# ── State transitions ─────────────────────────────────────────────
	if not ham_burrowed:
		last_known = Vector2i(ham_x, ham_y)
		if ham_dist <= C.CHASE_R:
			if state != "chase":
				state = "chase"
				state_timer = 0
		elif ham_dist <= C.ALERT_R:
			if state == "patrol" or state == "search":
				state = "alert"
				state_timer = 0
				dest = Vector2i(ham_x, ham_y)
			elif state == "alert":
				dest = Vector2i(ham_x, ham_y)
		else:
			if state == "alert" and state_timer > 200:
				state = "patrol"
				state_timer = 0
				dest = Vector2i(-1, -1)
	else:
		if state == "chase" or state == "alert":
			state = "search"
			state_timer = 0
			search_pts = _make_search_pts(last_known.x, last_known.y)
			search_idx = 0

	if state == "search" and state_timer > 520:
		state = "patrol"
		state_timer = 0
		dest = Vector2i(-1, -1)

	# ── Movement ──────────────────────────────────────────────────────
	move_timer += 1
	if move_timer >= _lspeed(llama_bonus):
		move_timer = 0
		_do_move(ham_x, ham_y)

	# ── Catch check ───────────────────────────────────────────────────
	if not ham_burrowed and x == ham_x and y == ham_y:
		return true
	return false


func _do_move(ham_x: int, ham_y: int) -> void:
	match state:
		"patrol":
			if dest == Vector2i(-1, -1) or (x == dest.x and y == dest.y):
				dest = _random_free_cell()
			var path = _bfs.bfs(_maze, x, y, dest.x, dest.y)
			if path.size() > 0:
				x = path[0].x
				y = path[0].y
			else:
				dest = Vector2i(-1, -1)

		"alert":
			if dest != Vector2i(-1, -1):
				var path = _bfs.bfs(_maze, x, y, dest.x, dest.y)
				if path.size() > 0:
					x = path[0].x
					y = path[0].y
				else:
					dest = Vector2i(-1, -1)
				if dest != Vector2i(-1, -1) and x == dest.x and y == dest.y:
					state = "patrol"
					state_timer = 0
					dest = Vector2i(-1, -1)

		"chase":
			var path = _bfs.bfs(_maze, x, y, ham_x, ham_y)
			if path.size() > 0:
				x = path[0].x
				y = path[0].y

		"search":
			if search_idx < search_pts.size():
				var t: Vector2i = search_pts[search_idx]
				var path = _bfs.bfs(_maze, x, y, t.x, t.y)
				if path.size() > 0:
					x = path[0].x
					y = path[0].y
				if x == t.x and y == t.y:
					search_idx += 1
			else:
				state = "patrol"
				state_timer = 0
				dest = Vector2i(-1, -1)


# Speed in move_timer ticks per step (lower = faster)
func _lspeed(bonus: int) -> int:
	var base: int = C.LSPEED_BASE.get(state, 32)
	return max(6, base - bonus)


# Search points around last known hamster position
func _make_search_pts(cx: int, cy: int) -> Array:
	var offs: Array = [
		[0,0],[1,0],[-1,0],[0,1],[0,-1],
		[2,0],[-2,0],[0,2],[0,-2],
		[2,2],[-2,2],[2,-2],[-2,-2],
		[3,0],[-3,0],[0,3],[0,-3]
	]
	var pts: Array = []
	for o in offs:
		var px: int = clamp(cx + o[0], 1, C.COLS - 2)
		var py: int = clamp(cy + o[1], 1, C.ROWS - 2)
		if _maze[py][px] == 0:
			pts.append(Vector2i(px, py))
		if pts.size() >= 9:
			break
	return pts


func _random_free_cell() -> Vector2i:
	var px: int
	var py: int
	var attempts: int = 0
	while attempts < 300:
		px = 1 + randi() % (C.COLS - 2)
		py = 1 + randi() % (C.ROWS - 2)
		if _maze[py][px] == 0:
			return Vector2i(px, py)
		attempts += 1
	return Vector2i(1, 1)
