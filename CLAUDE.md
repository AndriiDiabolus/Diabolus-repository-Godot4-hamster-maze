# CLAUDE.md — Контекст проекта "Хомяк в Лабиринте"

## Репозитории
- **Текущий (Godot 4):** https://github.com/AndriiDiabolus/Diabolus-repository-Godot4-hamster-maze.git
- **Старый (HTML версия):** https://github.com/AndriiDiabolus/Diabolus-Repository.git
- **Локальный путь:** `/Users/andriidiablo/Documents/Test 3.1/`
- **Ветка:** main

## Файлы проекта
- `hamster_maze.html` — полная браузерная версия игры (Test 3.1), ~1895 строк, один файл без зависимостей

## Описание игры
Браузерная игра "Хомяк в Лабиринте" (один HTML файл, без зависимостей).

### Технологии (HTML версия)
- Чистый HTML5 + CSS + JavaScript (no framework)
- Canvas API для рендеринга
- Web Audio API — процедурные звуки (осцилляторы, без файлов)
- Supabase REST API — онлайн таблица рекордов
- PWA: manifest, apple-touch-icon, A2HS баннер
- Язык интерфейса: русский

### Константы карты
- `CELL = 36` — размер клетки в пикселях
- `COLS = 25`, `ROWS = 19` — размер лабиринта (25x19 клеток)
- `HUD = 58` — высота HUD панели
- `W = COLS * CELL = 900`, `H = ROWS * CELL = 684`

### Механика игры
- **Цель:** собрать все орехи (nuts), появляются волнами каждые 25 секунд (~35% первая волна, далее по 40% от скрытых)
- **Хомяк:** управляется стрелками / WASD, шаг каждые 8 фреймов
- **Синяя лама:** патрулирует (patrol/alert/chase/search), слышит на 8 клеток (ALERT_R), видит на 4 (CHASE_R); каждые 30 сек ускоряется (+1 llamaBonus, макс 8)
- **Красная лама:** появляется через 60 секунд, независимый AI, та же логика
- **Скорости ламы (фреймов на шаг):** patrol=32, alert=22, chase=16, search=20 (минус llamaBonus)
- **Норы:** Пробел — спрятаться/вылезти, всего 3 норы (ham.burrows)
- **Кроличьи норы:** 2 пары порталов (rhPairs), cooldown 60 сек, за 10 сек до открытия появляется кролик-маркер
- **Туман войны:** innerR=3.8*CELL, outerR=5.8*CELL, evenodd fill + radial gradient
- **Управление:** WASD / стрелки, M — музыка, Enter — рестарт, Пробел — нора

### Алгоритмы (строки в файле)
- **Генерация лабиринта** (строки 413-462): recursive backtracking + устранение тупиков (dead end removal)
- **BFS pathfinder** (строки 465-482): поиск пути врагов, возвращает массив шагов
- **AI лам** (строки 975-1031): `updateLlama()`, 4 состояния, `makeSearchPts()` для поиска
- **Rabbit holes** (строки 782-833): `rhInit()`, `rhUpdate()`, `pickRHPos()`

### Звуки (Web Audio API, процедурные)
- `sfxHamStep()` — шаг хомяка (sine 920Hz)
- `sfxLlamaStep()` — шаг ламы (triangle 130Hz)
- `sfxNut()` — сбор ореха (трезвучие 440/554/659 Hz)
- `sfxBurrow()` / `sfxUnburrow()` — нора (sawtooth/sine sweep)
- `sfxEnrage()` — лама в погоне (square 700/900/1050 Hz)
- `sfxWin()` / `sfxLose()` — победа/поражение
- `sfxTeleport()` — кроличья нора (sine sweep x3)
- `sfxWheee()` — хомяк крутится на победном экране
- Фоновая музыка: BG_MEL (16 нот) + BG_BASS (6 нот), setTimeout loop

### UI / UX
- Тёмная тема: фон `#0d0d1a`, акцент `#ffd700` (золотой), синее свечение `#1e4a8a`
- Адаптив для мобильных: d-pad кнопки (tc-up/down/left/right), кнопка норы, кнопка музыки
- Splash-экран с правилами + таблицей рекордов (две колонки)
- Online таблица рекордов через Supabase (lb-panel, обновление каждые 8 сек)
- Модалка ввода никнейма (name-modal, localStorage 'hamsterName')
- Модалка комментария к рекорду (comment-modal, PATCH в Supabase)
- A2HS баннер (beforeinstallprompt + iOS инструкция)
- Победный экран: анимация хомяка (~3.5 сек, WIN_DUR=210 фреймов) → win screen с leaderboard
- Проигрыш: overlay "КОНЕЦ" + модалка ника

### Supabase (онлайн рекорды)
- URL: `https://ytipfibgtnrvtsygetnb.supabase.co`
- Таблица: `scores` (id, uid, name, time, date, comment)
- Игрок идентифицируется по `hamsterUID` из localStorage
- Загрузка при старте + каждые 15 сек на сплэше, каждые 8 сек в панели

