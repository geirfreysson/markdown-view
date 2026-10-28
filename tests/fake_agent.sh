#!/bin/sh
# Deterministic CLI fixture. No model requests, auth, or user configuration access.
if [ "$1" = app-server ]; then
    while IFS= read -r line; do
        case "$line" in
            *'"method":"initialize"'*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *config/read*)
                printf '%s\n' '{"id":1,"result":{"config":{"developer_instructions":"Existing instructions: keep quotes \"and\" Unicode ü.\nSecond line."}}}' ;;
        esac
    done
else
    printf '%s\0' "$@" > "${MDV_TEST_ARGUMENTS:-mdv-captured.args}"
    exec /bin/cat
fi
