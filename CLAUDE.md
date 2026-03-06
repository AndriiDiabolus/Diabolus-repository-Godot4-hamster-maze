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
  main.gd            — extends Node2D, вся игровая логика + весь рендер (~1100 строк)
scenes/
  Main.tscn          — uid://c431j5hrtri71, Node2D + main.gd
assets/
  sounds/
    eat_nut.mp3      — хруст ореха (CC BY-NC 4.0, orangefreesounds.com)
    burrow.wav       — звук норки (CC0, Juhani Junkala)
    teleport.wav     — звук телепорта (CC0, Juhani Junkala)
    llama_catch.wav  — поимка хомяка (CC0, Juhani Junkala)
    win.wav          — победный фанфар (CC0, Juhani Junkala)
    bg_music.ogg     — фоновая музыка Arcade Puzzler (CC-BY 3.0, Eric Matyas)
    rabbit_laugh.ogg — смех кролика при копании (CC0, AntumDeluge)
project.godot        — config v5, Godot 4.6, autoload C, viewport 900x742
hamster_maze.html    — оригинальный HTML файл (reference only)
```

---

## Константы (C.*)
```gdscript
COLS=25, ROWS=19, CELL=36, HUD=58, W=900, H=684
CHASE_R=4, ALERT_R=8
LSPEED_BASE = {patrol:52, alert:36, chase:28, search:34}  # frames per step (higher=slower)
RH_COOLDOWN_MS=60000, RH_DIG_MS=10000
NUT_WAVE_INTERVAL_MS=25000, NUT_FIRST_WAVE_PCT=0.35, NUT_NEXT_WAVE_PCT=0.40
NUT_MIN_COUNT=20, NUT_SPAWN_CHANCE=0.18
LLAMA2_SPAWN_MS=60000, LLAMA_BONUS_INTERVAL_MS=30000, LLAMA_BONUS_MAX=8
```

---

## Архитектура main.gd

### State machine
```
splash → (Enter/Tap) → play → (поймана) → lost → (Enter/Tap) → splash
                             → (все орехи) → won_name → (ввёл имя) → won → (Enter/Tap) → splash
```

### Ключевые переменные
```gdscript
_state: String           # splash | play | lost | won_name | won
_ham: Dictionary         # {x, y, burrowed, burrows}
_maze: Array             # [ROWS][COLS], 0=проход 1=стена
_llama: LlamaAI          # синяя лама
_llama2: LlamaAI         # красная лама (спавн через 60с)
_llama_bonus: int        # +1 каждые 30с, макс 8
_nuts: Array             # [{x,y,got,visible}]
_next_wave_ms: int       # когда следующая волна орехов
_rh: RHManager           # 2 пары порталов
_scores: Array           # [{name,time_ms}], топ-10, persistent (ConfigFile)
_online_scores: Array    # топ-10 из Supabase
_player_uid: String      # UUID игрока (хранится в scores.cfg)
_show_touch: bool        # true если touchscreen доступен
_touch_dirs: Dictionary  # finger_id -> "up"/"down"/"left"/"right"
_name_layer: CanvasLayer
_name_edit: LineEdit     # для ввода имени после победы
_frame: int              # счётчик кадров (для анимаций)
```

### Туман войны
```gdscript
FOG_INNER_R = 3.8  # клеток — полная видимость
FOG_OUTER_R = 5.8  # клеток — полная темнота
FOG_ALPHA   = 0.40 # максимальная непрозрачность
fog_color = Color(0.05, 0.05, 0.10)  # тёмно-синий тон
```

### Мобильные контролы
```gdscript
MB_DPAD_CX=90, MB_DPAD_CY=585  # центр d-pad (левый нижний угол)
MB_BTN_STEP=62, MB_BTN_R=26    # шаг и радиус кнопок
MB_BURROW_X=820, MB_BURROW_Y=585  # кнопка "нора" (правый нижний)
# Показываются только если DisplayServer.is_touchscreen_available()
# Для теста на десктопе: Project Settings → Input Devices → Emulate Touch From Mouse
```

### Supabase
```gdscript
SB_URL = "https://ytipfibgtnrvtsygetnb.supabase.co/rest/v1/scores"
# Таблица: scores (id, uid, name, time, date)
# Анон ключ хранится в SB_KEY константе в main.gd
# Persistent scores: user://scores.cfg (ConfigFile)
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
| 6 | Сплэш экран + локальный рекорд + ввод имени | ✅ Готово (баг исправлен) |
| 7 | Звук (.ogg/.wav/.mp3) + Supabase leaderboard + persistent scores | ✅ Готово |
| 8 | Мобильные touch контролы | ✅ Готово (экспорт — вручную в Godot) |
| 9 | Спрайты / анимации (визуальная переработка) | ❌ Запланировано |

