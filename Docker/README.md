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