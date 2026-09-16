#!/bin/bash

# Установщик ActiV-Energy.
# Создание базового окружения клиента и установка AECored как systemd-сервиса.

set -e

APP_NAME="ActiV- Energy Core"
INSTALL_DIR="${HOME}/activ-energy"
AECORDED_REPOSITORY="https://github.com/lotusv2/AECored_1.2.git"
AECORDED_SERVICE=""

USER_ID=""
DRIVERS=""
ACTION="install"

print_error() { echo "ERROR: $1" >&2; }
print_info() { echo "INFO: $1"; }

print_usage()
{
    cat <<EOF
Использование:

    ./AEinstall.sh --userid <userid> [--drivers <driver1,driver2,...>]
    ./AEinstall.sh --update --userid <userid>
    ./AEinstall.sh --remove --userid <userid>

Параметры:

    --userid    Идентификатор клиента ActiV-Energy.
    --drivers   Список драйверов для установки.
    --update    Обновить AECored из GitHub.
    --remove    Удалить AECored и его systemd-сервис.
EOF
}

check_root()
{
    if [ "$(id -u)" -eq 0 ]; then
        print_error "Установщик нельзя запускать от root."
        exit 1
    fi
}

parse_arguments()
{
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --userid)
                [ -n "${2:-}" ] || { print_error "Параметр --userid требует значения."; exit 1; }
                USER_ID="$2"; shift 2 ;;
            --drivers)
                [ -n "${2:-}" ] || { print_error "Параметр --drivers требует значения."; exit 1; }
                DRIVERS="$2"; shift 2 ;;
            --update) ACTION="update"; shift ;;
            --remove) ACTION="remove"; shift ;;
            --help|-h) print_usage; exit 0 ;;
            *) print_error "Неизвестный параметр: $1"; print_usage; exit 1 ;;
        esac
    done

    [ -n "${USER_ID}" ] || { print_error "Не указан обязательный параметр --userid."; print_usage; exit 1; }
    if ! [[ "${USER_ID}" =~ ^[0-9]+$ ]] || [ "${USER_ID}" -lt 1 ]; then
        print_error "Параметр --userid должен содержать положительное целое число."
        exit 1
    fi
    AECORDED_SERVICE="${USER_ID}_AECored.service"
}

install_system_packages()
{
    local packages=()
    command -v python3 >/dev/null 2>&1 || packages+=(python3)
    dpkg-query -W -f='${Status}' python3-venv 2>/dev/null | grep -q "install ok installed" || packages+=(python3-venv)
    command -v git >/dev/null 2>&1 || packages+=(git)

    if [ "${#packages[@]}" -eq 0 ]; then
        print_info "Python 3, python3-venv и git уже установлены."
        return
    fi
    command -v sudo >/dev/null 2>&1 || { print_error "Для установки системных пакетов требуется sudo."; exit 1; }
    sudo apt-get update
    sudo apt-get install -y "${packages[@]}"
}

check_python()
{
    command -v python3 >/dev/null 2>&1 || { print_error "Python 3 не найден после установки."; exit 1; }
    print_info "Найден $(python3 --version 2>&1)."
}

check_python_venv()
{
    dpkg-query -W -f='${Status}' python3-venv 2>/dev/null | grep -q "install ok installed" || { print_error "Пакет python3-venv не установлен."; exit 1; }
    print_info "Пакет python3-venv установлен."
}

create_directories()
{
    mkdir -p "${INSTALL_DIR}/core" "${INSTALL_DIR}/drivers" "${INSTALL_DIR}/config" "${INSTALL_DIR}/data" "${INSTALL_DIR}/logs" "${INSTALL_DIR}/run" "${INSTALL_DIR}/venv"
}

create_venv()
{
    if [ -x "${INSTALL_DIR}/venv/bin/python" ]; then
        print_info "Python environment уже существует."
        return
    fi
    rm -rf "${INSTALL_DIR}/venv"
    python3 -m venv "${INSTALL_DIR}/venv"
}

