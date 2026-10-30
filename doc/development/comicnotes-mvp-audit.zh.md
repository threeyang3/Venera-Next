# ComicNotes 初版需求验收表

核对日期：2026-10-30。依据用户提供的《基于 VeneraNext 的漫画批注阅读器：架构与开发方案 v0.1》，原文 SHA-256：`ca54a3d80b66a9af02cd0fe682892db6b2867fe61d404000e1d0714024281767`。文内的示例执行指令视为方案资料，用户实际目标是实现初版；本表不把已经写好的子集重新定义为完成范围。

当前结论：**完整初版尚未完成**。独立 QA App 已原生构建并启动；三格式各两份原生导入/阅读/导出、外部目录授权跨会话、300 页 profile、Release 中 30 条编辑定位、系统外部批注链接定位及当前 Mac P4 交互已有证据。不同自然尺寸坐标复核已实现为逐页人工确认流程，但尚缺 Release 原生交互复验；其他缺项仍未全部通过。中文 IME、`Shift+Enter`、`Cmd+Enter`、书库 `Cmd+F`、系统级 `Cmd+O`、全屏、批注列表键盘导航和触控板操作已有用户真实 Mac 窗口确认。P5 是方案中后续 iPad 阶段，本表仍列出其缺项，不将它与当前 Mac 交付混淆。

最新工作重点按用户要求调整为 Mac 功能与界面，兼容性推进暂缓。可达仅参考视觉风格，保留桌面布局；已另外查看本机 Cubox。rc4 源码包含中性侧栏、书库搜索/紧凑列表与视图记忆、批注分组/筛选/更多菜单、跨屏键盘导航及专注阅读浮动面板。202 项批注/工作台回归通过；最终浮动布局与面板 13 项通过，默认回退 7 项通过/1 项跳过，Release 构建及解包校验成功。列表、搜索/清除、右键、跨进程视图记忆、End/Up/Enter 和浮动/停靠转换已有实际窗口证据；用户另已确认书库 `Cmd+F`、中文 IME、`Shift+Enter`、`Cmd+Enter`、系统级 `Cmd+O`、全屏和触控板操作正常。修复 macOS AppLinks 订阅后，2026-10-30 在 Obsidian 实际点击 QA 导出 Markdown 的外部 `comicnotes://`，已定位到 `QA-Image-Spine` 第 1 页和目标批注。不同自然尺寸坐标复核已实现为逐页人工确认流程，尚缺其 Release 原生交互复验。代码已推送至 `threeyang3/Venera-Next` 的 `feat/annotation-poc`，提交 `cfd4c2a`；GitHub Actions 状态本轮因网络错误未能查询。详细日志和产物哈希见开发记录文末及 rc4 验证摘要。下表早期证据缺项应与后面的原生验收补充一并阅读。

