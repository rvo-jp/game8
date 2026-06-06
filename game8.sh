#!/usr/bin/env bash

set -euo pipefail

APP_NAME="game8-post"
SYSTEMD_DIR="/etc/systemd/system"
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
BASE_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CONFIG_FILE="${GAME8_CONFIG:-$BASE_DIR/game8.conf}"
CONFIG_DIR="$(cd "$(dirname "$CONFIG_FILE")" && pwd)"

if [[ -f "$CONFIG_FILE" ]]; then
    # game8.conf は shell 設定ファイルとして読み込みます。heredoc による複数行設定も使えます。
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

GAME8_POST_INTERVAL="${GAME8_POST_INTERVAL:-8h}"
GAME8_POST_BASE_URL="https://game8.jp"
GAME8_POST_ARCHIVE_ID="216448"
GAME8_POST_PAGE_PATH="/minecraft/216448"
CURL_USER_AGENT="${CURL_USER_AGENT:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36}"

usage() {
    cat <<EOF
使い方: $0 <コマンド>

コマンド:
  start      Game8 POST の systemd service/timer を準備して timer を起動します。
  restart    systemd service/timer を再生成して timer を再起動します。
  stop       Game8 POST timer を停止します。
  status     Game8 POST timer と service の状態を確認します。
  logs       Game8 POST service の journal を表示します。
  run        Game8 POST を1回実行します。
  timers     Game8 POST timer を一覧表示します。
  uninstall  Game8 POST の systemd service/timer を削除します。

設定:
  game8.conf GAME8_POST_* を書くローカル設定ファイル。既定: $BASE_DIR/game8.conf
  GAME8_CONFIG 設定ファイルのパスを上書きします。
EOF
}

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "必要なコマンドが見つかりません: $1" >&2
        echo "Ubuntu では依存パッケージを入れてください: sudo apt update && sudo apt install -y curl sed coreutils" >&2
        exit 1
    fi
}

need_cmds() {
    local cmd
    for cmd in "$@"; do
        need_cmd "$cmd"
    done
}

require_game8_post_deps() {
    need_cmds curl sed head date
}

is_root() {
    [[ "$(id -u)" -eq 0 ]]
}

systemctl_run() {
    if is_root; then
        systemctl "$@"
    else
        sudo systemctl "$@"
    fi
}

systemd_unit_path() {
    printf '%s/%s\n' "$SYSTEMD_DIR" "$1"
}

