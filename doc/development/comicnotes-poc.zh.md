# ComicNotes 初版开发与验收记录

已接入区域批注、整页笔记、书签、独立 SQLite、全书批注面板与标签、跨章节原图定位、引用链接处理、Markdown 图文导出、CBZ/图片 EPUB 原图副本映射、文件夹逐页来源清单、PDF 原件直接裁剪和全部批注备份。**完整初版仍在实现中：同指纹原件路径关联与同来源重新导入恢复已接入；Mac 书库外壳和可回退的 Reader 工作台已接入；备份恢复预览与缺失文档导入已接入；旧页手工逐页重映射支持同尺寸直接核对和不同自然尺寸逐页坐标复核，后者保持归一化坐标并需人工确认；macOS 三格式、外部目录跨会话、长篇 profile、系统外部批注引用定位及不同尺寸 Release 原生复核已有证据；其他未完成门禁仍在记录。**

## 基线和运行

- 上游：`https://github.com/CyrilPeng/Venera-Next`。
- 标签：`v1.18.1`，提交 `087147a7810039398f4eed3bcc794b576f92c46b`；标签对象 SHA 与提交 SHA 不同。
- 本地分支：`feat/annotation-poc`；已推送至 `https://github.com/threeyang3/Venera-Next/tree/feat/annotation-poc`，未修改上游仓库。
- Flutter `3.41.4`，框架提交 `ff37bef603469fb030f2b72995ab929ccfc227f0`；Dart `3.11.1`。
- 当前持久 SDK：`/Users/threeyang/.local/share/mangareader-sdk/flutter`，依赖缓存使用标准 `~/.pub-cache`。原临时 SDK 已被清理，本轮已重新下载并校验官方 SHA-256。
- 当前 Xcode `27.1`（`27A9275`）、Apple Swift `6.4`、CocoaPods `1.17.0`；Rust `1.92.0` 用于项目，stable `1.99.1` 用于旧版原生插件构建器，两套均有 arm64/x64 Mac 目标。

工具链已配置。使用 Flutter 3.41.4：

```bash
flutter pub get --enforce-lockfile
bash tool/run_annotation_poc.sh
```

本机持久 SDK 的等价命令：

```bash
export FLUTTER_BIN=/Users/threeyang/.local/share/mangareader-sdk/flutter/bin/flutter
bash tool/run_annotation_poc.sh
```

默认启动不启用批注和工作台；脚本传入 `--dart-define=COMICNOTES_POC=true --dart-define=COMICNOTES_WORKSPACE=true`。单独启用批注开关保留旧阅读器外壳；`COMICNOTES_WORKSPACE=false bash tool/run_annotation_poc.sh` 可运行该回退路径。移除两个选项恢复默认路径。

## 操作范围

导入本地 CBZ、PDF、图片型 EPUB 或图片文件夹，在**画廊或连续模式**打开。开启批注后新导入的四类原生本地来源都会记录指纹与映射；无来源凭据的旧导入仍明确按未关联缓存处理。工具栏仅用于本地漫画，并在开启自定义图片处理时隐藏，避免把经脚本变形后的画面当作原始坐标。纵向、横向、反向横向及瀑布连续模式已接入当前原图的交互批注；多图画廊已接入逐原图选择；纵向/瀑布宽图拆分及反转也使用同一原图坐标。

1. 点击画面右上角框选工具，拖拽选择区域，填写文字并保存。Esc 退出框选；编辑器支持 Enter / Cmd+Enter / Ctrl+Enter 保存，Shift+Enter 换行；输入法组词中的 Enter 交回文本系统。
2. 可添加整页笔记、书签，打开本页列表编辑或删除，并隐藏/显示画框。
3. 列表中的「复制坐标 JSON」可复制 ID、源图片编号、源尺寸、归一化矩形和文字，供几何验算。
4. 「全书批注」打开本书面板，可搜索、按类型和标签筛选、编辑标签、复制引用链接或定位原图。跨页定位临时使用单页画廊；面板中的「返回阅读布局」恢复原阅读设置。
5. 工具栏「导出图文笔记」或 Cmd/Ctrl+S 导出本书所有已有批注到用户选择的文件夹；支持取消，结果为独立的新文件夹。
6. 全书面板中的「备份全部批注」备份所有书籍的批注数据库和来源映射，图片需另行保留。Mac 书库导航中的「恢复批注备份」先校验并预览，只导入缺失文档；导入同一来源后可在空白批注面板中恢复旧批注。

**真实应用启用批注后，笔记提交到应用数据目录的独立 `annotations.db`。**重新打开同一漫画可恢复文档、页和批注 UUID；更新、删除在 SQL 提交成功后才改变内存。保存失败会重新打开保留文字的编辑器供重试，初始化失败会显示「批注暂不可用」，不会悄悄改成临时保存。

不注入运行时服务的组件预览/测试仍使用内存会话，界面会明确标记「临时」「本轮阅读内有效」。`comicnotes://` 已接入应用路由，macOS Info.plist 已声明 scheme；2026-10-30 使用 QA 导出 Markdown 在 Obsidian 点击系统链接，已实际定位 `QA-Image-Spine` 第 1 页及目标批注。新导入 PDF/EPUB 的原文件定位、同指纹原件路径关联和重新导入恢复已接入；无指纹旧导入支持同尺寸直接核对和不同自然尺寸逐页坐标复核，Release 原生窗口复验已通过。

Mac 工作台支持根级 Cmd/Ctrl+O 在书库、发现或推入的 Reader 页面打开现有导入窗口；弹窗/右键菜单期间不叠加导入窗口，退出禁止状态不打开。书库支持 Cmd/Ctrl+F 查找本地漫画。启用批注的本地 Reader 支持 Cmd/Ctrl+F 查找批注，Cmd/Ctrl+Shift+N 在已加载的画廊当前原图或连续原图进入框选；编辑/列表输入期间不会触发新框选或翻页。自定义图片处理模式仍受前述范围限制。

## 实现边界

- `features/annotations/domain`：纯 Dart 的 `PageAnchor`、`Annotation`、归一化矩形和可逆仿射变换；不依赖 Flutter、reader State 或数据库。
- `application/annotation_session.dart`：可注入事务存储的会话工作集。正式运行时使用 repository，预览和既有组件测试保留内存构造器。
- `data/annotation_repository.dart`：独立数据库、事务迁移、版本拒绝、FK/几何约束、索引、CRUD 与删除墓碑。文档 UUID 持久保存，以本地库 ID + 导入创建时间（与上游一致的毫秒精度）关联；页面按章 + 漫画根目录内相对路径关联，因此库根目录搬迁或显示顺序变化不重分配 pageId。CBZ 新导入记录解包后的归档相对路径与图片哈希；同来源重新导入的恢复及全库备份在新安装中的缺失文档恢复已接入；跨设备后仍需导入相同原件并逐页重新关联，未实现系统授权书签同步或云同步。
- `app_runtime/annotations.dart` 与 `AnnotationServicesScope`：运行时打开 owned 数据库连接，Reader 在释放或更换漫画时关闭。数据库不随漫画删除级联，也未加入原有自动云同步。
- `presentation/region_overlay.dart`：只消费页面、注释列表、变换和回调。框线宽度在视口逻辑像素空间绘制，不随缩放变粗。
- `reader/annotation_layer.dart`：将实际解码尺寸与 PhotoView 的缩放、中心平移和旋转组合为 source-to-viewport 变换。选择使用逆变换，限定在 `[0,1]`；在选框开始时冻结页面与变换，变换或页面变化时取消拖拽。
- `gallery_view.dart`：仅添加可选覆盖层插槽，保留 PhotoView 和页面控制器生命周期。邻页进入当前页时不会重新挂载已有图片子树。
- `images_host.dart`：负责 feature flag、本地类型、单页及图片处理的启用条件。
- `reader_page.dart`：拥有会话，在框选、编辑或列表打开时停止自动阅读，屏蔽阅读器手势与翻页快捷键。保存再次检查内容快照和目标有效性，防止迟到编辑误存到新页。
- 架构基线仅新增单向 `reader → annotations` UI 边；业务文件单独分类，未豁免分层或循环依赖检查。

P1 页面自然方向以未处理的本地图片解码为准；后续已为新导入 PDF 记录 MediaBox/CropBox/有效区域与旋转，为 EPUB 记录 spine occurrence，并为 CBZ/7Z 记录解包路径与导入重命名映射。新 ZIP/7Z 导入均记录原始条目 0 基索引、同规范路径 occurrence、重复候选和字节匹配结果；原生 7Z 动态库仍待 Release 验收。缩放/旋转/双页/RTL/拆图/连续流的通用变换已做纯函数测试；连续原图现已另补实际 Reader UI 集成，双页/多图画廊及纵向/瀑布宽图拆分均已另补实际 UI 集成，仍不等同于原生 App 验收。

## 基线检查与已知环境问题

未修改稳定版在 `/private/tmp/mangareader-baseline` 独立副本运行，用于对照。源码核对了方案列出的 image_position、page_layout、gallery/continuous、scaffold、image_export/binding、本地 CBZ/PDF/EPUB 导入器及架构检查器；稳定版存在这些入口。本轮没有移植 main 的变动；未执行 main 与稳定版的逐提交差异评估。

- `flutter pub get --enforce-lockfile`：成功，未升级依赖或改写锁文件。独立 `tool/code_audit` 子包也按其锁文件初始化。
- 基线结构与架构检查：通过。
- 基线 Python 脚本测试：139 项，1 项失败、10 项跳过。失败为 `test_resolves_uri_and_relative_package_roots_with_spaces` 的 `/var` 与 `/private/var` 路径比较。系统 Python 3.9 还缺少现代类型语法和 tomllib，正式结果使用应用附带的新 Python。
- 基线 reader Flutter 测试：886 通过、30 跳过、1 失败；`display_image_provider_test.dart` 的 `two visible listeners stay mounted while preparation joins and resumes` 出现异步监听数量断言失败。保留原日志，没有改变该上游测试。
- 基线与修改版的 `flutter build macos --debug --no-pub`：均实际执行，均因缺少完整 Xcode、`xcrun` 无法调用 `xcodebuild` 而失败；不是已产出可运行 App。Flutter 构建工具自动修改的 Xcode scheme / gitignore 已还原，没有纳入发布配置改动。
- Mac 原生启动截图、macOS App 内的 CBZ/PDF/EPUB 导入与翻页、原生窗口图片导出、真机 profile、Rust 测试、iPad 验证、完整上游 CI：**未执行**。

## P1 验证结果（2026-10-29，后续新增检查见下节）

| 检查 | 实际结果 |
| --- | --- |
| `flutter analyze --no-pub` | 通过，No issues found |
| `flutter test --no-pub test/features/annotations` | 31 项通过；含坐标模型、会话 CRUD、覆盖层、真实 PhotoView 编辑与生命周期测试 |
| `flutter test --no-pub test/features/reader` | 890 项通过、30 项原有测试跳过 |
| 批注测试 + gallery_page_continuity_test | 合计 43 项通过，包含批注启用时 LTR / RTL / 纵向翻页的图片帧与控制器连续性检查 |
| Python 脚本测试，`TMPDIR=/private/tmp` | 共 139 项，129 通过、10 跳过；通过临时目录配置规避基线 `/var` 别名问题，没有修改上游测试 |
| check_structure_imports / check_architecture_dependencies | 均通过 |
| `dart tool/check_git_dependencies.dart` | 通过，声明与锁文件一致 |
| `tool/code_audit` 的 `dart run bin/self_check.dart` | 通过，AST inventory checks passed |
| 修改的 15 个 Dart 文件格式检查 | 通过，0 个文件需修改 |
| `git diff --check` / `bash -n tool/run_annotation_poc.sh` | 均通过 |
| macOS debug 构建 | 未通过，缺完整 Xcode；见上面的基线说明 |

基线和历次命令输出保留在本地 `logs/`，包括 `pub-get.log`、`baseline-python-tests.log`、`baseline-reader-tests.log`、`baseline-macos-build.log`、`annotation-tests.log`、`reader-tests.log`、`python-tests.log`、`flutter-analyze.log`、`macos-build.log` 和 `audit-self-check.log`。日志不纳入源代码提交。

可复现的组件测试证据位于 `build/annotation-qa/annotation-widget.png` 和同目录 `annotation.json`。它们来自 **Flutter 组件测试的合成页面，不是 Mac 原生 App 截图**；测试字体会将工具栏图标显示为方块。JSON 中原图尺寸为 400×600，选区 `[0.25, 0.4, 0.65, 0.7]`；在缩放 2.5、平移 `(30,-20)`、800×600 视口中，对应截图上的 `(180,130)` 到 `(580,580)`。复现命令：

```bash
COMICNOTES_QA_DIR="$PWD/build/annotation-qa" \
  flutter test --no-pub test/features/annotations
```

## P2 持久化接入（2026-10-29）

持久化连接由 `AnnotationServicesScope` 注入；生产启动路径在应用数据目录打开 `annotations.db`，Reader 在释放或切换漫画时关闭连接。新增事务 schema v1，包含来源文档/页、批注、标签与导出清单表（P2 接入时后两项表预留；后续标签功能已使用 annotation_tags，export_manifests 尚未使用）。迁移失败整体回滚；高版本数据库拒绝打开，不清库。外键、矩形边界和类型约束由 SQLite 再次执行。

会话只在数据库提交成功后更新工作集；失败的保存保留文字和选框，失败删除保留原批注。另一个阅读会话已经删除的批注不能被迟到编辑悄悄复活。来源尺寸变化会要求重新关联，原笔记仍保留；数据库不可用时显示错误入口，阅读功能继续工作。

