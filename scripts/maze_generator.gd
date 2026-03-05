class_name MazeGenerator
extends RefCounted

# Transliterated from hamster_maze.html makeMaze() — lines 413-462
# Algorithm: recursive backtracking + dead end elimination

var _grid: Array = []


func make_maze() -> Array:
	# Fill grid with walls (1)
	_grid = []
	for r in range(C.ROWS):
		_grid.append([])
		for col in range(C.COLS):
			_grid[r].append(1)

	_carve(1, 1)
	_eliminate_dead_ends()
	return _grid


# dirs format: [dcol, drow]  (column delta first, row delta second)
# grid access: _grid[row][col]
func _carve(x: int, y: int) -> void:
	_grid[y][x] = 0
	var dirs: Array = [[0, -2], [2, 0], [0, 2], [-2, 0]]
	dirs.shuffle()
	for d in dirs:
		var nx: int = x + d[0]
		var ny: int = y + d[1]
		if nx > 0 and nx < C.COLS - 1 and ny > 0 and ny < C.ROWS - 1 and _grid[ny][nx] == 1:
			_grid[y + d[1] / 2][x + d[0] / 2] = 0
			_carve(nx, ny)


# D format: [drow, dcol]  (row delta first, column delta second)
# Each passage cell must have >= 2 open neighbours → no dead ends
func _eliminate_dead_ends() -> void:
	var D: Array = [[0, 1], [1, 0], [0, -1], [-1, 0]]
	var changed: bool = true
	while changed:
		changed = false
		for r in range(1, C.ROWS - 1):
			for col in range(1, C.COLS - 1):
				if _grid[r][col] == 1:
					continue
				# Count open neighbours
				var open_count: int = 0
				for d in D:
					if _grid[r + d[0]][col + d[1]] == 0:
						open_count += 1
				if open_count != 1:
					continue  # not a dead end
				# Collect wall neighbours (candidate walls to open)
				var walls: Array = []
				for d in D:
					var wr: int = r + d[0]
					var wc: int = col + d[1]
					if _grid[wr][wc] == 1 and wr > 0 and wr < C.ROWS - 1 and wc > 0 and wc < C.COLS - 1:
						walls.append(d)
				walls.shuffle()
				# Open the first wall that leads to another passage
				for d in walls:
					var wr: int = r + d[0]
					var wc: int = col + d[1]
					for d2 in D:
						var nr: int = wr + d2[0]
						var nc: int = wc + d2[1]
						if nr == r and nc == col:
							continue
						if _grid[nr][nc] == 0:
							_grid[wr][wc] = 0
							changed = true
							break
					if _grid[wr][wc] == 0:
						break
