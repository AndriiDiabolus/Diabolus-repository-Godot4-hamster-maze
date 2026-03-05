class_name RHManager
extends RefCounted

# Port of rhInit/rhUpdate/pickRHPos from hamster_maze.html lines 782-833
# Manages 2 pairs of rabbit-hole portals.

# Visual styles per pair: [ring color, glow color]
const RH_STYLES: Array = [
	[Color(0.71, 0.24, 1.0), Color(0.63, 0.16, 1.0)],   # pair 0 — purple
	[Color(0.0,  0.86, 0.55), Color(0.0, 0.78, 0.47)],   # pair 1 — emerald
]

var _pairs: Array = []   # Array of Dictionaries
var _maze: Array = []


func init(maze: Array) -> void:
	_maze = maze
	var p0 := _pick_rh_pos([Vector2i(1, 1)])
	var excl1: Array = [Vector2i(1, 1)] + p0
	var p1 := _pick_rh_pos(excl1)
	_pairs = [
		{"holes": p0, "next_pos": [], "open_at": 0, "rabbit_at": 0},
		{"holes": p1, "next_pos": [], "open_at": 0, "rabbit_at": 0},
	]


# Returns teleport destination Vector2i if hamster stepped on a hole.
# Returns Vector2i(-1,-1) otherwise.
func update(ham_x: int, ham_y: int, ham_burrowed: bool, now_ms: int) -> Vector2i:
	for pair in _pairs:
		# Re-open hole when cooldown expires
		if pair.holes.is_empty() and pair.open_at > 0 and now_ms >= pair.open_at:
			pair.holes = pair.next_pos
			pair.next_pos = []
			pair.open_at  = 0
			pair.rabbit_at = 0

		# Pick new positions when rabbit should start digging
		if pair.holes.is_empty() and pair.open_at > 0 \
				and pair.next_pos.is_empty() and now_ms >= pair.rabbit_at:
			var taken: Array = [Vector2i(1, 1)]
			for p2 in _pairs:
				for h in p2.holes:
					taken.append(h)
				for h in p2.next_pos:
					taken.append(h)
			pair.next_pos = _pick_rh_pos(taken)

		if pair.holes.is_empty() or ham_burrowed:
			continue

		# Check if hamster is on either hole
		var idx: int = -1
		for i in range(pair.holes.size()):
			var h: Vector2i = pair.holes[i]
			if h.x == ham_x and h.y == ham_y:
				idx = i
				break

		if idx == -1:
			continue

		# Teleport hamster to the other hole
		var dest: Vector2i = pair.holes[1 - idx]
		pair.holes    = []
		pair.next_pos = []
		pair.open_at   = now_ms + C.RH_COOLDOWN_MS
		pair.rabbit_at = now_ms + C.RH_COOLDOWN_MS - C.RH_DIG_MS
		return dest

	return Vector2i(-1, -1)


# Accessors for drawing
func get_pairs() -> Array:
	return _pairs


# Pick two free cells far from all exclusion cells
func _pick_rh_pos(exclude: Array) -> Array:
	var a := _find_far_cell(exclude, Vector2i(-1, -1), 0)
	var excl_b: Array = exclude + [a]
	var b := _find_far_cell(excl_b, a, 7)
	return [a, b]


func _find_far_cell(exclude: Array, other: Vector2i, min_dist_other: int) -> Vector2i:
	for _i in range(300):
		var px: int = 1 + randi() % (C.COLS - 2)
		var py: int = 1 + randi() % (C.ROWS - 2)
		if _maze[py][px] != 0:
			continue
		var p := Vector2i(px, py)
		if p == Vector2i(1, 1):
			continue
		# Must be far from all exclusions
		var ok: bool = true
		for e in exclude:
			if abs(e.x - px) + abs(e.y - py) < 5:
				ok = false
				break
		if not ok:
			continue
		# Must be far enough from the other anchor
		if other != Vector2i(-1, -1) and abs(other.x - px) + abs(other.y - py) < min_dist_other:
			continue
		return p
	return Vector2i(3, 3)
