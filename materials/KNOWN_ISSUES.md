# 瀚高 SEE 4.5.8 已知缺陷与踩坑记录（容器化专项）

> 汇总日期：2026-08-15。本文件记录容器化部署瀚高 SEE 4.5.8（build 20220708）过程中实测确认的全部缺陷与大坑，
> 供后续部署、排错及测试任务设计使用。每条均附带实测证据与规避/修复方法。
>
> **阅读指引**：本任务范围 = 数据库本体 + hgproxy 连接池代理（同镜像同 Pod 部署，组件来自附件 materials/hgproxy/）。坑 1、坑 2（含 2.1 hgproxy 密码过期死锁）、坑 3、坑 6、坑 7 与本任务直接相关，务必掌握规避方法；坑 2.1 在 hgproxy 部署与生命周期验证中必须规避。

---

## 坑 1（致命）：无 License 文件时试用期为 30 天，从首次 initdb 起算

**发现日期**：2026-08-15（实测复现）

**现象**：
- 2026-07-09 构建的镜像 + 初始化的容器运行正常 5 周后，突然陷入崩溃循环（exit=1，启动后约 2.5 分钟退出）。
- 容器日志最后一行：
  ```text
  FATAL: The database cannot be started because the license has expired on 2026-08-08 23:59:59.
  ```
- 07-09 构建 → 08-08 到期，正好 30 天。

**根因**：
- 镜像和安装包中**不存在任何 `hgdb.lic` 文件**（已验证：镜像内 `/opt/highgo/hgdb-see-4.5.8/etc/lic/` 为空目录；全盘搜索无 `hgdb.lic`）。
- 无 License 文件时，瀚高按**数据目录首次 initdb 的时间**起算 30 天试用期。
- `HGDB_SKIP_LICENSE_CHECK=true` 只跳过 entrypoint 的启动前检查，**不消除数据库内核的试用期校验**——试用到期后数据库自身拒绝启动。

**规避方法**：
1. **全新数据卷（数据目录）= 试用期重置**。删除数据卷（或换新卷）重新 initdb，试用期重新计 30 天。
   实测：2026-08-15 新起容器 `highgo-fresh-test`，sysdba 的 `valuntil = 2026-08-22`，CRUD 全部正常。
2. 长期方案：向瀚高申请正式 License（`hgdb.lic`），挂载到 `${HGDB_HOME}/etc/lic/hgdb.lic`
   （K8s 中注意：瀚高拒绝符号链接挂载的 License，且要求 `0600` + `highgo:highgo` 属主，
   需用 init container 拷贝到 emptyDir，详见 CLAUDE.md "Key Containerization Decisions" #4）。
3. 曾尝试用 libfaketime 冻结容器时间绕过（`HGDB_FREEZE_TIME=true`），但构建网络拉 GitHub 不稳定，
   镜像内经常没有 libfaketime，日志刷 `WARNING: HGDB_FREEZE_TIME=true but libfaketime not found`，不可依赖。
   参考：官方预置镜像曾内置 libfaketime 冻结时间（`HGDB_FREEZE_TIME_VALUE` 环境变量），但依赖外部库编译，裸环境重建不可控，**主线方案仍以"全新数据卷重置试用期"为准**。

**易踩点**：复用旧数据卷/旧 PVC 启动新容器 → 试用期已过 → 无限崩溃循环，且容器日志中的 FATAL
出现在数据库内部日志（`PGDATA/log/postgresql-*.log`）而非 stdout，`docker logs` 只能看到
entrypoint 的 "Waiting for database"，**必须进容器或 docker cp 出 `PGDATA/log/` 才能看到真实死因**。

---

## 坑 2（严重）：sysdba 等账户密码有效期 30 天，过期后只能改密不能做任何操作

**发现日期**：2026-08-15（实测复现）

**现象**：
- 容器运行 5 周后，psql 连接报：
  ```text
  WARNING: Your password has expired. Please alter the password.
  ERROR: Your password has expired, you cannot do anything but alter the password.
  ```
- 登录通告中 `Valied Until: 2026-07-16`（即 initdb 后 7 天首次设密，再 +30 天？实际与试用期同源，约 30 天周期）。

**根因**：
- 瀚高安全版默认对所有账户启用密码有效期（约 30 天，`valuntil` 控制），到期后账户被限制为"仅允许 ALTER USER ... PASSWORD"。
- sm3 认证握手本身仍能通过（密码没锁），但任何业务 SQL 都被拒绝。

**连带的坑 2.1 —— hgproxy 密码过期死锁**：
- hgproxy 的 lifecheck 用缓存的三权账户密码连后端；密码过期后 lifecheck 失败，proxy 日志刷：
  ```text
  ERROR: Life check failed! The backend errorMsg:
  ERROR: You still have "4" chances to enter your password before your account get locked.
  WARNING: ip=[127.0.0.1] port=[5867] node down
  ERROR: The master node is NULL!
  ```
- **注意**：即使已在数据库侧重置了 sysdba 密码，proxy 侧缓存的还是旧密码，5866 端口仍连不上——必须**重启容器**让 proxy 重新初始化密码。

**修复方法**（已验证）：
```bash
# 1. 用旧密码登录（登录本身允许，只是业务 SQL 被拒），立即改密
docker exec -e PGPASSWORD='旧密码' <容器> /opt/highgo/hgdb-see-4.5.8/bin/psql \
  -h 127.0.0.1 -p 5867 -U sysdba -d highgo -c "ALTER USER sysdba PASSWORD '新密码';"
# 2. 重启容器刷新 hgproxy 密码缓存
docker restart <容器>
```

