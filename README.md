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
│   ├── aecored/
│   ├── config.ini          # шаблон, скопированный из репозитория AECored
│   ├── tests/
│   └── requirements.txt
├── config/
│   ├── aecored.ini         # конфигурация экземпляра
│   └── scheduler.ini
├── drivers/
├── data/
├── logs/
├── run/
└── venv/
```

Шаблон основной конфигурации хранится в репозитории AECored по пути `config/config.ini`. Установщик не генерирует основной конфигурационный файл с нуля: он копирует шаблон, после чего подставляет `user_id`, пути конкретного экземпляра и пароль HTTP.

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

HTTP-порт для `user_id=45` — `9045` (`9000 + user_id`).

### Обновление AECored

При выпуске новой версии AECored достаточно выполнить:

```bash
./AEinstall.sh --update --userid 45
```

Установщик:

1. останавливает сервис;
2. отключает старый systemd unit;
3. загружает свежий `AECored_1.2` из GitHub;
4. обновляет Python-зависимости;
5. создаёт systemd unit заново;
6. выполняет `daemon-reload`;
7. включает сервис;
8. запускает новую версию.

Пользовательские `config/aecored.ini` и `config/scheduler.ini` при обновлении не заменяются. Каталоги `drivers`, `data` и `logs` также не затрагиваются.

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
