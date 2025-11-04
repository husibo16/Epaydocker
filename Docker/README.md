# Epay Docker Stack

该目录提供基于 **PHP 8.2 + MySQL 8.0 + Redis 7.0** 的生产级容器化方案，覆盖 Web、Nginx 网关、数据库、缓存及任务调度服务。所有服务均加入同一虚拟网络 `backend`，便于内部通信并保持外部隔离。

## 目录结构
```
Docker/
├── Dockerfile          # 构建 PHP FPM / Scheduler 镜像
├── docker-compose.yml  # 多容器编排入口
├── nginx.conf          # Nginx 反向代理配置
├── php.ini             # PHP 自定义配置
├── entrypoint.sh       # PHP 容器启动脚本
├── env.example         # 环境变量示例
├── data/               # 持久化数据卷
│   ├── mysql/
│   └── redis/
└── logs/
    └── nginx/
```

## 先决条件
- Docker Engine ≥ 24.x
- Docker Compose Plugin ≥ 2.20（或安装 `docker-compose` 二进制）
- 服务器需开放 80、3306、6379 端口供外部访问

## 快速开始
1. 复制环境变量模板并按需修改：
   ```bash
   cp Docker/env.example Docker/.env
   vi Docker/.env
   ```
2. 初始化持久化目录（首次部署时执行，可按需自定义宿主机路径）：
   ```bash
   mkdir -p Docker/data/mysql Docker/data/redis Docker/logs/nginx
   ```
   Redis 持久化目录的权限会在启动时由自动化任务修正，无需手工 `chown`。
3. 在 `Docker` 目录下启动：
   ```bash
   cd Docker
   docker compose up -d --build
   ```
4. 通过浏览器访问 `http://<宿主机 IP>`，完成彩虹易支付的安装流程。

## 关键环境变量
| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `APP_URL` | `http://localhost` | 应用对外访问地址，用于生成回调、静态资源链接。 |
| `DB_HOST` | `mysql` | 数据库主机名，指向 Compose 内部的 MySQL 服务，可改为外部数据库地址。 |
| `DB_PORT` | `3306` | 数据库端口。 |
| `DB_DATABASE` | `epay` | 业务数据库名，与应用安装向导保持一致。 |
| `DB_USERNAME` / `DB_PASSWORD` | - | 数据库账号与密码，首次部署可在 `.env` 中设定，并与安装界面保持一致。 |
| `REDIS_HOST` / `REDIS_PORT` | `redis` / `6379` | 缓存与队列服务连接信息，可切换到托管 Redis。 |
| `PHP_MEMORY_LIMIT` | `256M` | PHP 内存限制，可根据业务场景调整。 |
| `PHP_UPLOAD_LIMIT` | `64M` | 上传文件大小限制，对支付凭证等上传敏感。 |
| `SCHEDULER_INTERVAL` | `60` | 调度器容器重复执行 `cron.php` 的时间间隔（秒），用于控制任务频率。 |
| `TZ` | `Asia/Shanghai` | 容器时区，影响系统日志、计划任务及数据库默认时区。 |
| `PHP_TIMEZONE` | 空 | 覆盖 PHP `date.timezone` 设置；为空时默认继承 `TZ`，否则保持镜像内置值。 |

> **提示**：`Docker/.env` 会被 Compose 自动加载，应用代码内的 `.env` 需另外维护。

## 服务说明
| 服务       | 说明                         | 端口映射 | 数据卷挂载 |
|------------|------------------------------|----------|------------|
| `web`      | PHP 8.2 FPM 主业务进程，预装常用扩展及调试工具 | 无外部暴露 | 项目目录挂载至 `/var/www/html`，并将日志输出到宿主机 `Docker/logs/nginx` |
| `nginx`    | Nginx 1.27 反向代理，转发到 `web` 服务 | 80:80 | 共享项目目录、`nginx.conf`，日志输出到 `Docker/logs/nginx` |
| `mysql`    | MySQL 8.0 数据库             | 3306:3306 | `Docker/data/mysql`（持久化数据） |
| `redis`    | Redis 7.0 缓存与队列（启动时自动矫正数据目录权限） | 6379:6379 | `Docker/data/redis` |
| `scheduler`| 与 `web` 同镜像的任务容器    | 无外部暴露 | 与 `web` 共用代码目录、环境变量 |