本地库关联键使用上游实际持久化的毫秒时间精度，避免第一次导入与重开后时间截断导致出现两份批注文档。页面身份使用漫画目录内相对路径，移动整个库后可保留 UUID；**重新导入同一个原始文件的去重/重新关联仍未实现**；后续已为新导入 CBZ 补充导出时的内容哈希校验和全部批注备份，旧导入尚无这些来源凭据。

本轮验证：

- 批注开关开启：`flutter test --no-pub --dart-define=COMICNOTES_POC=true test/features/annotations test/features/reader`，**937 项通过、30 项原有测试跳过**。其中 46 项批注测试，891 项阅读器测试。
- 覆盖真实 Reader 路由中的持久化笔记创建、列表弹窗编辑、写回；修复弹窗打开后路由检查错误阻止编辑的问题。
- 覆盖数据库重新打开、同名文档隔离、库路径移动、页面排序变化、缺失原图、30 条记录 CRUD、写失败工作集一致性、跨文档 FK、非法矩形、迁移回滚、高版本拒绝，以及删除墓碑的迟到编辑保护。
- `flutter analyze --no-pub`：No issues found；结构检查、架构检查、`git diff --check` 均通过。
- 日志：`logs/annotation-enabled-reader-tests.log`、`logs/annotation-persistence-tests.log`、`logs/annotation-persistence-integration-tests.log` 与 `logs/flutter-analyze.log`。

这些是源代码与组件测试证据；缺少完整 Xcode 的原生构建阻塞没有解除。

## P3 图文导出接入（2026-10-29）

已接入阅读器工具栏「导出图文笔记」与 Cmd/Ctrl+S：对本书所有现存批注建立不可变快照，选择目标文件夹后生成完整的新笔记目录。目录包含标题命名的 Markdown、`assets/<annotation-id>.png` 和 `manifest.json`。PNG 使用现有 image 引擎无损编码，没有增加新图像依赖；本轮不采用示例中的 WebP 格式。

- 区域批注按自然方向归一化矩形从图片资源裁剪；整页笔记导出整图；书签导出文字和定位链接，不要求读取图片。
- 裁剪以 floor/ceil 向外取整，最多增加边缘的舍入像素；JPEG EXIF 方向在裁剪前烘焙。超过四千万像素、超过 256 MiB 的输入或动态图会明确拒绝导出，不静默截断或跳过笔记。
- P3 初次接入时导入器尚未输出原始映射，因此使用本地导入/渲染缓存（后续 CBZ 原图副本映射见下节），并在 Markdown、manifest 和成功提示中明确注明；不能将此理解为已完成原件质量导出。
- 先在目标文件系统的临时目录写完图片、Markdown、清单并核对文件，再将目录重命名发布。任何读取、编码或写入失败都会放弃整份本次导出；旧导出和外部手写内容不覆盖。
- 导出由原有 ImageWork 持有，支持取消与退出收尾；结果提示不持有仍需等待的图片工作。已修复快速完成时进度路由未正常移除的问题，并验证成功提示打开时仍可完成工作释放。
- 清单记录批注 UUID、坐标、时间、图片相对路径与 SHA-256、质量说明和管理区块 hash。Markdown 输出 URL 编码的 `comicnotes://open` 链接；后续已接入应用路由，系统分发仍待原生验收。
- 数据库升级到 schema v2，添加原始文件大小字段并补充来源读取接口；v1 数据升级后保留原 ID 和笔记。该阶段原始文件信息尚未填充；后续新 CBZ/PDF/EPUB 导入已接入来源映射。

验证结果：

- 开启批注后的完整测试：**950 项通过、30 项原有测试跳过**（57 项批注测试 + 893 项阅读器测试）。
- 像素测试检查裁剪尺寸及边缘像素；覆盖 Unicode/特殊字符标题、路径穿越、重复 ID、跨文档数据、文件冲突、用户改写的旧 Markdown、来源缺失、图片损坏、尺寸变化、取消和完整清单。
- 真实 Reader 路由测试通过文件选择器模拟选择目录，实际写出 Markdown、PNG 和 manifest；验证关闭时取消以及成功提示不阻碍资源释放。
- 完整静态分析、结构/架构检查和 Git 空白检查通过。日志见 `logs/annotation-export-tests.log`、`logs/annotation-export-integration-tests.log`、`logs/annotation-enabled-reader-tests.log` 和 `logs/flutter-analyze.log`。

后续已补充全书 Inspector、标签、定位与引用协议、CBZ 原图副本导出和备份，详见下节。后续又接入新 PDF/EPUB 原件读取；仍未完成来源重新关联、Mac 书库外壳和原生 App 运行验收。上述通过结果不等同于已经完成整个初版。

## 全书面板、引用、CBZ 来源和备份（2026-10-29）

- 全书面板按文字、章节、类型和标签筛选；支持编辑、删除、复制引用和定位。标签最多 32 个、每个不超过 64 字，去重后独立存储；标签和批注写入处于同一 SQL 事务，失败不改变工作集。标签随正文写入 Markdown 与清单。
- 引用契约为 `comicnotes://open?document=<UUID>&annotation=<UUID>`。处理器先校验参数、文档与批注，再按本地库 ID 和导入时间核对当前导入版本，最后从当前图片列表按来源身份重新解析位置。失联、删除、版本不一致或异步处理器失效时不打开错误页面。
- 画面定位临时切换为单页画廊，显示选中框和文字，保留存储的阅读模式和每屏图片数；「返回阅读布局」恢复这些设置。打开面板、回到旧 Reader 和导出前刷新数据库工作集，避免继续显示另一 Reader 已删除的批注。
- 新 CBZ/ZIP/7Z 导入在开启批注开关时写入漫画目录内的 `.comicnotes-source.json`。记录原归档 URI/大小/SHA-256、解包相对路径、重命名后的库内相对路径、每页大小和 SHA-256；注册前验证原归档未变化，并验证页副本字节一致。元数据失败沿用既有导入生命周期回滚规则。
- CBZ 库内页本身是未经转码的原图片副本。导出时重新计算哈希，匹配后以 `original` 质量裁剪，并在 manifest 的资源来源中记录归档哈希与解包路径。原压缩包删除或库目录移动不影响这些已验证副本；副本内容变化会拒绝导出，笔记保留。**没有额外保留整份压缩包，也没有从压缩包重新解码导出；记录的是解包路径，重名 ZIP entry 的原始 occurrence 尚未识别。**
- 该阶段旧导入与 PDF/EPUB 按原流程导出缓存，并明确警告（后续新 PDF/EPUB 来源接入见下节）；不能将新 CBZ 的原图副本保障推广到所有来源。不存在通过标题自动合并或跨版本重绑的逻辑。
- 「备份全部批注」使用 SQLite 在线 backup API，覆盖所有文档、批注、标签、来源映射和删除墓碑，包括已提交的 WAL 页面。独立 isolate 只传入路径，不共享原生连接或 Reader 状态；生成新目录，校验数据库完整性/外键与 SHA-256 后发布。备份含 `annotations.db` 和 `backup.json`，不含图片或显示缓存，也未提供覆盖现有数据库的恢复 UI。
- macOS 已声明 URL scheme；应用内真实路由测试覆盖链接打开新 Reader、跨章节定位、图片顺序改变、导入版本拒绝、过期处理器及恢复原布局。**系统级唤起、原生插件和 App 启动仍未验证。**

新增验证包括真实 CBZ 导入到图片裁剪、删除原归档、移动库目录、同长度图片字节变化、标签事务回滚、跨文档 WAL 备份、备份取消/损坏来源，以及真实 Reader 面板通过文件选择器完成备份。加入工作台前，相关完整回归为 **1036 项通过、30 项跳过**（93 项批注、898 项 reader、45 项 CBZ/导入回滚检查）；工作台后的最终计数见下节。

扩展运行整个 `test/features/local_comics/import_export` 时，有 3 项 `import_presentation_test.dart` 测试因 `venera/method_channel` 的目录/文件选择器未实现而失败；在未修改的稳定版副本单独执行同文件也得到 6 项通过、同样 3 项失败。其余 234 项通过（包括新增来源测试）。不是已通过真实 macOS 选择器验收。日志：`logs/archive-provenance-tests.log` 与 `logs/baseline-import-presentation-tests.log`。

## Reader 工作台适配（2026-10-29）

应用 `frontend-design` 技能制定了与漫画观察/研究场景对应的布局：图像占据主体，工具区保持安静，不增加卡片装饰或动画。设计 token 为浅灰 `#F5F5F7`、分隔线 `#DCDCE1`、正文 `#1D1D1F`、次要文字 `#6E6E73`、选择蓝 `#007AFF`、画布 `#151515`，另有对应暗色值；延续应用配置的字体，测试截图载入本机中文系统字体，没有新增字体或图片依赖。

- Mac、本地批注启用且额外开启 `COMICNOTES_WORKSPACE` 时，在至少 980×480 的窗口显示固定工具栏、阅读画布和可折叠 360 dp Inspector。窄窗口使用既有模态侧栏；其他平台和关闭开关时保留原外壳。Toolbar 提供返回书库、章节、阅读设置、专注阅读和批注栏开关。
- 并排 Inspector 中的定位保留面板。搜索和编辑持有输入状态，防止左右方向键变成翻页；结束输入或面板释放后归还。专注模式隐藏工具区，并提供返回工作台入口。
- 布局只调整同一个阅读画布的约束，更新画布局部 MediaQuery 和 Reader 的实际尺寸；不把窗口尺寸用于批注坐标。开合面板和专注模式保留图片控制器；真正定位到另一页按原导航生命周期重新装配。
- 采用中性工具区与深色画布的局部 Theme，未更改全局主题或用户保存的阅读模式。控件支持暗色；工具栏高度随文字缩放增加，批注操作行可换行。
- 此阶段提供 Reader Toolbar + Inspector，**左侧书库/收藏夹/标签外壳、Settings 重设计、原生窗口效果和性能 profile 尚未完成**。

工作台布局组件测试 3 项通过，含画布状态连续性、局部尺寸、专注模式和窄窗回退；开启两个开关的真实 Reader 批注路由定向测试 9 项通过，覆盖并排面板、原图坐标中心、输入焦点、定位后保留 Inspector 及控制器连续性。浅色/暗色截图 `build/annotation-qa/workspace-light.png` 与 `workspace-dark.png` 均是实际 Reader 组件在合成黑色测试图片上的渲染，**不是已构建的 macOS App，也不是原生启动证据**。

扩大并发回归时，`gallery_input_test` 和 `reader_exit_integration_test` 出现超时及后续 runAsync 连锁异常；停止该轮后，独立重跑分别 7 项和自动模式检测 14 项均通过，未改动这些用例的超时设置。随后以 `--concurrency=1` 串行核对完整相关回归：**1039 项通过、31 项跳过**（93 项批注、901 项 reader、45 项 CBZ/导入回滚检查；跳过项含 30 项原有测试与 1 项需单独启用工作台的测试）。该次通过不抹去此前并发失败，尚不能确认超时的唯一原因。日志保留在 `logs/annotation-enabled-reader-tests.log`、`logs/workspace-gallery-input-tests.log`、`logs/workspace-auto-mode-tests.log`、`logs/annotation-workspace-full-tests.log` 和 `logs/annotation-workspace-qa.log`。

最新检查：`flutter analyze --no-pub` 无问题；结构/架构检查通过；46 个相关 Dart 文件格式检查通过；`git diff --check`、`bash -n tool/run_annotation_poc.sh` 和 `plutil -lint macos/Runner/Info.plist` 通过。最新串行完整日志为 `logs/annotation-serial-regression-tests.log`，两个工作台开关启用后的定向日志为 `logs/annotation-workspace-full-tests.log`。仍无 macOS 原生构建产物。

## PDF 原件与图片 EPUB 来源（2026-10-29）

已在现有锁定的 pdfrx/PDFium 上接入新导入来源，没有升级包版本。`pdfium_dart 0.2.5` 和 `ffi 2.2.0` 从已有传递依赖提升为直接依赖，锁文件仅改变这两项的依赖分类。数据库仍为 schema v2，来源元信息和页映射使用既有 JSON 字段。

### PDF

- 通过 pdfrx 提供的 `useNativeDocumentHandle` 只读桥接获取 MediaBox、CropBox、有效内容区域、原始 0 基页索引及 `/Rotate`；原生句柄不跨 isolate、不逃逸且及时释放。记录 pdfrx 已旋转有效页面的尺寸与坐标空间版本。
- 导入前后校验整份原 PDF 的大小/SHA-256，并记录每张导入 JPEG 的哈希。中途原件变化会在注册前失败，清理本次拥有的输出；不会注册错版本页面。
- 导入窗口选择 PDF 后提供默认开启的「保留 PDF 原件副本」复选项，说明额外空间与失联降级。原件副本保存在漫画目录内，页映射使用相对路径；原压缩包/文件删除、漫画目录整体移动和显示缓存丢失后，已有 UUID 与原件导出仍可保留。
- 导出先验证仍存在的显示缓存未被换图，再校验原 PDF 指纹与几何；按约定的归一化区域，直接从原 PDF 以 300 dpi 渲染选区，使用 floor/ceil 向外舍入后编码 PNG。不会将导入 JPEG 放大冒充原质量。单次渲染最多四千万像素，过大选区明确拒绝。
- 原 PDF 缺失、指纹变化或几何不一致时，只允许使用指纹匹配的导入缓存，Markdown/manifest/结果提示均注明降级。缓存也变化时拒绝导出并保留笔记；不把旧坐标用于另一份图片。不能重新关联的状态保存在批注库。
- 新增两份可复现测试 PDF：`test/fixtures/annotations/pdf-crop-rotate.pdf`（非零/负原点 MediaBox、CropBox 和 0/90/180/270 度旋转）及 `pdf-mixed-boxes.pdf`（CropBox 超出 MediaBox、混合页面尺寸）。生成器为 `tool/generate_annotation_pdf_fixtures.py`，仅测试再生成需要 Python reportlab/pypdf。
- **真实 PDFium 原生库测试**核对 6 页几何、跨象限裁剪的像素与导入 JPEG 中的对应位置，并实际导出 Markdown/PNG/manifest；不是用假 PdfPage 支撑原件裁剪结论。还覆盖原件副本移动/源文件删除/缓存删除、原件变化与失联警告、坏缓存拒绝、导入中原件变化。PDFium 库由现有 native assets hook 提供，不需要先构建完整 macOS App。
- 按 `pdf` 技能另用 Poppler 渲染并查看了全部 6 页；预览在 `build/annotation-pdf-qa/`，Poppler 默认 MediaBox 预览含白色裁切外区域，与 PDFium 有效 CropBox 的尺寸区别是有意的。捆绑 Poppler 的字体缓存路径不可写，验证时使用该目录中的临时 fonts.conf 和 `/private/tmp/comicnotes-font-cache`，没有更改系统字体设置。

