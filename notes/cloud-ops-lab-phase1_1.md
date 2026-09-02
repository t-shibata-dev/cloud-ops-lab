# cloud-ops-lab — Phase 1 作業まとめ（Day 1〜5）

> 目的：AWS/クラウドインフラの学習。マネージドの裏で何が起きているかを、VPCから手作業で組んで理解する。
> 記録日：2026-08-31 / リージョン：ap-northeast-1（東京）

## 達成したこと

自分で手組みしたAWSインフラ上で WordPress（サイト名「プログラム制作演習」）を公開まで通した。

```
Internet
   │  HTTP(80) 0.0.0.0/0
   ▼
[ Elastic IP  13.196.53.206 ]
   │
┌── VPC 10.0.0.0/16 (ap-northeast-1) ───────────────────────┐
│                                                            │
│   Public Subnet 10.0.1.0/24 (ap-northeast-1a)              │
│      └─ EC2 t3.micro / Ubuntu 26.04 LTS                    │
│           Apache 2.4 + PHP 8.5 + MySQL 8.4                 │
│           └─ WordPress  (/var/www/html, DB=同居)           │
│                                                            │
│   Internet Gateway ── Route Table (0.0.0.0/0 → IGW)        │
└────────────────────────────────────────────────────────────┘
   ▲
   │ 管理アクセス：AWS Systems Manager (SSM) セッションマネージャー
   │             ※ SSHポート(22)は開けていない
```

## 構築の流れ（Day 1〜5）

- **Day 1 ネットワーク**：VPC（10.0.0.0/16）→ パブリックサブネット（10.0.1.0/24, ap-northeast-1a）→ インターネットゲートウェイをVPCにアタッチ → 専用ルートテーブルに `0.0.0.0/0 → IGW` を追加しサブネットに関連付け。「IGW＋ルート＋関連付けの3点が揃って初めてパブリックサブネット」を体で理解。
- **Day 2 EC2**：Ubuntu 26.04 / t3.micro を起動。キーペア(.pem)、セキュリティグループ、Elastic IP を割り当て。
- **Day 3 Webサーバー**：`apt` で Apache2 + PHP 8.5 + 各拡張を導入。`http://13.196.53.206` で "Apache2 Ubuntu Default Page" 確認。
- **Day 4 MySQL**：`mysql-server`（8.4）導入 → `mysql_secure_installation` → DB `wordpress` と ユーザー `wpuser` を作成。
- **Day 5 WordPress**：本体を `/var/www/html` に配置 → Webインストーラーで初期設定 → 公開・ログイン完了。

## 主要リソース

| 種別 | 名前 / 値 |
|---|---|
| VPC | `cloud-ops-lab-vpc` (vpc-0f3734eee186134d2) / 10.0.0.0/16 |
| サブネット | `cloud-ops-lab-public-1a` (subnet-0caa10c353f99d2de) / 10.0.1.0/24 / ap-northeast-1a |
| IGW | `cloud-ops-lab-igw` (igw-0f160fb8a89e75e5c) |
| ルートテーブル | `cloud-ops-lab-public-rt` (rtb-06076653fc110db94) |
| セキュリティグループ | `cloud-ops-lab-sg` (sg-03c44ef5df323fd75) — 現在は HTTP(80) 0.0.0.0/0 のみ |
| EC2 | `cloud-ops-lab-web` (i-0c5818f0ef2518d19) / t3.micro / Ubuntu 26.04 |
| Elastic IP | 13.196.53.206 |
| IAM ロール | `cloud-ops-lab-ec2-ssm-role`（AmazonSSMManagedInstanceCore） |
| DB | 名前 `wordpress` / ユーザー `wpuser` / ホスト `localhost` |

## つまずきと学び（ここが一番の収穫）

- **IAM 権限**：IAMユーザー `*********` に EC2/VPC 権限が無く VPC 作成が `not authorized` で失敗 → root で `Administrators` グループ（AdministratorAccess）に追加して解決。「コンソール操作は identity-based policy に許可されて初めて通る」。
- **リージョン表示制限**：アカウント設定の「表示リージョン」が東京のみに絞られており、IAM等グローバル系（us-east-1利用）で毎回ポップアップ → 全リージョン表示に変更（表示だけの制御でAPIは止めない）。
- **SSH タイムアウトの真因＝IP揺れ**：`curl` で見えたIPと実際のSSH送信元IPが別だった（CGNAT。サーバーの `Last login ... from 49.109.166.248` で判明）。80番(全開放)は届くのに22番(/32制限)だけ timeout する、で切り分け。→ **SSM セッションマネージャー**に切替え、**SSHの22番は閉鎖**（IP揺れ・拠点変更・会社の22番ブロックと無縁に）。
- **Ubuntu 特有の差分**（Amazon Linux手順からの読み替え）：`httpd`→`apache2`、`php-mysqlnd`→`php-mysql`、`dnf`→`apt`、MySQLサービス名は `mysql`（`mysqld`でない）、root は auth_socket なので `sudo mysql`、デフォルトの `index.html` を削除、Web所有者は `www-data`、SSHユーザーは `ubuntu`。
- **MySQL パスワードポリシー**：`VALIDATE PASSWORD` 有効時は大文字・小文字・数字・記号・8文字以上が必須。
- **t3.micro のメモリ枯渇（重要）**：RAM 1GB＋スワップ無し＋MySQL8 で、WordPress配置時に **OOMでフリーズ**。再起動しても再発。→ **2GBスワップ追加**で解決（小さいインスタンスの定番対処）。
- **ブラウザSSMターミナルの弱点**：大量ファイルの展開でフリーズ → **Run Command**（非対話実行）に切替えて回避。

## 現在のアクセス方法

- サイト：`http://13.196.53.206`
- 管理画面：`http://13.196.53.206/wp-admin/`（ユーザー名：*********.***）
- サーバー操作：AWSコンソール → Systems Manager → セッションマネージャー →（`sudo su - ubuntu`）

## セキュリティ状態

- SSH(22) 閉鎖、サーバー操作は SSM 経由のみ。
- インバウンドは HTTP(80) のみ公開。
- 未対応：********* の MFA、HTTPS(443)化、root設定の自己点検。

## コスト注意（クレジット制アカウント）

- EC2・Elastic IP は稼働中はクレジットを消費。数日触らないなら EC2 を「停止」で稼働課金は止まる。
- ただし **停止中は Elastic IP が課金対象**（約$0.005/時）。長期放置するなら EIP解放＋インスタンス終了が確実。
- 学習終了時の掃除：EC2 terminate → EIP release → 不要なEBS/セキュリティグループ削除。

## 残タスク

- Week 2：**S3 連携**（メディアをS3に逃がす。Day 8〜10）
- **構成図（draw.io等）＋この内容の README 化**（ポートフォリオ用。cloud-ops-lab リポジトリへ）
- 後片付け：********* の **MFA**、空セキュリティグループ `cloud-ops-lab-vpc` の削除、（安定化のため）MySQL のメモリ節約設定
- **手元ターミナル/Emacs からの SSM 接続**（AWS CLI + session-manager-plugin + 認証情報、TRAMP over SSM）

## シークレット（このファイルには書かない・GitHubに上げない）

- `wpuser` の DBパスワード / WordPress 管理者パスワード → パスワードマネージャーで管理。
- `wp-config.php`、`.pem` キーは `.gitignore` で除外。
