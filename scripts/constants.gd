extends Node

# Map constants (same as HTML version)
const COLS: int = 25
const ROWS: int = 19
const CELL: int = 36
const HUD: int  = 58

const W: int = COLS * CELL  # 900
const H: int = ROWS * CELL  # 684

# Llama AI constants
const CHASE_R: int = 4   # llama sees hamster within 4 cells
const ALERT_R: int = 8   # llama hears hamster within 8 cells

# Llama base speed (frames per step)
const LSPEED_BASE: Dictionary = {
	"patrol": 52,
	"alert":  36,
	"chase":  28,
	"search": 34,
}

# Rabbit holes
const RH_COOLDOWN_MS: int = 60000
const RH_DIG_MS:      int = 10000

# Nut waves
const NUT_WAVE_INTERVAL_MS: int = 25000
const NUT_FIRST_WAVE_PCT:   float = 0.35
const NUT_NEXT_WAVE_PCT:    float = 0.40
const NUT_MIN_COUNT:        int   = 20
const NUT_SPAWN_CHANCE:     float = 0.18

# Llama 2 spawn delay
const LLAMA2_SPAWN_MS: int = 60000

# Llama speed bonus (every 30 sec +1, max 8)
const LLAMA_BONUS_INTERVAL_MS: int = 30000
const LLAMA_BONUS_MAX:         int = 8
