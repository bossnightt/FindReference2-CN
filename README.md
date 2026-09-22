# Find Reference 2 中文界面补丁

这是 **Find Reference 2 v2.4.3** 编辑器窗口的中文补丁，不含插件源码。本仓库只提供运行时本地化代码、中文词表，以及把补丁打进已安装插件的工具脚本。

## 安装

在仓库根目录执行（将 `<工程>` 换成你的 Unity 工程路径）：

```powershell
.\tools\apply.ps1 -PluginPath "<工程>\Assets\FindReference2"
```

`apply.ps1` 会先把当前 `Assets\FindReference2` 目录打成 zip 备份，再注入本地化文件并改写编辑器脚本。

### 备份位置

备份 zip 写在 Unity **工程目录的上一级**（与工程根目录同级），文件夹名为 `FindReference2-CN-backups`，**不在** `Assets` 里。例如工程在 `D:\MyGame`，备份在 `D:\FindReference2-CN-backups\FindReference2_yyyyMMdd_HHmmss.zip`。

## 开关与重载

安装后在 Unity 菜单：

- **Tools → Find Reference 2 → 中文界面** — 开关中文界面（勾选即启用）
- **Tools → Find Reference 2 → 重新载入中文词表** — 重载词表（紧挨「中文界面」下一项）

## 覆盖范围

启用后会翻译：

- 窗口页签
- 按钮
- 提示（HelpBox 等）
- 设置项
- 类型筛选
- 分组标题
- Group / Sort 下拉选项

鼠标悬停可看到对应英文原文。

## 不覆盖

以下保持英文或原样，不做翻译：

- 资源名、路径、GUID
- 进度条文字
- 菜单 **Window → Find Reference 2**
- **Assets/FR2** 右键菜单
- 分组标题上的右键菜单

## 升级 Find Reference 2

覆盖安装新版插件后，在仓库根目录：

```powershell
.\tools\extract.ps1 -PluginPath "<工程>\Assets\FindReference2"
```

查看 `out\missing.json`，把需要翻译的新键补进 `table\zh-CN.json`，确认词表无误后再执行：

```powershell
.\tools\test-table.ps1 -TablePath table\zh-CN.json
.\tools\apply.ps1 -PluginPath "<工程>\Assets\FindReference2"
```

## 还原

从最新备份 zip 还原整个 `Assets\FindReference2` 目录：

```powershell
.\tools\revert.ps1 -PluginPath "<工程>\Assets\FindReference2"
```

也可指定某个备份 zip：`.\tools\revert.ps1 -PluginPath "..." -BackupZip "...\FindReference2_20260922_180000.zip"`

## 词表测试

```powershell
.\tools\test-table.ps1 -TablePath table\zh-CN.json
```

编译并运行词表校验，不依赖 Unity。

## 已知上限

- 若文件夹名刚好等于词表键（如 `Scene`、`Selection`），分组标题会被误译成中文。
- `Filter` / `Ignore` 按钮宽度仍是原版固定的 50 和 60 像素，中文可能显示不全。

## 工具脚本编码

`tools\` 下的 PowerShell 脚本为 **ASCII**。在 **PowerShell 5.1** 中，无 BOM 的 `.ps1` 可能被当作 GBK 读取；若遇乱码或解析错误，请用 PowerShell 7+，或确保脚本以 UTF-8 BOM 保存后再运行。
