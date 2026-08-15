# 瀚高数据库 SEE 4.5.8 背景资料

## 产品概述

HighGo Security Enterprise Edition（安全版）4.5.8，基于 PostgreSQL 12.7 内核（build 20220708），
面向安全审计场景的国产数据库。与社区 PostgreSQL 的关键差异如下，容器化时必须逐项处理：

## 三权分立账户体系

| 账户 | 角色 | 用途 |
|------|------|------|
| `sysdba` | 数据库管理员 | CREATEDB/CREATEROLE，日常管理 |
| `syssso` | 安全管理员 | 用户锁定/解锁（`SELECT user_unlock('user')`） |
| `syssao` | 审计管理员 | 审计策略管理 |

三个账户密码在 `initdb` 时通过密码文件设置（三行文本，依次对应 sysdba/syssao/syssso）。
initdb 不接受 `-U` 参数，固定初始化 `sysdba`。

## 密码规则（重要）

密码必须同时包含大小写字母、数字、特殊字符，且**不得包含子串 "go"**。
示例合规密码：`Secsmart#612`。

## 认证方式

- 仅支持 **sm3**（国密哈希）认证；**不支持 trust**（服务端报 `invalid authentication method "trust"` 并拒绝 reload）
- psql 客户端通过 `PGPASSWORD` 环境变量传密码；`.pgpass` 在 sm3 下不可靠
- 容器方案建议 `ssl = off`（SSL 在本环境下存在兼容问题）

## 端口约定

| 端口 | 用途 |
|------|------|
| 5866 | hgproxy 连接池代理监听端口（应用连接入口） |
| 5867 | 数据库服务端口（运维/探针/验证直连入口） |

**本任务范围：数据库本体 + hgproxy 连接池代理**。hgproxy 是瀚高自带的连接池代理组件：
- 监听 5866，后端指向数据库 5867（同 Pod 内 127.0.0.1:5867）
- 配置：`proxy.conf`（[Proxy] 段 port=5866；[BackendNode] 段 hostname0/port0 指向数据库；[DatabaseCheck] 段 lifecheck_user=sysdba、lifecheck_dbname=highgo）
- 启动/停止：`proxy_ctl start|stop`（hgproxy 安装目录 `/opt/highgo/hgproxy/bin/`）
- 应用连接走 hgproxy（5866），运维/探针/验证直连数据库端口（5867）

**hgproxy 组件来源**：安装包 `hgdb-see-4.5.8/` 内**不含** hgproxy（仅含客户端工具 pcmcli）。hgproxy 完整组件（bin/proxy_ctl + etc/proxy.conf + lib/）位于附件 `materials/hgproxy/`（提取自官方镜像，REVISION f0344bc），镜像构建时拷入镜像，来源与 REVISION 在 PROGRESS.md 如实记录。

## hgproxy 初始化机制（必读，关键）

hgproxy 启动前必须完成**密码初始化**，否则 lifecheck 无法连接数据库（坑 2.1 的死锁即源于此）。完整流程：

1. **准备 runtime 配置**：`proxy.conf` 需先渲染到 `${HGPROXY_HOME}/etc/runtime/proxy.conf`（目录需自行创建），渲染要点：
   - `[Proxy]` 段 `port` = hgproxy 监听端口（默认 5866）
   - `[BackendNode]` 段 `hostname0`/`port0` 指向同 Pod 数据库（127.0.0.1:5867）
   - `[DatabaseCheck]` 段 `lifecheck_user=sysdba`、`lifecheck_dbname=highgo`
2. **初始化密码**（首次启动时执行一次，生成 `.proxy_passwd`）：
   ```bash
   ${HGPROXY_HOME}/bin/proxy_ctl init \
     -h 127.0.0.1 -p 5867 -d highgo \
     -U sysdba -w '<sysdba密码>' \
     -f ${HGPROXY_HOME}/etc/runtime/proxy.conf
   ```
   该命令会连接数据库校验 sysdba 密码，并在 `${HGPROXY_HOME}/etc/runtime/.proxy_passwd` 写入 lifecheck 密码（sm3 哈希 JSON 格式）。**必须先等数据库就绪（pg_isready 通过）再执行 init**。
