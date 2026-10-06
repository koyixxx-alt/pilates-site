# Pilates Studio アプリ

個人ピラティススタジオ向けの顧客・計測・予約・会計・売上管理アプリ。
ビルド不要の単一HTML + Supabase 構成。GitHub へ push すると Netlify が自動デプロイします。

## 構成

| フォルダ | 役割 | Netlify公開ディレクトリ |
|---|---|---|
| `owner/` | お店側アプリ（オーナー・管理） | `owner` |
| `customer/` | お客様側アプリ（マイページ） | `customer` |

## デプロイ（自動）

`main` ブランチに push すると、連携済みの Netlify サイトが自動でビルド・公開します。
手動の設定は不要（ビルドコマンドなし・公開ディレクトリのみ指定）。

## 更新の流れ

1. `owner/index.html` または `customer/index.html` を編集
2. `git add -A && git commit -m "..." && git push`
3. 数十秒で各サイトに反映
