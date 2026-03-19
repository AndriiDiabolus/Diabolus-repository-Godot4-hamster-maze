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
  main.gd            — extends Node2D, вся игровая логика + весь рендер (~1180 строк)
scenes/
  Main.tscn          — uid://c431j5hrtri71, Node2D + main.gd
assets/
  sounds/
    eat_nut.mp3      — хруст ореха (CC BY-NC 4.0, orangefreesounds.com) ⚠️ не для коммерции
    burrow.wav       — звук норки (CC0, Juhani Junkala)
    teleport.wav     — звук телепорта (CC0, Juhani Junkala)
    llama_catch.wav  — поимка хомяка (CC0, Juhani Junkala)
    win.wav          — старый победный звук (не используется)
    win_new.ogg      — победный джингл pizzicato (CC0, Kenney music-jingles pack)
    bg_music.ogg     — фоновая музыка Arcade Puzzler (CC-BY 3.0, Eric Matyas)
    rabbit_laugh.ogg — смех кролика при копании (CC0, AntumDeluge)
  fonts/
    flintstone.ttf   — шрифт для заголовка в HTML-зоне (free, wfonts.com)
export_presets.cfg   — Web export + html/head_include (мобильные контролы в HTML)
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
menu → play → level_up → play → ... → lost → won_name → won → menu
                                     → (все орехи) → level_up → (авто) → play (следующий уровень)
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
_held_keys: Dictionary   # keycode→bool, web-совместимое удержание клавиш
_name_layer: CanvasLayer
_name_edit: LineEdit     # для ввода имени после победы
_frame: int              # счётчик кадров (для анимаций)
_win_anim_t: int         # таймер анимации победы (0..WIN_SPIN_DUR=240)
_level: int              # текущий уровень (с 1)
_level_trans_t: int      # таймер анимации перехода уровня
_total_time_ms: int      # суммарное время всех уровней
_bonuses: Array          # [{x,y,type,got}] shield/speed/freeze
_shield_until: int       # Time.get_ticks_msec() до которого щит
_speed_until: int        # до которого скорость x2
_freeze_until: int       # до которого ламы заморожены
_particles: Array        # [{x,y,vx,vy,life,max_life,color}]
```

### Анимация победы (танец хомяка)
```gdscript
WIN_SPIN_DUR: int = 240  # ~4 секунды при 60fps

# 4 фазы в _draw_win_anim():
# t 0-60:   Прыжки x3 — bounce с squish (расплющивание при приземлении)
# t 60-120: Раскачка влево-вправо — sin rotation + ox смещение + ноты ♪
# t 120-165: Один полный спин (TAU) + пульсация масштаба
# t 165-240: Финал — лёгкое покачивание + 8 искр по орбите + пульс "ПОБЕДА!"
# draw_set_transform(pos, rot, scale) для всех трансформаций в _draw()
# _show_name_input() вызывается автоматически после WIN_SPIN_DUR кадров
```

### Туман войны — УБРАН
```gdscript
# Код _draw_fog() остался в main.gd, но вызов закомментирован
# Константы FOG_INNER_R, FOG_OUTER_R, FOG_ALPHA ещё в коде (не используются)
```

### Мобильные контролы (HTML-зона, не canvas)
```
CTRL_H = 0  # контролы убраны из canvas в HTML-зону ниже
Viewport 900x742 — только игровой экран без зоны управления

