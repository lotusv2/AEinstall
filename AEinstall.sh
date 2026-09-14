#!/bin/bash

# Установщик ActiV-Energy.
# Создание базового окружения клиента и установка AECored как systemd-сервиса.

set -e

APP_NAME="ActiV-Energy Core"
INSTALL_DIR="${HOME}/activ-energy"
AECORDED_REPOSITORY="https://github.com/lotusv2/AECored_1.2.git"
AECORDED_SERVICE=""

USER_ID=""
DRIVERS=""
ACTION="install"

print_error()
{
    echo "ERROR: $1" >&2
}

print_info()
{
    echo "INFO: $1"
}

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

Примеры:

    ./AEinstall.sh --userid 45 --drivers test_driver
    ./AEinstall.sh --userid 45 --drivers test_driver,itron761,gama
    ./AEinstall.sh --update --userid 45
    ./AEinstall.sh --remove --userid 45
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
                if [ -z "${2:-}" ]; then
                    print_error "Параметр --userid требует значения."
                    exit 1
                fi

                USER_ID="$2"
                shift 2
                ;;

            --drivers)
                if [ -z "${2:-}" ]; then
                    print_error "Параметр --drivers требует значения."
                    exit 1
                fi

                DRIVERS="$2"
                shift 2
                ;;

            --update)
                ACTION="update"
                shift
                ;;

            --remove)
                ACTION="remove"
                shift
                ;;

            --help|-h)
                print_usage
                exit 0
                ;;

            *)
                print_error "Неизвестный параметр: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    if [ -z "${USER_ID}" ]; then
        print_error "Не указан обязательный параметр --userid."
        print_usage
        exit 1
    fi

    if ! [[ "${USER_ID}" =~ ^[0-9]+$ ]] || [ "${USER_ID}" -lt 1 ]; then
        print_error "Параметр --userid должен содержать положительное целое число."
        exit 1
    fi

    AECORDED_SERVICE="${USER_ID}_AECored.service"
}

install_system_packages()
{
    local packages=()

    if ! command -v python3 >/dev/null 2>&1; then
        packages+=(python3)
    fi

    if ! dpkg-query -W -f='${Status}' python3-venv 2>/dev/null | grep -q "install ok installed"; then
        packages+=(python3-venv)
    fi

    if ! command -v git >/dev/null 2>&1; then
        packages+=(git)
    fi

    if [ "${#packages[@]}" -eq 0 ]; then
        print_info "Python 3, python3-venv и git уже установлены."
        return
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        print_error "Для установки системных пакетов требуется sudo."
        print_error "Установите sudo или установите вручную: ${packages[*]}"
        exit 1
    fi

    print_info "Требуются системные пакеты: ${packages[*]}"
    print_info "Для их установки потребуется пароль sudo."

    sudo apt-get update
    sudo apt-get install -y "${packages[@]}"
}

check_python()
{
    if ! command -v python3 >/dev/null 2>&1; then
        print_error "Python 3 не найден после установки."
        exit 1
    fi

    PYTHON_VERSION="$(python3 --version 2>&1)"
    print_info "Найден ${PYTHON_VERSION}."
}

check_python_venv()
{
    if ! dpkg-query -W -f='${Status}' python3-venv 2>/dev/null | grep -q "install ok installed"; then
        print_error "Пакет python3-venv не установлен."
        exit 1
    fi

    print_info "Пакет python3-venv установлен."
}

create_directories()
{
    print_info "Создание структуры ${INSTALL_DIR}..."

    mkdir -p \
        "${INSTALL_DIR}/core" \
        "${INSTALL_DIR}/drivers" \
        "${INSTALL_DIR}/config" \
        "${INSTALL_DIR}/data" \
        "${INSTALL_DIR}/logs" \
        "${INSTALL_DIR}/run" \
        "${INSTALL_DIR}/venv"
}

