# Open Nokia 3310 — Tang Nano 20K

Порт **оригинальной прошивки Nokia 3310 (NHM-5, DCT3)** на Tang Nano 20K.
Интерфейсы платы взяты из [open-pocket-gbc](https://github.com/LakoMoor/open-pocket-gbc).
Управление — DualShock 2 через адаптер Sipeed; экраны — HDMI и ST7735S 128×128.

**Оригинальная прошивка v6.39 PPM W загружается на Tang Nano 20K.**
На HDMI проверены английское меню, список языков и применение русского языка.
Проверка стабильности SIM и физического контроллера продолжается; GSM-радиотракт отсутствует.

## Что реализовано

- ARM7TDMI-S ARM/Thumb с big-endian шиной, соединённый с начальной моделью MAD2.
- MAD2: матрица клавиш 3310, команды LCD через GENSIO, Timer0/Timer1,
  IRQ/FIQ, начальная модель CCONT ADC/RTC. Неизвестные обращения отмечаются
  сигналом `unsupported_mmio`; readback shadow-регистров не означает реализацию устройства.
- PCD8544: 504 байта DDRAM, горизонтальная/вертикальная адресация,
  extended commands, blank/all-on/normal/inverse, power-down и два порта чтения.
- Общий буфер 84×48 для HDMI и ST7735S. HDMI: 720×480, увеличение 8×
  до 672×384, поля 24/48 пикселей. ST7735S: 1:1, смещение 22/40 пикселей.
- DualShock: проверка ID/ответа, публикация пары кнопочных байтов, цифровой слой.
- Диагностический USB-UART: команды PCD8544 и дистанционные клавиши.
- Подготовлены образы v5.79 и v6.39 W (русский/английский); подробности в [firmware/README.md](firmware/README.md).

## Цели сборки

| Цель | Содержимое | Степень готовности |
|---|---|---|
| `nokia_io_top` | HDMI + ST7735S + DualShock + UART | Собираемый диагностический битстрим; CPU отсутствует |
| `arm7_probe` | ARM7TDMI-S, big-endian | Синтез для оценки ресурсов, не битстрим платы |
| `nokia_core` | ARM + MAD2 + NOR + ROM6 device service | Внешняя шина памяти; проверяется оригинальным ROM в симуляции |
| `nokia_top` | ARM + SDRAM + SPI loader + оба дисплея + DualShock | Timing пройден, оригинальное меню проверено на HDMI |

Нужны Python 3, OSS CAD Suite с yosys-slang/nextpnr-himbaechel/Apicula.
Для симуляций нужны Verilator и g++ с C++20. Путь по умолчанию —
`E:/tools/oss-cad-suite`, его можно изменить через `--tools` или `TOOLS`.

```powershell
python tools/test.py
python tools/build.py nokia_io_top
python tools/build.py nokia_core --synth-only
```

Битстрим: `build/nokia_io_top/nokia_io_top.fs`. Сборка прерывается при
ошибках синтеза, размещения, timing или упаковки; `--timing-allow-fail` не используется.
Диагностическая цель загружена на физическую плату; пользователь подтвердил рамку по HDMI. Полная сборка телефона пока отлаживается.

Для временной загрузки диагностической цели в SRAM:

```powershell
openFPGALoader -b tangnano20k build/nokia_io_top/nokia_io_top.fs
python -m pip install pyserial
python tools/lcd_remote.py COM6
python tools/capture_hdmi.py
```

На обоих дисплеях должна появиться прямоугольная рамка. Можно передать
`--frame file.bin` с 504 байтами DDRAM. Пустой экран до передачи кадра — ожидаемое
состояние диагностической цели. S1 сбрасывает её, LED0 показывает готовность
буфера, LED1 — нажатие кнопок. UART TX пока постоянно в idle.

## Подключение

Распиновка соответствует указанному репозиторию. Питание ST7735S — 3,3 В.

| ST7735S | Номер вывода FPGA |
|---|---:|
| SCL/SCK | 73 |
| SDA/MOSI | 74 |
| RES | 71 |
| DC/A0 | 72 |
| CS | 53 |
| BL | 52 |

HDMI — разъём платы. DualShock: CLK 17, CS 18, MISO 19, MOSI 20 (адаптер Sipeed).
Все номера — package pin из CST, а не порядковые контакты разъёма.
Параметры панели по умолчанию унаследованы: MADCTL=C8, X offset=2, Y offset=3.
Для других вариантов ST7735 ориентация/смещения могут потребовать настройки.

| DualShock | Клавиша Nokia | При удержании L1 |
|---|---|---|
| D-pad ↑/↓ | ↑/↓ | 2/8 |
| D-pad ←/→ | 4/6 | 4/6 |
| ○ / ✕ | Menu / C | 3 / 5 |
| △ / □ | 2 / 8 | 1 / 0 |
| R2 / L2 | — | 7 / 9 |
| Select / Start | — / Power | * / # |

В `nokia_top` контроллер напрямую управляет матрицей клавиатуры оригинальной
прошивки. Удержание кнопки передаётся телефону, повтор выполняет сама прошивка.
Отключение/неверный ответ контроллера отпускает все кнопки. Все кнопки обеих
раскладок проверяются тестом keypad; транспорт DS2 проверяется отдельно.

## Проверки

`tools/test.py` выполняет fail-hard проверки PCD8544 (все 4032 пикселя), всех
клавиш матрицы, MMIO byte/halfword lanes, LCD/CCONT/IRQ/FIQ, UART,
центровки кадра на ST7735 и границ HDMI. `core_smoke` исполняет небольшой
открытый диагностический ARM→Thumb код через настоящий RTL CPU с wait states
и проверяет ровно четыре записи LCD. Это не тест загрузки Nokia ROM.

Отдельная ограниченная трассировка оригинальной прошивки:

```powershell
python tools/trace_firmware.py firmware/nokia3310.bin
```

Она исполняет ограниченное число тактов RTL (`--cycles`) с моделью памяти на ПК, печатает
неподдерживаемые MMIO и количество LCD/NOR обращений. NOR-команды обрабатывает RTL `nor_bus`. Результат — `build/boot_trace/trace.log`; успешное завершение
трассировщика **не означает загрузку телефона**.

## Текущая интеграция и оставшиеся проверки

`nokia_top` соединяет ARM с SDRAM, загрузчиком SPI flash и обоими дисплеями.
Исходный ROM должен лежать в SPI flash по адресу `0x200000`; loader очищает
RAM, копирует 2 МиБ ROM в SDRAM и запускает reset trampoline на `0x200040`.
NOR program/erase меняет рабочую копию в SDRAM; сохранение этих изменений
обратно в SPI flash пока не реализовано.

Виртуальная SIM содержит тестовые файлы и отключённый PIN. ATR, T=0,
SELECT/STATUS/GET RESPONSE, READ/UPDATE BINARY/RECORD проверяются RTL-тестом.
Нет реального абонентского ключа. DSP ROM6 service реализует загрузочные
mailbox, локальные ответы и idle telemetry; это модель устройства, а не
полная реализация C54x. Меню и изображения исполняет оригинальный ARM ROM.

Оригинальный v5.79 в симуляции прошёл распознавание SIM и вывел установку
времени. Продолжается проверка управления, меню, игр и полного битстрима
на реальной плате. Последний стандартный вариант синтеза не разместился
при 93% LUT; вариант без wide LUT уменьшил загрузку до 75%:

```powershell
python tools/build.py nokia_top --lut4-only
python tools/trace_firmware.py firmware/nokia3310.bin --cycles 250000000
python tools/key_remote.py COM6 menu
python tools/capture_hdmi.py
```

`--keys file.txt` в трассировщике позволяет задавать клавиши строками
`absolute_cycle hex_key_mask`; файл перечитывается во время работы.
Промежуточные кадры сохраняются через 25 млн тактов в `build/boot_trace/`.
Ограниченный прогон сам по себе не подтверждает рабочую загрузку телефона.

Радиотракт GSM в этом проекте не реализован. Источники, версии и лицензии:
[docs/PROVENANCE.md](docs/PROVENANCE.md). Текущие результаты и физические
проверки — [docs/STATUS.md](docs/STATUS.md).