---

## Цель разработки: перенос на Godot 4

### Решение принято
Пользователь выбрал **Godot 4** для дальнейшего развития игры (не Electron).
- Причина: кроссплатформенный экспорт (Windows/Mac/Linux/Android/iOS/Web), лучшая графика, нативная производительность, визуальный редактор уровней

### Что переносится 1:1 (почти дословно)
- `makeMaze()` → `maze_generator.gd` (recursive backtracking, тот же алгоритм)
- `bfs()` → `bfs_pathfinder.gd` (BFS, Array вместо queue)
- `updateLlama()` + AI состояния → `llama_ai.gd`
- `rhUpdate()` + rabbit holes логика → `rh_manager.gd`
- Supabase fetch → `HTTPRequest` нода (те же заголовки, тот же REST API)

### Соответствие компонентов HTML → Godot 4
| HTML/JS | Godot 4 |
|---|---|
| Canvas 2D (CELL=36) | TileMap, TileSet 36x36 px |
| drawMaze() | TileMap слой |
| drawHamster() / drawLlama() | CharacterBody2D + _draw() или AnimatedSprite2D |
| drawFog() evenodd | CanvasItem шейдер или Light2D + CanvasModulate |
| requestAnimationFrame loop | _process(delta) |
| mTimer (frame counter) | delta накопление |
| Web Audio API | AudioStreamGenerator или .ogg файлы |
| BG_MEL/BG_BASS массивы | AudioStreamPlayer + генератор |
| Supabase fetch | HTTPRequest нода |
| localStorage | FileAccess / ConfigFile |
| Mobile d-pad HTML | TouchScreenButton нода |
| Splash screen HTML | Сцена SplashScreen.tscn (Control ноды) |
| PWA manifest | Godot export настройки |

### Запланированная структура проекта Godot 4
```
hamster_maze_godot/
├── project.godot
├── scenes/
│   ├── Main.tscn
│   ├── Maze.tscn               ← TileMap + maze_generator.gd
│   ├── Hamster.tscn            ← CharacterBody2D
│   ├── Llama.tscn              ← CharacterBody2D + llama_ai.gd
│   ├── RabbitHolePair.tscn
│   └── UI/
│       ├── HUD.tscn
│       └── SplashScreen.tscn
├── scripts/
│   ├── maze_generator.gd
│   ├── bfs_pathfinder.gd
│   ├── llama_ai.gd
│   ├── rh_manager.gd
│   ├── game_manager.gd
│   └── leaderboard.gd
├── shaders/
│   └── fog_of_war.gdshader
└── assets/
	└── sounds/
```

### Этапы переноса
1. **Этап 1** — Лабиринт + BFS (maze_generator.gd, bfs_pathfinder.gd) ~1 неделя
2. **Этап 2** — Хомяк + движение (CharacterBody2D) ~2-3 дня
3. **Этап 3** — AI лам (синяя + красная) ~1 неделя
4. **Этап 4** — Орехи, волны, норы, порталы ~1 неделя
5. **Этап 5** — Туман войны (шейдер fog_of_war.gdshader) ~2-3 дня
6. **Этап 6** — HUD + UI (Control ноды) ~1 неделя
7. **Этап 7** — Звук + Supabase leaderboard ~1 неделя
8. **Этап 8** — Мобильные контролы + экспорт ~2-3 дня

### Что улучшится в Godot 4 vs HTML
- Туман войны — шейдер вместо Canvas clip, визуально лучше
- Анимации — AnimatedSprite2D вместо Canvas draw
- Звук — пространственный AudioStreamPlayer
- Мобайл — нативный APK
- Производительность — 60fps стабильно
- Редактирование — TileMap редактор для уровней

---

## История диалога

### Сессия 1 (2026-03-05)
- Открыт файл `hamster_maze.html` в VSCode
- Привязка к репозиторию https://github.com/AndriiDiabolus/Diabolus-Repository.git
- Создан CLAUDE.md с контекстом проекта

### Сессия 2 (2026-03-05, продолжение)
- Обсуждение вариантов переноса игры: Electron vs Godot 4
- **Решение:** развивать игру на Godot 4
- Прочитан полный код `hamster_maze.html` (1895 строк)
- Составлен детальный план переноса на Godot 4 с анализом реального кода
- Новый репозиторий для Godot 4 версии: https://github.com/AndriiDiabolus/Diabolus-repository-Godot4-hamster-maze.git
- Remote обновлён, проект запушен в новый репозиторий
- Обновлён CLAUDE.md с полным контекстом

### Текущий статус
- HTML версия (Test 3.1): завершена, запушена в новый репозиторий
- Godot 4 версия: не начата, ожидает старта разработки
- Следующий шаг: установить Godot 4.3+, создать проект, написать maze_generator.gd
