# Phase 2 — RDS移行ログ

**AWS 三層アーキテクチャ実習 / Cloud Ops Lab**

| 項目 | 内容 |
|---|---|
| 実施日 | 2026-09-02 |
| リージョン | ap-northeast-1 |
| 結果 | 移行成功 → 検証後クローズ（RDS削除・Phase 1状態へロールバック） |

---

## 目標と結果

EC2に同居していた MySQL を RDS に分離し、二層（Web+DB同居）から三層（Web / DB / Storage）へ移行する。DBを独立サービスに逃がすことで、1GB の t3.micro に載っていた MySQL プロセスが外れ、メモリ的にも楽になる——という三層化の実利を体験するのが狙い。

移行は**旧DBを残したまま**行い、いつでも戻せる形で実施した。学習が目的のため、検証完了後は課金停止のためRDSを削除し、Phase 1状態へロールバックしている。

---

## 移行フロー

```
EC2 ローカル MySQL          /tmp/wp.sql            RDS MySQL 8.4
(wordpress DB / 旧)   ──①──▶ (mysqldump出力) ──②──▶ (private / db.t4g.micro)
※消さず残す=保険                                      wpuser@'%' 作成
                                                          │
                                                          ③ 切替
                                                          ▼
                                                    wp-config.php
                                                    DB_HOST → RDSエンドポイント

ロールバック: DB_HOST を localhost に戻し、旧MySQLを起動すれば即復帰
```

旧DBを残したまま **dump →  import → 接続先切替** の3手で移行。切替後に不具合が出ても `wp-config.php.bak` を戻して旧MySQLを起動すれば即ロールバックできる設計にした。

---

## 手順ログ

### 1. プライベートサブネットを2つ作成

RDSのDBサブネットグループは**2AZ必須**。別AZに分けて作り、IGWルートを持たない（＝プライベート）ことを確認。

```
10.0.2.0/24  ap-northeast-1a  (cloud-ops-lab-private-1a)
10.0.3.0/24  ap-northeast-1c  (cloud-ops-lab-private-1c)
# ルートは 10.0.0.0/16 local のみ / 0.0.0.0/0→IGW 無し
```

### 2. RDS用セキュリティグループ

ソースをIPではなく **EC2のSGを参照**して3306を許可。EC2以外はDBに到達不可になる。

```
cloud-ops-lab-rds-sg
  inbound: MySQL/Aurora 3306  source = cloud-ops-lab-sg (EC2のSG)
```

### 3. DBサブネットグループ → RDS作成

サブネットグループ（2AZ）を作り、RDS を作成。

- パブリックアクセス = **いいえ**
- SG = **cloud-ops-lab-rds-sg のみ**（default は外す）
- テンプレート = 無料利用枠 / クラス = **db.t4g.micro**（ネイティブarm、amd64比で安い）
- ストレージ自動スケーリング off / 拡張モニタリング off

### 4. 旧DBを dump（消さない）

```bash
sudo mysqldump --databases wordpress \
  --single-transaction --routines --triggers > /tmp/wp.sql
```

### 5. RDS接続テスト → import → wpuser作成

接続テストがSG設定の検証を兼ねる（通れば経路OK）。

```bash
# 接続確認（★ここが通らなければSG不整合。止めて切り分け）
mysql -h <RDSエンドポイント> -u admin -p

# 取込
mysql -h <RDSエンドポイント> -u admin -p < /tmp/wp.sql
```

```sql
-- RDS側で（wp-configはDB_HOSTだけ変更で済むよう、同じユーザーを作る）
CREATE USER 'wpuser'@'%' IDENTIFIED BY '********';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'%';
FLUSH PRIVILEGES;
```

### 6. wp-config の DB_HOST を切替

```bash
sudo cp wp-config.php wp-config.php.bak   # 保険
sudo sed -i "s#'DB_HOST', 'localhost'#'DB_HOST', '<RDSエンドポイント>'#" wp-config.php
```

### 7. 検証 → 後始末

サイトヘルスでRDS接続を確認 → 学習終了のため RDS削除・Phase 1状態へロールバック。

---

## 検証（どうRDSと確証したか）

WordPress サイトヘルスの「データベース」欄が決め手：

- **データベースホスト** = `cloud-ops-lab-db...rds.amazonaws.com`（RDSエンドポイント）
- **サーバーバージョン** = `8.4.9`（RDS側）。ローカルMySQLは `8.4.10 / 8.4.11` → **番号が違う＝別サーバーを見ている確証**
- 接続テストのエラーも判断材料に：**timeout = 経路不通** / **ERROR 1045 = 経路OK・認証だけ失敗**

---

## つまずき & 学び

| 分類 | ポイント |
|---|---|
| 設計 | **サブネットは2AZ必須** — RDSのDBサブネットグループはSingle-AZ構成でも最低2AZのサブネット登録を要求。1つしか無いと着手直後に詰まる。 |
| 設計 | **「プライベート」の定義はルートテーブル** — 名前ではなく `0.0.0.0/0→IGW` が無いことが条件。新規サブネットはメインRT（localのみ）に自動で紐づくのでそのままプライベートになる。 |
| セキュリティ | **SGのソースはIPでなくSG参照** — 3306の許可元をEC2のSGにするとIPが変わっても効き続ける。CGNATでIPが揺れる回線ではこれが正解。 |
| 運用 | **wp-config変更「だけ」ではデータが消える** — 空のRDSに向けるだけだと記事が全消えに見える。`mysqldump→import` でデータを先に移すのが必須。 |
| 環境 | **Emacs eshell の head/cat が効かない** — eshell経由だと `head/cat/tail` が uutils に化けTRAMPのリモートファイルを開けずコケる。実作業は **SSM Session Manager の素のbash** で。`hostname`=ip-10-0-1-25 でEC2上を確認。 |
| コスト | **RDSは停止しても7日で自動起動** — 停止運用は7日以内に再開する時だけ。長く使わないなら削除が確実。停止中もストレージ保管料は発生。 |
| 運用 | **ロールバックは「戻してから消す」** — RDS削除の前に、ローカルMySQL起動＋`wp-config.php.bak`復元でPhase 1状態に戻し、表示確認してから削除。順番を逆にするとサイトが一時的に落ちる。 |

---

## 次へ

課金源のRDSは削除済み、環境はPhase 1状態でクリーン。地固め（課金確認・構成ノート・MFA）を完了し、**Phase 3 = Terraform で今の三層構成をコード化**へ進む。

- 更地から新規（別CIDR 例 `10.10.0.0/16`）・手構築スタックは参照用に残す
- ローカルstateから開始（S3バックエンドは後の応用回）
- ネットワーク層から `plan → apply → destroy` の順で練習

---

*Cloud Ops Lab · Phase 2 実習ログ · ap-northeast-1 · 個人学習記録*