### 调度器任务
`scheduler` 服务以内置脚本循环执行 `php /var/www/html/cron.php`，默认每 60 秒运行一次，可在 `.env` 中通过 `SCHEDULER_INTERVAL` 调整频率。若需改为框架原生任务（如 `php artisan schedule:work`、`php think queue:listen`），可在 Compose 中覆盖 `command` 并视需要扩容多个调度器服务。

## 健康检查
- `web`：通过 FPM `/ping` 接口判断进程可用性。
- `nginx`：执行 `nginx -t` 确认配置语法正常。
- `mysql`：使用 `mysqladmin ping` 检测。
- `redis`：执行 `redis-cli ping`。
- `scheduler`：执行 `php -v` 验证 PHP 运行时可用，确保任务循环脚本运行正常。

`docker compose ps` / `docker inspect` 可实时查看健康状态，失败时自动重启，便于运维监控。

## 自愈与重启策略
所有服务均设置 `restart: unless-stopped`，Docker 在宿主机重启或容器异常退出后会自动恢复运行。若需手动停用，请执行 `docker compose stop <service>`；恢复时使用 `docker compose start <service>` 即可。

## 故障排查
- **Nginx 启动提示 `can not modify /etc/nginx/conf.d/default.conf`**：项目自带的覆盖脚本会阻止官方镜像修改挂载的 `default.conf`，以免出现只读警告。若日志仍出现该提示，请确认 `Docker/nginx-entrypoint.d` 目录已正确挂载。
- **Redis 启动提示 `Can't open or create append-only dir appendonlydir`**：容器会在启动时自动修复数据目录权限并预创建 `appendonlydir`，通常下一次重启即可恢复。若仍然失败，请确认宿主机目录可写，并重新执行 `docker compose up -d redis` 以触发修复流程。
- **Redis 警告 `Memory overcommit must be enabled`**：这是宿主机内核参数未开启所致，进入宿主机执行 `sysctl -w vm.overcommit_memory=1`，并在 `/etc/sysctl.conf` 加入 `vm.overcommit_memory = 1` 以便重启后生效。

## 常用操作
| 操作 | 命令 |
|------|------|
| 查看实时日志 | `docker compose logs -f <service>` |
| 进入容器调试 | `docker compose exec web bash` |
| 执行数据库备份 | `docker compose exec mysql mysqldump -uroot -p$MYSQL_ROOT_PASSWORD epay > backup.sql` |
| 停止并移除服务 | `docker compose down` |
| 清理数据后重装 | `docker compose down -v`（将删除 `data/` 数据，谨慎操作） |

## 生产环境最佳实践
- 将 `Docker/.env` 和应用内 `.env` 列入 `.gitignore`，敏感信息通过 CI/CD 或密钥管理系统注入。
- 开启 HTTPS：在宿主机或上层负载均衡器终止 TLS，并将请求转发到 `nginx`。
- 配置备份：
  - MySQL：使用计划任务执行 `mysqldump` 或者对接云数据库备份。
  - Redis：启用持久化（AOF/RDB）并复制 `Docker/data/redis`。
- 监控报警：结合 Prometheus、Zabbix 等工具监控容器 CPU、内存、磁盘以及服务健康状态。
- 水平扩展：生产环境可将 `nginx`、`web` 拆分至多台宿主机，通过 Swarm/Kubernetes 或外部负载均衡统一调度。
- 日志管理：将 Nginx、PHP 日志挂载到宿主机后可接入 ELK / Loki 等集中式日志系统。
- 


# Epaydocker 生产部署手册（Debian/Ubuntu）

