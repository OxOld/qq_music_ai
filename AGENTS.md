# AGENTS.md

本文件供 AI 编码助手（ZCode / Codex / Cursor 等）在本仓库工作时阅读。改动代码前先读完这一页。

## 项目是什么

**QQ 音乐 AI 歌单助手**：用户一句话描述场景/情绪 → LLM 选曲生成候选歌单 → 搜索匹配 QQ 音乐曲库 → 自动在用户账号创建真实歌单 →（远期）车机投屏播放。

- **个人自用、不上架、纯客户端、无后端**。不要引入服务端、数据库、账号体系、第三方统计等设计。
- **Android 优先**；`web/` 目录仅是 Flutter 默认生成物，不在交付范围，不要为它写适配。
- 详细设计见《QQ音乐AI歌单助手-技术方案与功能文档.md》（本目录）。**注意：文档是早期方案稿，与代码冲突时以代码为准**（例如网络层实际用 `http`，不是文档写的 Dio）。

## 环境与命令（本机已就绪）

每次新开 shell 都要先设置：

```bash
export ANDROID_HOME="C:/Projects/Tools/Android/Sdk"
export JAVA_HOME="C:/Projects/Tools/jdk17/jdk-17.0.20.1+1"   # 必须带，否则 Gradle 找不到 JDK
export PATH="/c/Projects/Tools/flutter/bin:$PATH"
```

```bash
flutter pub get      # 拉依赖
flutter run          # 调试运行（Android 模拟器 / 真机）
flutter analyze      # 提交前必须通过
```

- Android 构建内存已在 `android/gradle.properties` 配好（`-Xmx8G`），不要动。
- 换 JDK 后或首次构建慢属正常（Gradle 守护进程冷启动）；不要频繁 kill 构建进程，让 daemon 保持存活。

## 目录结构与职责

```
lib/
  main.dart               入口，ProviderScope 包裹
  models/                 playlist.dart、qq_song.dart 纯数据类
  services/               业务核心，全部无 UI 依赖
    llm_service.dart        OpenAI 兼容协议直连 LLM，response_format 强制 JSON
    qq_music_client.dart    QQ 音乐逆向 HTTP 接口：搜索/建歌单/加歌/我的歌单
    qq_auth_service.dart    WebView 扫码登录，解析 Cookie（uin/skey/g_tk），存 secure_storage
    match_service.dart      歌名+歌手相似度打分匹配
    player_service.dart     just_audio + audio_service 播放与后台控制
    settings_service.dart   用户配置（LLM base_url/api_key/model）读写
  providers/              Riverpod 依赖注入，页面不直接 new service
  pages/                  home_page、settings_page、login_page
  theme/                  app_theme.dart 深色车载友好主题
```

## 硬性约定

1. **密钥与登录态**（LLM api_key、QQ 音乐 Cookie）只存 `flutter_secure_storage`，绝不硬编码、绝不打印到日志、绝不写进测试快照。
2. **QQ 音乐是非官方逆向接口**，属灰色地带：保持低频调用，批量操作加请求间隔（`Future.delayed`），不要并发轰炸；接口字段解析要容错（Cookie 字段存在多种变体，参考 `qq_auth_service.dart` 现有写法）。
3. **LLM 调用**必须带 `response_format: {type: "json_object"}` 并做 JSON 解析容错；返回结构约定见方案文档 §5.1。
4. **风格**：注释与 UI 文案一律中文，公共成员用 `///` 文档注释；状态管理统一 Riverpod；网络统一 `http` 包；UI 组件用 Material + `tdesign_flutter`。
5. 逆向接口的签名实现（qimei / 3DES / g_tk）新增时，参考方案文档 §5.2 路径 A（移植 Python 实现）/ 路径 B（先跑 Node 验证），并注明移植来源。

## 当前里程碑（完成一项就更新此节）

- [x] M1 项目骨架 + 设置页 + AI 选曲直连
- [ ] M2 QQ 音乐扫码登录 + 搜索 + 建歌单（进行中：Cookie 解析与 g_tk 已就绪）
- [ ] M3 播放器（just_audio + audio_service，锁屏/方向盘控制）
- [ ] M4 车载横屏 UI 适配 + 夜间模式
- [ ] M5 Carlink 镜像投屏实车联调（无需集成 SDK，只需车载 UI，见方案文档 §6）

## 其他背景

- 本项目 2026-11-07 由 `D:\WorkBuddy\`（机械硬盘）迁至 `C:\Projects\`（NVMe）以加快 Gradle 构建，旧目录不再维护。
- 车机投屏走 ICCOA Carlink **系统级镜像**，App 本身零适配成本；M4 只需做好横屏大屏响应式 UI。