game8_post() {
    require_game8_post_deps

    local page_url endpoint csrf_token name body upload_file http_status
    page_url="$GAME8_POST_BASE_URL$GAME8_POST_PAGE_PATH"
    endpoint="$GAME8_POST_BASE_URL/api/archive_comments"
    name="${GAME8_POST_NAME:-}"
    body="${GAME8_POST_BODY:-}"
    upload_file="${GAME8_POST_UPLOAD_FILE:-}"

    if [[ -n "$upload_file" && "$upload_file" != /* ]]; then
        upload_file="$CONFIG_DIR/$upload_file"
    fi

    if [[ -n "$upload_file" && ! -f "$upload_file" ]]; then
        echo "Game8 POST に失敗しました: 添付ファイルが見つかりません: $upload_file" >&2
        exit 1
    fi

    if [[ -n "$upload_file" && ! -r "$upload_file" ]]; then
        echo "Game8 POST に失敗しました: 添付ファイルを読み込めません: $upload_file" >&2
        exit 1
    fi

    csrf_token="$(
        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --compressed \
            --user-agent "$CURL_USER_AGENT" \
            --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8" \
            --header "Accept-Language: ja,en-US;q=0.9,en;q=0.8" \
            --header "Cache-Control: no-cache" \
            --header "Pragma: no-cache" \
            "$page_url" \
            | sed -n 's/.*<meta name="csrf-token" content="\([^"]*\)".*/\1/p' \
            | head -n 1
    )"

    if [[ -z "$csrf_token" ]]; then
        echo "Game8 POST に失敗しました: csrf-token を取得できませんでした: $page_url" >&2
        exit 1
    fi

    local post_args=(
        --silent
        --show-error
        --location
        --compressed
        --output /dev/null
        --write-out '%{http_code}'
        --user-agent "$CURL_USER_AGENT"
        --referer "$page_url"
        --header "Accept: application/json, text/javascript, */*; q=0.01"
        --header "Accept-Language: ja,en-US;q=0.9,en;q=0.8"
        --header "Origin: $GAME8_POST_BASE_URL"
        --header "X-CSRF-Token: $csrf_token"
        --header "X-Requested-With: XMLHttpRequest"
        --form "archive_comment[archive_id]=$GAME8_POST_ARCHIVE_ID"
        --form "archive_comment[name]=$name"
        --form "archive_comment[body]=$body"
    )

    if [[ -n "$upload_file" ]]; then
        post_args+=(--form "archive_comment[upload_file]=@$upload_file")
    fi

    post_args+=("$endpoint")

    http_status="$(curl "${post_args[@]}")"

    case "$http_status" in
        200|201|204)
            if [[ -n "$upload_file" ]]; then
                echo "Game8 POST が完了しました: HTTP $http_status archive_id=$GAME8_POST_ARCHIVE_ID name=$name upload_file=$upload_file"
            else
                echo "Game8 POST が完了しました: HTTP $http_status archive_id=$GAME8_POST_ARCHIVE_ID name=$name"
            fi
            ;;
        *)
            if [[ -n "$upload_file" ]]; then
                echo "Game8 POST に失敗しました: HTTP $http_status archive_id=$GAME8_POST_ARCHIVE_ID name=$name upload_file=$upload_file" >&2
            else
                echo "Game8 POST に失敗しました: HTTP $http_status archive_id=$GAME8_POST_ARCHIVE_ID name=$name" >&2
            fi
            exit 1
            ;;
    esac
}

configure_systemd() {
    if ! is_root; then
        echo "root 権限で実行してください: sudo $0 start" >&2
        exit 1
    fi

    cat >"$(systemd_unit_path "$APP_NAME.service")" <<EOF
[Unit]
Description=Game8 POST 定期実行
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=GAME8_CONFIG=$CONFIG_FILE
Nice=10
IOSchedulingClass=idle
TimeoutStartSec=2min
ExecStart=$SCRIPT_PATH run
EOF

    cat >"$(systemd_unit_path "$APP_NAME.timer")" <<EOF
[Unit]
Description=Game8 POST 定期実行

[Timer]
OnBootSec=15min
OnUnitActiveSec=$GAME8_POST_INTERVAL
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$APP_NAME.timer"
    echo "Game8 POST timer を起動しました: $APP_NAME.timer"
}

stop_timer() {
    systemctl_run disable --now "$APP_NAME.timer"
}

status_command() {
    systemctl status "$APP_NAME.timer"
    systemctl status "$APP_NAME.service"
}

logs_command() {
    journalctl -u "$APP_NAME.service" -n "${1:-100}" --no-pager
}

timers_command() {
    systemctl list-timers "$APP_NAME.timer"
}

uninstall_systemd() {
    if ! is_root; then
        echo "root 権限で実行してください: sudo $0 uninstall" >&2
        exit 1
    fi

    systemctl disable --now "$APP_NAME.timer" 2>/dev/null || true
    rm -f "$(systemd_unit_path "$APP_NAME.service")" "$(systemd_unit_path "$APP_NAME.timer")"
    systemctl daemon-reload
    echo "Game8 POST の systemd unit を削除しました。"
}

cmd="${1:-}"
case "$cmd" in
    start|restart)
        configure_systemd
        ;;
    stop)
        stop_timer
        ;;
    status)
        status_command
        ;;
    logs)
        logs_command "${2:-100}"
        ;;
    run)
        game8_post
        ;;
    timers)
        timers_command
        ;;
    uninstall)
        uninstall_systemd
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        echo "不明なコマンドです: $cmd" >&2
        usage >&2
        exit 1
        ;;
esac