### 图片 EPUB

- 记录 OPF 路径、spine item ID/资源路径、**原始 itemref 索引**（包括被忽略的非线性项所占位置）、图片引用次序、同一 spine 中的资源出现次数、资源路径以及匹配的 manifest ID 集合。
- 同一资源在一个 XHTML 中重复、同一 spine item 再次出现，以及直接图片 spine 的重复引用都会导入为独立页身份；不会按资源路径去重成一条批注。
- 记录原 EPUB 指纹、原资源路径与重命名页的 SHA-256；导入/注册前验证原件未变。库内图片未经转码，导出重新校验后标记为 `original` 并保留 OPF/spine 上下文。删除原 EPUB 和移动漫画目录后仍可用已验证的原图副本。
- 两种真实 ZIP/EPUB 样本由 `epub_source_test.dart` 在运行时生成：直接图片 spine、含重复图片/重复 spine item/非线性项的 XHTML spine；验证多个 occurrence 的不同 page UUID 和导出截图的边缘像素。重排式文本 EPUB 不作为批注支持范围。

CBZ 同时补了第二份实际图片样本：平面归档加 metadata 章节范围与特殊字符原文件名；两份 CBZ 的裁剪使用像素梯度而非单色图，核对非零选区偏移和边缘像素。

定向验证：PDF 原件及原有 PDF 导入/批处理/任务检查 **40 项通过**；图片 EPUB 初次回归仅旧生命周期用例的固定文件数断言失败，已改为精确检查普通页、封面及开启开关时应有的来源清单。三格式与完整阅读器的串行相关回归 **1091 项通过、31 项跳过**；随后补充原 PDF 找回后的状态恢复并复测真实 PDF 流程 **8 项通过**。静态分析、结构/架构和 Git 依赖清单检查通过。日志为 `logs/source-formats-full-regression-tests.log`、`logs/pdf-source-final-tests.log` 和 `logs/flutter-analyze.log`。

**上述是引擎、文件和组件层面的真实验证，不能代替 macOS App 启动、原生文件提供者授权、系统 scheme 唤起、窗口操作与性能 profile。**完整 Xcode 缺失的 App 构建阻塞仍未解除。

## 后续接口

1. 配置 Xcode/Rust/CocoaPods，完成真正的 Mac 启动、系统 scheme 唤起、样本导入与原生导出验收。
2. 提供孤儿批注文档的浏览和按来源指纹重新关联；保留 UUID，拒绝标题或旧页码自动绑定。补充备份恢复工作流。
3. PDF/EPUB 的新导入来源已接入；继续补充旧导入的重新关联、CBZ 重名 archive entry occurrence、图片文件夹来源凭据和真实文件提供者验证。
4. Reader 工作台、Mac 书库外壳与 tokens 已接入；继续真实 profile 和完整可访问性检查。

关闭编译开关即可禁用批注入口；保留 `annotations.db`，不删除用户笔记或降低其 schema 版本。上游 GPL 声明与许可证保留。

## 后续原件路径重新关联（待复测）

新增全书面板「重新关联原件」入口：通过文件选择器选择原件，流式校验大小与 SHA-256，只有与导入时内容完全相同才更新独立批注库的 source_uri。数据库事务再次核对来源类型、大小和哈希；不修改文档/页/批注 UUID、坐标和标签。不同版本或没有原件指纹的旧导入明确拒绝自动关联。Reader 的 ImageWork 持有解析过程，过期或关闭的会话不能提交。此功能用于原件路径迁移，尚不提供跨版本重映射或孤儿书籍与重新导入记录的合并。

新增 source_relocation_test.dart 覆盖错误版本不改绑定、重开后 UUID/标签/路径保持及异步退休；尚未运行。上轮已确认 105 项批注测试、8 项 Reader 绑定测试和静态分析通过；在此之后新增的原件关联与「保留 PDF 副本缺失时改读外部原件」仍待 Flutter 测试和静态分析复验。

本次 Flutter 复测命令被自动审批服务拒绝执行，理由是审批服务额度限制导致审核无法完成，并非安全判定。未绕过审批，保留代码、测试与现有日志；完整初版目标仍未完成。

继续补充的待执行验证：`pdf_source_test.dart` 增加实际旋转 PDF 移动后重新关联、重开数据库并比较导出 PNG 字节的端到端用例；`inspector_widget_test.dart` 增加关联中禁用按钮、失败保留提示和重试成功的组件用例。修复 Reader 关联入口 guard 的代码风格问题。新增与相关 12 个 Dart 文件的格式检查、结构/架构检查和 `git diff --check` 通过；这些检查不等同于测试或完整静态分析，新增行为仍待验证。

待审批服务可用后执行：

```bash
PUB_CACHE=/private/tmp/mangareader-pub-cache /private/tmp/mangareader-flutter/bin/flutter analyze --no-pub
PUB_CACHE=/private/tmp/mangareader-pub-cache /private/tmp/mangareader-flutter/bin/flutter test --no-pub --concurrency=1 --dart-define=COMICNOTES_POC=true test/features/annotations test/features/reader
```

当前新增关联仅处理「同一原件迁移路径」，不声称完成孤儿批注与重新导入漫画的绑定，也未完成 Mac 书库外壳、原生 App 构建与性能验收。

### 当前验证阻塞与最后一项路径修复

代码核查发现保留 PDF 副本存在但内容损坏时会遮蔽已重新关联的完好原件。已改为依次计算候选文件指纹，只有匹配导入时指纹的文件可用于渲染；两份都不可用时明确按 missing/changed 降级。渲染后再次校验所用文件。新增测试覆盖保留副本损坏、外部原件迁移后关联、原件导出恢复及不改写损坏副本。格式、结构/架构和 Git 空白检查通过；Flutter 回归仍未运行。

当前停止继续叠加功能，先解除自动审批服务额度导致的测试执行阻塞。该条件已连续多轮存在；当前时间仍早于服务提示的恢复时间，没有重新执行此前未获审核的测试，也没有复制 SDK 或改用其他执行路径绕过审批。恢复后优先执行上一节的 analyze 和完整串行回归，失败修复完成后再继续孤儿文档重绑定与 Mac 书库外壳。完整 Xcode 仍另行阻塞原生 App 构建与系统验收；不能将上述测试或源码视为初版全部完成。

## 审批恢复后的原件关联复验（2026-10-29）

目标恢复后，通过相同的 require_escalated 审批路径执行 Flutter 命令已成功，先前审批额度导致的验证阻塞已解除。原件关联/PDF 实际裁剪/面板重试的定向测试 **16 项通过**，包括损坏保留副本被正确跳过、选择完好的同指纹原件、真实 PDF 迁移后重开数据库并比较裁剪 PNG、错误版本拒绝与退休异步结果不提交。

新增真实 Reader 面板到文件选择器的集成测试 **1 项通过**：在 SQLite 注入已知来源指纹，通过实际运行时选择器绑定选择移动后的同一文件，核对 source_uri、批注 UUID、输入状态和路由保留。文件选择器原生窗口由测试 channel 替代，此结果不代表已验证 macOS 原生选择窗口或权限书签。测试初次卡在 Flutter fake async 中的真实文件哈希读取，已用 tester.runAsync 驱动文件 I/O，未修改产品行为或放宽断言。日志为 `logs/source-relocation-verification.log` 和 `logs/source-relocation-reader-selector.log`。

静态分析 `flutter analyze --no-pub` 已通过（No issues found）；两处新增代码风格问题已修复。完整批注/阅读器串行回归 **1010 项通过、31 项跳过**（编译该轮测试之后新增的原件选择器集成用例另行运行 1 项通过）；日志为 `logs/source-relocation-full-regression.log`。这轮未重复执行未改动的 86 项导入专项用例，因此计数不能直接和上一轮 1091 项比较。尚待孤儿文档重绑定、Mac 书库外壳、原生 App 构建与性能验收；完整初版目标保持未完成。

## 同来源重新导入后的旧批注恢复（2026-10-29）

已在空白漫画的全书批注面板加入「恢复旧批注」：查询原件类型/大小/SHA-256 完全一致、旧本地导入 ID+时间已不在漫画库中的批注文档。用户选择其中一份后，再校验旧页身份、章节、原件 locator 上下文和当前导入图片的内容哈希；当前导入已存在任何批注行（包括删除墓碑）时拒绝，不覆盖、不合并。

恢复在独立批注库的单个事务中完成：复查双方文档身份与页集合、移除当前空文档的页/清单记录和空文档行、把旧文档 UUID 绑定到当前库 key、更新当前图片位置与 locator。旧批注、标签、页 UUID、坐标、创建时间和旧文档 UUID 均保留。任何写入失败整体回滚。旧漫画仍注册在库中、图片变化、映射变化、旧来源没有可靠 locator 或异步操作退休时拒绝。成功后 Reader 重新建立 owned 会话并重建对应画布，原来的 comicnotes:// 引用可以定位到当前导入版本。

此恢复面向**原文件字节相同、导入器生成的页/章节身份仍相同**的重新导入，不能按标题匹配不同版本、不能合并两份已有笔记，也不提供跨导入器改变章节结构后的手工逐页映射。旧导入无来源指纹仍需后续迁移工作；未新增云同步或改动原文件。

验证：全部批注测试 **117 项通过**；真实 CBZ 重导入恢复（旧链接定位、标签和 UUID）、已有笔记与墓碑拒绝、坏图片与过期操作拒绝、旧导入仍注册时拒绝、事务中途写失败回滚及重试，均有测试。真实 PDF 重导入改变保留副本选项后仍可恢复并导出原件；重复 spine EPUB 重导入恢复 7 个独立 page UUID。真实 Reader 面板候选选择/恢复会话/旧引用定位的组件集成测试通过。

日志：`logs/annotation-recovery-all-tests.log`、`logs/annotation-recovery-integration-tests.log`；最新完整批注/阅读器回归及 Mac 工作台结果分别见 `logs/annotation-recovery-full-regression.log` 和 `logs/annotation-recovery-workspace-tests.log`。仍需 Mac 书库外壳、备份恢复 UI、原生 App 构建和窗口/文件提供者/性能验收。

本阶段最终验证：完整批注/Reader 串行回归 **1020 项通过、31 项跳过**；其中完整回归编译后新增的两个面板取消/退休用例，及章节列表缓存调整后复验的三格式恢复、PDF/EPUB 来源相关用例，共 **26 项定向检查通过**。Mac 工作台启用时的画布和恢复操作另 **2 项通过**。静态分析 No issues found，结构/架构、格式与 Git 空白检查通过。归档测试使用既有 Dart ZIP 后备路径，日志中的 zip_flutter/7zip 原生动态库缺失警告不代表这两个原生提取器已验证；实际 macOS App 原生验收仍受完整 Xcode 缺失阻塞。

## 可回退的 Mac 书库外壳（2026-10-29）

继续按 `frontend-design` 技能实现书库界面，沿用中性系统灰、蓝色选中态、现有配置字体；深色对应 Reader 工作台 token。没有新增图片或字体依赖、没有重做存储层。两个开关都开启且运行在 macOS 时，MainPage 默认进入本地书库；窗口宽度超过 980 dp 时使用左侧书库/收藏夹/本地漫画标签、主体封面网格、已有搜索/排序/下载与导入操作。原 Home/Favorites/Explore/Categories 入口仍保留。

- `NaviPane` 增加可选展开侧栏 builder、展开阈值和根内容 revision。复用原 nested Navigator/observer/pop 逻辑；改变标签刷新原根页面，缩放窗口保持 Navigator 实例，低于阈值回退原图标/底部导航。关闭工作台后仍为原四个入口并尊重已保存的初始页偏好。
- Mac 书库对现有 `SliverGridComics` 使用可选 gallery 显示参数，按窗口宽度选择列数，不改写全局漫画展示设置；原调用不传参数时行为保持。点击封面仍经原 `openLocalComic` 路由，长按多选及上下文操作继续复用。
- 标签来自本地漫画元数据，按完整标签精确筛选，并与现有文字搜索相交；不是批注标签。改变筛选会清除原多选，防止旧隐藏选中项被误删。漫画元数据更新时刷新标签列表，当前标签消失则回到完整书库。
- 侧栏收藏夹复用真实 FavoritesPage/LocalFavoritesPage，传入目标文件夹并经原 SettingsSaveState 保存选择；保留错误态、退出守卫与连接作用域。宽窗口不重复展示第二列收藏目录，原文件夹选择器仍可用；其他调用与窄窗保留原布局。
- 导入入口直接打开原导入窗口，没有另写导入流程。真实组件检查发现原帮助按钮固定 90 dp 会溢出，已改为内容宽度，操作保持不变。
- 样式仅在开启工作台的 MainPage 下面作用，关闭开关保留原应用主题。当前未新增原生毛玻璃/系统 Toolbar 桥接或修改窗口发布配置。