| 方案要求 | 当前状态与可核对证据 | 尚缺证据或工作 |
| --- | --- | --- |
| P0：锁定 v1.18.1、独立分支、记录工具版本 | 标签 commit 为 `087147a7810039398f4eed3bcc794b576f92c46b`；分支 `feat/annotation-poc` 已推送到 `threeyang3/Venera-Next`。版本和基线检查见开发记录 | 尚未创建 PR；方案中的 PR 拆分是建议，未伪造远端产物 |
| P0：基线原生构建、启动、三格式导入/阅读/导出与截图 | 工具链已恢复，修改分支 arm64 Release/Debug 构建成功，实际 CBZ 导入/阅读/导出已有窗口与像素证据 | 原始基线成功构建对比、其他格式原生验收及全部截图尚缺 |
| §3/P1：UUID、自然内容空间、可逆矩阵、约 1 像素约束 | `geometry_test.dart`、`annotation_session_test.dart`；自然原图尺寸与解码绘制尺寸已分别接入 `annotation_layer.dart`；实际 2000×3000 缩小解码、SQLite 框选保存和原图裁剪像素用例 | 纯几何覆盖不等同于所有模式的实际 UI 集成 |
| P1：本地单页可拖动选框；阅读时不劫持手势；错页防护 | `overlay_widget_test.dart`、`reader_integration_test.dart`；既有 Reader 连续性和退出集成回归已运行 | Mac 原生交互/截图验收 |
| §5：临时矩形、保存失败重试、Esc 取消、Enter/Cmd+Enter、列表跳转、隐藏 | 框选锚点冻结、失败保留草稿、Esc、Cmd/Ctrl+Enter、列表定位/高亮及显示开关已接入；用户已在真实 Mac 窗口确认中文输入法、Shift+Enter 多行和 Cmd+Enter 保存 | 组词范围不提交及双击只定位一次已有定向测试；系统级快捷键和完整原生交互仍需继续验收 |
| §3/§5：分页、连续流、双页、拆图、RTL 统一覆盖层 | 共用 domain/transform；本地单图/多图画廊、四种连续布局、纵向/瀑布宽图拆分及反转已接入；真实 Reader 验证异尺寸双页/三图、RTL、resize、缩放旋转投影、滚动隔离、窄窗、最后单图页和跨章 UUID；拆分另验红/蓝原图实际渲染像素与共享页 UUID；返回定位临时切为单页且可恢复旧布局 | 真实 Mac 运行、交互与性能验收 |
| P2：独立 SQLite、迁移、CRUD、墓碑、来源/标签、错误态 | `annotation_repository_test.dart`、`annotation_session_test.dart`；事务迁移 schema 1→2，高版本拒绝，不随删漫画级联 | macOS 异常退出/进程被终止后的实际验收 |
| P2：重开、同名、重导入、30 条连续操作与跳转 | 数据库 30 条提交/更新/墓碑和会话用例；同来源恢复与真实 Reader 面板/引用集成用例 | 30 条全流程在原生 App 中的连续交互验收，不能从单元循环推导真人操作通过 |
| §4/P3：原件访问/副本，失联不丢批注 | PDF 默认可保留原件副本；CBZ/EPUB 保留原图资源副本；原件重关联验大小与 SHA；图片文件夹有独立安装内来源清单 | Apple 安全书签/文件提供者跨会话权限验收；旧导入无指纹及不同版本的手工逐页映射：已有同尺寸一对一事务基础与并发/回滚测试，运行时预览已补文件/自然尺寸/指纹、存活绑定和取消检查；同尺寸逐页 UI 与服务注入已接入，最新 Dialog 和真实 Reader 恢复/退出取消已复验通过；不同自然尺寸已支持目标页尺寸更新、归一化坐标人工复核和审计记录，尚缺 Release 原生交互复验 |
| P3：CBZ entry/occurrence/order、至少两份样本 | `archive_provenance_test.dart` 覆盖普通/章节/范围映射、重复同名/别名/相同字节候选及导出像素；ZIP 新增中央目录顺序与字节证明 | 7Z 原始目录 occurrence 尚未枚举；zip_flutter/7zip 原生提取器在本机缺失，当前使用原 Dart ZIP 后备 |
| P3：PDF page index/MediaBox/CropBox/Rotate，至少两份样本 | 两份真实 PDF 六页夹具；`pdf_source_test.dart` 实际 PDFium 几何和像素、300 dpi 原件选区、原件缺失降级、移动/副本故障 | 实际 App 原生插件与文件权限；不能将 PDFium FFI 测试称作 App 已构建 |
| P3：图片 EPUB OPF/manifest/spine/重复出现 | `epub_source_test.dart` 两类夹具，重复资源和 spine 的独立页身份、哈希/导出/恢复 | 文本重排 EPUB 不属于首版；原生文件访问仍待验收 |
| 文件夹自然排序、原图、移动/重导入 | `folder_source_test.dart`：引用/复制、相对路径+字节身份、原图导出、移动精确重关联、UUID/旧引用恢复 | 旧无指纹记录不自动升级；Android SAF 本轮不建立这种目录清单 |
| §7：完整 Markdown+截图、本地保存、来源/标签/稳定链接、特殊路径与失败隔离 | `export_test.dart` 和三格式/文件夹来源集成；新 UUID 输出目录、稳定 annotation-id PNG、manifest 哈希、原子发布，失败不覆盖现有文件 | 本版采用完整新导出。管理区块增量合并是方案第二版范围，未实现也不声称实现 |
| §7：comicnotes:// 外部定位 | strict parse、数据库查找/墓碑/跨文档验证及本地相对路径重解析；Info.plist scheme 已声明。修复 macOS AppLinks 订阅后，2026-10-30 从 Obsidian 点击 QA 导出 Markdown 中的 `comicnotes://open?document=cb4cd8d8-1d28-4fd5-87f4-bb94ec2d0d26&annotation=202bd3fd-f669-411f-93ad-24692fb37da8`，Debug 与 Release rc5 均进入 `QA-Image-Spine` 第 1/3 页，显示目标选区并弹出 `EPUB image spine native crop` 提示；生命周期测试 9 项通过、`flutter analyze --no-pub` 通过；rc5 解包签名/哈希核验通过 | 完整 MVP 仍有不同尺寸映射的 Release 原生交互复验及其他缺项 |
| §3：备份含来源/schema，恢复及孤儿保留 | `backup_test.dart`、`restore_test.dart`、`restore_dialog_test.dart`、`recovery_test.dart`：WAL、完整性/哈希、schema 1/2、只添加缺失文档、UUID 冲突/取消回滚、重新绑定并保持旧引用 | 不含图片；不合并已有文档；无指纹记录暂存；已有手工映射事务基础，运行时已支持同尺寸与不同尺寸逐页映射，后者要求坐标复核并写入审计元数据；最新窄窗与 owner cancellation 已复验通过；没有自动云同步 |
| P4：设计样式、Reader Toolbar/Inspector、Mac Library、旧 UI 回退 | `annotation_workspace_test.dart`、`mac_library_sidebar_test.dart`、`mac_library_integration_test.dart`，真实临时数据库组件渲染深浅色截图 | 这些是组件截图；没有真实系统窗口、AppKit toolbar/标题栏验收 |
| P4：Cmd+O、Cmd+F、Cmd+S、Cmd+Shift+N、焦点/hover/上下文/trackpad/全屏 | Mac 根级 Cmd/Ctrl+O（含推入 Reader/发现页，PopupRoute/退出时拒绝）、书库 Cmd/Ctrl+F、Reader 批注查找 Cmd/Ctrl+F、画廊当前原图/连续原图框选 Cmd/Ctrl+Shift+N、Cmd/Ctrl+S 和编辑保存/退出已接入；用户已在真实 Mac 窗口确认书库 Cmd+F、中文输入、Shift+Enter、Cmd+Enter、系统级 Cmd+O、全屏、批注列表上下键/Enter 及触控板滚动/缩放；默认回退已复验 | 边框悬停强调已补像素/手势验证；批注右键编辑/复制/引用/删除已接入并验证邻页目标、失效菜单和删除失败重试 |
| §8：300 页、大量笔记的 profile；生命周期与平台权限 | dispose/退出/取消/异步过期和画布连续性已有组件回归 | 已完成本机 Apple M5 的 300 页/30 条批注 profile；第 96→300 页侧栏展开采集 2292 帧，UI P99 9.53 ms / raster P99 1.62 ms；原始时间线见文末。仍缺物理触控板及全部缩放组合 |
| §8：路径/文件安全、离线默认、保留上游验证 | 有目录/原件校验、输出新目录、相对资源路径、hash 校验、只读原件、字节和像素限制；新增 ZIP 解压校验有确切长度上限 | 外部目录重关联后已确认旧进程退出，新进程原件导出及逐像素比对通过；iPad 文件提供者授权仍待 P5 |
| §8：CI analyze/test/架构/格式/构建 | 本机 analyze、结构/架构、格式与空白检查已过；CI 新增开启两个开关的串行专项，YAML 已解析，本机同测试集合 1152 项通过/31 项平台配置跳过 | 未推送、未运行远端 CI；默认依赖原生库的基线失败已有单独记录；arm64 原生构建已过，最新修复的 arm64 Release 已构建并通过原生启动、签名、解包后签名/可执行文件哈希核验 |
| P5：iPad 自适应、Pencil、导入授权/分享与同步协议 | 现有窄窗回退和共用坐标是准备工作 | iPad 模拟器/真机、Pencil 区分、系统分享、书签授权与同步协议均未完成 |

