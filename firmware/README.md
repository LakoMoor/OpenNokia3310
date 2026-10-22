# Локальные образы Nokia 3310

Образы в этой папке исключены из Git. Скачан архив
[Planet Emulation — noki3310](https://www.planetemu.net/en/rom/mame-roms-merged/noki3310)
21 октября 2026 года. В `mame/` лежат исходные файлы без изменений.

`nokia3310.bin` — копия полного дампа **v5.79, PPM N**, 2 097 152 байта.
SHA-1 исходника: `649de05ed88205a080693b918cd1295ac691dff1`.
SHA-256: `14f5f650de01cccee9e4d12b6c1c132e60df1d24cf97cbb95efe94840d2bfaf1`.
SHA-1 сверена с [MAME](https://github.com/mamedev/mame/blob/master/src/mame/nokia/nokia_3310.cpp).
EEPROM внутри полного дампа сохранена; отдельный virgin EEPROM автоматически не подмешивается.

В архиве также есть полный v6.07 (SHA-1
`0e80b5f1698909c9850be770c1289566582aa77a`), v5.13, отдельная
EEPROM/PM на 192 КиБ и сервисные контейнеры обновления v6.39.
Последние нельзя подавать как линейный образ flash: их сначала нужно распаковать.

Повторная подготовка:

```powershell
python tools/prepare_firmware.py "firmware/mame/3310 nr1 v5.79.fls"
```

`--eeprom <file>` явно заменяет раздел образа `0x1D0000..0x1FFFFF`.
Образ телефона отображается на `0x200000..0x3FFFFF`, точка входа `0x200040`.
Смещение образа в SPI flash платы — `0x200000`. Цель `nokia_top` аппаратно
копирует образ в SDRAM и запускает ARM. FPGA-конфигурация загружается в SRAM.

## Русский и английский: v6.39 W

22 октября скачан `https://nokia-moding.narod.ru/download/3310w639.rar`.
Внутри линейный `3310w639.fls`, 0x1D0000 байт, MCU+PPM W.
SHA256: `11f86ac4f350d279a536963f8834ddc5eae064f5e615d396875d85229c58cc96`.
Все 1 248 256 MCU-байт совпадают с распакованным сервисным `nhm5ny06.390`
из MAME. Языки: English, Eesti, Русский, Deutsch (и Automatic).
На реальной Tang подтверждены английское меню и применение русского языка.

Полный `nokia3310-v639-w.bin` дополнен явной EEPROM/PM из сохранённого v5.79.
SHA256: `5cd18ff08b40f44c9dbe155bc09efbcea15b5037234fa9d54b3e43bac8fcc8a2`.
Записан на плату с `openFPGALoader --verify`. Исходный v5.79 не удалён,
дополнительная копия — `backups/nokia3310-v579-ppm-n.bin`.

```powershell
python tools/prepare_firmware.py firmware/3310w639/3310w639.fls --eeprom firmware/donor-v579-eeprom.bin --output firmware/nokia3310-v639-w.bin
```

Выбор языка: Menu → Settings (6) → Phone settings (2) → Language (1).
Изменения EEPROM пока живут только в SDRAM и теряются при перезапуске.