验证与证据：

- 侧栏深浅色/2 倍文字、动作分发、同 Navigator 根内容 revision、推入页面返回和窄窗回退，以及既有 navigation 生命周期共 **8 项通过**。
- 真实本地库/收藏库的 MainPage 集成：两次收藏夹切换（含真实偏好保存）、连续标签筛选、清除旧多选、元数据更新清除失效筛选、原导入窗口和宽窄缩放均通过。开启工作台时 1 项通过、关闭开关的相反配置用例跳过；关闭开关时原四入口与启动页用例另运行通过。
- 默认配置的书库/导航/卡片/全部收藏专项扩展回归：**569 项通过、1 项配置跳过、3 项失败**。失败均位于 `favorite_metadata_source_test.dart`，因缺少 `flutter_qjs.framework/flutter_qjs`，其后 callbacks 未初始化是连锁异常；未修改稳定版单独运行同文件也复现相同 3 项失败。保留日志，不改成跳过，不声称通过原生 QuickJS 验收。
- 关闭工作台的导航与侧栏定向复验 **9 项通过、1 项配置跳过**；静态分析 No issues found、结构/架构/格式及 Git 空白检查通过。
- 浅色 `build/annotation-qa/library-light.png`、暗色 `library-dark.png` 均为实际 MainPage 组件渲染并已查看：使用真实临时漫画/收藏数据库、合成几何封面和显式注入的本地 FileImage，**不是 macOS App 启动截图，也不是实际漫画内容**。截图不涉及外部浏览器。

日志：`logs/mac-library-sidebar-tests.log`、`logs/mac-library-final-integration-tests.log`、`logs/mac-library-fallback-tests.log`、`logs/mac-library-full-regression-tests.log`、`logs/baseline-favorite-metadata-source-tests.log`、`logs/mac-library-light-qa.log`、`logs/mac-library-dark-qa.log`。完整 Xcode、原生插件、文件提供者权限、系统深浅色/窗口/trackpad 与性能 profile 仍需原生 App 验收，当前不将 P4 真机门禁视为完成。


## 批注备份恢复预览与导入（2026-10-29）

工作台开启时，Mac 书库侧栏提供「恢复批注备份」，折叠/窄窗导航保留同一动作。选择备份文件夹后，先创建私有快照，验证清单格式、schema 版本、数据库 SHA-256、完整性、外键和记录计数。通过固定列的参数化值复制到应用自建 schema，再验证坐标、UUID 和 JSON；备份里的触发器/视图拒绝导入，不执行外来 schema。数据库上限 256 MiB、清单上限 64 KiB；兼容 schema 1/2，不修改所选备份。

预览显示书籍数、未删除笔记数和当前已存在的文档数。用户确认后，只添加缺失文档；同 UUID 文档整册跳过，即使现有内容被编辑或删除，也不会被备份复活或覆盖。提交事务重新检查已有 UUID，页/批注/导出 UUID 冲突及写入失败整体回滚；取消验证或导入会清理未发布的临时目录。关闭窗口后到达的文件选择结果不能提交。

恢复保留文档/页/批注 UUID、坐标、标签、时间、删除墓碑和导出清单。安装局部 library_key 改为 `restored:<documentUUID>`，旧显示缓存 URI 清空，状态标为待关联，防止不同设备碰巧使用相同 local ID+时间而把旧坐标套到错误漫画。具备原件指纹的 CBZ/PDF/EPUB 可导入同一原件后，在空白批注面板选择「恢复旧批注」，沿用已有逐页校验及事务绑定。无来源指纹的旧记录同样保留在库中，但暂不支持手工映射；界面已明确提示。本阶段未实现已有文档合并、逐页人工映射或整个数据库覆盖。

验证：

- 启用 POC + 工作台的批注、真实来源及书库相关回归 **136 项通过、1 项相反开关配置跳过**，日志 `logs/annotation-restore-enabled-tests.log`。
- 最终恢复/预览/侧栏定向复验 **16 项通过**：覆盖 schema 1 兼容且原备份不变、哈希/记录数错误、触发器、非有限尺寸拒绝、已验证快照抗后续篡改、已有文档在提交前出现时仍跳过、跨文档页 UUID 冲突与取消回滚，以及明确预览/取消/异步关闭/错误提示。
- 随后补充的真实 CBZ「全库备份 → 新批注库恢复 → 同 local ID 不自动附着 → 指纹逐页重新绑定 → 旧引用跳转」用例及既有重新导入恢复用例 **7 项通过**，日志 `logs/annotation-backup-source-recovery-tests.log`。归档仍使用既有 Dart ZIP 后备提取路径，不将缺失的 zip_flutter/7zip 原生插件视为验收通过。
- 静态分析 No issues found，结构/架构依赖、格式和 Git 空白检查通过。当前仍没有可运行的原生 macOS 构建，完整 Xcode/原生插件及窗口、协议分发、文件权限和性能门禁未通过；完整初版目标保持未完成。


## 图片文件夹来源清单与重导入恢复（2026-10-29）

新导入的原生图片目录也建立来源映射：使用与 Reader 相同的章节/封面/页面规则，按排序后的相对页路径、每页字节数和 SHA-256 构造带版本标记的目录内容指纹。目录绝对路径、文件修改时间与封面缩略图不进入该身份；相对页路径变化或图片字节变化会改变指纹，不按同名/同尺寸绑定。目录页 locator 为 `folderImage`，保留相对页路径和单页字节指纹。

引用原目录及复制到书库两种导入均支持。来源清单保存在应用数据区 `comicnotes-sources/<libraryKey哈希>.json`，libraryKey 包括本次导入时间；不往用户所选目录写旁车文件。复制导入以完成且经原复制记录校验的库内原图为来源。写入采用同目录暂存后重命名，已有不同指纹的同一导入身份拒绝覆盖。捕获/持久化失败时原漫画仍按原导入流程注册，显示批注来源映射未保存的单独提示，不把导入成功回滚成失败。批注开关关闭时不进行此捕获；Android SAF 目录本轮不做此映射。

Runtime 优先读取当前 libraryKey 的安装内来源清单；文件夹原图导出要通过逐页指纹校验，质量标为原图并保留目录指纹。目录移动后可经现有「重新关联原件」选择目录，重新构建整册清单，完全相同才更新 URI。原显示路径已失联时，导出可按已验证目录 URI + 相对页路径读取，并检查链接不能逃出目录；旧图片仍存在但变化时拒绝沿用旧坐标。目录重新导入可沿用同来源旧批注恢复，逐页复核并保留页/文档/批注 UUID、标签和旧引用。

验证：

- 开启 POC + 工作台，完整批注与导入服务/目录复制/存储协调回归 **182 项通过**，日志 `logs/annotation-folder-regression-tests.log`。
- 新增来源元数据写入失败用例后，文件夹专项最终 **6 项通过**，日志 `logs/annotation-folder-final-tests.log`。包含引用/复制真实导入、源目录无新增元数据、原件/副本导出、移动、外部图片链接拒绝、同大小内容变化拒绝、重新导入后的 UUID/标签/旧引用定位及元数据失败保留漫画。
- 关闭 POC 的原导入服务/目录复制/存储协调 **44 项通过**，日志 `logs/folder-import-default-regression-tests.log`；静态分析 No issues found，结构/架构、格式和 Git 空白检查通过。

目录来源的 SQLite 备份包含已记录的文档指纹和已批注页 locator；安装内旁车清单不是图片备份，跨设备恢复仍需导入相同图片及相对路径，由新导入重建清单后关联。已经存在、没有页字节指纹的旧批注本轮不自动升级为原图来源，也未实现跨版本手工逐页映射。macOS 原生构建/文件权限/窗口/性能验收仍受完整 Xcode 缺失阻塞，完整初版目标保持未完成。


## ZIP 中央目录身份与功能开关 CI（2026-10-29）

对照方案 §3.1、P3 补齐 ZIP/CBZ 原始条目身份：新导入在后台 worker 中读取一次原文件中央目录，保留原始顺序和同规范化路径的所有 occurrence，不使用会按名称折叠重复条目的 Archive map 作为身份清单。对实际导入的每个图片资源重新读取条目原字节，使用大小和 SHA-256 与提取结果比较，之后原有 copy receipt 再验证目标副本与提取结果一致。普通条目同样校验字节，不能仅凭解压后的名字认定来源。

页 locator 新增 `archiveEntryIndex`（原始目录 0 基顺序）、`archiveEntryOccurrence`（同规范化路径 0 基顺序）、`archiveEntryCount`、原始 `archiveEntryName` 和解析方式。ZIP 与 7Z 都先按实际提取字节找候选；若多个候选字节完全相同，则确定性选择第一个，并保留全部等价 `matchingEntryIndices`。这些原始名称仅作为数据，不用于输出路径拼接。验证解压输出不得超过已提取页的确切长度，单页校验上限 256 MiB；不匹配或异常时不登记不可靠来源，不发布导入结果，暂存清理。未修改原解压器的候选次序、旧 ZIP 路径校验或发布配置。旧 path-only receipt 仍可读取；7Z 原生动态库尚未在本机 Release 验收。

现有 `.github/workflows/analyze.yml` 默认 Flutter 测试之后增加启用 `COMICNOTES_POC=true` 和 `COMICNOTES_WORKSPACE=true` 的串行批注/Reader 工作台/书库专项。继续使用原 Linux 原生测试库准备步骤；不覆盖默认回归和覆盖率结果，也不修改发布开关。Linux 上的 Mac 特定用例仍按已有平台条件跳过，不能据此替代原生 Mac 验收。工作流修改尚未推送、未在远端执行，不声称 CI 已绿。

验证：ZIP 来源专项 **10 项通过**，包含普通条目顺序、自然排序重命名、重复同名、规范路径别名、相同字节多候选、原文件删除后导出携带来源、异常解压长度回滚、旧清单及无效 occurrence 校验；完整批注 + CBZ 兼容/生命周期 **166 项通过**；关闭批注的 CBZ 兼容/生命周期 **22 项通过**。新增 CI 测试集合在本机（相同 flags，加 `--no-pub`）**151 项通过、1 项相反开关配置跳过**。静态分析 No issues found；Ruby 标准 YAML 解析和功能开关断言通过（本机 Python 没有 PyYAML，未增加依赖）。日志：`logs/annotation-zip-entry-tests.log`、`logs/annotation-zip-source-regression-tests.log`、`logs/cbz-default-regression-tests.log`、`logs/comicnotes-ci-command-local-tests.log`。

当前需求核对见 [初版需求验收表](comicnotes-mvp-audit.zh.md)。本轮再次确认基线提交仍为 `087147a7810039398f4eed3bcc794b576f92c46b`，工作分支为 `feat/annotation-poc`；Xcode 仍选中 CommandLineTools，`xcrun --find xcodebuild` 失败，未发现可用 cargo/pod。原生运行、系统协议/文件权限与真机性能仍不能证明完成。


## Mac 快捷键与编辑焦点（2026-10-29）

对照方案 §5/P4 补齐当前范围的快捷键：

| 作用范围 | 操作 | 行为 |
| --- | --- | --- |
| Mac 工作台书库 | Cmd/Ctrl+O | 打开原有导入窗口；重复请求不叠加窗口，取消保留原搜索/筛选 |
| 本地书库根页 | Cmd/Ctrl+F | 打开/聚焦既有搜索输入，与标签筛选继续相交；多选期间不隐式切换为搜索 |
| 启用批注的本地 Reader | Cmd/Ctrl+F | 打开批注 Inspector 并聚焦搜索；支持窄窗侧栏及并排 Inspector；已打开面板内部同组合键重新聚焦 |
| 已加载、未图片处理的单页画廊 | Cmd/Ctrl+Shift+N | 向当前活跃图层请求框选，预加载邻页不能响应；输入期间不触发新框选 |
| 批注编辑器 | Enter / Cmd+Enter / Ctrl+Enter | 保存；Shift+Enter 留给多行文本，Alt+Enter不拦截；组词范围未结束时交回文本/输入法系统，不提交笔记 |
| 由键盘开始的框选 | Esc / 编辑器返回 | 恢复此前阅读焦点；页面/会话退休后不重新抢焦点 |

库页与 Inspector 使用局部 FocusNode 和 Shortcuts，关闭开关的原导航树不添加工作台快捷键。Reader 拿到键盘命令后仍检查本地类型、有效会话和输入占用；请求下一帧打开查找面板时重新核对会话、请求序号和输入状态。选择请求通过 UI Listenable 传递，只有活跃、已解码且仍有效的图层响应；监听器随更换/释放解绑，不进入纯业务 domain。原 Cmd/Ctrl+S 导出路径保持。

列表文字区域已有双击定位实现，本轮补了真实双击只定位一次、保持稳定 annotation ID 的组件用例。整册 30 条保存/编辑的数据库用例与原图定位用例继续存在；没有把它们当作原生键盘、输入法或真机性能验收。

验证与边界：完整批注 + 全部 Reader + 书库串行回归 **1060 项通过、31 项平台/配置跳过**，日志 `logs/annotation-keyboard-full-regression-tests.log`。在这轮编译之后细化的 IME Enter 透传及框选焦点恢复，最终通过编辑/重试/双击/退休相关 **19 项定向复验**，以及真实 Reader 窄窗/并排栏「快捷键框选 → Enter 持久保存 → 恢复阅读焦点 → 查找输入不翻页」**2 项复验**。书库实际数据库组件中的快捷键查找、重复打开导入、取消后筛选保留也已通过（同配置 1 项通过、1 项相反开关跳过）。关闭开关的原启动页/导航/画廊连续性 **18 项通过、1 项配置跳过**。最终静态分析 No issues found、结构/架构、格式和 Git 空白检查通过。

