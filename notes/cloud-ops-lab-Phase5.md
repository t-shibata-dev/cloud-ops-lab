# Phase 5：Docker / コンテナ まとめ

## やったこと

ColimaをコンテナランタイムとしてMac（Apple Silicon）に導入し、単体コンテナの起動からDocker Composeによる複数コンテナ構成まで動作確認した。

## 環境構成

- ランタイム：Colima（Lima VM、arm64ネイティブ）
- クライアント：Docker CLI + docker-compose（Homebrew経由）
- ホスト：macOS / Apple Silicon（darwin/arm64）
- VM内アーキテクチャ：linux/arm64

## Step 1：単体コンテナの起動

### インストール

```bash
brew install colima docker docker-compose
colima start
```

### 動作確認

```bash
docker run --rm hello-world
docker run -d --name web -p 8080:80 nginx
```

`http://localhost:8080` でnginxの初期ページが表示されることを確認。

### 片付け

```bash
docker rm -f web
```

### 学んだこと

- `docker run` の3要素：イメージ（設計図）／コンテナ（起動した実体）／ポート公開（外から繋ぐ穴）
- EC2へのapt installと違い、1コマンドで環境ごと起動し、削除すれば跡形もなく消える

## Step 2：Docker Compose で WordPress + MySQL を立ち上げる

### ディレクトリ構成

```
~/docker-wp/
└── compose.yaml
```

### compose.yaml

```yaml
services:
  db:
    image: mysql:8.0
    platform: linux/arm64
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpass
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wpuser
      MYSQL_PASSWORD: wppass
    volumes:
      - db_data:/var/lib/mysql

  wordpress:
    image: wordpress:latest
    platform: linux/arm64
    restart: always
    ports:
      - "8080:80"
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_NAME: wordpress
      WORDPRESS_DB_USER: wpuser
      WORDPRESS_DB_PASSWORD: wppass
    depends_on:
      - db

volumes:
  db_data:
```

### 起動・確認

```bash
docker-compose up -d
docker-compose ps
```

`http://localhost:8080` でWordPressの初期設定画面が表示されることを確認。

### 学んだこと

- `docker-compose up -d` 1コマンドで2コンテナ、ネットワーク、ボリュームが同時に作成される
- `WORDPRESS_DB_HOST: db` と書くだけでMySQLに繋がる：Composeが自動作成したネットワーク内でコンテナ名がそのままDNS名として機能するため
- EC2での手動設定（MySQLインストール・設定ファイル編集・WordPress設定）が、compose.yaml 1枚に集約される
- `volumes: db_data` により、コンテナを削除してもMySQLのデータは残る（永続化）

## SREとしての意味

- インフラをコードで宣言する考え方はTerraformと同じ：構成がファイルとして残り、再現性が保証される
- 依存関係（WordPressはDBが先に起動している必要がある）を `depends_on` で明示できる
- 本番ではコンテナをEC2やECS上で動かすことになる。Dockerの基礎を持っていることがその前提になる