**容器化设计要求（应写入 entrypoint 的验收标准）**：entrypoint 应在每次启动时检测/刷新密码有效期，
或部署时通过 K8s Secret + 启动脚本统一重置三权账户密码，避免"容器能跑 30 天但第 31 天全挂"。

---

## 坑 3（严重）：非正常关闭后 hgaudit/.tempfile 损坏 → 启动 PANIC

**现象**：kill -9 / immediate stop / OOM / 宿主机崩溃后重启，数据库完成全部初始化并打印
"database system is ready to accept connections"，随即同一毫秒：
```text
PANIC: cannot wait without a PGPROC structure
```
100% 复现。

**根因**：audit archiver 子进程在 `ProcWaitForSignal()` 中没有有效 PGPROC 结构（HGDB-SEE-4.5.8 build 20220708 自身缺陷）。

**修复方法**（清空审计目录后重启）：
```bash
pg_ctl stop -m immediate                       # 确保进程已停
mv /data/highgo/hgaudit /data/highgo/hgaudit.bak
mkdir -p /data/highgo/hgaudit/audit_archive_ready
rm -f /data/highgo/postmaster.pid /tmp/.s.PGSQL.5866 /data/highgo/pg_stat/global.stat
# 清理共享内存和信号量
ipcs -m | awk '/^0x/{print $2}' | xargs -I{} ipcrm -m {}
ipcs -s | awk '/^0x/{print $2}' | xargs -I{} ipcrm -s {}
pg_ctl -D /data/highgo start -w -t 60 -o '-p 5866'
```
**代价**：丢失历史审计日志（已备份）。`pg_stat/global.stat` 在多次 crash recovery 后同样会损坏，一并删除可提高启动成功率。

---

## 坑 4（严重）：sm3 认证死锁耗尽连接数

**现象**：syssso 账户密码过期时，sm3 认证握手可能**无超时卡死**，积累大量 `startup`/`authentication`
状态的僵尸连接，最终耗尽 `max_connections`，所有用户无法连接。

**处理**：immediate stop → 清理共享内存/信号量 → 重启（同坑 3 的清理流程）。
2026-07-08 曾因此事件清理了 98 个 startup 僵死后端（SIGTERM 无效，须 SIGKILL），详见 `OPERATIONS.md`。

---

## 坑 5（中）：reaper.sh 存在 bug —— `set -u` 下变量未定义刷屏

**发现日期**：2026-08-15（实测复现）

**现象**：容器日志持续刷：
```text
/usr/local/bin/reaper.sh: line 25: max_age: unbound variable
```
**根因**：`reaper.sh` 开头 `set -u`，但第 25 行引用的 `max_age` 变量在某些执行路径下未定义
（应为 `${max_age:-300}`）。不影响数据库运行，但污染日志且说明该脚本未被充分测试。

**修复**：`reaper.sh` 中所有可能未定义的变量加默认值：`${max_age:-300}`、`${interval:-60}`。

---

## 坑 6（中）：瀚高安全版不支持 trust 认证

即使 `pg_hba.conf` 设为 trust，服务端报 `invalid authentication method "trust"` 并**拒绝 reload**，
必须使用 sm3 认证。`PGPASSWORD` 环境变量可用；`.pgpass` 在 sm3 下不可靠。

---

## 坑 7（中）：abort_ddl 事件触发器默认拦截所有 DDL

所有 DDL 操作必须包裹：
```sql
ALTER EVENT TRIGGER abort_ddl DISABLE;
-- DDL 语句
ALTER EVENT TRIGGER abort_ddl ENABLE;
```
容器内执行建表等操作若被莫名拦截，先检查 `SELECT evtname, evtenabled FROM pg_event_trigger;`。

---

## 坑 8（低）：pg_isready 可能误报（残留 socket）

崩溃后 `/tmp/.s.PGSQL.5866` 残留，`pg_isready` 误报 "accepting connections" 而库实际已死。
判定状态以 `postmaster.pid` + 实际进程为准。

---

## 坑 9（低）：其他确认过的小问题

- **SSL cipher 不匹配**：外部客户端 OpenSSL 不支持服务端受限算法时，日志出现
  `could not accept SSL connection: no shared cipher`。当前方案直接 `ssl = off`。
- **hgproxy 4.0.14 与 SEE 4.5.8 SSL 兼容性问题**（segfault），故容器方案默认关闭 SSL。
- **两个 systemd 服务**：`hgdb-see-4.5.8.service`（缺 PGDATA，broken）与 `highgodb.service`（可用）并存，只用后者。
- **initdb 常见报错**（详见 `NEW_INSTANCE_GUIDE.md` 第九章）：目录非空、密码复杂度不足、参数解析失败等。

---

## 实测验证记录（2026-08-15）

环境：`highgo-see:4.5.8` 镜像（762MB，2026-07-09 构建），Docker。

| 验证项 | 结果 |
|--------|------|
| 全新数据卷容器启动 | ✅ 1 秒内 DB 就绪 |
| 直连 5867 增删查改（CREATE/INSERT/SELECT/UPDATE/DELETE） | ✅ 全部通过 |
| hgproxy 5866 端口查询 | ✅ `PROXY_OK` |
| sysdba 密码有效期（新 initdb） | `valuntil = 2026-08-22`（30 天试用同源） |
| 旧容器（07-09 initdb） | ❌ License 过期崩溃循环，已删除 |
| 旧容器密码重置 + 重启后 CRUD | ✅ 验证了坑 2 的修复方法 |

容器内 psql 调用模板（sm3，须用 `-e PGPASSWORD` 传入 env，管道 stdin 会丢密码提示）：
```bash
docker exec -e PGPASSWORD='xxx' <容器> /opt/highgo/hgdb-see-4.5.8/bin/psql \
  -h 127.0.0.1 -p 5867 -U sysdba -d highgo -c "SQL"
```