日志：`logs/annotation-keyboard-final-tests.log`、`logs/reader-annotation-keyboard-final-tests.log`、`logs/mac-library-keyboard-tests.log`、`logs/keyboard-default-fallback-tests.log`。实际中文输入法候选面板、系统级快捷键、键盘布局/原生窗口与 trackpad 仍需 Mac App 验收；组件中的 composing range 验证不等同于真实输入法验收。当前未把 Cmd+O 扩展为 Reader/所有发现页的全局打开命令，也未实现连续/多图批注、无指纹旧记录手工映射或 iPad Pencil 交互。完整初版目标保持进行中。


## 连续原图批注接入（2026-10-29）

纵向连续、左至右、右至左和跨章瀑布模式复用 `ReaderAnnotationLayer` 与领域变换。连续图层从实际 `ComicImageState` 的原始解码尺寸、图片绘制区域以及 RenderBox 到视口的矩阵构造变换；由真实列表视口裁切覆盖层，框线和工具保持逻辑像素尺寸。缩放、平移、侧边距、窗口尺寸变化由布局重新投影，不把连续流整体当作一张图片，也不按显示索引分配新页 UUID。

当前页提供框选、整页笔记、书签及编辑入口；其他已挂载可见页绘制已有标注。显示开关对整个连续画布生效。选择/编辑期间阻止底层画布接收拖拽，防止选区同时滚动图片；结束后使用原控制器继续阅读。当前页按原有可见面积规则选出，缩放可能改变它；已有笔记继续绑定原页。跨章使用图片 provider 的真实章节 ID 和相对来源路径。迟到编辑提交前仍检查会话、当前图和页身份。

四种布局的实际 Reader 测试验证归一化坐标、源尺寸、缩放后的原图投影小于 1 逻辑像素、窗口变化后坐标和控制器保留、选择时滚动不移动、隐藏所有页标注，以及跨页迟到编辑不提交。另有瀑布跨章用例验证两个章节相同图片序号的 page UUID 独立。定向日志：`logs/continuous-annotation-integration-tests.log`（4 项通过）、`logs/waterfall-annotation-chapter-tests.log`（1 项通过）。这不是原生 App 验收；双页画廊、宽图拆分、实际系统输入和真机性能仍待实现/验证。

本轮完整批注 + 全部 Reader + Mac 书库串行回归 **1065 项通过、31 项平台/配置跳过**（`logs/continuous-annotation-full-regression-tests.log`）。随后把四种连续布局的首次框选改为实际 Cmd+Shift+N 后，4 项再次通过（`logs/continuous-annotation-keyboard-tests.log`）；工具栏入口由同用例的第二次框选覆盖。最终静态分析 No issues found，结构/架构检查和格式检查通过。

关闭开关的连续流所有权、连续输入和画廊连续性回归 **23 项通过**（`logs/continuous-annotation-default-fallback-tests.log`）。没有运行外部 Chrome，也没有将组件回归当作 macOS App 构建成功证据。


## 多图画廊批注接入（2026-10-29）

画廊的左至右、右至左与纵向布局现在按每张原图绘制批注。双页/多图页面上方的「批注原图 N」用于明确选择框选、整页笔记和书签的目标；窄窗口可以横向滚动此选择条。未选中的原图继续显示已有标注。工具栏和选择条位于共享 PhotoView 外部，缩放/旋转不改变其按钮尺寸。

每张原图使用实际 `ComicImageState` 的自然尺寸和绘制区域，合成它到画廊视口的矩阵。原图编号由页面的源图片区间取得，RTL 只改变排布，页身份与来源路径不变。几张图片仍共用原有 PhotoView 与 PageController；最后一页只剩单图时复用单图适配器，正确绑定剩下的源图片编号。批注隐藏作用于当前多图页面的全部原图。

测试揭示仅吸收 PhotoView 指针不足以隔离外层 PageView 的横向拖动识别器，因此批注输入期间还禁用画廊翻页 physics，结束后恢复原滚动配置；这也改善原有单图框选的横向拖动。保存/取消仍经由同一会话和迟到结果校验，不按显示页号提交原图笔记。

六项实际 Reader 用例覆盖双页/三图 × 左至右/右至左/纵向：逐图框选与独立 page UUID、Cmd+Shift+N、选区拖动时显示页不移动、窗口变化后保留控制器、缩放/平移/旋转后投影小于 1 逻辑像素、统一隐藏，以及双页设置下最后的单图页持久保存。这些是组件集成验证，不是 macOS App 已启动的证明。宽图拆分仍未接入；原生运行及性能门禁保持未通过。

完整回归中的原有重复图片导出用例曾暴露停用 Element 的布局读取问题：Flutter 的 State.mounted 在 deactivate 后到最终 dispose 前仍为 true。现在 `ComicImageState` 单独记录布局活跃状态，画廊及连续图层只访问仍活跃的图片；同时核对图片 provider 与当前来源路径，列表替换期间不使用旧来源的布局。首轮失败保留于 `logs/spread-annotation-full-regression-tests.log`，最终复验另记日志，不覆盖失败证据。

最终验证：修复布局停用问题后的完整批注 + 全部 Reader + Mac 书库回归 **1072 项通过、31 项平台/配置跳过**（`logs/spread-annotation-full-regression-final-tests.log`）。之后增加的来源路径核对，以及采用不同长宽比的双页夹具，连同窄窗第三张原图保存、原有重复图导出和替换漫画/来源/章节用例，**11 项最终定向复验通过**（`logs/spread-annotation-final-tests.log`）。最终 analyze 为 No issues found，结构/架构、格式、Git 空白检查通过。

关闭开关的画廊输入、旋转、画面连续性、图片重试、连续流所有权/输入 **41 项通过**（`logs/spread-annotation-default-fallback-tests.log`）。原生 macOS App 构建、系统权限/协议分发、性能和宽图拆分仍未验收，不将此轮回归视为完整初版已完成。


## 宽图拆分与反转批注（2026-10-29）

纵向连续与跨章瀑布的宽图现在可在两个显示切片上框选。`ComicImageState.imagePaintSlices` 给出每片的完整原图归一化来源矩形与本地实际绘制矩形；使用与原有绘制器相同的切片顺序，默认右半先读，反转后左半先读。一个切片的局部绘制变换先补回原图偏移/比例，再与图片到阅读视口的矩阵组合。

一个 `ReaderAnnotationLayer` 接受主投影和附加投影，在每片的真实可见范围内分别绘制/接收框选。两片共享同一 anchor、页 UUID、原图尺寸、编辑器和工具栏；矩形始终存为完整原图中的归一化坐标，不创建“上半页/下半页”的额外来源身份。整页笔记/书签仍针对完整原图，选择某个切片不会把它变成独立图片。跨切片显示的已有矩形会按各切片裁切；未拆分的图片继续使用一个投影。

实际 Reader 用例覆盖纵向/瀑布 × 正常/反转共 4 项。使用 300×100 的左右红/蓝宽图，分别在原图左右区域保存笔记，验证自然尺寸、完整原图坐标和共享 page UUID。组件真实渲染的像素采样验证投影命中对应红/蓝区域；改变窗口尺寸并缩放/平移后，与实际绘制矩形的投影误差小于 1 逻辑像素，保留原 PhotoViewController。定向日志 `logs/split-annotation-integration-tests.log`：4 项通过。这些是组件渲染和交互测试，原生 macOS 运行及系统权限/协议、真机性能仍未验收。

本轮完整批注 + 全部 Reader + Mac 书库串行回归 **1076 项通过、31 项平台/配置跳过**（`logs/split-annotation-full-regression-tests.log`）。随后加入的「拖拽中反转切片」在两个模式、两种初始顺序中均取消旧拖拽，不打开编辑器、不新增错误笔记；原有笔记在新顺序下继续正确投影。四项最终复验通过（`logs/split-annotation-final-tests.log`）。最终 analyze 为 No issues found，结构/架构、格式及 Git 空白检查通过。

关闭功能开关的原有宽图拆分、尺寸、画廊输入/旋转/连续性、图片重试及连续流所有权/输入回归 **51 项通过**（`logs/split-annotation-default-fallback-tests.log`）。初版目标仍在进行：无指纹旧记录的明确手工恢复、边框 hover/上下文菜单、全局打开命令以及 macOS 原生运行/系统权限/协议/性能门禁尚未全部完成。


## 缩小解码与原图尺寸分离（2026-10-29）

大图开启缩小解码时，单图画廊曾将 PhotoView 使用的解码宽高同时用于持久页尺寸。真实 2000×3000 PNG 的回归用例证实它会写为解码宽度 1568（失败证据 `logs/annotation-original-size-before-tests.log`）。这会把展示优化混入来源元数据，并可能令同原图在另一解码设置下触发尺寸冲突。

`ReaderAnnotationLayer` 现在分别记录 `decodedOriginalSize` 提供的自然宽高与本次解码像素宽高。自然宽高用于 anchor/SQLite；PhotoView 的默认适配、缩放、旋转和平移变换继续使用解码宽高。连续、多图及拆分的外部布局投影仍使用各自实际绘制矩阵。原有数据库“来源尺寸变化需重新关联”的约束保持，不根据缩略尺寸静默改写旧来源身份；此前开发版本若已写入错误尺寸，仍需明确的重新关联流程。

新增实际大图用例使用同一 `ReaderDisplayImageProvider` 共享加载，确认实际 RawImage 小于原图、anchor 保存 2000×3000、缩放/旋转/平移的投影与真实 RawImage 几何误差小于 1 逻辑像素；通过真实框选编辑器保存 SQLite，再从原始 PNG 导出，验证裁剪像素边界及两个精确像素标记。定向日志 `logs/annotation-original-size-tests.log` 已通过初次完整路径验证。最终用例进一步切换到全尺寸解码，确认实际 RawImage 恢复 2000 宽、页 UUID 与已保存笔记不变，变换仍与实际画面一致。

本轮完整批注 + 全部 Reader + Mac 书库回归 **1077 项通过、31 项平台/配置跳过**（`logs/annotation-original-size-full-regression-tests.log`）。最终加入解码设置切换复验后，整个尺寸测试文件在默认编译配置下 **6 项通过**（`logs/annotation-original-size-final-tests.log`），包含真实框选/SQLite/原图裁剪、尺寸观察、切片与重试路径。

尺寸分离修复的最终 analyze 为 No issues found；结构/架构、格式和 Git 空白检查通过。完整初版仍未完成，剩余项目继续以需求验收表为准。


## 批注悬停反馈（2026-10-29）

共用 `AnnotationOverlay` 增加鼠标悬停强调：通过当前逆矩阵把鼠标位置换算为原图内容点，选择实际绘制顺序中最上层的区域批注，将框线从 1.5 加重为 3 逻辑像素。已选中的蓝色框保持优先；隐藏标注和框选模式不产生悬停强调。鼠标位置留在同一处但图片位姿改变时，重新计算命中；换页或进入框选清除旧悬停位置。

阅读模式的外层 MouseRegion 使用透明命中，内部手势仍 IgnorePointer；因此底层阅读的鼠标 hover、点击和拖动继续收到事件。进入框选才使用不透明命中和现有选区手势。覆盖层仍只接收页身份、批注、变换和回调，没有查询数据库或全局 Reader。

真实组件像素比较覆盖重叠矩形只突出最上层、移出恢复原图、隐藏不响应、位移后不残留旧高亮，以及缩放/旋转/平移后的逆变换命中；同时验证底层收到 hover、点击和拖动。`logs/annotation-hover-widget-tests.log`：5 项覆盖层测试通过。批注编辑/删除等完整右键菜单尚未接入；本轮不将悬停加重等同于原生 Mac 菜单或触控板验收。

本轮完整批注 + 全部 Reader + Mac 书库回归 **1078 项通过、31 项平台/配置跳过**（`logs/annotation-hover-full-regression-tests.log`）。最终 analyze 为 No issues found；结构/架构、格式及 Git 空白检查通过。完整初版仍在推进，批注上下文菜单、旧记录明确恢复和原生门禁等缺项继续列于验收表。


## 批注右键菜单（2026-10-29）

右键已有区域批注提供「编辑批注」「复制批注文字」「复制批注引用」「删除批注」。临时内存会话不提供可持久解析的引用。逆矩阵命中最上层可见区域，复用同一覆盖层回调；空白处或隐藏标注时保留原有图片菜单。菜单不拦截普通左键阅读拖动。

操作绑定打开时的会话、页身份、笔记对象版本与可见图片目标；同一笔记被外部编辑、换页或组件退休会撤销旧菜单。多图画廊未选中的原图也可直接右键自己的区域；连续/瀑布可见邻页通过有单一 UI owner 的控制器调用同一编辑器，并携带邻页身份校验，编辑不借用当前页 anchor。

复用 `MenuRouteController`，新增可选的单次 `onClosed` 回调，使选择、外部关闭、退休/释放都能归还批注输入占用。菜单及异步操作/错误窗口期间保持输入占用；删除仍先写入 SQLite 再修改内存，失败显示错误且保留笔记。编辑继续使用现有失败草稿/重试逻辑。

