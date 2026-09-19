# iptables-portforward

> 高效地設定機器之間的 Port Forwarding。

一個以 Bash 撰寫的輕量級工具，透過簡單的設定檔管理 Linux `iptables` Port Forwarding 規則。

## 功能

- 透過設定檔管理 Port Forwarding
- 自動同步 `iptables` 規則
- 避免重複建立規則
- 使用獨立的 `iptables` Chain
- 安全移除由本工具管理的規則
- 支援 Bash 與 Zsh Tab Completion
- 可以安全地重複執行

## 系統需求

- Linux
- Bash
- `iptables`
- Root 權限

本工具主要針對使用 `iptables` 的 Linux 系統設計。

## 安裝

Clone Repository：

```bash
git clone https://github.com/USERNAME/iptables-portforward.git
cd iptables-portforward
```

安裝指令：

```bash
sudo install -m 755 portforward /usr/local/bin/portforward
```

安裝必要套件：
```bash
sudo apt update sudo apt install -y iptables jq
```
```bash
sudo apt install -y iptables-persistent
```

## 使用方式

```text
Usage: sudo portforward [action]
```

### 操作

| 操作 | 說明 |
|---|---|
| `apply` | 從設定檔同步並套用規則 |
| `edit` | 編輯設定檔；完成後需要執行 `apply` |
| `rm` | 移除本工具建立的 Chain 與 Jump Rule |
| `completion` | 安裝 Bash 與 Zsh Tab Completion |
| `help` | 顯示說明文件 |

### 範例

套用目前的設定：

```bash
sudo portforward apply
```

編輯 Port Forwarding 設定：

```bash
sudo portforward edit
```

移除由本工具管理的規則：

```bash
sudo portforward rm
```

安裝 Shell 自動補全：

```bash
sudo portforward completion
```

## 設定

Port Forwarding 規則儲存在：

```text
/etc/port_forwards.json
```

設定檔用來定義進入的流量應該如何從一個介面或機器轉發到另一個介面或機器。

一個基本的轉發流程如下：

```text
External Port
      │
      ▼
Input Interface
      │
      ▼
  iptables
      │
      ▼
Destination IP:Port
```

修改設定後，執行：

```bash
sudo portforward apply
```

## 運作方式

本工具會建立並管理獨立的 `iptables` Chain，而不是直接將所有規則加入主要 Chain。

概念上：

```text
iptables
│
├── INPUT
│
├── OUTPUT
│
└── FORWARD
      │
      └── FORWARD_TOOL
             │
             ├── Port Forward Rule 1
             ├── Port Forward Rule 2
             └── Port Forward Rule 3
```

這樣可以讓規則更容易被識別、更新與移除。

工具在建立 Jump Rule 前也會先確認規則是否已存在，以避免不必要的重複。

## 規則管理

本工具使用自己的識別 Tag 來區分由工具管理的規則。

當套用新的設定時，可以先移除屬於本工具的舊規則，再同步新的設定。

因此可以將設定檔視為 Port Forwarding 狀態的主要來源。

```text
Configuration
      │
      ▼
  Synchronize
      │
      ▼
 Remove old rules
      │
      ▼
 Add current rules
      │
      ▼
   iptables
```

## 檔案

| 檔案 | 說明 |
|---|---|
| `/etc/port_forwards.json` | Port Forwarding 設定 |
| `$COMPLETION_FILE` | Bash 自動補全 |
| `$ZSH_COMPLETION_FILE` | Zsh 自動補全 |

## 說明

執行：

```bash
sudo portforward help
```

或直接：

```bash
sudo portforward
```

預設操作為 `help`。

## 設計目標

本專案主要追求：

- 簡單的設定方式
- 高效的規則同步
- 避免重複規則
- 容易維護
- 可以安全地重複執行
- 明確區分本工具管理與其他來源的 `iptables` 規則

## 授權

本專案為開源專案，詳細授權條款請參閱 [`LICENSE`](LICENSE)。
