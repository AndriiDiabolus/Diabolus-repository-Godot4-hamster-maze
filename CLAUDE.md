# CLAUDE.md — Контекст проекта "Хомяк в Лабиринте" (Godot 4)

## Репозитории
- **Текущий (Godot 4):** https://github.com/AndriiDiabolus/Diabolus-repository-Godot4-hamster-maze.git
- **Оригинал (HTML):** https://github.com/AndriiDiabolus/Diabolus-Repository.git
- **Локальный путь:** `/Users/andriidiablo/Documents/Test 3.1/`
- **Ветка:** main

## Критически важно
- `hamster_maze.html` — эталонный файл (~1895 строк), **НИКОГДА НЕ ТРОГАТЬ**
- Godot 4.6.1, GDScript, рендер Node2D + `_draw()` (без TileMap и CharacterBody2D)
- Autoload `C` = `scripts/constants.gd` (глобальный доступ из всех скриптов)
- Весь рендер — чистый `_draw()` + `_ell()` helper для эллипсов через `draw_colored_polygon`
- "Няма" = пользователь говорит "всё верно/отлично"

---

## Файлы проекта (актуально)

```
scripts/
  constants.gd       — autoload C, все константы игры
  maze_generator.gd  — class MazeGenerator, recursive backtracking + dead end removal
  bfs_pathfinder.gd  — class BFSPathfinder, BFS pathfinding → Array[Vector2i]
  llama_ai.gd        — class LlamaAI, 4 состояния (patrol/alert/chase/search)
  rh_manager.gd      — class RHManager, 2 пары кроличьих нор (порталов)
  main.gd            — extends Node2D, вся игровая логика + весь рендер
scenes/
  Main.tscn          — uid://c431j5hrtri71, Node2D + main.gd
project.godot        — config v5, Godot 4.6, autoload C, viewport 900x742
hamster_maze.html    — оригинальный HTML файл (reference only)
```

---

## Константы (C.*)
```gdscript
COLS=25, ROWS=19, CELL=36, HUD=58, W=900, H=684
CHASE_R=4, ALERT_R=8
LSPEED_BASE = {patrol:32, alert:22, chase:16, search:20}
RH_COOLDOWN_MS=60000, RH_DIG_MS=10000
NUT_WAVE_INTERVAL_MS=25000, NUT_FIRST_WAVE_PCT=0.35, NUT_NEXT_WAVE_PCT=0.40
NUT_MIN_COUNT=20, NUT_SPAWN_CHANCE=0.18
LLAMA2_SPAWN_MS=60000, LLAMA_BONUS_INTERVAL_MS=30000, LLAMA_BONUS_MAX=8
```

---

## Архитектура main.gd

### State machine
```
splash → (Enter) → play → (поймана) → lost → (Enter) → splash
						→ (все орехи) → won_name → (ввёл имя) → won → (Enter) → splash
```

### Ключевые переменные
```gdscript
_state: String          # splash | play | lost | won_name | won
_ham: Dictionary        # {x, y, burrowed, burrows}
_maze: Array            # [ROWS][COLS], 0=проход 1=стена
_llama: LlamaAI         # синяя лама
_llama2: LlamaAI        # красная лама (спавн через 60с)
_llama_bonus: int       # +1 каждые 30с, макс 8
_nuts: Array            # [{x,y,got,visible}]
_next_wave_ms: int      # когда следующая волна орехов
_rh: RHManager          # 2 пары порталов
_scores: Array          # [{name,time_ms}], топ-10, сессионные
_name_layer: CanvasLayer
_name_edit: LineEdit    # для ввода имени после победы
_frame: int             # счётчик кадров (для анимаций)
```

### Туман войны
```gdscript
FOG_INNER_R = 3.8  # клеток — полная видимость
FOG_OUTER_R = 5.8  # клеток — полная темнота
FOG_ALPHA   = 0.40 # максимальная непрозрачность
fog_color = Color(0.05, 0.05, 0.10)  # тёмно-синий тон
```

### _ell() helper
```gdscript
func _ell(center, rx, ry, color, rot=0.0, seg=24)
# → draw_colored_polygon(PackedVector2Array, Color)
# Единственный способ рисовать эллипсы в Godot 4 draw API
```

---

## Этапы (статус)

| Этап | Содержание | Статус |
|------|-----------|--------|
| 1 | Лабиринт (рендер + генерация) | ✅ Готово |
| 2 | Хомяк (рисование + WASD движение) | ✅ Готово |
| 3 | Лама AI (синяя + красная) + game over | ✅ Готово |
| 4 | Орехи + норы (Space) + порталы + экран победы | ✅ Готово |
| 5 | Туман войны | ✅ Готово |
| 6 | Сплэш экран + локальный рекорд + ввод имени | ⚠️ Есть баг |
| 7 | Звук (.ogg) + Supabase leaderboard | ❌ Не начато |
| 8 | Мобильные контролы + экспорт | ❌ Не начато |
| 9 | Спрайты / анимации (визуальная переработка) | ❌ Запланировано после 8 |

---

## Known Issues / Риски

