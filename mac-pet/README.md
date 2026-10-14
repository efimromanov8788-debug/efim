# Исходный код Мурки

Как установить готовую программу — в [README в корне репозитория](../README.md).

## Сборка

```bash
./build.sh
open build/Murka.app
```

Нужны Xcode Command Line Tools (`xcode-select --install`). Сборка сразу для Apple Silicon и Intel, macOS 12+.

## Устройство

- `Sources/App.swift` — запуск, строка меню, список котов, общий игровой цикл, поиск окон других программ;
- `Sources/Pet.swift` — один кот: его окно, поведение по характеру, прогулки по полу, окнам, стенам и потолку;
- `Sources/CatRenderer.swift` — рисование кота кодом по внешности и позе;
- `Sources/CatModel.swift` — внешность, характеры, фразы, готовые коты и сохранение;
- `Sources/Editor.swift` — окно настройки на SwiftUI с живым превью.