HTML-зона (230px, position:fixed;bottom:0):
  - Заголовок "HAMSTER MAZE" — CSS stone/Flintstones стиль (Georgia, #d4a020, 3D-тени)
  - D-pad: ▲▼◄► кнопки, dispatch WASD KeyboardEvent на canvas
  - OK кнопка: dispatch Enter KeyboardEvent (навигация в меню)
  - НОРА кнопка: dispatch Space KeyboardEvent
  - Создаётся только на touch устройствах (ontouchstart in window)
  - Canvas сжимается до innerHeight-230px через JS setProperty important

_held_keys: Dictionary  # keycode→bool, обновляется в _input()
# Input.is_key_pressed() НЕ работает с JS synthetic KeyboardEvent
# Движение в _process() использует _held_keys.get(KEY_W/S/A/D, false)

# Тест мобильных контролов на десктопе:
# Project Settings → Input Devices → Pointing → Emulate Touch From Mouse ✓
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
| 6 | Сплэш экран + локальный рекорд + ввод имени | ✅ Готово |
| 7 | Звук + Supabase leaderboard + persistent scores | ✅ Готово |
| 8 | Мобильные touch контролы (HTML-зона ниже canvas) | ✅ Готово |
| 9A | Танец хомяка при победе (4 фазы + искры + ноты) | ✅ Готово |
| 9M | Анимация меню: intro сцена + looping chase (пары поочерёдно) | ✅ Готово |
| 9B | Геймплей: уровни, бонус-предметы, частицы | ✅ Готово |
| 9C | Визуальная переработка + пауза + polish | ✅ Готово |

---

## Known Issues / Риски

### 🟡 Средние риски
- `eat_nut.mp3` лицензия CC BY-NC 4.0 — не для коммерческого использования.
  Для релиза заменить на CC0 звук (аналогично win_new.ogg взять с Kenney.nl).
- Anon key Supabase хранится в открытом виде в main.gd — нормально для anon key,
  но если RLS не настроен — любой может писать/читать таблицу.
- Persistent scores хранятся в `user://scores.cfg`. После переустановки — сбрасываются.
- Кнопки меню (Музыка, Кредиты) на мобильном — добавлен grow(28) padding и OK кнопка
  для навигации, но не тестировалось на реальном устройстве после этой сессии.

### 🟢 Нормально работает (Etap 1-9C)
- Лабиринт генерируется корректно
- Хомяк движется плавно (lerp): WASD + _held_keys (web) + touch d-pad (HTML)
- Лама AI (синяя + красная), все 4 состояния, синяя краснеет при chase
- Орехи (15-30 штук, с искоркой), волны, норы (Space/tap), порталы (с искрами)
- Бесконечные уровни + бонусы (shield/speed/freeze) + частицы
- Пауза (Escape), звуки всех событий + фоновая музыка (loop)
- Стены с текстурой камня + тени, пол с градиентом
- Анимация ног при ходьбе, пыль под ногами
- Supabase топ-10 (GET при старте, POST после проигрыша)
- HTML мобильные контролы: d-pad + OK + НОРА, заголовок HAMSTER MAZE
- Меню с анимацией (intro + chase), танец хомяка при победе
- Туман войны УБРАН (полная видимость карты)

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
| JavaScriptBridge.eval() для Supabase на Web | HTTPRequest ненадёжен в браузере с кастомными хедерами |
| HTML-зона для мобильных контролов | Canvas не знает о touch → dispatch KeyboardEvent в JS проще |
| `_held_keys` dict в `_input()` | `Input.is_key_pressed()` не видит JS synthetic KeyboardEvent |
| `draw_set_transform(pos, rot, scale)` | Единственный способ трансформировать в _draw() Godot 4 |
| `int / int` в GDScript = int | Использовать `float()` или `/ 1000.0` для деления |
| Kenney.nl для CC0 звуков | Freesound.org требует логин для скачивания, Kenney — нет |

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

**Commits:**
```
d19e1a6 Etap 8: mobile touch controls (d-pad + burrow button)
3f69b4d Etap 7B: sound effects + background music
aae9696 Etap 7: Supabase online leaderboard + persistent local scores + llama speed fix
140bb68 fix: Etap 6 — replace Array.get() with proper indexing, remove debug prints
```

### Сессия 5 (2026-03-07)
**Сделано:**
- Web (HTML5) экспорт настроен и задеплоен на GitHub Pages
  - Godot CLI headless export: `Godot --headless --export-release "Web"`
  - Deploy: orphan `gh-pages` ветка, git worktree
  - Live URL: https://andriidiabolus.github.io/Diabolus-repository-Godot4-hamster-maze/
- Зона управления расширена: `CTRL_H` 240→360, viewport_height 982→1102
- Кнопки d-pad и нора перенесены НИЖЕ игрового экрана
- Надпись "HAMSTER MAZE" — Flintstones стиль, TTF шрифт flintstone.ttf
- Исправлен баг: WASD не работали в web-билде (physical_keycode)
- Исправлен баг: таблица рекордов — JavaScriptBridge.eval() + нативный JS fetch()

**Commits:**
```
ba18499 feat: use Flintstone TTF font for HAMSTER MAZE title
3c85e12 feat: Flintstones-style HAMSTER MAZE title with rocky font in controls zone
9f13f4d fix: WASD physical_keycode for web + JavaScriptBridge fetch for leaderboard
```

---

### Сессия 6 (2026-03-07)
**Сделано:**

**Архитектура мобильных контролов — полный переезд в HTML:**
- Контролы полностью убраны из canvas Godot (`CTRL_H=0`, viewport_height=742)
- HTML-зона 230px (`position:fixed;bottom:0`) в `export_presets.cfg` `html/head_include`
- Создаётся JS-кодом только на touch устройствах (`ontouchstart in window`)
- D-pad (▲▼◄►) + кнопка **OK** (Enter) + кнопка **НОРА** (Space) — dispatch KeyboardEvent
- Заголовок "HAMSTER MAZE" в CSS: Georgia, `#d4a020`, 3D stone shadows, `font-size:30px`
- Canvas сжимается до `innerHeight - 230px` через `setProperty('important')`

**Фикс движения на web:**
- `_held_keys: Dictionary` — обновляется в `_input()` для каждого KeyboardEvent
- `_process()` использует `_held_keys.get(KEY_W/S/A/D, false)` вместо `Input.is_key_pressed()`
- Причина: `Input.is_key_pressed()` читает hardware-state, не реагирует на JS-синтетические события

**Фикс кнопок меню на мобильном:**
- `_handle_menu_click()` использует `grow(28)` padding на hit rects при `_show_touch`
- OK кнопка в HTML позволяет навигацию Enter в меню без касания экрана

**Новый CC0 победный звук:**
- `assets/sounds/win_new.ogg` — `jingles_PIZZI03.ogg` из Kenney music-jingles pack
- Pizzicato (щипковые струны), бодрый ~1.5 сек, CC0
- Kenney.nl не требует авторизации для прямого скачивания (в отличие от Freesound.org)

**Танец хомяка при победе (заменяет spinning):**
- `WIN_SPIN_DUR=240` (~4 сек), `_draw_win_anim()` полностью переписан
- Фаза 1 (t 0-60): **Прыжки x3** — squish при приземлении (sc_x /= sq, sc_y *= sq)
- Фаза 2 (t 60-120): **Раскачка** — sin rotation ±0.35 rad + боковое смещение + ноты ♪
- Фаза 3 (t 120-165): **Спин** — полный TAU оборот + пульсация масштаба
- Фаза 4 (t 165-240): **Финал** — покачивание + 8 искр по орбите + "ПОБЕДА!" пульсирует
- `_show_name_input()` вызывается автоматически по истечении анимации

**Commits:**
```
371d496 Etap 9: hamster dance animation (4 phases)
2e8ff5c Etap 9: win animation (spinning hamster) + new CC0 win sound
[+gh-pages deploys: 3e4fb36, 0d7efcc]
```

---

### Сессия 7 (2026-03-08)
**Сделано:**

**Анимация меню — вступительная сцена (Etap 9A-menu, intro):**
- `MENU_INTRO_DUR=285` кадров — однократная intro сцена при открытии меню
- Хомяк появляется по центру, смотрит влево/вправо, замечает ламу, прыгает с "!", убегает вправо
- Лама входит справа, осматривается, прыгает с "!!", краснеет, гонится влево
- `_menu_anim_t` сбрасывается при каждом входе в menu-state через `_prev_state` tracking

**Анимация меню — зацикленная погоня (looping chase):**
- После intro: пары бегут попеременно (не одновременно)
  - Фаза 1 (340 кадров): большая пара sc=2.2, cy=455, лево→право, красная лама
  - Фаза 2 (260 кадров): малая пара sc=1.2, cy=425, право→лево, синяя лама
  - Цикл: 600 кадров (~10 сек при 60fps)
- Расстояние хомяк↔лама = 1 ширина тела хомяка (40px × scale): 88px / 48px
- Пыль под ногами (`_menu_dust`) синхронизирована с фазами цикла

**Критическое решение — персонажи поверх кнопок:**
- Проблема: `_draw_menu_anim()` вызывалась ДО кнопок → персонажи рисовались под ними
- Решение: перенос вызова ПОСЛЕ всех кнопок и лидерборда
- Кнопки остались с непрозрачным фоном, персонажи видны поверх полностью
- Попытки сделать кнопки прозрачными (alpha 0.35 → 0.10) не работали: _draw() рендерит
  последовательно, поздний вызов = поверх — это правильная архитектура

**Критическое решение — деплой (из сессии 6, закреплено):**
- Godot Web JS всегда грузит `executable + ".pck"` = `index.pck`
- `fileSizes` в GODOT_CONFIG — только для прогресс-бара, не влияет на загрузку
- Переименование `index2/3.pck` бесполезно без `mainPack` override
- **Правильный способ сброса кэша:**
  ```bash
  cp export/web/index.pck /tmp/gh-pages-clean/gameN.pck
  sed -i '' 's/"gdextensionLibs":\[\]/"mainPack":"gameN.pck","gdextensionLibs":[]/g' index.html
  ```
- Текущий деплой: `game7.pck` (gh-pages, 2026-03-08)

**Commits (main):**
```
cda4185 feat: menu chase — alternating pairs, 1-hamster gap, chars over buttons
89863f0 fix: menu anim cy=420-460 (visible range), draw before buttons
b6b2c65 fix: scale up menu animation characters (HSC=3.5, LSC=3.0, chase 3.0/1.7)
24b587d feat: menu animation — hamster/llama intro + looping chase
01a3829 feat: menu animations — twinkling stars + pulsing title
```

**gh-pages deploys этой сессии:**
```
game2.pck — remove debug circles
game3.pck — alternating pairs + bigger gap
game4.pck — 1-hamster-width gap (88px/48px)
game5.pck — transparent buttons attempt (alpha 0.35)
game6.pck — transparent buttons attempt (alpha 0.10)
game7.pck — FINAL: chars drawn on top of buttons ← ТЕКУЩИЙ
```

---

### Сессия 8 (2026-03-16)
**Сделано:**

**Etap 9B — Уровни:**
- Бесконечные уровни: `_level` счётчик, после сбора всех орехов → `level_up` экран → новый лабиринт
- `LEVEL_TRANS_DUR=150` кадров (~2.5 сек) — экран "УРОВЕНЬ N!" с анимацией (пульс, хомяк прыгает, звёздочки)
- Масштабирование сложности: лама +3 скорости за уровень, красная лама спавнится раньше (-10с/ур, мин 10с)
- Время суммируется (`_total_time_ms`) через все уровни
- Проигрыш: `lost` → Enter → `won_name` (ввод имени) → `won` → меню
- Рекорды сортируются по уровню (выше=лучше), затем по времени

**Etap 9B — Бонус-предметы:**
- 3 типа: `shield` (5с неуязвимость), `speed` (4с двойная скорость), `freeze` (4с заморозка лам)
- 3-5 штук на уровне (`2 + min(_level, 3)`)
- Визуал: shield=синий шар, speed=жёлтый с молнией, freeze=голубой с вращающейся снежинкой
- Эффекты: shield=синяя аура+кольцо на хомяке, freeze=ледяная аура+кольцо на ламах
- HUD: таймеры обратного отсчёта для активных бонусов

**Etap 9B — Частицы:**
- 7 золотых кружков при сборе ореха/бонуса, разлетаются с гравитацией

**Изменения орехов:**
- `NUT_SPAWN_CHANCE` 0.18→0.12, `NUT_MIN_COUNT` 20→15, `NUT_MAX_COUNT`=30 (новая константа)

**Commits (main):**
```
b2b8c79 feat: Etap 9B — levels, bonus items, nut particles
7529e37 docs: session 7 wrap-up — update CLAUDE.md with menu animation details
cda4185 feat: menu chase — alternating pairs, 1-hamster gap, chars over buttons
```

**gh-pages deploys сессии 8:**
```
game8-11.pck — Etap 9B (levels, bonuses, particles)
game12-16.pck — Etap 9C (visual overhaul, legs, walls, dust, etc.)
game17.pck — FINAL: pause, bonus sound, llama blush ← ТЕКУЩИЙ
```

---

### Сессия 8 (продолжение, 2026-03-16)
**Сделано (Etap 9C — визуальная переработка + polish):**

**Визуал:**
- Плавное движение хомяка (lerp 0.28 между клетками вместо телепорта)
- Анимация ног: хомяк и лама шагают только при движении (±5px)
- Пыль под ногами хомяка при ходьбе (коричневые частицы)
- Стены: текстура камня (вариативность цвета) + швы + тени на пол
- Пол: градиент (светлее вверху, темнее внизу) + крапинки текстуры
- Орехи блестят (бегущая искорка по поверхности)
- Шерсть ламы (светлые пятна на теле)
- Синяя лама краснеет при chase (пульсирующий lerp → красный)
- Порталы: больший ореол + 3 вращающиеся искорки по орбите
- HUD: градиентный фон с подсветкой сверху и тенью снизу

**Геймплей/polish:**
- Пауза (Escape) — оверлей "ПАУЗА", Esc снова → продолжить
- Звук при подборе бонуса (телепорт sfx)
- Туман войны УБРАН (вся карта видна)
- Щёки хомяка округлее + блик

**Технические:**
- Очищены старые game*.pck с gh-pages (экономия ~45 MB)
- `_ham_moving` — per-frame проверка зажатых клавиш (не по таймеру)
- `_ham_visual_x/y` — визуальная позиция (lerp), логическая `_ham.x/y` — дискретная
- `_dust_particles` — отдельный массив частиц пыли

**Commits (main):**
```
7e1fd29 feat: 9C visual overhaul + pause + polish
aa75585 docs: session 8 wrap-up — Etap 9B complete (levels, bonuses, particles)
b2b8c79 feat: Etap 9B — levels, bonus items, nut particles
```

---

## Next Steps (следующая сессия)

### 🔧 Технические улучшения (по желанию)
- Заменить `eat_nut.mp3` (CC BY-NC) на CC0 с Kenney.nl
- RLS политики в Supabase (сейчас таблица открыта всем)
- Android экспорт: нужен Android SDK + JDK, `Project → Export → Add → Android`

### 🎮 Новые фичи (идеи)
- Ловушки (шипы, движущиеся стены)
- Мини-карта в углу HUD
- Достижения ("Пройди 5 уровней", "Собери 100 орехов")
- Второй режим игры (таймер на скорость, бесконечный)

### 🌐 Deploy
```bash
# Headless export:
"/Users/andriidiablo/Desktop/Godot.app/Contents/MacOS/Godot" \
  --headless --path "/Users/andriidiablo/Documents/Test 3.1" \
  --export-release "Web" "/Users/andriidiablo/Documents/Test 3.1/export/web/index.html"

# Deploy gh-pages (ПРАВИЛЬНЫЙ способ с cache bust):
PACK_NAME="gameN.pck"  # N = следующий номер
rm -rf /tmp/gh-pages-clean && git worktree prune
git worktree add /tmp/gh-pages-clean gh-pages
cp export/web/index.html /tmp/gh-pages-clean/index.html
cp export/web/index.pck /tmp/gh-pages-clean/$PACK_NAME
sed -i '' "s/\"gdextensionLibs\":\[\]/\"mainPack\":\"$PACK_NAME\",\"gdextensionLibs\":[]/g" /tmp/gh-pages-clean/index.html
cd /tmp/gh-pages-clean && git add index.html $PACK_NAME
git commit -m "deploy: $PACK_NAME — описание изменений"
git push origin gh-pages
git worktree remove /tmp/gh-pages-clean
```