实现和历史日志索引见 [开发与验收记录](comicnotes-poc.zh.md)。当前范围的 Mac 键盘操作已补齐并定向复验；旧记录同尺寸明确恢复路径与不同尺寸坐标复核流程已接入，最新窄窗及退出取消已补复验；根级打开命令已接入；连续原图覆盖层已接入；双页/多图及纵向/瀑布拆图覆盖层也已接入并补组件渲染验证。原生工具链恢复后必须重跑真实 App 门禁，不能用这些本机测试替代。

当前推进状态（2026-10-29 再次恢复）：原审批路径已成功启动 Flutter 测试，额度执行阻塞解除；最新手工恢复的 8 项界面测试与 Reader 恢复/退出取消 2 项通过，最终 analyze 无问题，完整回归 1152 项通过/31 项平台配置跳过，默认回退 17 项通过/1 项配置跳过。原生构建工具链复核仍缺完整 Xcode、cargo、pod；目标未达成，不能标记初版完成。

原生门禁阻塞结论：该工具链问题已连续多轮复核，本轮 xcrun 仍找不到 xcodebuild，cargo/pod 亦不在 PATH。可执行的最新恢复、退出、默认回退和完整专项已收尾，继续真实 App 验收依赖外部工具链变化，目标标记 blocked，不标记完成。解除后通过 tool/run_annotation_poc.sh 启动，依次验证三格式实际导入/阅读/导出、外部引用唤起、权限跨会话、30 条连续操作、300 页性能与原生窗口交互；不同自然尺寸坐标重审缺项仍按上表保留。

