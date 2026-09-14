# AEinstall

Установщик ActiV-Energy Core.

## AECored

Установщик создаёт отдельный экземпляр AECored для каждого `user_id` и запускает его как systemd-сервис.

### Новая установка

```bash
./AEinstall.sh --userid 45
```

После установки:

```text
~/activ-energy/
├── core/
│   └── aecored/
├── config/
│   └── aecored.ini
├── drivers/
├── data/
├── logs/
├── run/
└── venv/
```

Сервис получает имя:

```text
45_AECored.service
```

и автоматически включается в автозапуск Debian.

Проверка:

```bash
systemctl status 45_AECored.service
journalctl -u 45_AECored.service -f
```

### Обновление AECored

При выпуске новой версии AECored достаточно выполнить:

```bash
./AEinstall.sh --update --userid 45
```

Установщик:

1. останавливает сервис;
2. отключает старый systemd unit;
3. удаляет старый код AECored из памяти/файловой системы;
4. загружает свежий `AECored_1.2` из GitHub;
5. сохраняет существующую конфигурацию клиента;
6. создаёт systemd unit заново;
7. выполняет `daemon-reload`;
8. включает сервис;
9. запускает новую версию.

Каталоги `drivers`, `data` и `logs` при обновлении не затрагиваются.

### Удаление AECored

```bash
./AEinstall.sh --remove --userid 45
```

Удаляется systemd-сервис, код AECored и его конфигурация. Остальное окружение ActiV-Energy сохраняется.

## Системные требования

Установщик проверяет наличие:

- Python 3;
- `python3-venv`;
- `git`;
- `sudo` для установки недостающих системных пакетов.

Установщик запускается обычным пользователем, не от `root`.
