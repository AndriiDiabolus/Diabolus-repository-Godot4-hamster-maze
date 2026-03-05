extends Node2D

# Stage 1 — Maze + BFS test scene
# Opens in Godot 4: shows generated maze, BFS path from hamster start to llama start

var _maze_gen: MazeGenerator
var _bfs: BFSPathfinder
var _maze: Array = []
var _path: Array = []
var _llama_start: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	_maze_gen = MazeGenerator.new()
	_bfs      = BFSPathfinder.new()

	_maze       = _maze_gen.make_maze()
	_llama_start = _find_llama_start()

	# Test BFS: path from hamster (1,1) to llama start
	_path = _bfs.bfs(_maze, 1, 1, _llama_start.x, _llama_start.y)

	queue_redraw()


func _find_llama_start() -> Vector2i:
	# Bottom-right free cell (same logic as HTML llamaStart())
	for r in range(C.ROWS - 2, 0, -1):
		for col in range(C.COLS - 2, 0, -1):
			if _maze[r][col] == 0:
				return Vector2i(col, r)
	return Vector2i(3, 3)


func _draw() -> void:
	# ── Maze ────────────────────────────────────────────────────────
	for r in range(C.ROWS):
		for col in range(C.COLS):
			var px: float = col * C.CELL
			var py: float = r * C.CELL
			if _maze[r][col] == 1:
				# Wall
				draw_rect(Rect2(px, py, C.CELL, C.CELL), Color("#1a3358"))
				draw_rect(Rect2(px, py, C.CELL, 2),      Color("#25487a"))
				draw_rect(Rect2(px, py, 2,      C.CELL), Color("#25487a"))
				draw_rect(Rect2(px + C.CELL - 2, py, 2,      C.CELL), Color("#0e1f3a"))
				draw_rect(Rect2(px, py + C.CELL - 2,    C.CELL, 2),   Color("#0e1f3a"))
			else:
				# Passage — alternating sandy tiles
				var tile_col: Color = Color("#d4a85a") if (r + col) % 2 == 0 else Color("#ca9e50")
				draw_rect(Rect2(px, py, C.CELL, C.CELL), tile_col)

	# ── BFS path highlight ───────────────────────────────────────────
	for step in _path:
		draw_rect(
			Rect2(step.x * C.CELL + 6, step.y * C.CELL + 6, C.CELL - 12, C.CELL - 12),
			Color(1.0, 1.0, 0.0, 0.35)
		)

	# ── Hamster start (1,1) — green dot ─────────────────────────────
	draw_circle(
		Vector2(1 * C.CELL + C.CELL * 0.5, 1 * C.CELL + C.CELL * 0.5),
		10.0, Color("#44ff88")
	)

	# ── Llama start — red dot ────────────────────────────────────────
	if _llama_start != Vector2i(-1, -1):
		draw_circle(
			Vector2(_llama_start.x * C.CELL + C.CELL * 0.5, _llama_start.y * C.CELL + C.CELL * 0.5),
			10.0, Color("#ff4444")
		)

	# ── HUD bar ──────────────────────────────────────────────────────
	draw_rect(Rect2(0, C.H, C.W, C.HUD), Color("#08080f"))
	draw_rect(Rect2(0, C.H, C.W, 2),     Color("#1a3060"))

	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(10, C.H + 22), "Хомяк в Лабиринте — Godot 4",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#ffd700"))
	draw_string(font, Vector2(10, C.H + 42),
		"Этап 1: Лабиринт + BFS  |  Зелёный = хомяк  |  Красный = лама  |  Жёлтый = путь BFS  |  Шагов: %d" % _path.size(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#7799cc"))
