# EC2自動化 まとめ

## やったこと

`scripts/ec2_control.py` を作成し、PythonスクリプトからEC2を操作できるようにした。

## 実装した機能

- `status` — インスタンスの現在の状態を確認
- `start` — インスタンスを起動
- `stop` — インスタンスを停止

## 使い方

```shell
python ec2_control.py status i-0c5818f0ef2518d19
python ec2_control.py start  i-0c5818f0ef2518d19
python ec2_control.py stop   i-0c5818f0ef2518d19
```

## 動作確認

本番EC2（`i-0c5818f0ef2518d19`）で実際にstart・stopを実行し、AWSコンソールで「保留中」「実行中」「停止中」「停止済み」の状態遷移を確認した。

## Python環境

```shell
python3 -m venv .venv
source .venv/bin/activate
pip install boto3
```

## SREとしての意味

- 手動操作をコード化することで自動化の基盤になる
- 深夜の自動停止・障害時の自動再起動などに応用できる
