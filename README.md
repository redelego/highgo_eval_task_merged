# 瀚高 SEE 4.5.8 容器化平台任务材料包

方舟39期众测任务材料。模型下载本仓库后使用 materials/ 目录完成镜像制作、K8s 部署与 Web 控制台开发。

## 下载方式

仓库公开，任选其一（推荐方式一）：

```bash
# 方式一：git clone（推荐）
git clone https://github.com/redelego/highgo_eval_task_merged.git task-materials
cd task-materials

# 方式二：归档直链下载（git clone 网络异常时）
curl -L -o task-materials.tar.gz https://codeload.github.com/redelego/highgo_eval_task_merged/tar.gz/refs/heads/main
tar xzf task-materials.tar.gz && cd highgo_eval_task_merged-main
```

## 解包安装包（重要，必做）

安装包以分卷形式存放（GitHub 单文件限制 100MB），需先合并再解压：

```bash
# 合并分卷（仓库根目录下）
cat materials_full_v2.tar.gz.part_* > materials_full_v2.tar.gz
tar xzf materials_full_v2.tar.gz   # 解压出完整 materials/（含 hgdb-see-4.5.8/）
```

解压后 materials/ 完整结构：

```
materials/
├── hgdb-see-4.5.8/       # 数据库安装包（解压即用，约 416MB）
├── hgproxy/              # hgproxy 连接池组件（REVISION f0344bc）
├── kind                  # kind 二进制（v0.24.0）
├── kubectl               # kubectl 二进制（v1.31.0）
├── DATABASE_CONTEXT.md   # 数据库背景资料（必读）
└── KNOWN_ISSUES.md       # 已知缺陷与踩坑记录（必读）
```

## 重要：libgdal 分卷合并

安装包内 `lib/libgdal.so.20`（139MB）已拆分为两个分卷，使用前需合并：

```bash
cd materials/hgdb-see-4.5.8/lib
cat libgdal.so.20.part_* > libgdal.so.20
chmod +x libgdal.so.20
```

## 使用说明

模型任务：按任务 Prompt 要求，基于本材料从零构建瀚高容器化平台。
两份 md 文档为必读，含全部已知坑与规避方法、hgproxy 初始化机制、环境变量命名参考、initdb 实测模板。
