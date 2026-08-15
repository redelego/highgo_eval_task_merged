# 瀚高 SEE 4.5.8 容器化平台任务材料包

方舟39期众测任务材料。模型下载本仓库后使用 materials/ 目录完成镜像制作、K8s 部署与 Web 控制台开发。

## 目录结构

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

GitHub 单文件限制 100MB，安装包内 `lib/libgdal.so.20`（139MB）已拆分为两个分卷：

```bash
cd materials/hgdb-see-4.5.8/lib
cat libgdal.so.20.part_* > libgdal.so.20
chmod +x libgdal.so.20
```

## 使用说明

模型任务：按任务 Prompt 要求，基于本材料从零构建瀚高容器化平台。
两份 md 文档为必读，含全部已知坑与规避方法、hgproxy 初始化机制、环境变量命名参考、initdb 实测模板。