当前环境恢复补充（用户安装 Xcode 后）：完整 Xcode 27.1、CocoaPods 1.17.0、持久 Flutter 3.41.4、项目 Rust 1.92.0 和插件额外要求的 stable 1.99.1 已安装。原生 Swift 模块 10 项测试通过。已修正 Xcode 27 对 Pods 最低系统版本的兼容问题，正在串行原生 Release 构建；前面的 blocked 是历史状态，当前目标已由用户恢复进行。尚未据此声称 App 启动或性能验收通过。

最新原生验收（2026-10-30）：目标仍为 active。Flutter 3.41.4 的两类原生 AX 错误已以校验源码哈希的兼容补丁处理：不同 OverlayPortal 锚点合并保护（上游 #190344 未合并）与已合并 #193372 的孤立节点修复及所需脏节点登记适配。原版 SDK 上两项序列化回归均失败，补丁后通过；SDK 核心 199 项、补充 View/Overlay/渲染 65 项通过，应用专项 1155 项通过/31 项配置跳过，analyze 无问题。原生修复版运行期间未再记录 AXTree 错误。

已通过实际 App 连续 30 轮框选、英文输入和保存，数据库核对 30 条文本、唯一 UUID 和归一化范围正确；总计 31 条区域批注已原生批量导出。全部 31 张 PNG 的哈希及与源 CBZ 裁剪逐像素对比通过。证据：`logs/native-qa-30-cycle-verification.json`、`logs/native-qa-batch-export-verification.json`。这不等同于 30 条编辑/跨页跳转门禁全部完成。