定向集成 `logs/annotation-context-integration-tests.log`：6 项通过，覆盖单图、多图未选中原图、纵向/瀑布可见邻页的编辑/文字与 UUID 引用复制/删除，以及换页、笔记版本变化撤销菜单；SQL trigger 模拟删除失败，验证笔记保留、错误窗口输入占用和重试成功。`logs/annotation-context-menu-lifecycle-tests.log`：22 项菜单测试通过，包含新增三种关闭路径恰好调用一次及原有菜单键盘/退休/布局测试。真实系统菜单、原生焦点和触控板仍需 Mac App 验收，不能由组件测试推导原生门禁已过。

右键菜单初轮完整回归中的空白菜单断言曾落在双页的原图选择条上，已将测试点改到明确画面空白处；失败证据保留在 `logs/annotation-context-full-regression-tests.log`，不将该日志当作全部通过。菜单回归与最终定向结果分别记录。

最终证据：完整批注 + 全部 Reader + 菜单 + Mac 书库首轮 **1105 项通过、31 项平台/配置跳过、1 项失败**，唯一失败是上述双页空白测试点碰到选择条（`logs/annotation-context-full-regression-tests.log`）。调整测试点后，启用批注和工作台两个开关的全部 **6 项右键集成最终复验通过**（`logs/annotation-context-final-tests.log`），含点击外部关闭释放输入、原图片菜单回退、邻页编辑/复制/删除、失败重试及过期撤销；没有把首轮日志改写成全部通过。独立默认配置下菜单生命周期 **22 项通过**。最终 analyze 为 No issues found；结构/架构、格式和 Git 空白检查通过。


## 根级打开文件命令（2026-10-29）

启用两个 ComicNotes 开关的 Mac 工作台在根 Navigator 上方安装 `ImportCommands`，Cmd/Ctrl+O 因此也作用于推入的 Reader/发现页面，而非仅留在书库页。根路由观察器只允许当前最上层为 PageRoute 时打开；编辑弹窗、菜单和其他 PopupRoute 保留原输入焦点，不叠加导入。命令同时检查宿主退出状态、NavigationAdmission 和本次应用认证状态；启用应用锁但尚未认证时禁止打开。关闭开关的启动/阅读树不安装这组命令。

调用仍使用既有 `showLocalComicImportDialog`，不另建导入器。共享入口按根 Navigator 保存正在打开的 Future，快捷键、工具栏或其他调用同时到达时返回同一次窗口的完成结果；窗口结束后解除登记，新的用户请求可以再次打开。命令本身也防止异步打开尚未创建 PopupRoute 前重复执行。不会自动选择文件或开始导入。

`logs/global-import-commands-tests.log`：根命令两项测试通过，覆盖新页面、文本焦点、编辑弹窗、导航禁止、重复命令和未创建路由的异步等待。实际书库组件连同命令测试 **3 项通过、1 项相反配置跳过**（`logs/global-import-integration-tests.log`），验证新推入页面打开真实导入窗口、直接重复入口共享窗口、取消后搜索/筛选保留。真实 Reader 测试 **1 项通过**（`logs/global-import-reader-tests.log`），确认打开/取消仍保留原 Reader、PhotoView 所属视口和页码，批注编辑期间 Cmd+O 不覆盖草稿。测试仍非原生 Mac App 验收。

本轮完整批注 + 全部 Reader + 菜单 + 根命令 + Mac 书库回归 **1109 项通过、31 项平台/配置跳过**（`logs/global-import-full-regression-tests.log`），也重新覆盖上一轮空白处右键菜单修正。默认编译配置的根命令组件、旧书库导航及启动错误页 **6 项通过、1 项相反开关跳过**（`logs/global-import-default-fallback-tests.log`）。认证门禁的代码在最终静态分析中复核，真实认证窗口和系统 Cmd+O 仍需原生验收。最终 analyze 为 No issues found；结构/架构、格式、Git 空白检查通过，CI YAML 已解析且加入根命令组件测试；未运行远端 CI。完整初版继续进行，旧无指纹记录的明确手工恢复及原生运行/系统协议/权限/性能门禁等尚未全部完成。


## 手工页映射的事务基础（2026-10-29，尚未开放 UI）

为旧无指纹/不同布局来源新增独立 `prepareManualRecovery` / `applyManualRecovery` 存储路径，不放宽原有同指纹自动恢复。准备阶段捕获旧文档与目标文档的文档、全部来源页、笔记（含墓碑）、标签和导出记录快照；提交阶段在 immediate 事务内逐项重新校验。预览后笔记/标签/来源/导出或目标变化均拒绝；目标有任何笔记或墓碑也拒绝。

提交接收每个旧 page UUID 对应的目标 page UUID，必须覆盖全部旧页且一对一，不允许遗漏、合并或引用预览之外的目标。当前只接受自然宽高一致且有缓存 URI 的目标，不隐式缩放旧坐标。先临时退休旧来源唯一键，再更新来源路径/章节/图片编号，支持明确交换页顺序，整个过程失败回滚。文档、页、笔记 UUID、归一化坐标、文字、标签、墓碑、旧导出记录保持；当前来源证据取自目标，原来源信息保留于 `manualMapping` 审计，目标无指纹时保持 unlinked，绝不声称内容相同。提交从事务内数据库读取目标映射，不使用调用者可能保留/修改的预览 locator。

这只是准备 UI 所需的存储能力。**尚未接入手工逐页比较/确认界面、运行时文件验证和旧书库绑定存活检查，因此目前用户不能从界面执行手工恢复；不同自然尺寸的坐标重审也未实现。**恢复前后的存活库检查仍必须由运行时服务完成，不把裸 repository 事务当作已具备来源验证的用户操作。

启用两个开关的全部批注回归在初版事务上 **166 项通过**（`logs/annotation-manual-recovery-full-tests.log`）。随后补旧来源审计及后续同指纹恢复兼容，手工事务 + 实际 CBZ 恢复最终专项 **24 项通过**（`logs/annotation-manual-recovery-final-tests.log`）：遗漏/重复/未知目标、尺寸差异、目标笔记/墓碑、预览后旧笔记/标签/导出/来源变化、SQL 失败回滚、页交换、引用身份与审计保留。原有 ZIP 原生插件在此环境缺失，CBZ 用例使用既有 Dart ZIP 后备，没有将它称为原生插件通过。

最终代码的完整批注回归 **168 项通过**（`logs/annotation-manual-recovery-final-full-tests.log`），覆盖新增来源审计、页交换与实际同指纹 CBZ 后续恢复。最终 analyze 为 No issues found，结构/架构、格式及 Git 空白检查通过。手工恢复 UI 与运行时验证未接入的边界保持如上。


## 手工恢复运行时预览与校验（2026-10-29，UI 待接入）

新增纯应用接口 `AnnotationManualRecoveryPreview` 与运行时 `prepareManualAnnotationRecovery`。候选只来自失去存活书库绑定的旧文档；目标必须是当前本地导入且没有任何笔记/墓碑。预览按实际章节和 Reader 图片列表读取目标图，校验真实路径在漫画目录内、链接不越界、文件为有限大小的普通文件；解码前检查四千万像素/单帧限制，使用 EXIF 自然方向生成 192 像素缩略图。每张图片的字节读取以 stat 长度加一限定，避免读取期间文件增长造成无界分配。解码 isolate 只捕获原始路径参数，不携带 LocalManager/SQLite/取消回调。

已有导入凭据的目标页还必须匹配凭据中的哈希与字节数；预览包含目标页自然尺寸、缩略图、旧页身份和笔记供后续 UI 逐页比较。目标总页数不足或没有匹配自然尺寸时提前拒绝。预览准备可以登记空白目标的来源页元数据，但不改旧文档、旧笔记或书库绑定。尚未通过用户逐页确认，不调用提交。

提交前重新核对同一 LocalManager、旧绑定仍失联、目标绑定/根目录仍一致和完整页列表不变；逐张重新读取所选目标验证指纹/自然尺寸，然后才调用上一节的快照事务。取消、组件退休或 dispose 使提交返回 false；dispose 等待在途校验结束并释放连接。旧会话不能自动变成新会话，UI 成功后仍需使用既有 Reader 重开/刷新流程。

真实 CBZ/旧无指纹数据用例验证恢复后原文档/页/批注 UUID 与旧 comicnotes 引用保持；预览后修改字节、链接越界、页列表变化、旧文档重新绑定、新/旧笔记变化、取消、释放均不移动旧绑定。另测目标缺失、损坏、来源凭据不符和解码后取消可重新预览。初轮运行时暴露 Dart isolate 闭包捕获 LocalManager 的问题，已通过独立的原始参数 helper 修复。当前 CBZ 仍采用此环境可用的既有 Dart ZIP 后备，非原生插件验收。

完整批注回归 **183 项通过**（`logs/annotation-manual-preview-full-tests.log`）；随后补在途 dispose 排空，运行时最终 **16 项通过**（`logs/annotation-manual-preview-final-tests.log`）。最终 analyze 为 No issues found，结构/架构、格式、Git 空白检查通过。**运行时能力尚未注入 AnnotationServicesScope，逐页比较/确认 UI 尚未实现，因此目前没有手工恢复按钮；不同自然尺寸的坐标重审与原生 App 门禁仍未完成。**


## 手工逐页恢复 UI 接入与待复验状态（2026-10-29）

`AnnotationServicesScope` 和真实应用运行时已注入手工恢复候选/预览服务。空白批注面板增加「手工逐页关联旧批注」：先选择失去书库绑定的旧文档，再进入可取消的目标页校验。逐页面板展示旧来源路径、自然尺寸、笔记文字，将旧归一化选区叠加于目标缩略图；目标仅列同尺寸且尚未被其他旧页使用的图片。无按页号自动匹配，支持清除重选；必须完整映射所有旧页并勾选逐页核对确认，才能提交。缩略图是位置比较辅助，旧原图没有自动验证，界面要求对照原件/原导出，不声称两个版本内容相同。

弹窗拥有预览准备 Future，取消后等待准备返回并 dispose；提交失败保留映射，重试时重新验证来源与事务快照。成功后 Reader 重开旧文档 UUID 所属会话、更新视口绑定，原批注 ID/页 ID 与引用继续生效。不同自然尺寸的坐标重审仍未实现。

最新窄窗排版变更**之前**已通过：

- `logs/annotation-manual-dialog-tests.log` 中 5 项组件测试：逐页唯一选择/确认、原矩形预览、清除重选、写失败保留重试、准备/提交取消、准备错误展示与释放。
- `logs/annotation-manual-reader-tests.log` 中 1 项真实 Reader/SQLite/原图片集成：从 Inspector 选无指纹旧文档，明确关联到第二张图片，保存后原文档/页/批注 UUID 与标签保持，原 comicnotes 引用重新定位到第二张图。该集成测试使用真实异步解码和文件定位，需显式等待图片就绪并以 tester.runAsync 等待原件定位。

之后将提示、选择、预览和确认勾选移入可滚动内容区，并新增 320×667、2 倍文字缩放的操作测试。执行此轮测试时自动审批服务拒绝运行：服务报告用量上限，提示恢复时间 **2026-10-30 01:31（服务原文未标注时区）**。该命令没有启动，因此原 5 项日志**不覆盖这次排版**。没有复制 SDK、切换执行路径或用其他运行器绕过审批。

在不依赖 Flutter 执行的静态审查中，还发现退出取消的遗漏：Reader 的 ImageWork 取消任务时，等待用户确认的模态路由也必须结束，才能排空任务。源码现通过 cancelSignal 关闭仅属于该操作的 DialogRoute，再等待准备/提交排空；新增 owner cancellation 组件测试。此取消连接及新增测试同样**尚未运行**。最后安全完成的格式、结构/架构检查与 git diff --check 已通过；尚未执行最终 flutter analyze、窄窗测试、取消测试和完整回归。应用原生 Xcode 门禁仍另行未通过。

待审批服务恢复后先执行手工恢复 Dialog 全部测试（含窄窗、owner cancellation），再复验真实 Reader 手工恢复/退出收尾和最终 analyze，失败修复完成后再运行完整批注、Reader、菜单与书库回归。不得把之前 1109 项整体验证用于证明这一轮新 UI 已完成。

静态审查同时收紧准备失效时的关闭目标：不使用通用 Navigator.pop 弹出可能后来覆盖的无关窗口，而是移除明确拥有的预览 DialogRoute；新增覆盖无关弹窗时的失效准备测试，待审批恢复后运行。


## 当前阻塞复核（2026-10-29）

审批服务用量限制在连续目标推进中仍未解除；本轮 UTC 时间为 2026-10-29 13:38，仍早于错误提示的 2026-10-30 01:31。没有可继续等待的 Flutter 进程：最新测试请求被审批服务拒绝，未启动。保留目标完整范围，不把已有组件测试视为全部初版完成，也不通过其他执行路径绕过审批。

原生构建前提重新检查：`xcode-select -p` 为 `/Library/Developer/CommandLineTools`，`xcrun --find xcodebuild` 退出 72，PATH 中没有 cargo 或 pod。故真实 macOS App、系统 scheme/权限和性能门禁仍不能完成。本轮可执行的结构/架构检查已再次通过。

当前停止继续叠加未测试实现，目标应标为 blocked；解除条件是审批服务可再次审核运行测试，并为原生验收提供完整项目工具链。恢复时优先验证最新 `manual_recovery_dialog_test.dart` 的窄窗、大文字、owner cancellation 及无关弹窗保护，再验证真实 Reader 手工恢复和退出排空，最后运行 analyze 与完整回归。先前 5 项 Dialog、1 项 Reader 及 1109 项整体验证的证据范围仍按上节，不覆盖后续新改动。


## 手工恢复最新 UI 复验完成（2026-10-29，审批已恢复）