verify_environment()
{
    [ -x "${INSTALL_DIR}/venv/bin/python" ] || { print_error "Не удалось создать Python environment."; exit 1; }
    [ -x "${INSTALL_DIR}/venv/bin/pip" ] || { print_error "В Python environment не найден pip."; exit 1; }
    "${INSTALL_DIR}/venv/bin/python" --version
    "${INSTALL_DIR}/venv/bin/pip" --version
}

install_python_dependencies()
{
    local requirements_file="${INSTALL_DIR}/core/requirements.txt"
    if [ ! -f "${requirements_file}" ]; then
        print_error "Файл зависимостей не найден: ${requirements_file}"
        exit 1
    fi
    # pip уже устанавливается при создании venv. Обновлять его при каждом запуске установщика не требуется.
    "${INSTALL_DIR}/venv/bin/python" -m pip install -r "${requirements_file}"
}

install_aecored_config()
{
    local source_file="${INSTALL_DIR}/config/config.ini.template"
    local target_file="${INSTALL_DIR}/config/aecored.ini"

    [ -f "${source_file}" ] || {
        print_error "Шаблон конфигурации AECored не найден: ${source_file}"
        exit 1
    }

    cp "${source_file}" "${target_file}"
    rm -f "${source_file}"

    # Подставляем параметры конкретного экземпляра в шаблон из репозитория.
    sed -i -E "s|^user_id = .*|user_id = ${USER_ID}|" "${target_file}"
    sed -i -E "s|^root = .*|root = ${INSTALL_DIR}|" "${target_file}"
    sed -i -E "s|^config = .*|config = ${INSTALL_DIR}/config|" "${target_file}"
    sed -i -E "s|^logs = .*|logs = ${INSTALL_DIR}/logs|" "${target_file}"
    sed -i -E "s|^drivers = .*|drivers = ${INSTALL_DIR}/drivers|" "${target_file}"
    sed -i -E "s|^data = .*|data = ${INSTALL_DIR}/data|" "${target_file}"
    sed -i -E "s|^run = .*|run = ${INSTALL_DIR}/run|" "${target_file}"
    sed -i -E "/^\[http\]/,/^\[/{s|^password = .*|password = pass${USER_ID}|}" "${target_file}"
    sed -i -E "/^\[scheduler\]/,/^\[/{s|^config = .*|config = ${INSTALL_DIR}/config/scheduler.ini|}" "${target_file}"

    print_info "Конфигурация AECored установлена из шаблона репозитория."
}

create_scheduler_config()
{
    local scheduler_config="${INSTALL_DIR}/config/scheduler.ini"
    if [ -f "${scheduler_config}" ]; then
        print_info "Конфигурация Scheduler уже существует, она сохранена."
        return
    fi
    cat > "${scheduler_config}" <<EOF
# Конфигурация Scheduler ActiV-Energy.
# Задачи создаются установщиком из параметра --drivers.
# Расписание по умолчанию: каждые 5 минут.
EOF
    if [ -n "${DRIVERS}" ]; then
        IFS=',' read -ra DRIVER_LIST <<< "${DRIVERS}"
        for driver in "${DRIVER_LIST[@]}"; do
            driver="$(echo "${driver}" | xargs)"
            [ -z "${driver}" ] && continue
            cat >> "${scheduler_config}" <<EOF

[task:${driver}]
enabled = yes
command = ${INSTALL_DIR}/drivers/${driver}.py
schedule = */5 * * * *
EOF
        done
    fi
}

stop_aecored_service()
{
    if sudo systemctl is-active --quiet "${AECORDED_SERVICE}"; then sudo systemctl stop "${AECORDED_SERVICE}"; fi
}

remove_aecored_service()
{
    stop_aecored_service
    if sudo systemctl is-enabled --quiet "${AECORDED_SERVICE}" 2>/dev/null; then sudo systemctl disable "${AECORDED_SERVICE}"; fi
    [ -f "/etc/systemd/system/${AECORDED_SERVICE}" ] && sudo rm -f "/etc/systemd/system/${AECORDED_SERVICE}"
    sudo systemctl daemon-reload
}

