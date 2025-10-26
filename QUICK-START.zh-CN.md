# 快速开始指南 - Synology SSL 证书自动化

这是一份精简指南，可帮助您快速上手运行。详细文档请参阅 [README.zh-CN.md](README.zh-CN.md)。

## 前置要求检查清单

- [ ] 已安装 Synology（群晖）DSM 6.2.3 或更高版本
- [ ] 已在 Synology 上安装 Docker 套件
- [ ] 已启用 SSH 访问（需要 root 权限）
- [ ] 在 dynv6.com 注册的域名（例如 example.v6.army）
- [ ] 从 https://dynv6.com/keys 获取的 dynv6 API 令牌

## 安装步骤（15分钟）

### 1. 复制文件到您的 NAS

```bash
# 在您的 NAS 上，创建目录
ssh root@your-nas-ip
mkdir -p /volume1/docker/synology-acme
cd /volume1/docker/synology-acme

# 从此仓库复制所有文件
# (使用 WinSCP、FileZilla 或 rsync 传输文件)
```

### 2. 配置环境

```bash
cd /volume1/docker/synology-acme

# 从模板创建 .env
cp .env.example .env

# 使用您的实际值进行编辑
vi .env
```

**最小 .env 配置：**
```bash
DYNV6_TOKEN=your_token_from_dynv6_com
DOMAIN=example.v6.army
EMAIL=your-email@example.com
SYNO_USE_TEMP_ADMIN=1
```

**保护文件：**
```bash
chmod 600 .env
```

### 3. 启动 Docker 容器

```bash
# 启动容器
docker-compose up -d

# 验证它正在运行
docker-compose ps
```

### 4. 安装原生 acme.sh

```bash
# 安装原生 acme.sh 用于 DSM 部署
sudo ./scripts/install-acme-native.sh

# 这使得无需存储密码即可进行安全部署
```

**为什么？** 原生安装使 acme.sh 能够访问 `SYNO_USE_TEMP_ADMIN=1` 模式所需的 DSM 系统工具。

### 5. 签发证书

```bash
# 签发您的第一个证书（使用 Docker）
./scripts/issue-cert.sh

# 这将需要 2-3 分钟
```

### 6. 部署到 DSM

```bash
# 将证书部署到 DSM（使用原生 acme.sh，需要 root）
sudo ./scripts/deploy-to-dsm.sh
```

### 7. 设置自动续期

**重要：** Synology DSM **不支持** `crontab` 命令。请改用任务计划。

**使用 DSM 任务计划（唯一方法）：**

1. 打开 DSM → 控制面板 → 任务计划
2. 新增 → 计划的任务 → 用户定义的脚本
3. 常规选项卡：
   - 任务名称：`SSL Certificate Renewal`
   - 用户账号：`root`
   - 已启用：✓
4. 计划选项卡：
   - 执行日期：`每天`
   - 执行时间：`02:00`（或任何您偏好的时间）
5. 任务设置选项卡：
   - 脚本：
     ```bash
     bash /volume1/docker/synology-acme/scripts/renew-cert.sh
     ```
6. 点击确定

**关于每日检查：**
脚本每天运行，但仅在剩余 < 30 天时续期。每日仅检查的运行耗时 < 1 秒，资源占用极小。这是 Let's Encrypt 的标准最佳实践。

### 8. 测试续期（可选）

**通过任务计划测试（推荐）：**
1. 进入 DSM 中的任务计划
2. 选择"SSL Certificate Renewal"任务
3. 点击"运行"按钮
4. 在任务计划或 `logs/renewal.log` 中查看结果

**预期结果：** 脚本将检查证书并退出（如果证书是新的，则不需要续期）

**通过 SSH 测试完整续期（可选）：**
```bash
# 切换到 root 并强制续期
sudo su -
cd /volume1/docker/synology-acme
./scripts/renew-cert.sh --force

# 查看日志
tail -f logs/renewal.log
```

## 完成！

您的证书现在将在过期前每天自动续期。证书有效期为 90 天，将在剩余不足 30 天时续期。

## 验证安装

### 在 DSM 中检查证书
1. 打开 DSM → 控制面板 → 安全性 → 证书
2. 找到名为"acme.sh"的证书
3. 验证域名和过期日期

### 检查证书文件
```bash
ls -lh acme-data/example.v6.army/
```

### 检查续期日志
```bash
tail -50 logs/renewal.log
```

## 常见问题和快速修复

### 问题："DYNV6_TOKEN is not set"
**修复：** 编辑 `.env` 并从 https://dynv6.com/keys 添加您的 dynv6 令牌

### 问题："acme.sh container is not running"
**修复：** 运行 `docker-compose up -d`

### 问题："Certificate deployment failed"
**修复：** 确保使用 sudo 运行：`sudo ./scripts/deploy-to-dsm.sh`

### 问题："DNS validation timeout"
**修复：** 等待 1-2 分钟后重试。dynv6 DNS 可能需要时间传播。

### 问题："Permission denied"
**修复：**
```bash
chmod +x scripts/*.sh
chmod 600 .env
```

## 下一步

- 阅读 [README.zh-CN.md](README.zh-CN.md) 获取详细文档
- 查看 [plan.md](plan.md) 了解架构详情
- 配置您的应用程序使用新证书
- 设置证书过期监控

## 文件结构概述

```
/volume1/docker/synology-acme/
├── docker-compose.yml         # 容器配置
├── .env                       # 您的设置（保密！）
├── .env.example              # 模板
├── README.md                 # 英文完整文档
├── README.zh-CN.md           # 中文完整文档
├── QUICK-START.md            # 英文快速开始
├── QUICK-START.zh-CN.md      # 本文件
├── docs/
│   └── DEPLOYMENT-OPTIONS.md # 架构详情
├── scripts/
│   ├── install-acme-native.sh # 安装原生 acme.sh
│   ├── issue-cert.sh        # 签发证书（Docker）
│   ├── renew-cert.sh        # 续期证书（Docker + 原生）
│   └── deploy-to-dsm.sh     # 部署到 DSM（原生）
├── acme-data/               # 证书（共享存储）
└── logs/                    # 日志（自动创建）

/usr/local/share/acme.sh/    # 原生 acme.sh（在 DSM 主机上）
```

## 重要命令

```bash
# 安装原生 acme.sh（一次性设置）
sudo ./scripts/install-acme-native.sh

# 签发证书（Docker）
./scripts/issue-cert.sh

# 部署到 DSM（原生 acme.sh）
sudo ./scripts/deploy-to-dsm.sh

# 续期证书（如需要时检查，Docker + 原生）
sudo ./scripts/renew-cert.sh

# 强制续期
sudo ./scripts/renew-cert.sh --force

# 检查证书过期时间
openssl x509 -in acme-data/${DOMAIN}/${DOMAIN}.cer -noout -dates

# 查看日志
tail -f logs/renewal.log
tail -f logs/acme-native.log

# 重启 Docker 容器
docker-compose restart

# 查看容器日志
docker-compose logs -f
```

## 支持

- 完整文档：[README.zh-CN.md](README.zh-CN.md)
- 架构：[plan.md](plan.md)
- acme.sh 文档：https://github.com/acmesh-official/acme.sh
- dynv6 文档：https://dynv6.com/docs/apis