### 🔴 Критический баг Etap 6 — тёмный серый экран при запуске
**Симптом:** после обновления до Etap 6 открывается темно-серое пустое окно.
**Вероятная причина (на расследовании):**
- Возможен тихий crash в `_draw_splash()` после отрисовки фона (#050510),
  из-за чего виден только серый дефолтный фон Godot (Forward Plus renderer)
- Подозрительное место: `["1.", "2.", "3."].get(i, ...)` — метод `.get()` не существует
  на массиве Array в GDScript (только на Dictionary). Хотя код в ветке `_scores.is_empty()`,
  GDScript может ловить это при парсинге.
- Другая возможность: `_setup_name_input()` падает при добавлении Control-нод в CanvasLayer

**Следующий шаг — ПЕРВОЕ ЧТО НУЖНО СДЕЛАТЬ:**
1. Открыть Godot → Output панель → найти красные ошибки
2. Если ошибка парсинга GDScript — исправить строку `.get()`:
   ```gdscript
   # Было (баг):
   var medal: String = ["1.", "2.", "3."].get(i, "%d." % (i + 1))
   # Надо:
   var medals_arr := ["1.", "2.", "3.", "4.", "5.", "6.", "7.", "8."]
   var medal: String = medals_arr[i] if i < medals_arr.size() else "%d." % (i + 1)
   ```
3. Если ошибок нет — добавить `print("draw called")` в начало `_draw()` для диагностики

### 🟡 Средние риски
- Leaderboard сессионный (в памяти) — после перезапуска Godot рекорды сбрасываются.
  Для постоянства нужен ConfigFile (Etap 7).
- `_rh` (RHManager) = null в splash state. В `_draw()` есть guard `if _state == "splash": return`,
  но если логика нарушится — NullPointerException.
- `_nuts` пустой в splash state. HUD использует `_nuts.size()` — защищено empty array.

### 🟢 Нормально работает (Etap 1-5)
- Лабиринт генерируется корректно
- Хомяк движется, WASD + held-key
- Лама AI (синяя + красная), все 4 состояния
- Орехи, волны, норы (Space), порталы
- Туман войны с плавным градиентом

---

## Ключевые технические решения

| Решение | Почему |
|---------|--------|
| Pure Node2D `_draw()` вместо TileMap | Быстрее портировать из Canvas JS, не нужен TileSet |
| `_ell()` через `draw_colored_polygon` | В Godot 4 нет `draw_ellipse` |
| RefCounted для AI классов | Не нужна сцена, чистый GDScript |
| Autoload `C` для констант | Все классы (RefCounted) видят C.* без импортов |
| CanvasLayer + LineEdit для ввода имени | Единственный способ сделать текстовый ввод поверх _draw() |
| Fog per-cell (не шейдер) | Проще реализовать, достаточно хорошо выглядит |
| `int / int` в GDScript = int | Использовать `float()` или `/ 1000.0` для деления |

---

## Оригинальная HTML игра — соответствие строк

| Механика | Строки HTML |
|----------|------------|
| `makeMaze()` | 413-462 |
| `bfs()` | 465-482 |
| `rhInit/rhUpdate/pickRHPos` | 782-833 |
| `drawNut()` | 1051-1058 |
| `drawHamster()` | 1061-1116 |
| `drawLlama()` | 1140-1180 |
| `drawFog()` | 1439-1460 |
| `updateLlama()` | 975-1031 |
| `doBurrow()` | 539-553 |
| Nuts init | 511-529 |
| Nuts update | 921-948 |

---

## Команды запуска

```bash
# Открыть проект в Godot (если не открыт)
open "/Users/andriidiablo/Documents/Test 3.1/project.godot"

# Git
cd "/Users/andriidiablo/Documents/Test 3.1"
git status
git log --oneline -8
git push

# Запустить игру — кнопка ▶ в правом верхнем углу Godot
# Горячая клавиша: F5 (может не работать если фокус не на Godot)
# Обновить: закрыть игровое окно → снова ▶
```

---

## История сессий

### Сессия 1-2 (2026-03-05)
- Решение перейти на Godot 4
- Создан репозиторий, начата структура проекта

### Сессия 3 (2026-03-05, текущая)
**Сделано:**
- Etap 1: лабиринт (maze_generator.gd, bfs_pathfinder.gd)
- Etap 2: хомяк (рисование + движение)
- Etap 3: llama_ai.gd, синяя + красная лама, game over
- Etap 4: nuts (волны), burrows (Space), rh_manager.gd (порталы), win screen
- Etap 5: туман войны, FOG_ALPHA=0.40 (настроен по вкусу пользователя)
- Etap 6: сплэш-экран, ввод имени (LineEdit), локальный leaderboard
  → **Баг: темный экран при запуске, причина не выяснена (отключили свет)**

**Commits этой сессии:**
```
923029d Etap 6: splash screen + local leaderboard + name input
ae9664b Tune fog of war: lighter alpha (0.40) + dark navy tint
b041b00 Etap 5: fog of war (туман войны)
1ab1fde Etap 4: nuts, burrows, rabbit holes, win screen
b7907b9 Etap 3: llama AI (blue + red) + game over screen
```

---

## Next Steps (следующая сессия)

### 🔴 Первым делом — исправить баг Etap 6
1. Открыть Godot, нажать ▶
2. Проверить Output на ошибки
3. Если ошибка GDScript parse — исправить `.get()` на массиве (см. Known Issues)
4. Если нет ошибок — добавить `print()` в `_draw()` для диагностики

### После фикса — Etap 7
- Звуки: `.ogg` файлы в `assets/sounds/` + AudioStreamPlayer
- Supabase leaderboard: HTTPRequest + `https://ytipfibgtnrvtsygetnb.supabase.co`
  - Таблица `scores` (id, uid, name, time, date, comment)
  - Игрок = UUID в FileAccess/ConfigFile (замена localStorage)
- Постоянное хранение рекордов: ConfigFile `user://scores.cfg`

### Etap 8 (после 7)
- Мобильные контролы: TouchScreenButton (d-pad + нора + музыка)
- Экспорт: Web (HTML5), Android