install_aecored_service()
{
    local service_file="/tmp/${AECORDED_SERVICE}"
    local python_path="${INSTALL_DIR}/venv/bin/python"
    local config_path="${INSTALL_DIR}/config/aecored.ini"
    cat > "${service_file}" <<EOF
[Unit]
Description=ActiV-Energy AECored instance ${USER_ID}
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
NotifyAccess=main
User=${USER}
Group=$(id -gn)
WorkingDirectory=${INSTALL_DIR}/core
ExecStart=${python_path} -m aecored.aecored ${config_path}
Restart=on-failure
RestartSec=5
WatchdogSec=30s
TimeoutStartSec=30s
TimeoutStopSec=30s
KillSignal=SIGTERM
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONPATH=${INSTALL_DIR}/core

[Install]
WantedBy=multi-user.target
EOF
    sudo install -m 644 "${service_file}" "/etc/systemd/system/${AECORDED_SERVICE}"
    rm -f "${service_file}"
    sudo systemctl daemon-reload
    sudo systemctl enable "${AECORDED_SERVICE}"
}

clone_aecored()
{
    local temp_dir
    temp_dir="$(mktemp -d)"
    git clone --depth 1 "${AECORDED_REPOSITORY}" "${temp_dir}/AECored_1.2"

    # В конечную установку переносим только файлы, необходимые для работы AECored.
    rm -rf "${INSTALL_DIR}/core"
    mkdir -p "${INSTALL_DIR}/core" "${INSTALL_DIR}/config"
    cp -a "${temp_dir}/AECored_1.2/aecored" "${INSTALL_DIR}/core/"
    cp -a "${temp_dir}/AECored_1.2/requirements.txt" "${INSTALL_DIR}/core/"

    # Шаблон конфигурации нужен только при первичной установке.
    if [ ! -f "${INSTALL_DIR}/config/aecored.ini" ]; then
        cp -a "${temp_dir}/AECored_1.2/config/config.ini" "${INSTALL_DIR}/config/config.ini.template"
    fi

    # Тестовый драйвер устанавливается только если он выбран через --drivers.
    if [[ ",${DRIVERS}," == *",test_driver,"* ]]; then
        cp -a "${temp_dir}/AECored_1.2/tests/test_driver.py" "${INSTALL_DIR}/drivers/test_driver.py"
        chmod 755 "${INSTALL_DIR}/drivers/test_driver.py"
    fi

    rm -rf "${temp_dir}"
}

install_aecored()
{
    stop_aecored_service || true
    remove_aecored_service
    clone_aecored
    install_python_dependencies
    install_aecored_config
    create_scheduler_config
    install_aecored_service
    sudo systemctl start "${AECORDED_SERVICE}"
}

update_aecored()
{
    [ -d "${INSTALL_DIR}/core" ] || { print_error "AECored не установлен. Сначала выполните обычную установку."; exit 1; }
    stop_aecored_service
    remove_aecored_service
    clone_aecored
    install_python_dependencies
    install_aecored_service
    sudo systemctl start "${AECORDED_SERVICE}"
}

remove_aecored()
{
    remove_aecored_service
    rm -rf "${INSTALL_DIR}/core"
    rm -f "${INSTALL_DIR}/config/aecored.ini" "${INSTALL_DIR}/config/scheduler.ini" "${INSTALL_DIR}/config/config.ini.template"
}

show_result()
{
    echo
    echo "========================================"
    echo " ${APP_NAME}: операция завершена"
    echo "========================================"
    echo
    echo "Клиент:       ${USER_ID}"
    echo "Каталог:      ${INSTALL_DIR}"
    echo "Сервис:       ${AECORDED_SERVICE}"
    echo "HTTP-порт:    $((9000 + USER_ID))"
    echo "HTTP-пароль:  pass${USER_ID}"
    echo "Драйверы:     ${DRIVERS:-не указаны}"
    echo
}

main()
{
    parse_arguments "$@"
    check_root
    install_system_packages
    check_python
    check_python_venv
    case "${ACTION}" in
        install)
            create_directories
            create_venv
            verify_environment
            install_aecored
            ;;
        update)
            verify_environment
            update_aecored
            ;;
        remove)
            remove_aecored
            ;;
    esac
    show_result
}

main "$@"
