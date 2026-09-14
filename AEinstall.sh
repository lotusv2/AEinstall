#!/bin/bash

# Установщик ActiV-Energy
# Создание базового окружения клиента.

set -e

APP_NAME="ActiV-Energy Core"
INSTALL_DIR="${HOME}/activ-energy"

USER_ID=""
DRIVERS=""

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

Параметры:

    --userid    Идентификатор клиента ActiV-Energy.
    --drivers   Список драйверов для установки.

Пример:

    ./AEinstall.sh --userid 45 --drivers itron761,gama
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

    if ! [[ "${USER_ID}" =~ ^[0-9]+$ ]]; then
        print_error "Параметр --userid должен содержать целое число."
        exit 1
    fi
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

    if [ "${#packages[@]}" -eq 0 ]; then
        print_info "Python 3 и python3-venv уже установлены."
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

show_result()
{
    echo
    echo "========================================"
    echo " ${APP_NAME}: установка завершена"
    echo "========================================"
    echo
    echo "Клиент:       ${USER_ID}"
    echo "Каталог:      ${INSTALL_DIR}"
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
    create_directories
    create_venv
    verify_environment
    show_result
}

main "$@"