> 适用对象：Debian/Ubuntu 系统管理员与开发人员。
>
> 目标：用 Docker Compose 在 /opt/Epaydocker 下以最小手工步骤完成稳定、可回滚、可观测的生产部署。

---

## 0. 环境与前置条件

* **操作系统**：Debian 11/12、Ubuntu 20.04/22.04/24.04（64 位）
* **用户权限**：root 或具备 sudo 权限
* **网络**：可访问 GitHub 与 Docker 官方仓库
* **时间同步**：建议启用 `systemd-timesyncd` 或 `chrony`
* **可选**：开启防火墙（ufw/iptable），本文示例以 `ufw` 为主

### 0.1 一次性基础检查（可选）

```bash
# 查看系统版本
lsb_release -a || cat /etc/os-release

# 时间同步状态（systemd）
timedatectl status

# 磁盘空间（建议留足 /var/lib/docker 与 /opt）
df -h
```

---

## 1. 安装 Docker 与 Docker Compose 插件

```bash
sudo apt update
curl -fsSL https://get.docker.com | bash
sudo systemctl enable docker
sudo systemctl start docker
sudo apt install -y docker-compose-plugin

# （可选）将当前用户加入 docker 组，避免到处写 sudo
sudo usermod -aG docker "$USER"
# 注：若执行，上线后需重新登录会话生效
```

### 1.1 验证安装

```bash
docker --version
docker compose version
sudo systemctl status docker --no-pager
```

---

## 2. 获取项目代码

```bash
sudo mkdir -p /opt && cd /opt
sudo git clone https://github.com/husibo16/Epaydocker.git
cd /opt/Epaydocker
```

> 若服务器不允许直连 GitHub，请提前配置代理或使用企业镜像。

---

## 3. 调整内核内存分配策略（overcommit）

> **目的**：某些服务在高并发或内存映射场景需要更宽松的内存承诺策略，避免异常 OOM 影响启动/构建过程。

```bash
echo "vm.overcommit_memory=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 验证
sysctl vm.overcommit_memory
# 期望输出：vm.overcommit_memory = 1
```

> 说明：`1` 表示允许内核在一定程度上超量承诺内存；如有严格合规需求，可在压测评估后调回 `0` 并配合 cgroup/oom_score 调优。

---

## 4. 准备环境变量与 Compose 文件

### 4.1 复制并进入 Docker 目录

```bash
cp Docker/env.example Docker/.env
cd /opt/Epaydocker/Docker
```

### 4.2 生成强随机口令（生产级）

```bash
# 生成 16 字符强口令（base64 源，去换行，截断 16）
openssl rand -base64 24 | tr -d '\n' | fold -w 16 | head -n 1
```

> 建议为数据库、JWT、管理后台等敏感字段分别生成不同口令，并妥善保存到密码管家（如 1Password / Bitwarden）。

### 4.3 编辑 `.env`

```bash
nano .env
```

将上面的随机口令填入相应变量（如 `DB_PASSWORD`、`JWT_SECRET`、`ADMIN_PASSWORD` 等）。

> **提示**：具体键名以 `env.example` 为准。不要在 `.env` 中加入引号；如有空格或特殊字符，建议改为不含空格的复杂口令。

### 4.4 修改 `docker-compose.yml` 端口映射

```bash
nano docker-compose.yml
```

* 将 `ports:` 下的 `宿主机端口:容器端口` 按需调整，例如将 Web 服务改到 `8080:80`。
* 如涉及多服务端口，确保宿主机端口**不冲突**；数据库端口如不对公网暴露，可仅在内部网络使用，去掉对应 `ports` 并通过 `depends_on`/网络别名访问。

> **意见**（生产化）：
>
> 1. 对公网只开放反向代理的 80/443，后端与数据库**不要**映射到宿主机；
> 2. 使用独立 `docker network`（compose 会自动建）维持容器间通信。

---

## 5. 首次启动与验证

### 5.1 构建并后台启动

```bash
docker compose up -d --build
```