create_venv()
{
    print_info "Создание Python virtual environment..."

    if [ -x "${INSTALL_DIR}/venv/bin/python" ]; then
        print_info "Python environment уже существует."
        return
    fi

    rm -rf "${INSTALL_DIR}/venv"
    python3 -m venv "${INSTALL_DIR}/venv"

    print_info "Python environment создан."
}

verify_environment()
{
    if [ ! -x "${INSTALL_DIR}/venv/bin/python" ]; then
        print_error "Не удалось создать Python environment."
        exit 1
    fi

    "${INSTALL_DIR}/venv/bin/python" --version
    print_info "Python environment проверен."
}

create_aecored_config()
{
    mkdir -p "${INSTALL_DIR}/config"

    cat > "${INSTALL_DIR}/config/aecored.ini" <<EOF
[aecored]
# Идентификатор пользователя ActiV-Energy.
user_id = ${USER_ID}
EOF
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

install_test_driver()
{
    local driver_name="test_driver"
    local source_file="${INSTALL_DIR}/core/tests/test_driver.py"
    local target_file="${INSTALL_DIR}/drivers/${driver_name}.py"

    if [[ ",${DRIVERS}," != *",${driver_name},"* ]]; then
        return
    fi

    if [ ! -f "${source_file}" ]; then
        print_error "Тестовый драйвер не найден в AECored: ${source_file}"
        exit 1
    fi

    cp "${source_file}" "${target_file}"
    chmod 755 "${target_file}"
    print_info "Тестовый драйвер установлен: ${target_file}"
}

stop_aecored_service()
{
    if sudo systemctl is-active --quiet "${AECORDED_SERVICE}"; then
        print_info "Остановка ${AECORDED_SERVICE}..."
        sudo systemctl stop "${AECORDED_SERVICE}"
    else
        print_info "${AECORDED_SERVICE} не запущен."
    fi
}

remove_aecored_service()
{
    stop_aecored_service

    if sudo systemctl is-enabled --quiet "${AECORDED_SERVICE}" 2>/dev/null; then
        sudo systemctl disable "${AECORDED_SERVICE}"
    fi

    if [ -f "/etc/systemd/system/${AECORDED_SERVICE}" ]; then
        sudo rm -f "/etc/systemd/system/${AECORDED_SERVICE}"
    fi

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

    print_info "Загрузка AECored из GitHub..."
    git clone --depth 1 "${AECORDED_REPOSITORY}" "${temp_dir}/AECored_1.2"

    rm -rf "${INSTALL_DIR}/core"
    mkdir -p "${INSTALL_DIR}/core"
    cp -a "${temp_dir}/AECored_1.2/aecored" "${INSTALL_DIR}/core/"
    cp -a "${temp_dir}/AECored_1.2/tests" "${INSTALL_DIR}/core/"

    rm -rf "${temp_dir}"
}

install_aecored()
{
    print_info "Установка AECored для пользователя ${USER_ID}..."

    stop_aecored_service || true
    remove_aecored_service
    clone_aecored
    create_aecored_config
    create_scheduler_config
    install_test_driver
    install_aecored_service

    sudo systemctl start "${AECORDED_SERVICE}"

    print_info "AECored установлен и запущен как ${AECORDED_SERVICE}."
}

update_aecored()
{
    if [ ! -d "${INSTALL_DIR}/core" ]; then
        print_error "AECored не установлен. Сначала выполните обычную установку."
        exit 1
    fi

    print_info "Обновление AECored для пользователя ${USER_ID}..."
    print_info "Текущие конфигурации будут сохранены."

    stop_aecored_service
    remove_aecored_service

    clone_aecored
    install_aecored_service

    sudo systemctl start "${AECORDED_SERVICE}"

    print_info "AECored обновлён и запущен."
}

remove_aecored()
{
    print_info "Удаление AECored для пользователя ${USER_ID}..."

    remove_aecored_service
    rm -rf "${INSTALL_DIR}/core"
    rm -f "${INSTALL_DIR}/config/aecored.ini"
    rm -f "${INSTALL_DIR}/config/scheduler.ini"

    print_info "AECored удалён. Остальные каталоги ActiV-Energy сохранены."
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
