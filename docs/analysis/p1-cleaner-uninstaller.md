# P1 清理与卸载模块验收

> 对照 [架构设计](../architecture.md)、[模块优先级](module-priority.md)、`../design-system/screens/mmcleaner/` 与 `../design-system/screens/mmuninstaller/`。技术方法参照 `../github-references/{Mole,Pearcleaner}` 和 `../lemon-cleaner/`，实现仍遵循 MacMaster 的删除闸门。

## 扫描到确认

缓存清理页用 `CleanerSelectionPlan` 生成确认与执行的共同清单：只取被选中、允许删除、可访问、未被排除的条目；相同路径只出现一次，已选父目录覆盖子路径。确认页的分类数、项数、体积来自这份清单。任何选中根没有测得体积时，显示“已测 X · N 项未测”，不把未知数加成 0。扫描未结束、清单为空或正在清理时，确认按钮不可提交。

用户文件夹页的安装包若未测得大小，底部与确认文案显示“体积未测得”。清理后只有 `FileTrashService` 确认移走的路径才会改变父目录统计；失败项保留在原列表中。

卸载页“仅卸载应用”的详情与操作栏入口现在都先进入确认面板。两种模式共用同一版式，分别列出应用本体或应用本体加勾选残留的绝对路径，合计包含本体大小；本体或残留未知时合计保持未知。谨慎项仅在用户主动勾选时进入清单，只读项在模型层再次过滤。废纸篓残留的删除根与体积也再次检查可删除风险档；未测大小不显示为 0。

## 设计核对

| 状态 | 原生窗口证据 | 结果 |
| --- | --- | --- |
| 缓存清理确认 | [清理确认图](../verification/mmcleaner/cleaner-confirm-p1.jpg) | 6 类、12 项与分类行之和一致；420pt 面板内无文字重叠 |
| 仅卸载应用 | [仅本体确认图](../verification/mmuninstaller/app-only-confirm.jpg) | 仅一条 `.app` 路径，残留明确保留 |
| 应用加残留 | [完整卸载确认图](../verification/mmuninstaller/with-residuals-confirm.jpg) | 两条路径与 455 + 14 = 469 字节对应；按钮、提示与模式一致 |

这些截图来自只读确认态，没有执行删除。卸载夹具由 `Scripts/uninstall-fixture.sh` 创建在 `/tmp`；`MM_UNINSTALL_CONFIRM_FIXTURE_HOME` 先解析符号链接，只接受物理位置仍在 `/tmp` 的目录，只加载其中假应用，不自动点击按钮。缺少完全磁盘访问时废纸篓横幅仍如实提示权限原因。

## 验证边界

`MMCleaner` 16 项、`MMUninstaller` 75 项测试通过，整 App 已构建。测试覆盖排除项、只读/不可访问项、父子路径去重、未测体积、应用与残留合计。真实用户目录的授权变化和真实删除交互没有通过自动点击验证；权限档需在具备相应授权的机器上复核。