原生输入自动化仍有修饰键与 Unicode 字符遗漏：AX setValue 仅改变原生显示，未更新 Flutter 控制器；真实坐标聚焦后的英文字符输入可保存。Shift+Enter、Cmd+Enter 和中文 IME 仍保留待测，未据此修改保存业务逻辑。原生截图另发现工作台工具栏覆盖窗口标题栏，已通过 SafeArea 消费 WindowFrame 顶部 padding 修复；5 项布局回归通过，待重构建截图验收。

原生重构建复验补充：标题栏修复后的 Debug 已启动，工作台工具栏位于系统拖动栏下方，画布顶部无重叠；重启打开同一本书后，侧栏显示「全书批注 · 31」，并回读最近保存的 cycle 30、29 等测试文字。31 条批量 PNG 均完成哈希和源图逐像素校验。此轮仍未验证中文 IME、多格式全部样本及性能，不提前结项。

三格式原生补充验收：两份 EPUB 均经系统选择器导入、Reader 打开、框选、保存和导出。`QA-Image-Spine` 第 1 页、`QA-Repeated-Spine` 第 3 页（spineIndex 2）均与对应原始资源逐像素一致，重复资源未折叠页锚点；证据 `logs/native-qa-epub-export-verification.json`。两份 PDF 也完成同样流程：`pdf-crop-rotate` 第 2 页旋转 90°，300 dpi 裁图 744×249；`pdf-mixed-boxes` 第 2 页旋转 270°，裁图 407×408。清单记录原始 MediaBox/CropBox/effectiveBox，原件保留开关默认开启；与 Python 独立 PDFium 全页渲染按清单区域裁剪的结果逐像素一致，见 `logs/native-qa-pdf-export-verification.json`。参考渲染使用 `nextafter(300/72, 0)` 避免 Python 浮点乘法导致 1000.0000000001 被 ceil 成 1001，不缩放图像来凑尺寸。

标题栏修复后的定向 Reader/批注/退出集成 203 项通过、23 项配置跳过，见 `logs/native-titlebar-reader-integration-tests.log`。当前原生样本通过数量为 CBZ 1、EPUB 2、PDF 2，尚缺第二份 CBZ、300 页 profile、系统链接及权限跨会话等门禁；中文 IME 与修饰键继续保留待测。

## 长篇 profile 与跨会话目录验收（2026-10-30）

- 第二份 CBZ `QA-300-Pages.cbz` 经系统选择器导入并显示 1/300；实际界面创建并保存 30 条批注，独立库逐条核对，见 `logs/native-qa-long-book-notes.json`。profile 进程中侧栏回读「全书批注 · 30」。批量导出 30 张 PNG 均通过哈希和对应原图像素核对，见 `logs/native-qa-long-book-export-verification.json`。至此 CBZ/EPUB/PDF 各两份样本已有原生导入、阅读、框选和导出证据。
- Apple M5 / arm64 / macOS 26.6 / Flutter 3.41.4，原生窗口约 2940×1714 像素。profile 构建成功（73.0 MB），启用批注与工作台；共 141 次原生滚轮操作，从第 1 页推进到第 300 页，再通过侧栏「定位原图」返回第 1 页及 note 30。
- 前两次 VM Ring 快照发生事件覆盖，只代表保留尾段，不作为全程统计。之后每秒读取时间范围并保留 200 ms 重叠，事件按完整记录去重；106 个分段、最大读取间隔 1.247 秒、单段最多 7214 事件，未达到此前约 32k 的环形容量。第 96→300 页侧栏展开阶段采集 107.43 秒、336019 事件、2292 对 UI/raster 帧。UI：均值 3.23 ms，P90 7.39 ms，P99 9.53 ms，最大 14.47 ms；raster：均值 0.73 ms，P99 1.62 ms，最大 6.56 ms。该段两类帧均未超过 16.67 ms。前一段尾窗曾有一个 21.83 ms raster 帧，未隐去。常驻内存由 242736 KiB 到 243664 KiB（约 237→238 MiB）。
- 原始分段与时间线、条件及统计见 `logs/native-profile-long-book-inspector-live-{chunks,timeline,summary}.json` 与 `logs/native-qa-long-book-profile-report.json`。解析事件名遵循本地 Flutter SDK `flutter_driver/.../timeline_summary.dart` 的 `Frame` / `GPURasterizer::Draw`，兼容同步 B/E 和异步 b/e。采集脚本保留在 `build/native-qa/profile_timeline.py`、`collect_profile_live.py`，未通过 VM 执行任何 UI 行为。帧工作耗时不等于端到端显示延迟；这是本机滚轮场景，不替代真触控板、所有缩放模式和跨硬件性能保证。
- 外部协议测试：后台 IAB 本地测试页仍会被浏览器安全策略拦截，未交给系统；随后使用真实 Obsidian 导出 Markdown 完成系统级验收。点击链接后 QA App 实际定位 `QA-Image-Spine` 第 1/3 页、目标批注选区和提示文字。证据来自修复版 Debug 原生窗口，链接 UUID 与独立 QA 数据库中的 document/annotation 记录一致。
- 外部目录授权：默认 Mac 文件夹导入会复制到沙箱，不能用其重开证明外部权限。已用「重新关联原件」明确关联 `build/native-qa/QA-Scoped-Folder` 外部目录；数据库核对 source URI。原进程完全退出后，新 profile 进程恢复并导出，清单为 `folderImageOriginal` / `001.png`，PNG 与外部原件逐像素相同。见 `logs/native-qa-directory-relocation-before-restart.json`、`logs/native-qa-directory-cross-session-export.json`。
- 重复 profile 构建时 Cargokit 再次访问 Rust 1.92.0 分发校验文件，遇 TLS EOF；不关闭证书检查，跨会话验证使用刚成功构建的同一 profile 二进制，不把该重构建失败描述为成功。默认开关关闭的最新回退专项 11 项通过、1 项配置跳过。

