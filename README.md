# Epay Docker Stack
   ```bash
   cd /opt/Epaydocker
   cp Docker/env.example Docker/.env
   vi Docker/.env
   cd /opt/Epaydocker/Docker/
   ```
2. 初始化持久化目录（首次部署时执行）：
   ```bash
   mkdir -p Docker/data/mysql Docker/data/redis Docker/logs/nginx
   sudo chown -R 1000:1000 Docker/data Docker/logs || true
   ```
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
| `TZ` | `Asia/Shanghai` | 容器时区，影响日志与定时任务。 |

> **提示**：`Docker/.env` 会被 Compose 自动加载，应用代码内的 `.env` 需另外维护。

## 服务说明
| 服务       | 说明                         | 端口映射 | 数据卷挂载 |
|------------|------------------------------|----------|------------|
| `web`      | PHP 8.2 FPM 主业务进程，预装常用扩展及调试工具 | 无外部暴露 | 项目目录挂载至 `/var/www/html`，并将日志输出到宿主机 `Docker/logs/nginx` |
| `nginx`    | Nginx 1.27 反向代理，转发到 `web` 服务 | 80:80 | 共享项目目录、`nginx.conf`，日志输出到 `Docker/logs/nginx` |
| `mysql`    | MySQL 8.0 数据库             | 3306:3306 | `Docker/data/mysql`（持久化数据） |
| `redis`    | Redis 7.0 缓存与队列         | 6379:6379 | `Docker/data/redis` |
| `scheduler`| 与 `web` 同镜像的任务容器    | 无外部暴露 | 与 `web` 共用代码目录、环境变量 |

### 调度器任务
`scheduler` 服务默认执行 `php /var/www/html/cron.php`，可在 `docker-compose.yml` 中通过 `command` 字段调整为框架任务（如 `php artisan schedule:work`、`php think queue:listen`）。如需多任务并行，可复制该服务并改名。

## 健康检查
- `web`：通过 FPM `/ping` 接口判断进程可用性。
- `nginx`：本地 `curl` 请求站点根路径。
- `mysql`：使用 `mysqladmin ping` 检测。
- `redis`：执行 `redis-cli ping`。
- `scheduler`：健康状态与 `web` 相同，确保任务执行容器保持可用。

`docker compose ps` / `docker inspect` 可实时查看健康状态，失败时自动重启，便于运维监控。

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