### 5.2 查看容器与日志

```bash
docker ps

docker compose logs -f
# 按 Ctrl+C 退出日志跟随
```

### 5.3 基本连通性检查

* 如果 web 服务暴露在 `http://SERVER_IP:PORT/`，从跳板机或本机浏览器访问。
* 服务器本地可用 `curl` 验证：

```bash
curl -I http://127.0.0.1:8080/
```

* 数据库类服务仅内部访问时，可在容器内 `exec`：

```bash
docker exec -it <web容器名> sh -lc 'nc -zv <db服务名> 5432'
```

---

## 6. 安全与网络加固（强烈建议）

### 6.1 防火墙（ufw）

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
# 仅按需开放
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP（若使用反代）
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
sudo ufw status verbose
```

### 6.2 仅暴露必要端口

* 在 `docker-compose.yml` 中移除数据库等内网服务的 `ports` 映射，改用容器网络访问。

### 6.3 HTTPS 与反向代理（可选）

* 生产上建议用 Nginx/Traefik 反向代理签发 Let’s Encrypt 证书。
* 若需要，一并纳入本 compose，或将反代放到独立节点。

---

## 7. 运维日常命令（速查）

```bash
# 查看/跟随日志
docker compose logs --tail=200 -f

# 查看单个服务日志
docker compose logs -f <service-name>

# 进入容器
docker exec -it <container-name> /bin/sh

# 重启单服务或全部
docker compose restart <service-name>
docker compose restart

# 重新构建（变更了 Dockerfile/依赖）
docker compose build --no-cache && docker compose up -d

# 查看资源占用
docker stats

# 导出当前容器与网络信息（排障）
docker compose ps
docker network ls && docker network inspect <network-name>
```

---

## 8. 备份与数据持久化

> **核心原则**：所有需要持久的数据（数据库、上传文件、配置卷）必须映射到宿主机目录或命名卷。

### 8.1 检查卷映射

```bash
docker compose config | sed -n '/volumes:/,$p'
```

确认关键路径是否为命名卷或 `./data/...` 主机目录。

### 8.2 快照式备份（示例）

```bash
# 备份命名卷到 tar.gz
VOL=mydata
BACKUP=/opt/backup
sudo mkdir -p "$BACKUP"
docker run --rm -v ${VOL}:/volume -v ${BACKUP}:/backup alpine \
  sh -lc 'cd /volume && tar czf /backup/${VOL}-$(date +%F).tar.gz .'
```

### 8.3 数据库备份（示例：PostgreSQL/MySQL）

```bash
# PostgreSQL
docker exec -t <pg-container> pg_dump -U <user> <db> | gzip > /opt/backup/pg-$(date +%F).sql.gz