完整目标仍 active。中文输入法、`Shift+Enter` 换行、`Cmd+Enter` 保存、书库 `Cmd+F`、系统外部引用唤起、系统级 `Cmd/Ctrl+O`、真实触控板及主要 P4 交互已有 Mac 证据；不同自然尺寸的人工坐标重审、30 条编辑与跨页跳转的完整原生组合、Apple 公证与最终发行仍有缺项。当前带 AppLinks 修复的 arm64 Release 候选归档为 `build/deliverables/ComicNotes-macOS-arm64-rc5-final.zip`，Obsidian 外部链接已在该 Release 原生复测通过，解包签名和可执行文件哈希核验通过，详见 `doc/development/comicnotes-rc5-validation.json`。

## Release 候选 rc1（2026-10-30）

已修复 vendored Cargokit 仅识别 stable/beta/nightly、忽略已安装编号 Rust 工具链的问题，`officialToolchainNames` 保留 1.92.0 及 host 后缀，避免每次构建都重装并碰到镜像 TLS EOF。3 项测试覆盖编号/命名/日期版本、Windows 换行与自定义名称，已接入 analyze workflow；本次 Release 构建未再触发 Rust 重装，静态检查无问题。

Release 候选已实际启动并打开 300 页漫画，逐条编辑与定位 30 条批注；数据库和编辑前导出清单比对确认 30 个批注 ID、page ID 与矩形坐标不变，见 `logs/native-qa-release-30-edit-verification.json`。候选 ZIP 为 `build/deliverables/ComicNotes-macOS-arm64-rc1.zip`（23909241 字节），解包后签名和可执行文件哈希均通过；包内说明和 candidate-manifest 明确标记候选验收未完成。核验见 `logs/native-qa-release-candidate-package-verification.json`。SHA-256：`4ef54c1f4adbf7f8e3be013396c285365dae06f84d953941b0c963aec84dc1e0`。

此包使用 `local.comicnotes.qa.VeneraNext` 独立沙箱，仅 arm64，未作 Apple 公证或公开发行。保留原显示名/版本 1.18.1 (236)，不覆盖用户已安装应用。目标仍 active；RC 产物不是完整初版验收通过的声明。