---

## Known Issues / Риски

### 🟡 Средние риски
- `_show_touch` = false на десктопе — мобильные контролы не видны без `Emulate Touch`.
  Если нужно форсировать на Web: добавить `or OS.get_name() == "Web"` в `_ready()`.
- Anon key Supabase хранится в открытом виде в main.gd — нормально для anon key,
  но если RLS не настроен — любой может писать/читать таблицу.
- `eat_nut.mp3` лицензия CC BY-NC 4.0 — не для коммерческого использования.
  Для релиза заменить на CC0 звук.
- Persistent scores хранятся в `user://scores.cfg`. После переустановки — сбрасываются.

### 🟢 Нормально работает (Etap 1-8)
- Лабиринт генерируется корректно
- Хомяк движется, WASD + held-key + touch d-pad
- Лама AI (синяя + красная), все 4 состояния, скорость сбалансирована
- Орехи, волны, норы (Space/tap), порталы
- Туман войны с плавным градиентом
- Splash, splash leaderboard (онлайн + локальный), ввод имени
- Звуки всех событий + фоновая музыка (loop)
- Supabase топ-10 (GET при старте, POST после победы)
- Мобильный d-pad + кнопка нора (touch)

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
| ConfigFile для persistent scores | Стандартный Godot способ, path = user://scores.cfg |
| HTTPRequest nodes для Supabase | Нативный Godot, без сторонних библиотек |
| Touch контролы через `_input()` + `_draw()` | Нет лишних нод, чистый код |
| `DisplayServer.is_touchscreen_available()` | Автодетект touch без проверки платформы |
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

# Тест мобильных контролов на десктопе:
# Project Settings → Input Devices → Pointing → Emulate Touch From Mouse ✓
```

---

## История сессий

### Сессия 1-2 (2026-03-05)
- Решение перейти на Godot 4
- Создан репозиторий, начата структура проекта

### Сессия 3 (2026-03-05)
- Etap 1-5: лабиринт, хомяк, AI, орехи/норы/порталы, туман войны
- Etap 6: сплэш, ввод имени, leaderboard → баг (Array.get() parse error)

### Сессия 4 (2026-03-06)
**Сделано:**
- Исправлен баг Etap 6 (`Array.get()` → правильная индексация)
- Etap 7A: ConfigFile persistent scores (`user://scores.cfg`) + player UUID
- Etap 7B: Supabase online leaderboard (HTTPRequest POST/GET, топ-10)
- Etap 7C: Все звуки — eat/burrow/teleport/catch/win/bg_music/rabbit_laugh
- Скорость лам снижена (LSPEED_BASE patrol:52, alert:36, chase:28, search:34)
- Etap 8: Мобильные touch контролы (d-pad + нора), автодетект, drag support

**Commits этой сессии:**
```
d19e1a6 Etap 8: mobile touch controls (d-pad + burrow button)
3f69b4d Etap 7B: sound effects + background music
aae9696 Etap 7: Supabase online leaderboard + persistent local scores + llama speed fix
140bb68 fix: Etap 6 — replace Array.get() with proper indexing, remove debug prints
```

---

## Next Steps (следующая сессия)

### Etap 9 — Web (HTML5) экспорт
1. В Godot: `Project → Export → Add → Web`
2. Export Path: `export/web/index.html`
3. Включить: `Export With Debug` = OFF для релиза
4. Проверить что `res://assets/sounds/` включены в экспорт
5. Загрузить на GitHub Pages или itch.io

### Etap 9 — Android экспорт (опционально)
1. Нужен Android SDK + JDK (Godot покажет где скачать)
2. `Project → Export → Add → Android`
3. Подписать APK (debug keystore для теста)

### Etap 9 — Визуальная переработка (спрайты/анимации)
- Заменить draw-примитивы на SpritesheetTexture или AnimatedSprite2D
- Или улучшить существующий _draw() рендер (шерсть, тени, детали)
- Решение принять в начале сессии

### Технические улучшения (по желанию)
- `_show_touch` на Web: добавить `or OS.get_name() == "Web"` (видеть контролы всегда)
- Заменить `eat_nut.mp3` (CC BY-NC) на CC0 звук для коммерческого релиза
- RLS политики в Supabase (сейчас таблица открыта всем)
- Кнопка "Музыка ON/OFF" в HUD или на сплэш