# MySQL/MariaDB
docker exec -t <mysql-container> mysqldump -u<user> -p<pass> <db> | gzip > /opt/backup/mysql-$(date +%F).sql.gz
```

> 备份需配合离站（对象存储/SFTP）与自动清理策略。

---

## 9. 升级与回滚

### 9.1 更新代码与镜像

```bash
cd /opt/Epaydocker
git pull
cd Docker
docker compose pull        # 拉取新镜像（若使用远端镜像）
docker compose up -d --build
```

### 9.2 回滚策略

* 代码层面：`git checkout <tag/commit>` 后重建
* 镜像层面：使用**显式版本标签**锁定镜像（避免 `latest`），回滚时切换回旧 tag
* 数据层面：用第 8 节的备份包恢复

---

## 10. 监控与告警（建议）

* 轻量方案：`docker logs` + `node_exporter`/`cAdvisor` + Prometheus + Grafana
* SLA 要求较高：接入现有 APM（如 OpenTelemetry/Jaeger）与外网可用性探测（Upptime/Uptime Kuma）

---

## 11. 常见问题（FAQ）

**Q1: `permission denied` 或代码目录不可写？**
A：检查宿主机目录所属与权限，必要时：

```bash
sudo chown -R $USER:$USER /opt/Epaydocker
sudo chmod -R u+rwX,go-rwx /opt/Epaydocker
```

**Q2: `bind: address already in use` 端口占用？**
A：查找占用并调整 compose 端口：

```bash
sudo lsof -iTCP -sTCP:LISTEN -nP | grep ':80\|:443\|:8080'
```

**Q3: 容器反复重启（Restarting）？**
A：`docker compose logs -f <service>` 查看具体报错；重点核对 `.env` 必填项与数据库连通性。

**Q4: GitHub 拉取失败？**
A：配置代理或使用镜像站；或转为企业 GitLab 并更新仓库地址。

**Q5: 如何彻底清理重来？**
A：

```bash
cd /opt/Epaydocker/Docker
docker compose down -v   # 小心：会删除命名卷数据
# 如需保留数据，先做第 8 节的备份
```

---

## 12. 一键部署脚本（可选，生产化模板）

> 以下脚本基于“智能版 Bash 标准模板”裁剪版，适合首次安装与升级。请在 **交付前** 根据你的实际服务名称、端口与必需环境变量调整注释处。

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME=$(basename "$0")
LOG() { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }
ERR() { printf "[%s] [ERROR] %s\n" "$(date +'%F %T')" "$*" 1>&2; }

trap 'ERR "${SCRIPT_NAME} failed at line $LINENO"' ERR

#=== 0) preflight ===#
command -v curl >/dev/null || { ERR "curl 未安装"; exit 1; }
command -v git  >/dev/null || { ERR "git 未安装"; exit 1; }

#=== 1) docker ===#
if ! command -v docker >/dev/null; then
  LOG "安装 Docker..."
  sudo apt update
  curl -fsSL https://get.docker.com | bash
  sudo systemctl enable --now docker
  sudo apt install -y docker-compose-plugin
fi

#=== 2) sysctl ===#
if ! sysctl vm.overcommit_memory | grep -qE ' = 1$'; then
  LOG "设置 vm.overcommit_memory=1"
  echo "vm.overcommit_memory=1" | sudo tee -a /etc/sysctl.conf
  sudo sysctl -p
fi

#=== 3) fetch repo ===#
TARGET=/opt/Epaydocker
if [ ! -d "$TARGET/.git" ]; then
  LOG "克隆仓库到 $TARGET"
  sudo mkdir -p /opt && cd /opt
  sudo git clone https://github.com/husibo16/Epaydocker.git
fi

cd "$TARGET/Docker"

#=== 4) env bootstrap ===#
[ -f ./.env ] || { cp ../Docker/env.example ./.env && LOG "已生成 .env（请根据实际修改）"; }

#=== 5) build & up ===#
LOG "构建并启动..."
docker compose up -d --build

docker compose ps
LOG "完成。使用 'docker compose logs -f' 查看启动日志。"
```

> 使用：将脚本保存为 `bootstrap.sh`，上传到服务器并执行：

```bash
chmod +x bootstrap.sh && ./bootstrap.sh
```

---

## 13. 交付清单（上线前确认）

* [ ] `.env` 已按生产要求设置，敏感信息存于密码管家
* [ ] `docker-compose.yml` 仅对外暴露 80/443 或必要端口
* [ ] 防火墙规则已生效，禁止多余入站
* [ ] 卷与数据目录映射清晰，备份策略已就绪并验证还原
* [ ] 监控/日志/告警链路可用
* [ ] 明确的升级与回滚流程已在预生产验证

---

## 14. 附录：快速故障排查命令

```bash
# 查看失败容器的退出码与重启次数
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# 查看容器最后 200 行日志
docker logs --tail 200 <container>

# 检查容器内 DNS/网络
docker exec -it <container> sh -lc 'cat /etc/resolv.conf; ping -c2 8.8.8.8 || true'

# 检查卷的实际挂载点
docker inspect <container> | jq '.[0].Mounts'
```

> 若需面向团队或客户的 PDF 版，可在右上角导出/打印本手册。