3. **启动**：`${HGPROXY_HOME}/bin/proxy_ctl start`
4. **幂等**：`.proxy_passwd` 已存在时跳过 init（重启不重复初始化）；若三权密码变更，需删除 `.proxy_passwd` 重新 init。

**易踩点**：`proxy_ctl init` 必须在数据库就绪后执行（需等待 pg_isready）；`proxy_ctl start` 失败时先看 `/var/log/hgproxy/hgproxy.log`（或 proxy.conf `[Log]` 段配置的日志路径）。

## 关键目录（容器内建议路径）

- 软件家目录：`/opt/highgo/hgdb-see-4.5.8`（安装包直接解压即可用）
- hgproxy 目录：`/opt/highgo/hgproxy`（构建镜像时从附件 materials/hgproxy/ 拷入）
- 数据目录 `PGDATA`：建议 `/var/lib/highgo/data`
- 审计目录：`${PGDATA}/hgaudit`

## 环境变量命名参考（建议约定，非强制）

为保证"镜像 env 配置体系 ↔ Web 表单参数"一一对应可评审，建议采用以下命名（与官方镜像实现一致的惯例）：

| 环境变量 | 含义 | 默认值 |
|---------|------|--------|
| `HGDB_HOME` | 数据库软件目录 | /opt/highgo/hgdb-see-4.5.8 |
| `HGPROXY_HOME` | hgproxy 目录 | /opt/highgo/hgproxy |
| `PGDATA` | 数据目录 | /var/lib/highgo/data |
| `PGPORT` | 数据库监听端口 | 5867 |
| `HGPROXY_PORT` | hgproxy 监听端口 | 5866 |
| `HGDB_SYSDBA_PASSWORD` | sysdba 密码 | 无 |
| `HGDB_SYSSAO_PASSWORD` | syssao 密码 | 无 |
| `HGDB_SYSSSO_PASSWORD` | syssso 密码 | 无 |
| `HGDB_MAX_CONNECTIONS` | max_connections | 100 |
| `HGDB_SHARED_BUFFERS` | shared_buffers | 128MB |
| `HGDB_ENCODING` | 编码 | UTF8 |
| `HGDB_LOCALE` | locale | C |
| `HGDB_SSL` | 数据库 SSL | off |
| `HGDB_LISTEN_ADDRESSES` | 监听地址（远程访问须为 \*） | \* |
| `HGPROXY_ENABLE` | 是否启用 hgproxy | true |
| `HGPROXY_MAX_CONNECTION` | proxy 最大连接 | 1000 |

**三权密码三行密码文件顺序**：依次为 sysdba/syssao/syssso（initdb `--pwfile` 读取，每行一个密码，末尾换行）。

## initdb 实测命令模板（参考，非强制）

```bash
# 首次初始化（PGDATA 必须为空目录，先 mkdir -p $(dirname PGDATA) 但不要创建 PGDATA 本身）
PWFILE=$(mktemp); umask 077
printf '%s\n' "${HGDB_SYSDBA_PASSWORD}" "${HGDB_SYSSAO_PASSWORD}" "${HGDB_SYSSSO_PASSWORD}" > "${PWFILE}"
${HGDB_HOME}/bin/initdb \
  -D "${PGDATA}" \
  --encoding="${HGDB_ENCODING:-UTF8}" \
  --locale="${HGDB_LOCALE:-C}" \
  --pwfile="${PWFILE}"
rm -f "${PWFILE}"
```

- initdb **不接受** `-U` 参数（固定初始化 sysdba）
- 二次启动判定：`PGDATA/PG_VERSION` 存在即视为已初始化，跳过 initdb
- 日志目录 `${PGDATA}/log` 须在 initdb 成功后创建（initdb 要求数据目录为空）

## DDL 限制

默认存在 `abort_ddl` 事件触发器拦截所有 DDL，操作时需：
```sql
ALTER EVENT TRIGGER abort_ddl DISABLE;
-- DDL
ALTER EVENT TRIGGER abort_ddl ENABLE;
```

## License 机制（必读）

- 安装包内**不含** License 文件（`etc/lic/` 为空目录）
- 无 License 文件时启用试用模式，试用期 30 天，**从数据目录首次 initdb 起算**
- 试用期结束后数据库内核拒绝启动（`FATAL: ... license has expired`）
- **全新数据目录重新 initdb = 试用期重置**
- 详见 KNOWN_ISSUES.md 坑 1