目标恢复后按原审批路径提交 Flutter 测试成功启动，执行额度阻塞已解除；没有绕过审批或换用其他运行器。前两节的“待复验/blocked”是当时的历史状态，不是本节之后的当前测试结论。

- 最新 `logs/annotation-manual-dialog-tests.log` **8 项通过**，覆盖明确唯一映射/勾选确认、清除重选和写失败重试、准备/提交取消、320×667 两倍文字滚动操作、owner cancellation 关闭自有路由、准备失效时保留无关弹窗、错误展示及资源释放。
- `logs/annotation-manual-reader-final-tests.log` **2 项真实 Reader 集成通过**：成功恢复时保持旧文档/页/批注 UUID、标签与旧引用，明确关联第二张原图并定位；调用真实 ImageWork.prepareForExit 时取消并关闭待确认路由，排空预览资源，不移动旧绑定、不丢笔记，释放输入占用。
- `logs/annotation-manual-ui-full-regression-tests.log` **1152 项通过、31 项平台/配置跳过**，命令含全部 annotations、全部 Reader、菜单、根命令、Mac 书库。旧日志与旧测试结果不替代此轮结果。
- 默认编译回退和界面组件 `logs/annotation-manual-ui-default-fallback-tests.log` **17 项通过、1 项相反配置跳过**；最终 analyze 为 No issues found，结构/架构、格式和 Git 空白检查通过。

CI 的开启两个开关专项现覆盖全部 Reader 和菜单，不再只运行工作台布局文件；YAML 已解析，本机完整同集合已验证，未推送或运行远端 CI。手工恢复同自然尺寸路径现已具备 UI、服务注入、运行时验证和事务保护；不按名称、图片编号或缩略图相似度自动关联。不同自然尺寸的坐标重审仍未实现。原生 macOS 工具链、实际系统协议/权限、原生窗口及性能验收仍是独立缺项，完整初版目标保持进行中。


## 原生工具链恢复与 Xcode 27 兼容性（2026-10-29）

用户安装完整 Xcode 并授权安装其他工具后，已安装持久 Flutter 3.41.4、Rustup、CocoaPods，恢复锁文件依赖。Flutter 官方 ZIP SHA-256 为 `16984a0dae1f13c7b3e05b973913a939144b7e9e3aa6439fa3382599a6326f8c`；Rust 组件同样按官方清单校验。项目 Rust 1.92.0 与 super_native_extensions 旧 Cargokit 额外要求的 stable 1.99.1 均已安装。安装遇到的 TLS 失败通过正常重试和已验证缓存处理，未关闭证书校验；半安装与并行竞争按仓库既有准备/串行化逻辑处理。工具目录已加入用户交互式 zsh PATH。

原生 `swift test --package-path apple` **10 项通过**（日志 `logs/native-directory-access-tests.log`）。这验证原生模块逻辑，不等同于真实文件提供者跨会话权限验收。

首轮 Xcode 27 构建暴露 Pods 的 10.x deployment target 已不被新 SDK 接受（主 App 原来已要求 12.0）。Podfile 在 post_install 将低于 12.0 的依赖及隐私资源 bundle 对齐到已有最低版本，同时保留高于该版本的依赖要求；补充 Flutter 要求的安全窗口恢复声明，并保留 SDK 对 scheme/Git ignore 的迁移。第一轮、兼容修复轮、Rust 安装竞争中断轮及最终串行 Release 轮分别保留独立日志，不将中断视为成功。

原生 QA 构建使用 `build/native-qa/NativeQA.xcconfig` 的独立 bundle identity。生成的两类 CBZ（含 300 页）、两类图片 EPUB 和两份 PDF 样本及其哈希见 `build/native-qa/manifest.json`。实际启动、交互、导出和性能结果待后续记录。

执行合规记录：本轮 Flutter doctor 的浏览器校验器本身只读，但设备枚举随后调用了 Chrome --version，违反用户的禁止调用规则；已向用户说明。后续不再使用通用 doctor/device 枚举，不通过外部 Chrome 做页面/测试或截图。

## 原生 AX 修复与实际闭环（2026-10-30）

构建环境已恢复，Apple Silicon QA Release/Debug 可启动。QA bundle 为 `local.comicnotes.qa.VeneraNext`，使用独立沙箱，不影响已安装的应用资料。当前 Release 产物早于最新修复，不能当作最终交付。

