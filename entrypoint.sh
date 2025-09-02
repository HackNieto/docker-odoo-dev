#!/bin/bash

set -e

if [ -v PASSWORD_FILE ]; then
    PASSWORD="$(< $PASSWORD_FILE)"
fi

# set the postgres database host, port, user and password according to the environment
# and pass them as arguments to the odoo process if not present in the config file
: ${HOST:=${DB_PORT_5432_TCP_ADDR:='db'}}
: ${PORT:=${DB_PORT_5432_TCP_PORT:=5432}}
: ${USER:=${DB_ENV_POSTGRES_USER:=${POSTGRES_USER:='odoo'}}}
: ${PASSWORD:=${DB_ENV_POSTGRES_PASSWORD:=${POSTGRES_PASSWORD:='odoo'}}}

DB_ARGS=()
function check_config() {
    param="$1"
    value="$2"
    if grep -q -E "^\s*\b${param}\b\s*=" "$ODOO_RC" ; then
        value=$(grep -E "^\s*\b${param}\b\s*=" "$ODOO_RC" |cut -d " " -f3|sed 's/["\n\r]//g')
    fi;
    DB_ARGS+=("--${param}")
    DB_ARGS+=("${value}")
}
check_config "db_host" "$HOST"
check_config "db_port" "$PORT"
check_config "db_user" "$USER"
check_config "db_password" "$PASSWORD"

# Función para ejecutar Odoo con o sin debugpy
run_odoo() {
    wait-for-psql.py ${DB_ARGS[@]} --timeout=30

    if [ -n "$DEBUGPY" ]; then
        DEBUGPY_PORT=${DEBUGPY_PORT:-5678}
        # Variables de entorno para mejorar la compatibilidad con debugpy
        export PYDEVD_DISABLE_FILE_VALIDATION=1
        export PYDEVD_WARN_SLOW_RESOLVE_TIMEOUT=10
        # Argumentos para Python que mejoran la compatibilidad
        PYTHON_ARGS="-Xfrozen_modules=off -u"
        # Argumentos adicionales para debugpy que mejoran la estabilidad
        DEBUGPY_ARGS="--listen 0.0.0.0:$DEBUGPY_PORT"
        # Solo agregar --wait-for-client si está habilitado
        if [ "$DEBUGPY_WAIT" = "1" ]; then
            DEBUGPY_ARGS="$DEBUGPY_ARGS --wait-for-client"
        fi
        # Agregar argumentos para mejorar la compatibilidad con Odoo
        ODOO_ARGS="$@ ${DB_ARGS[@]}"
        # Si no hay --max-cron-threads, agregarlo para evitar problemas con cron
        if ! [[ "$ODOO_ARGS" =~ --max-cron-threads ]]; then
            ODOO_ARGS="$ODOO_ARGS --max-cron-threads=1"
        fi
        # Si no hay --workers y no está en modo dev, usar 0 workers para evitar problemas
        if ! [[ "$ODOO_ARGS" =~ --workers ]] && ! [[ "$ODOO_ARGS" =~ --dev ]]; then
            ODOO_ARGS="$ODOO_ARGS --workers=0"
        fi
        exec python3 $PYTHON_ARGS -m debugpy $DEBUGPY_ARGS /usr/bin/odoo $ODOO_ARGS
    else
        exec odoo "$@" "${DB_ARGS[@]}"
    fi
}

case "$1" in
    odoo)
        # Si el primer argumento es 'odoo', lo quitamos y pasamos el resto
        shift
        if [[ "$1" == "scaffold" ]] ; then
            exec odoo "$@"
        else
            run_odoo "$@"
        fi
        ;;
    -*)
        # Si empieza con '-', son argumentos para odoo
        run_odoo "$@"
        ;;
    *)
        # Si no es 'odoo' ni empieza con '-', ejecutamos el comando tal como viene
        exec "$@"
        ;;
esac

exit 1
