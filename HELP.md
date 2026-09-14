# AEInstall — краткая помощь

`AEinstall.sh` — установщик и менеджер экземпляра AECored для ActiV-Energy.

## Синтаксис

```bash
./AEinstall.sh --userid <userid>
./AEinstall.sh --userid <userid> --drivers <driver1,driver2,...>
./AEinstall.sh --update --userid <userid>
./AEinstall.sh --remove --userid <userid>
./AEinstall.sh --help
./AEinstall.sh -h
```

## Команды

### Установка

```bash
./AEinstall.sh --userid 45
```

Создаёт окружение ActiV-Energy, Python virtual environment, загружает AECored из GitHub, создаёт конфигурацию и systemd-сервис `45_AECored.service`, затем запускает сервис.

### Установка с указанием драйверов

```bash
./AEinstall.sh --userid 45 --drivers itron761,gama
```

Параметр `--drivers` принимает список драйверов через запятую. В текущей версии список сохраняется только как параметр команды и ещё не используется для автоматической установки драйверов.

### Обновление AECored

```bash
./AEinstall.sh --update --userid 45
```

Останавливает текущий сервис, удаляет старую версию AECored, загружает свежую версию из GitHub, сохраняет пользовательскую конфигурацию и запускает обновлённый сервис.

### Удаление AECored

```bash
./AEinstall.sh --remove --userid 45
```

Удаляет systemd-сервис, код AECored и файл конфигурации AECored. Каталоги `drivers`, `data`, `logs`, `run` и virtual environment не удаляются.

### Помощь

```bash
./AEinstall.sh --help
```

или:

```bash
./AEinstall.sh -h
```

Показывает краткую справку прямо в терминале.

## Основные ограничения

- Установщик нельзя запускать от `root`.
- Для установки системных пакетов требуется `sudo`.
- `--userid` обязателен для всех операций.
- `--userid` должен быть положительным целым числом.
- Целевой каталог установки: `~/activ-energy/`.
- Экземпляр AECored работает как отдельный systemd-сервис `<userid>_AECored.service`.