原生 Reader 切路由曾触发 `accessibility_bridge.cc` 孤立 AX 节点并永久冻结原生语义树。框架内存树正常不能证明引擎更新正常。兼容安装脚本 `.github/scripts/prepare_flutter_compat.py` 与相邻 patch 固定 stock/patch SHA，支持幂等 apply/check/restore、中间补丁迁移和失败前源文件保留，7 项安装测试通过。补丁组合了不同非空遍历父锚点合并保护（[PR #190344](https://github.com/flutter/flutter/pull/190344)，未合并）及 [已合并 PR #193372](https://github.com/flutter/flutter/pull/193372) 的框架修复和旧版所需节点登记/命中树过滤。未禁用语义或 Tooltip。

- SDK stock SHA：`33d009f0da337e7accbdc22cbc02bcee6061e4862ec2738b8ae698401f0a96a7`。
- 组合补丁 SHA：`20688689940ad19935cd3ed1ec78f9ea116ff7f73dcf954dd36890ccd50fd70a`。
- 原版两项序列化回归失败：`logs/native-overlay-serialization-stock-tests.log`；补丁后含双锚点共 3 项通过：`logs/native-overlay-serialization-composite-final-tests.log`。
- SDK 核心 199 项与额外 View/Overlay/渲染 65 项通过；应用专项 1155 项通过、31 项配置跳过。`logs/native-composite-final-analyze.log` 无问题。
- 实际原生 30 轮框选、英文输入、保存均完成；独立库有 31 条区域批注。`logs/native-qa-30-cycle-verification.json` 核对文本、UUID、坐标。
- 首次单条原生导出裁图 764×285，与原图对应像素完全一致；第二次 31 条批量导出的 PNG 哈希和像素全部通过，见 `logs/native-qa-export-verification.json`、`logs/native-qa-batch-export-verification.json`。

自动化 AX setValue 显示文本但不更新 Flutter 控制器，paste/修饰键及 Unicode 输入仍需进一步核对；坐标聚焦后的 ASCII 输入已实际保存。不能据此声称中文输入法或 Shift+Enter 已通过。标题栏顶部重叠已修复并有 5 项布局测试；仍需最新构建的原生截图。三格式每类两份原生样本、重启权限、外部 URL、30 条编辑/跳转、300 页 profile 和不同尺寸人工坐标重审仍未完成。

原生重构建复验补充：标题栏修复后的 Debug 已启动，工作台工具栏位于系统拖动栏下方，画布顶部无重叠；重启打开同一本书后，侧栏显示「全书批注 · 31」，并回读最近保存的 cycle 30、29 等测试文字。31 条批量 PNG 均完成哈希和源图逐像素校验。此轮仍未验证中文 IME、多格式全部样本及性能，不提前结项。

三格式原生补充验收：两份 EPUB 均经系统选择器导入、Reader 打开、框选、保存和导出。`QA-Image-Spine` 第 1 页、`QA-Repeated-Spine` 第 3 页（spineIndex 2）均与对应原始资源逐像素一致，重复资源未折叠页锚点；证据 `logs/native-qa-epub-export-verification.json`。两份 PDF 也完成同样流程：`pdf-crop-rotate` 第 2 页旋转 90°，300 dpi 裁图 744×249；`pdf-mixed-boxes` 第 2 页旋转 270°，裁图 407×408。清单记录原始 MediaBox/CropBox/effectiveBox，原件保留开关默认开启；与 Python 独立 PDFium 全页渲染按清单区域裁剪的结果逐像素一致，见 `logs/native-qa-pdf-export-verification.json`。参考渲染使用 `nextafter(300/72, 0)` 避免 Python 浮点乘法导致 1000.0000000001 被 ceil 成 1001，不缩放图像来凑尺寸。

标题栏修复后的定向 Reader/批注/退出集成 203 项通过、23 项配置跳过，见 `logs/native-titlebar-reader-integration-tests.log`。当前原生样本通过数量为 CBZ 1、EPUB 2、PDF 2，尚缺第二份 CBZ、300 页 profile、系统链接及权限跨会话等门禁；中文 IME 与修饰键继续保留待测。

## 长篇 profile 与跨会话目录验收（2026-10-30）

- 第二份 CBZ `QA-300-Pages.cbz` 经系统选择器导入并显示 1/300；实际界面创建并保存 30 条批注，独立库逐条核对，见 `logs/native-qa-long-book-notes.json`。profile 进程中侧栏回读「全书批注 · 30」。批量导出 30 张 PNG 均通过哈希和对应原图像素核对，见 `logs/native-qa-long-book-export-verification.json`。至此 CBZ/EPUB/PDF 各两份样本已有原生导入、阅读、框选和导出证据。
- Apple M5 / arm64 / macOS 26.6 / Flutter 3.41.4，原生窗口约 2940×1714 像素。profile 构建成功（73.0 MB），启用批注与工作台；共 141 次原生滚轮操作，从第 1 页推进到第 300 页，再通过侧栏「定位原图」返回第 1 页及 note 30。
- 前两次 VM Ring 快照发生事件覆盖，只代表保留尾段，不作为全程统计。之后每秒读取时间范围并保留 200 ms 重叠，事件按完整记录去重；106 个分段、最大读取间隔 1.247 秒、单段最多 7214 事件，未达到此前约 32k 的环形容量。第 96→300 页侧栏展开阶段采集 107.43 秒、336019 事件、2292 对 UI/raster 帧。UI：均值 3.23 ms，P90 7.39 ms，P99 9.53 ms，最大 14.47 ms；raster：均值 0.73 ms，P99 1.62 ms，最大 6.56 ms。该段两类帧均未超过 16.67 ms。前一段尾窗曾有一个 21.83 ms raster 帧，未隐去。常驻内存由 242736 KiB 到 243664 KiB（约 237→238 MiB）。
- 原始分段与时间线、条件及统计见 `logs/native-profile-long-book-inspector-live-{chunks,timeline,summary}.json` 与 `logs/native-qa-long-book-profile-report.json`。解析事件名遵循本地 Flutter SDK `flutter_driver/.../timeline_summary.dart` 的 `Frame` / `GPURasterizer::Draw`，兼容同步 B/E 和异步 b/e。采集脚本保留在 `build/native-qa/profile_timeline.py`、`collect_profile_live.py`，未通过 VM 执行任何 UI 行为。帧工作耗时不等于端到端显示延迟；这是本机滚轮场景，不替代真触控板、所有缩放模式和跨硬件性能保证。
- 外部协议测试：后台 IAB 本地测试页能显示正确 `comicnotes://` 链接，但点击被浏览器安全策略拒绝，未交给系统。没有尝试其他浏览器或间接方式绕过。系统协议唤起仍未通过，需允许的外部交互或用户实际点击导出 Markdown 引用来验证；不能以内部 URI 单测替代。
- 外部目录授权：默认 Mac 文件夹导入会复制到沙箱，不能用其重开证明外部权限。已用「重新关联原件」明确关联 `build/native-qa/QA-Scoped-Folder` 外部目录；数据库核对 source URI。原进程完全退出后，新 profile 进程恢复并导出，清单为 `folderImageOriginal` / `001.png`，PNG 与外部原件逐像素相同。见 `logs/native-qa-directory-relocation-before-restart.json`、`logs/native-qa-directory-cross-session-export.json`。
- 重复 profile 构建时 Cargokit 再次访问 Rust 1.92.0 分发校验文件，遇 TLS EOF；不关闭证书检查，跨会话验证使用刚成功构建的同一 profile 二进制，不把该重构建失败描述为成功。默认开关关闭的最新回退专项 11 项通过、1 项配置跳过。

完整目标仍 active。30 条编辑与跨页跳转的完整原生组合、不同自然尺寸复核的 Release 原生窗口确认、最终发行与其他门禁仍有缺项。

## 可试用 Release 候选 rc1（2026-10-30）

最新 arm64 Release 已包含框架 AX 修复、标题栏避让与 Cargokit 编号工具链识别修复；构建 `logs/native-final-arm64-release-build.log` 成功、57.2 MB，analyze 无问题。Cargokit 3 项回归已接入 CI。实际 Release 中完成 30 条批注编辑和定位，文字追加 reviewed，annotationId/pageId/选区均保持不变，见 `logs/native-qa-release-30-edit-verification.json`。

候选包：`build/deliverables/ComicNotes-macOS-arm64-rc1.zip`，约 23.9 MB；伴随 `.sha256`。内含 VeneraNext.app、使用说明及 candidate-manifest。代码签名深层严格校验通过，ZIP 解包后再次签名、架构与可执行文件 SHA 核验通过。`logs/native-qa-release-candidate-package-verification.json` 记录校验结果；ZIP SHA-256 为 `4ef54c1f4adbf7f8e3be013396c285365dae06f84d953941b0c963aec84dc1e0`。仅用于本机 Apple Silicon 试用，独立 QA 沙箱，未公证/公开发布；各项未验收限制写入包内说明，目标不标记 complete。

## Mac 功能与界面优先（2026-10-30）

用户明确调整优先级：先完善 Mac 功能与 UI，兼容性工作暂缓。已通过原生界面查看安装的可达阅读器；用户澄清该版本是平板布局，仅借鉴视觉风格。桌面布局保留侧栏、工具栏、阅读画布与常驻批注面板，参考其中性分层表面、系统蓝、线性图标及克制的控件层次。

当前源码与运行中的 debug App 已采用 Mac 字体层级、紧凑控件及中性配色；书库增加常驻搜索、清除与空结果提示，以及带当前状态的封面/详细分段视图切换。实际 Mac App 已确认两种视图可以切换，搜索与清除回到原有 7 本 QA 漫画。这里的“详细”仍为带文字的卡片网格，不称为列表。窄窗口工具栏标题可截断，避免溢出。

常驻批注列表选中后显示操作，减少每行按钮的视觉干扰。双击定位仅绑定正文，避免父级双击手势延迟编辑/标签按钮。`logs/mac-ui-functional-regression-final.log`：200 项通过、1 项配置跳过；新增 Mac 常驻面板选择后编辑保存回归见 `logs/mac-ui-docked-inspector-tests.log`：7 项通过。`logs/mac-ui-design-final-analyze.log` 静态检查无问题（新增测试前）；`git diff --check` 通过。

以上界面仍在迭代，尚未重新打包 Release；rc1 不包含本节的新 UI。原目标保持 active，未把视觉初改等同于完整交付。

### Cubox 参考与 rc2（2026-10-30）

随后依用户指示查看本机 Cubox，仅参考界面视觉，不复制其收藏内容。侧栏未选中图标改用中性色；Mac 常驻批注面板采用轻量白色/深色分组条目、选中蓝色、分类分段控件、可清除搜索及匹配数量。备份与重新关联移入标题栏更多菜单，降低常用阅读界面里的恢复操作干扰。其他布局继续保留原入口。

`logs/mac-ui-rc2-functional-tests.log`：204 项通过、1 项配置跳过；菜单后续回归 `logs/mac-ui-rc2-menu-tests.log`：7 项通过，涵盖选中编辑、分类/搜索/清除、备份和重新关联回调。最终 `logs/mac-ui-rc2-analyze.log` 无问题。实际 debug App 验证分类零结果、唯一文字搜索、清除恢复及选中操作；实际 Release PID 40756 验证 7 本书库、300 页阅读、30 条批注载入与更多菜单。

已成功构建并提供 `build/deliverables/ComicNotes-macOS-arm64-rc2.zip`（23,932,602 字节），SHA-256 `1cfb10380e6aec04559e388f49899d302f6e4be8ad5250d535e9a4ace83c7dbe`。包内包含本轮新 UI、说明和 manifest。解包后执行文件哈希、arm64 架构和严格深层签名校验通过，证据见 `logs/mac-ui-rc2-package-verification.json`。独立 QA 身份沿用 rc1，未替换 /Applications 中的安装；完整初版验收仍未完成，目标保持 active。

### 紧凑书库列表（rc2 之后的源码）

本地书库第二种视图从多列详细卡片改为真正的一列列表，显示小封面、书名、最多三个标签、添加日期及可用的阅读进度；保留原 ComicTile 的打开、长按选择和右键菜单入口。新增 `compactList` 模式只由 Mac 书库显式选择，其他原有详细/封面模式继续可用。列表使用固定行高并随文字缩放增长，不为整库一次性创建所有行。

`logs/mac-ui-list-functional-tests.log`：书库实际集成、漫画组件、收藏显示 37 项通过、1 项配置跳过；集成测试验证列表书名同列且分行，搜索/清除与视图切换保持可用。`logs/mac-ui-list-analyze.log` 无静态问题。`logs/mac-ui-list-release-build.log` arm64 Release 构建成功，签名深层严格校验通过。

`build/annotation-qa/library-list-light.png` 为实际 MainPage 组件渲染，使用临时书库和合成封面，显式加载本地支持中文的字体，已查看；它不是原生 App 截图。渲染回归 `logs/mac-ui-list-render-test.log` 1 项通过、1 项配置跳过。Mac 锁屏阻止了此次真实窗口列表操作，已请求用户手动解锁，未绕过。现有 rc2 ZIP 不包含这一后续列表变化；Release 输出目录已重新构建，但未宣称其已完成新的原生验收，也未替换 /Applications 中的安装。

### 视图记忆与 rc3

本地书库将封面/列表选择通过 `appdata.updateImplicit` 序列化写入 `implicitData.json` 的 `mac_library_view`，不参与跨设备设置同步；缺失或无效值回到封面。失败时保留当前可用视图并提示未能记住选择，避免未捕获异步错误。⌘F 聚焦搜索并全选已有关键词。`logs/mac-ui-library-preference-tests.log`：35 项通过、1 项配置跳过，集成测试实际检查文件内容，切到收藏页再返回验证列表恢复，并检查搜索选择范围。`logs/mac-ui-library-preference-analyze.log` 静态检查无问题。

`logs/mac-ui-rc3-release-build.log` arm64 Release 构建成功。`build/deliverables/ComicNotes-macOS-arm64-rc3.zip`（23,935,504 字节）包含列表、视图记忆及搜索全选，SHA-256 `a0bbfbe4856864ac894514dae4f32765298559e4643839d2a098ed0228bcc2b0`。解包后的签名、架构和可执行哈希校验通过，见 `logs/mac-ui-rc3-package-verification.json`。本轮再次查询时 Mac 仍锁屏，因此包内说明和 manifest 明确标记新的列表/偏好真实窗口验证待完成；不沿用 rc2 的原生验收来声称 rc3 已经通过，也不标记目标完成。

### 批注列表键盘导航（rc3 之后的源码）

Mac 工作台的常驻批注列表支持点击取得焦点后按 ↑/↓ 选择、Home/End 到首尾、Enter 定位原图；选择不可见条目时自动滚到该条目。按筛选后的列表导航，长按 Enter 的重复事件不重复定位。搜索框与编辑控件保留输入；列表及其按钮取得焦点时通过原 Reader 输入占用回调暂停翻页/自动阅读，面板销毁时释放。沿用项目现有 `scrollable_positioned_list`，未安装新依赖。

实际组件测试含 40 条笔记的跨屏导航、筛选后导航、长按 Enter、搜索 Enter 隔离、输入占用和销毁释放。完整回归 `logs/mac-ui-note-keyboard-regression.log`：202 项通过、1 项配置跳过。随后补足 Mac 样式的 `COMICNOTES_WORKSPACE` 开关条件，启用回归 `logs/mac-ui-note-keyboard-enabled-tests.log` 8 项通过；默认旧界面 `logs/mac-ui-note-keyboard-fallback-tests.log` 7 项通过、1 项配置跳过。结构/架构脚本和空白检查通过，最终静态结果见 `logs/mac-ui-note-keyboard-analyze.log`。

`logs/mac-ui-note-keyboard-release-build.log` arm64 Release 构建成功。原生窗口查询仍显示 Mac 锁屏，尚未重启验证此版本，不把组件键盘事件等同于实际 Mac 键盘验收。rc3 ZIP 保持不变，尚不含这次键盘导航；目标仍 active。

### 解锁后的原生验证与 rc4

用户确认解锁后恢复原生窗口测试。紧凑列表、右键菜单、文字搜索与清除均已实际操作；通过原生菜单完全退出，进程检查确认退出后重新启动，列表选择仍保留。30 条批注列表的 End 滚到末条、Enter 定位及 Up 选择上一条已在 Release 触发。自动输入的 ⌘F 两次未生效，因此修饰快捷键仍保留待确认，不用组件测试替代。

另按方案 §5.1 补齐专注阅读的浮动 Inspector：`showInspector` 在专注模式中不退出专注，也不减小画布。关闭浮动面板仍保持专注；显示工作台可返回停靠布局。原生预览发现额外入口与既有工具条重叠，最终去掉重复按钮，复用原工具条并增加面板顶部间距；最终 Release 已实际从原入口打开、关闭并返回停靠。组件验证画布尺寸、MediaQuery、内容 State 身份及 viewport 变化通知，最终工作台/面板 13 项测试通过，静态检查无问题。

`build/deliverables/ComicNotes-macOS-arm64-rc4.zip` 为当前本机候选，23,937,430 字节，SHA-256 `03a1b830003eef543fb2ad0511c2e5db617a37bad0988eda2cccf5686b9d0ec1`。解包后架构、可执行哈希及严格深层签名校验通过。可提交的摘要为 `doc/development/comicnotes-rc4-validation.json`；本地原始日志与构建目录被忽略。不同自然尺寸重审、外部协议、中文 IME/修饰键/实体触控板等剩余项继续列出，完整目标不标记完成。用户随后要求先更新到 GitHub，本轮接下来进行源码提交与独立 Fork 分支推送。

### 原生快捷键与中文输入人工复验（2026-10-30）

在提交 `cfd4c2a` 的测试 App 中，用户实际按下 `Cmd+F` 后确认书库搜索框取得焦点并完成筛选；自动化输入未能触发该组合键，因此以人工操作结果为准。随后在测试漫画的整页笔记编辑框中使用中文输入法输入「中文输入测试」，按 `Shift+Enter` 换行后输入「第二行」，最后按 `Cmd+Enter` 保存；用户确认选字、换行和保存均正常，内容已持久化。

这两项现在可以从“待确认”移出。随后用户在同一 QA App 中确认系统级 `Cmd+O`、全屏切换、批注列表上下键/Enter 定位，以及触控板滚动与缩放均正常。当前 Mac P4 交互的人工确认项已覆盖；当时外部 `comicnotes://` 系统唤起和最终 Release 交付仍未完成，后续缺陷修复与验收见下文。

### 外部批注链接唤起缺陷（2026-10-30）

用户从 Finder 打开 `build/native-qa/QA-Image-Spine-5ec36b72-4022-4035-9209-a6c9dbace0ac/QA-Image-Spine.md` 并点击「返回漫画批注」后，macOS 成功唤起 QA App，但没有定位批注。只读查询独立 QA 沙箱中的 `annotations.db` 确认链接目标 document UUID 与 annotation UUID 均存在，且对应 `QA-Image-Spine` 第 1 张原图，排除旧链接目标不存在。

根因是 `InteractiveBindings.start()` 仅在 Android 创建 AppLinks URI stream 订阅；macOS Info.plist 虽已声明 `comicnotes` scheme、`app_links` 插件也已接收系统 URL，但 Dart 端没有监听，因此活跃实例事件无人处理。现新增独立 macOS 平台标志，在 macOS 订阅链接流，同时保持 Android 专用文本分享和下载行为不变；新增生命周期测试检查 macOS 会订阅/排空 URI 流且不会启动分享订阅。

修复已通过 `test/app_runtime/interactive_bindings_test.dart`（9 项）、`flutter analyze --no-pub`，以及 app-runtime/routing 回归（235 项通过、37 项平台/配置跳过）。修复版 macOS Debug 已重建并签名校验。2026-10-30 从 Obsidian 打开上述 QA Markdown 并点击 `comicnotes://open?document=cb4cd8d8-1d28-4fd5-87f4-bb94ec2d0d26&annotation=202bd3fd-f669-411f-93ad-24692fb37da8` 后，Debug QA App 实际进入 `QA-Image-Spine` 第 1/3 页，显示目标蓝色选区和 `EPUB image spine native crop` 提示。外部协议 Debug 门禁通过。含修复的 Release rc5 已构建并完成解包签名/哈希核验；因随后 Mac 锁屏，未完成 rc5 进程内的同一链接复测。

## Release 候选 rc5（2026-10-30）

为包含 macOS AppLinks 订阅修复的当前源码重新构建 arm64 Release。构建日志为 `logs/native-app-links-final-release-build.log`；`flutter analyze --no-pub` 无问题，生命周期测试 9 项全部通过。rc5 Release 原生复测中，从 Obsidian 点击外部 `comicnotes://` 后成功进入 `QA-Image-Spine` 第 1/3 页，显示目标蓝色选区和 `EPUB image spine native crop` 提示。候选归档 `build/deliverables/ComicNotes-macOS-arm64-rc5-final.zip` 的 SHA-256 为 `3c169354789ed32cf4f5bc6c1bc489fa774ac1a90f2ec4c54381f8a694ed8e1f`；解包后深层签名、arm64 架构和可执行文件哈希校验通过。不同自然尺寸坐标复核已在后续实现，尚缺其 Release 原生交互复验；rc5 仍是本机候选，不是完整初版结项。

## 不同自然尺寸页面坐标复核（2026-10-30）

手工恢复允许旧页映射到不同自然尺寸的目标页，但提交前必须逐页勾选坐标复核。提交会更新目标页自然宽高，并在来源定位审计中记录旧/新尺寸及 `explicit-normalized-coordinate-review`；映射变更会清除该页复核状态。预览和恢复对话框均按目标页尺寸渲染选区。存储与 Dialog 专项测试通过，完整 `test/features/annotations` 共 196 项通过。

在当前 arm64 Release 中，使用独立 QA 沙箱构造孤立旧批注与空白目标页：将 1000×1500 的 `QA-Image-Spine` 旧页映射到 `QA-Mixed-Pages` 第 2 页 1500×1000 横向页，实际勾选不同尺寸复核和逐页确认后提交成功。数据库核对显示批注仍保留原 UUID 与归一化矩形，目标页自然尺寸已更新，审计含旧/新尺寸及 `explicit-normalized-coordinate-review`。验收后已恢复 QA 沙箱原始数据库。

### Release 候选 rc6（2026-10-30）

基于提交 `40a9ac4` 的 arm64 Release 已构建、深层签名校验、解包校验和可执行文件哈希校验通过。候选包为 `build/deliverables/ComicNotes-macOS-arm64-rc6.zip`，SHA-256 为 `282647b299ed32091e376901ff30ae9534ca4bcbc3fe26cc1cf4d9de77574e0b`。包内 manifest 和说明记录不同尺寸恢复已通过；本轮原生探针仅验证第 30/22 条编辑后跨页定位，完整 30 条组合仍待完成。该包为 ad-hoc 签名，当前机器没有可用 Apple Developer 签名身份，Apple 公证和公开发行仍未完成。
