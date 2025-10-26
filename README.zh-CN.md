# Synology DSM 自动化 SSL 证书管理

使用 acme.sh、Let's Encrypt 和 dynv6 DNS 验证为 Synology（群晖）DSM 6.2.3 实现自动化 SSL 证书签发和续期。

## 功能特性

- **自动化证书签发**：使用 Let's Encrypt 自动生成初始证书
- **自动续期**：每日检查并在过期前（30天内）自动续期
- **DNS-01 挑战**：通过 dynv6 DNS API 支持纯 IPv6 连接
- **DSM 集成**：自动将证书部署到 Synology DSM 网页界面
- **混合架构**：使用 Docker 进行证书签发/续期，使用原生 acme.sh 进行 DSM 部署
- **安全部署**：支持临时管理员模式（无需存储密码）
- **零停机时间**：证书自动续期和部署，无需人工干预

## 前置要求

### 在 Synology NAS 上
- Synology（群晖）DSM 6.2.3 或更高版本
- 已安装 Docker 套件
- 已启用 SSH 访问
- Root 或管理员权限

### 外部服务
- 在 [dynv6.com](https://dynv6.com) 注册的域名（例如 example.v6.army）
- dynv6 API 令牌（从 https://dynv6.com/keys 获取）

## 快速开始

### 1. 克隆或复制文件到 NAS

```bash
# 在您的 NAS 上创建目录
mkdir -p /volume1/docker/synology-acme
cd /volume1/docker/synology-acme

# 将此仓库的所有文件复制到上述目录
```

### 2. 配置环境变量

```bash
# 复制示例环境文件
cp .env.example .env

# 使用您的实际凭据编辑 .env 文件
vi .env
```

必需的变量：
- `DYNV6_TOKEN`：您从 https://dynv6.com/keys 获取的 dynv6 API 令牌
- `DOMAIN`：您的域名（例如 example.v6.army）
- `EMAIL`：用于接收 Let's Encrypt 通知的邮箱

可选的变量：
- `SYNO_USERNAME`：DSM 管理员用户名（留空则使用临时管理员）
- `SYNO_PASSWORD`：DSM 管理员密码（留空则使用临时管理员）

### 3. 设置文件权限

```bash
# 使脚本可执行
chmod +x scripts/*.sh

# 保护 .env 文件
chmod 600 .env

# 创建数据和日志目录
mkdir -p acme-data logs
```

### 4. 启动 Docker 容器

```bash
# 启动 acme.sh 容器
docker-compose up -d

# 验证容器正在运行
docker-compose ps
```

### 5. 安装原生 acme.sh 用于部署

```bash
# 在 DSM 上安装原生 acme.sh（部署所需）
sudo ./scripts/install-acme-native.sh
```

这将：
1. 下载并安装 acme.sh 到 `/usr/local/share/acme.sh`
2. 配置使用与 Docker 相同的证书目录
3. 设置符号链接和适当的权限
4. 无重复证书 - 两个安装共享相同的存储

**为什么需要原生 acme.sh？**
- `SYNO_USE_TEMP_ADMIN=1` 需要 DSM 系统工具（synouser、synogroup、synosetkeyvalue）
- 这些工具仅存在于 DSM 主机上，不在 Docker 容器内
- 原生安装允许在不存储管理员密码的情况下进行安全部署

### 6. 签发初始证书

```bash
# 运行证书签发脚本（使用 Docker）
./scripts/issue-cert.sh
```

这将：
1. 连接到 dynv6 API
2. 从 Let's Encrypt 请求证书
3. 完成 DNS-01 验证
4. 将证书保存到 `acme-data/`（共享存储）

### 7. 部署证书到 DSM

```bash
# 将证书部署到 Synology DSM（使用原生 acme.sh）
sudo ./scripts/deploy-to-dsm.sh
```

这将：
1. 使用带有 DSM 部署钩子的原生 acme.sh
2. 上传证书到 DSM 证书存储
3. 重启 DSM 网页服务
4. 验证部署成功

**注意：** 临时管理员模式需要 root/sudo 权限（推荐以提高安全性）

### 8. 配置自动续期

**重要：** 在 Synology NAS 上使用 DSM 任务计划进行自动续期。Synology DSM **不支持** `crontab` 命令。

#### 使用 DSM 任务计划（Synology 唯一方法）

1. 打开 DSM 控制面板 → 任务计划
2. 新增 → 计划的任务 → 用户定义的脚本
3. 配置任务：
   - **常规**：
     - 任务名称：SSL Certificate Renewal
     - 用户账号：root
     - 已启用：✓
   - **计划**：
     - 执行日期：每天
     - 首次运行时间：02:00（凌晨2点）或任何您偏好的时间
     - 频率：每天
   - **任务设置**：
     - 用户定义的脚本：
       ```bash
       bash /volume1/docker/synology-acme/scripts/renew-cert.sh
       ```
4. 点击确定保存

#### 理解每日续期检查

**为什么证书有效期90天却要每天运行？**

续期脚本是智能的：
- **每天运行**检查证书过期时间
- **仅在剩余 < 30 天时续期**（Let's Encrypt 默认设置）
- **每日仅检查的运行**耗时 < 1 秒，资源占用极小
- **提供重试机会**，如果某次续期尝试失败

**示例时间线：**
- 证书签发：2025-10-26
- 证书过期：2026-01-24（90天后）
- 每日检查：2025-10-26 至 2025-12-24（脚本立即退出，不执行任何操作）
- **首次续期：约 2025-12-25**（剩余 < 30 天时）
- 后续续期：自动每 60 天续期一次

**每日检查的好处：**
- ✓ 续期失败时有多次重试机会
- ✓ 处理 DSM 时钟漂移或停机
- ✓ Let's Encrypt 标准最佳实践
- ✓ 性能影响可忽略不计（< 0.01% CPU，< 1 秒）

### 9. 测试续期流程

#### 测试计划任务

**方法1：通过 DSM 任务计划测试（推荐）**
1. 进入 DSM 控制面板 → 任务计划
2. 选择您的"SSL Certificate Renewal"任务
3. 点击"运行"按钮
4. 在任务计划 → 操作 → 查看结果 中查看执行日志
5. 在 `logs/renewal.log` 中验证

**刚签发的新证书测试时预期结果：**
由于您的证书刚刚签发，脚本将：
- 检查证书过期时间
- 发现剩余 > 30 天
- 立即退出并显示消息："✓ Certificate is still valid"
- 不会执行续期（这是正确的行为！）

#### 测试完整续期（可选）

要测试完整的续期 + 部署工作流：

```bash
# 切换到 root 用户
sudo su -
cd /volume1/docker/synology-acme

# 即使证书有效也强制续期
./scripts/renew-cert.sh --force

# 查看日志
tail -f logs/renewal.log
```

这将：
1. 通过 Docker 强制证书续期（DNS-01 验证）
2. 使用原生 acme.sh 将续期的证书部署到 DSM
3. 重启 DSM 网页服务
4. 将所有操作记录到 `logs/renewal.log`

**注意：** 如果您的 `.env` 文件中设置了 `SYNO_USE_TEMP_ADMIN=1`，请使用 `sudo su -`（切换到 root）

## 文件结构

```
/volume1/docker/synology-acme/
├── docker-compose.yml         # Docker 容器配置
├── .env                       # 您的凭据（不在 git 中）
├── .env.example              # 环境变量模板
├── README.md                 # 英文文档
├── README.zh-CN.md           # 本文件
├── QUICK-START.md            # 英文快速开始指南
├── QUICK-START.zh-CN.md      # 中文快速开始指南
├── docs/
│   └── DEPLOYMENT-OPTIONS.md # 部署架构说明
├── scripts/
│   ├── install-acme-native.sh # 在 DSM 上安装原生 acme.sh
│   ├── issue-cert.sh        # 初始证书签发（Docker）
│   ├── renew-cert.sh        # 续期检查和执行（Docker + 原生）
│   └── deploy-to-dsm.sh     # 部署证书到 DSM（原生）
├── acme-data/               # 证书存储（Docker 与原生共享）
│   ├── account.conf         # acme.sh 账户配置
│   └── example.v6.army/       # 您的域名的证书
│       ├── example.v6.army.cer      # 证书
│       ├── example.v6.army.key      # 私钥
│       ├── ca.cer                  # CA 证书
│       └── fullchain.cer           # 完整证书链
└── logs/                     # 日志文件
    ├── renewal.log           # 续期流程日志
    └── acme-native.log       # 原生 acme.sh 日志

原生 acme.sh 安装（在 DSM 主机上）：
/usr/local/share/acme.sh/    # 原生 acme.sh 安装位置
/usr/local/bin/acme.sh       # 原生 acme.sh 的符号链接
```

## 使用方法

### 手动证书签发

```bash
./scripts/issue-cert.sh
```

### 手动证书续期

```bash
# 检查并在需要时续期（< 30 天到期）
./scripts/renew-cert.sh

# 无论过期日期如何都强制续期
./scripts/renew-cert.sh --force
```

### 手动部署到 DSM

```bash
# 使用临时管理员模式（推荐）
sudo ./scripts/deploy-to-dsm.sh

# 使用凭据模式
./scripts/deploy-to-dsm.sh
```

### 检查证书过期时间

```bash
# 使用 OpenSSL
openssl x509 -in acme-data/${DOMAIN}/${DOMAIN}.cer -noout -dates

# 使用容器中的 acme.sh
docker-compose exec acme.sh --list
```

### 查看日志

```bash
# 续期日志
tail -f logs/renewal.log

# Docker 容器日志
docker-compose logs -f acme.sh
```

## 架构：混合架构方法

本项目使用**混合架构**，结合了 Docker 和原生安装：

### 为什么使用混合架构？

**Docker 用于证书签发/续期：**
- 干净、隔离的环境
- 易于更新和维护
- 无需修改系统
- 非常适合 DNS-01 验证

**原生 acme.sh 用于 DSM 部署：**
- 访问 DSM 系统工具（synouser、synogroup、synosetkeyvalue）
- 启用 `SYNO_USE_TEMP_ADMIN=1` 模式（无需存储密码）
- 直接与 Synology DSM API 集成
- 安全的临时管理员用户创建

### 共享证书存储

两个安装共享相同的证书目录（`acme-data/`）：
- 无证书重复
- Docker 签发/续期证书
- 原生 acme.sh 部署证书
- 所有证书的单一真实来源

### 工作流

```
┌─────────────────────────────────────────────────────────────────┐
│                        证书生命周期                              │
└─────────────────────────────────────────────────────────────────┘

1. 签发/续期（Docker）：
   ┌──────────────┐      ┌──────────────┐      ┌──────────────┐
   │ Docker       │ ───▶ │ Let's        │ ───▶ │ acme-data/   │
   │ acme.sh      │      │ Encrypt      │      │ (共享)       │
   └──────────────┘      └──────────────┘      └──────────────┘
         │                                              │
         │ 通过 dynv6 进行 DNS-01 验证                  │
         └─────────────────────────────────────────────┘

2. 部署（原生）：
   ┌──────────────┐      ┌──────────────┐      ┌──────────────┐
   │ acme-data/   │ ───▶ │ 原生         │ ───▶ │ Synology     │
   │ (共享)       │      │ acme.sh      │      │ DSM          │
   └──────────────┘      └──────────────┘      └──────────────┘
                                │
                                │ 使用 DSM 系统工具
                                │ (临时管理员支持)
                                └─────────────────────────────
```

更多详情，请参阅 [docs/DEPLOYMENT-OPTIONS.md](docs/DEPLOYMENT-OPTIONS.md)

## 配置详情

### 环境变量

| 变量 | 必需 | 默认值 | 描述 |
|----------|----------|---------|-------------|
| `DYNV6_TOKEN` | 是 | - | 从 https://dynv6.com/keys 获取的 dynv6 API 令牌 |
| `DOMAIN` | 是 | - | 您的域名（例如 example.v6.army） |
| `EMAIL` | 是 | - | 用于 Let's Encrypt 通知的邮箱 |
| `SYNO_USERNAME` | 否 | (临时管理员) | DSM 管理员用户名 |
| `SYNO_PASSWORD` | 否 | (临时管理员) | DSM 管理员密码 |
| `SYNO_SCHEME` | 否 | http | DSM 连接方案（http/https） |
| `SYNO_HOSTNAME` | 否 | localhost | DSM 主机名 |
| `SYNO_PORT` | 否 | 5000 | DSM 端口 |
| `SYNO_CERTIFICATE` | 否 | acme.sh | DSM 中的证书描述 |
| `ACME_SERVER` | 否 | letsencrypt | CA 服务器（letsencrypt/letsencrypt_test） |

### 使用临时管理员（推荐）

如果您将 `SYNO_USERNAME` 和 `SYNO_PASSWORD` 留空，脚本将使用 `SYNO_USE_TEMP_ADMIN=1` 模式，它将：
- 在部署期间创建临时管理员用户
- 不需要存储您的管理员密码
- 更安全，因为凭据不会持久化
- 仅在 NAS 本地运行时有效

### 使用现有管理员账户

如果您更愿意使用现有的管理员账户：
1. 将 `SYNO_USERNAME` 设置为您的 DSM 管理员用户名
2. 将 `SYNO_PASSWORD` 设置为您的 DSM 管理员密码
3. 如果启用了双因素认证，您可能需要提供 `SYNO_OTP_CODE` 或 `SYNO_DEVICE_ID`

## 故障排除

### 证书签发失败

**症状**：`issue-cert.sh` 失败并显示 DNS 验证错误

**解决方案**：
1. 验证您的 dynv6 令牌是否正确：
   ```bash
   # 测试 dynv6 API 访问
   curl -H "Authorization: Bearer YOUR_TOKEN" https://dynv6.com/api/v2/zones
   ```
2. 在 dynv6.com 检查域名所有权
3. 确保 `.env` 中的域名配置正确
4. 查看日志：`docker-compose logs acme.sh`

### 证书部署失败

**症状**：`deploy-to-dsm.sh` 失败并显示身份验证错误

**解决方案**：
1. 如果使用临时管理员模式：
   - 确保脚本以 root 身份运行：`sudo ./scripts/deploy-to-dsm.sh`
   - 验证 DSM 可通过 localhost:5000 访问
2. 如果使用凭据：
   - 验证用户名和密码是否正确
   - 检查是否启用了双因素认证（可能需要 `SYNO_OTP_CODE`）
3. 测试 DSM API 访问：
   ```bash
   curl "http://localhost:5000/webapi/query.cgi?api=SYNO.API.Info&version=1&method=query"
   ```

### Docker 容器无法启动

**症状**：`docker-compose up -d` 失败

**解决方案**：
1. 检查 Docker 是否已安装并运行：
   ```bash
   docker --version
   docker ps
   ```
2. 验证 docker-compose.yml 语法：
   ```bash
   docker-compose config
   ```
3. 检查 .env 文件语法（`=` 周围没有空格）
4. 查看详细错误：`docker-compose up`（不带 `-d`）

### 证书不会自动续期

**症状**：续期脚本不运行或静默失败

**解决方案**：
1. 在 DSM 控制面板中检查任务计划状态
2. 验证脚本具有执行权限：`ls -l scripts/renew-cert.sh`
3. 手动运行以查看错误：`./scripts/renew-cert.sh`
4. 查看日志：`cat logs/renewal.log`
5. 确保任务计划中的路径是绝对路径

### DNS 验证超时

**症状**：DNS-01 挑战失败并显示超时

**解决方案**：
1. dynv6 API 可能较慢，脚本将重试
2. 检查 dynv6.com 状态页面
3. 验证您的域名的 DNS 是否已传播：
   ```bash
   dig _acme-challenge.example.v6.army TXT
   ```
4. 如需要，增加 acme.sh 中的超时时间（编辑脚本）

## 安全最佳实践

1. **保护 .env 文件**：
   ```bash
   chmod 600 .env
   chown root:root .env
   ```

2. **使用临时管理员模式**：尽可能避免存储管理员密码

3. **定期备份**：定期备份 `acme-data/` 目录

4. **监控日志**：定期检查 `logs/renewal.log` 是否有问题

5. **限制 SSH 访问**：仅在需要时启用 SSH

6. **保持 Docker 更新**：在 DSM 套件中心更新 Docker 套件

## 维护

### 更新 acme.sh

```bash
# 拉取最新的 acme.sh 镜像
docker-compose pull

# 使用新镜像重启容器
docker-compose up -d
```

### 备份证书

```bash
# 创建备份
tar -czf acme-backup-$(date +%Y%m%d).tar.gz acme-data/

# 从备份恢复
tar -xzf acme-backup-YYYYMMDD.tar.gz
```

### 更改域名或 DNS 提供商

1. 停止容器：`docker-compose down`
2. 使用新值更新 `.env`
3. 删除旧证书：`rm -rf acme-data/*`
4. 启动容器：`docker-compose up -d`
5. 签发新证书：`./scripts/issue-cert.sh`

### 监控证书过期时间

```bash
# 检查过期日期
openssl x509 -in acme-data/${DOMAIN}/${DOMAIN}.cer -noout -enddate

# 列出 acme.sh 中的所有证书
docker-compose exec acme.sh --list
```

## 高级配置

### 使用测试服务器（测试）

用于测试时，使用 Let's Encrypt 测试服务器以避免速率限制：

```bash
# 在 .env 文件中
ACME_SERVER=letsencrypt_test
```

测试后，改回生产环境：
```bash
ACME_SERVER=letsencrypt
```

### 多个域名（SAN 证书）

为多个域名签发证书：

1. 更新 `.env`：
   ```bash
   DOMAIN="example.v6.army"
   ADDITIONAL_DOMAINS="-d www.example.v6.army -d sub.example.v6.army"
   ```

2. 所有域名必须由 dynv6 管理或支持相同的 DNS API

### 在 DSM 中自定义证书描述

在 DSM 中标识您的证书：

```bash
# 在 .env 文件中
SYNO_CERTIFICATE="我的自定义证书名称"
```

## 常见问题

**问：证书多久续期一次？**
答：每天检查证书。Let's Encrypt 证书有效期为 90 天，将在剩余不足 30 天时续期。

**问：如果续期失败会发生什么？**
答：脚本会记录错误并在第二天重试。在证书过期前您有 30 天时间修复问题。

**问：我可以使用 ZeroSSL 而不是 Let's Encrypt 吗？**
答：可以，修改 `issue-cert.sh` 以使用 `--server zerossl` 参数。

**问：这适用于 DSM 7.x 吗？**
答：本项目专为 DSM 6.2.3 设计。对于 DSM 7.x，您可能需要调整路径和 API 调用。

**问：这会影响我现有的 DSM 证书吗？**
答：如果 `SYNO_CERTIFICATE` 与现有证书描述匹配，它将被更新。否则，将创建一个新的证书条目。

**问：我可以在不使用 Docker 的情况下运行吗？**
答：可以，但您需要直接在 DSM 上安装 acme.sh。Docker 方法更干净且易于管理。

## 支持和资源

- **acme.sh 文档**：https://github.com/acmesh-official/acme.sh
- **dynv6 API 文档**：https://dynv6.com/docs/apis
- **Synology DSM 指南**：https://github.com/acmesh-official/acme.sh/wiki/Synology-NAS-Guide
- **Let's Encrypt**：https://letsencrypt.org/

## 许可证

本项目使用 acme.sh，其采用 GPLv3 许可证。本仓库中的脚本按原样提供，供个人使用。

## 贡献

如果您遇到问题或有改进建议：
1. 检查现有的问题和文档
2. 彻底测试您的更改
3. 记录任何修改
4. 与社区分享您的解决方案

## 更新日志

- **2025-10-26**：初始版本
  - 基于 Docker 的解决方案
  - dynv6 DNS-01 验证
  - 自动 DSM 部署
  - 每日续期检查
