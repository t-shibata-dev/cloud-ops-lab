# Phase 7：Kubernetes 基礎

## 概要

Colima の Kubernetes モードを使い、ローカル環境で Kubernetes の基本操作を習得した。
Pod / Deployment / Service / Namespace を実際に操作し、スケールとセルフヒーリングを確認した。

---

## 環境

| 項目 | 内容 |
|---|---|
| ランタイム | Colima (Kubernetes モード) |
| Kubernetes バージョン | v1.35.0+k3s1 |
| 起動コマンド | `colima start --kubernetes --cpu 2 --memory 4` |
| kubectl | Homebrew でインストール |

### Colima を選んだ理由

- すでに Phase 5 で導入済み、追加インストール不要
- Apple Silicon ネイティブ arm64 対応
- minikube と比較して補助機能は少ないが、kubectl 操作の学習には十分

---

## 学習内容

### 1. Pod

Kubernetes の最小デプロイ単位。1つ以上のコンテナを含む。

```bash
# 起動
kubectl run nginx-pod --image=nginx --port=80

# 確認
kubectl get pods
kubectl describe pod nginx-pod

# アクセス
kubectl port-forward pod/nginx-pod 8080:80
```

### 2. Deployment

Pod を管理・スケールする仕組み。本番で Pod を直接使うことはない。

```bash
# 作成
kubectl create deployment nginx-deploy --image=nginx --replicas=2

# スケール
kubectl scale deployment nginx-deploy --replicas=4

# 確認
kubectl get deployments
```

### 3. Service

Pod へのネットワーク経路を提供する。Pod の IP は変わるが Service の IP は固定。

```bash
# 作成
kubectl expose deployment nginx-deploy --port=80 --type=NodePort

# アクセス（Colima 環境では port-forward が確実）
kubectl port-forward service/nginx-deploy 8080:80
```

**NodePort が Mac から直接アクセスできない理由：**
Colima は Lima ベースの VM のため、Kubernetes の NodePort は VM 内部に閉じている。
実務では NodePort より LoadBalancer や Ingress を使う。

### 4. スケールとセルフヒーリング

```bash
# スケールアウト（2→4）
kubectl scale deployment nginx-deploy --replicas=4

# Pod を強制削除 → 自動で再作成される
kubectl delete pod nginx-deploy-xxxxxxxx-xxxxx
kubectl get pods  # 新しい Pod が ContainerCreating → Running
```

Deployment が「レプリカ数=4」というあるべき状態を維持しようとするため、
Pod を削除しても即座に再作成される。これが Kubernetes のセルフヒーリング。

### 5. YAML による宣言的管理

コマンドではなく YAML ファイルでリソースを定義・管理する。

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deploy
  labels:
    app: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
```

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
```

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl get all
```

### 6. Namespace

クラスターを論理的に分割して環境を分離する。

```
クラスター
├── namespace: default    ← デフォルト
├── namespace: dev        ← 開発環境
├── namespace: staging    ← ステージング環境
└── namespace: kube-system ← Kubernetes システム Pod
```

```bash
# 作成
kubectl create namespace dev
kubectl create namespace staging

# Namespace を指定してデプロイ
kubectl create deployment nginx-dev --image=nginx --namespace=dev

# 確認
kubectl get pods -n dev
kubectl get pods --all-namespaces
```

**よくあるミス：** `-n` を忘れると default しか見えず「Pod が消えた」と焦る。

---

## 主要コマンド一覧

| 操作 | コマンド |
|---|---|
| Pod 起動 | `kubectl run <name> --image=<image>` |
| Deployment 作成 | `kubectl create deployment <name> --image=<image>` |
| Service 公開 | `kubectl expose deployment <name> --port=<port>` |
| スケール | `kubectl scale deployment <name> --replicas=<n>` |
| YAML 適用 | `kubectl apply -f <file>` |
| 全リソース確認 | `kubectl get all` |
| Namespace 指定 | `kubectl get pods -n <namespace>` |
| 全 Namespace | `kubectl get pods --all-namespaces` |
| ポートフォワード | `kubectl port-forward <resource> <local>:<remote>` |
| 詳細確認 | `kubectl describe <resource> <name>` |

---

## Kubernetes リソースの関係

```
Deployment
  └─ ReplicaSet（Pod 数を管理）
       └─ Pod × N（コンテナが動く最小単位）

Service
  └─ Pod を selector でまとめてネットワーク経路を提供
```

---

## 学習ポイント

- Pod を直接使わず Deployment で管理するのが基本
- セルフヒーリングは Kubernetes の最大の価値：あるべき状態を自律的に維持する
- YAML による宣言的管理がコマンドより再現性が高く実務での標準
- Namespace は `-n` の指定忘れが実務でよくあるミス
- Colima 環境では NodePort に Mac から直接アクセスできないため `port-forward` を使う
