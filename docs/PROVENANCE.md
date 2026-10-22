# Источники

| Компонент | Источник и зафиксированный commit | Использование |
|---|---|---|
| Плата, HDMI, ST7735S | [LakoMoor/open-pocket-gbc](https://github.com/LakoMoor/open-pocket-gbc), `5e743424a308fb06b7de0923c02e6d0d1434b30b` | Скопированы HDMI RTL, `lcd_st7735`, `gb_color`, font8x8, PLL/primitive wrappers, placement helper; выбраны нужные ограничения выводов |
| ARM7TDMI-S | [birdybro/arm7tdmi-sv](https://github.com/birdybro/arm7tdmi-sv), `2b350d9c3902062329d9fdc55432fd4080bd88c9` | RTL с локальной поправкой IRQ/FIQ (см. `third_party/arm7tdmi-sv/LOCAL_CHANGES.md`); каноническая оболочка `arm7tdmi_mister`, `BIG_ENDIAN=1`, debug/coprocessor выключены |
| Поведение Nokia | [djr-747/nokia-dct3-emulator](https://github.com/djr-747/nokia-dct3-emulator), `2b4c10ffd6b22a2d021c7f515f27ceb2fb6c78cd` | Модель 3310, распиновка матрицы, регистры MAD2, LCD и CCONT использованы как спецификация для начальной HDL-модели |
| Контрольные суммы прошивки | [MAME nokia_3310.cpp](https://github.com/mamedev/mame/blob/master/src/mame/nokia/nokia_3310.cpp) | Проверка v5.79/v6.07; оригинальная прошивка не входит в исходники HDL |

Лицензия собственного HDL и интеграции — GPL-3.0-or-later, текст в `LICENSE`.
Лицензии двух скопированных репозиториев сохранены в `third_party/*/LICENSE`.
HDMI в Open Pocket происходит из [hdl-util/hdmi](https://github.com/hdl-util/hdmi),
автор Sameer Puri; MIT license сохранена в `third_party/open-pocket-gbc/rtl/hdmi/LICENSE-MIT`.
Font8x8 происходит из public-domain `font8x8_basic.h`;
исходное описание сохранено в `third_party/open-pocket-gbc/font8x8_basic.h`.

Контроллер DualShock реализован заново в `rtl/nokia/ds2_pad.sv`;
скопированный upstream `dualshock_controller.v` не используется.
Изменения файлов платы: оставлены только нужные группы выводов, SDC настроен
на 27/135 МГц для HDMI и 16,875 МГц для ARM/SDRAM. Имена PLL и CLKDIV сохранены ради размещения рядом с HDMI OSER10.

`reference/` — локальные shallow checkout для исследования, исключены из Git
и не нужны для сборки. Все необходимые для текущих целей RTL зависимости
находятся в `third_party/`; пути в ARM `files.f` адаптированы к этой структуре.
Upstream ARM-ядро само отмечено как prerelease;
его успешный синтез и наши smoke tests не доказывают полную совместимость телефона.
