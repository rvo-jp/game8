# game8

Game8 のコメント投稿 API へ定期的に POST するための運用スクリプトです。

## 構成

```text
game8/
├── game8.sh
├── game8.conf
└── game8.conf.example
```

`game8.conf` はローカル設定ファイルのため Git 管理しません。

## 初回セットアップ

Ubuntu LTS サーバーで依存パッケージを入れます。

```bash
sudo apt update
sudo apt install -y curl sed coreutils
```

スクリプトに実行権限を付け、設定ファイルを作ります。

```bash
chmod +x game8.sh
cp game8.conf.example game8.conf
nano game8.conf
```

投稿内容を設定します。

```bash
GAME8_POST_NAME=backend-receive-check
GAME8_POST_BODY=$(cat <<'EOF'
1行目
2行目
3行目
EOF
)
GAME8_POST_UPLOAD_FILE=
```

`GAME8_POST_BODY` が未指定なら本文は空文字列です。`GAME8_POST_NAME` が未指定なら投稿者名は空文字列です。

画像などのファイルを添付する場合は、`GAME8_POST_UPLOAD_FILE` にファイルパスを指定します。相対パスは `game8.conf` のあるディレクトリからの相対パスとして扱います。

```bash
GAME8_POST_UPLOAD_FILE=./upload.png
```

CSRF取得元ページは `https://game8.jp/minecraft/216448`、投稿先APIは `https://game8.jp/api/archive_comments` で固定しています。通常の設定項目からは変更できないため、誤設定で投稿先が変わることはありません。

## 起動

systemd service/timer を作成して、定期実行を開始します。

```bash
sudo ./game8.sh start
```

実行頻度を変える場合は、`game8.conf` の `GAME8_POST_INTERVAL` を変更して `restart` します。初期値は `8h` です。

```bash
sudo ./game8.sh restart
```

## 操作

状態を確認します。

```bash
./game8.sh status
./game8.sh timers
```

ログを確認します。

```bash
./game8.sh logs
./game8.sh logs 300
```

1 回だけ手動実行します。

```bash
./game8.sh run
```

定期実行を停止します。

```bash
sudo ./game8.sh stop
```

systemd unit を削除します。

```bash
sudo ./game8.sh uninstall
```

## ログ

成功や失敗は journal にだけ簡潔に記録します。レスポンス本文の詳細分析は行いません。
