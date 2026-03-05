class_name BFSPathfinder
extends RefCounted

# Transliterated from hamster_maze.html bfs() — lines 465-482
# Returns Array of Vector2i steps from (sx,sy) to (tx,ty), excluding start.
# Returns [] if already at target or no path found.

# dirs format: [dcol, drow]
const _DIRS: Array = [[0, 1], [1, 0], [0, -1], [-1, 0]]


func bfs(maze: Array, sx: int, sy: int, tx: int, ty: int) -> Array:
	if sx == tx and sy == ty:
		return []

	var queue: Array = [{"x": sx, "y": sy, "p": []}]
	var vis: Array = []
	vis.resize(C.ROWS * C.COLS)
	vis.fill(0)
	vis[sy * C.COLS + sx] = 1

	while queue.size() > 0:
		var cur: Dictionary = queue.pop_front()
		var x: int = cur["x"]
		var y: int = cur["y"]
		var p: Array = cur["p"]

		for d in _DIRS:
			var nx: int = x + d[0]
			var ny: int = y + d[1]

			if nx < 0 or nx >= C.COLS or ny < 0 or ny >= C.ROWS:
				continue
			if maze[ny][nx] == 1 or vis[ny * C.COLS + nx] == 1:
				continue

			var np: Array = p.duplicate()
			np.append(Vector2i(nx, ny))

			if nx == tx and ny == ty:
				return np

			vis[ny * C.COLS + nx] = 1
			queue.append({"x": nx, "y": ny, "p": np})

	return []
