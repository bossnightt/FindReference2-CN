# Find Reference 2 中文界面补丁设计

> 日期：2026-09-22
> 状态：待实现
> 实验工程：ZenaClient，`Assets/FindReference2`（v2.4.3）
> 补丁正本：`e:\软件\1AAAAA插件\Unity\FindReference2-CN`
> 方案：按 MC2 的方式，词表外置，源码只在 GUI 入口做机械改写，升级后重跑补丁

---

## 1. 目标

给 Find Reference 2 的编辑器窗口做中文界面，并且插件升级后汉化还在。

- 译文在补丁仓库的 `table/zh-CN.json`，不写进插件逻辑
- 插件源码只把绘制入口改成调用翻译层。英文原文留在源码里当查表键
- 默认中文。菜单可切回英文，立刻生效，不用重新编译
- 中文标签悬停显示英文原文
- 查不到的键显示英文原文

## 2. 不做什么

- 不翻资源名、路径、GUID、文件大小、数量
- 不翻进度条（`Refreshing ...`、`Scanning {0} / {1}`）和 `Debug.Log`
- 不翻插件原来的菜单：`Window/Find Reference 2`、`Assets/FR2/...`，以及窗口里 `menu.AddItem` 的右键项（含分组标题上的右键 `Select` / `Append Selection`，和窗口菜单里的 `Commit Selection (数量)`）
- 不全局替换 `new GUIContent` 和 `GUI.Label`
- 不改分组、排序用的英文键。只在画出来的那一下翻译
- 这次不推 GitHub。本地试通后再说
- 不把 FR2 源码收进补丁仓库

## 3. 仓库与注入

补丁仓库只含翻译层、词表和脚本：

```
FindReference2-CN/
  runtime/FR2Loc.cs
  runtime/FR2Json.cs
  table/zh-CN.json
  tools/apply.ps1
  tools/extract.ps1
  tools/revert.ps1
  tools/test-table.ps1
  README.md
```

`apply.ps1 -PluginPath "<工程>\Assets\FindReference2"` 做这些事：

1. 把整个 `FindReference2` 目录打成带时间戳的 zip，放到 Unity 工程的上一级目录 `FindReference2-CN-backups\`。找不到工程根时，放到插件目录的上一级。
2. 覆盖拷贝到 `Assets/FindReference2/Editor/Script/Localization/`：
   - `FR2Loc.cs`
   - `FR2Json.cs`
   - `fr2-zh-CN.json`（内容来自 `table/zh-CN.json`）
3. 改写 `Editor/Script` 下的插件 `.cs`。跳过 `Localization` 目录。文件里已经出现 `FR2Loc.` 则整份跳过。
4. Unity 自己生成 `.meta`，补丁仓库不提交 meta。

`FR2Loc` 放在命名空间 `vietlabs.fr2`，改写后的调用不用加 `using`。插件没有 asmdef，放在这个目录就会跟编辑器脚本一起编译。

中英开关写在 `FR2Loc.cs` 里，不改插件原来的 `MenuItem`：

- `Tools/Find Reference 2/中文界面`
- `Tools/Find Reference 2/重新载入中文词表`

开关存在 `EditorPrefs`，键 `FindReference2.Localization.zhCN`，默认 `true`。关掉后所有查表直接跳过。重新载入把词表缓存清掉再读一次，并重绘所有 `EditorWindow`。

`revert.ps1` 默认用最新备份 zip 还原该插件目录，也可以 `-BackupZip` 指定某一次。

脚本全部用 ASCII 写。Windows PowerShell 5.1 会把无 BOM 的 `.ps1` 当 GBK 读，中文注释会把引号吃掉。含中文的 `FR2Loc.cs` 写入工程时带 UTF-8 BOM。

## 4. 翻译层

`FR2Loc` 对外就这些：

| 方法 | 行为 |
|---|---|
| `T(string)` | 查 `strings`。空串、开关关闭、查不到，都原样返回 |
| `C(string)` | `GUIContent`：标签是译文，tooltip 是英文原文。译文和原文相同时不填 tooltip |
| `Button` / `Label` / `Toggle` / `HelpBox` / `IntSlider` / `Foldout` / `ColorField` | 字符串参数走 `T` 再画，并用 `GUIContent` 带上英文 tooltip。`GUIContent` 参数原样放行 |
| `Button(string format, object arg0, GUIStyle style, params GUILayoutOption[] options)` | 先 `T(format)`，再 `string.Format`。给 `Commit Selection [{0}]` 用 |
| `EnumPopup(string label, Enum selected, params GUILayoutOption[] options)` | 标签走 `T`。选项用枚举类型键查 `enums`，画中文，tooltip 为成员原名。返回值仍是原来的枚举值，调用处的强制转换保持有效 |

包装只覆盖 v2.4.3 里实际出现的重载：

- `Button(string, params GUILayoutOption[])`
- `Button(string, GUIStyle, params GUILayoutOption[])`
- `Button(GUIContent, GUIStyle, params GUILayoutOption[])`
- 上面的格式化 `Button`
- `Label(string, params GUILayoutOption[])`
- `Label(string, GUIStyle, params GUILayoutOption[])`
- `Toggle(bool, string, params GUILayoutOption[])`
- `Toggle(bool, string, GUIStyle, params GUILayoutOption[])`
- `Toggle(bool, GUIContent, GUIStyle, params GUILayoutOption[])`
- `HelpBox(string, MessageType)`
- `IntSlider(string, int, int, int, params GUILayoutOption[])`
- `Foldout(bool, string)`
- `ColorField(Color, params GUILayoutOption[])` 原样转发
- `ColorField(string, Color, params GUILayoutOption[])` 翻译标签
- `EnumPopup(string, Enum, params GUILayoutOption[])`

枚举查表键用 `声明类型名.枚举名`，例如 `FR2_RefDrawer.Mode`。不用 `FullName`（那会带上命名空间，嵌套类型还会变成 `+`）。某个成员没有译文时，该项显示英文成员名，其余照常中文。下拉始终走自己的弹窗，不退回 Unity 的 `EnumPopup`。

`GUIContent` 参数不查表。锁图标、刷新图标、设置图标保持插件原来的样子。

词表缺失、根节点不是对象、或解析抛错：打一条警告，界面保持英文。

## 5. 改写规则

同一轮里先做机械替换，再做手写钩子。`Localization` 目录不参与。注释里的 `GUILayout.Button(` 也会被改成 `FR2Loc.Button(`，注释掉的代码不会运行。

### 5.1 机械替换

把下列调用的类型名换成 `FR2Loc`，参数不动：

- `GUILayout.Button(`
- `GUILayout.Label(`
- `GUILayout.Toggle(`
- `EditorGUILayout.HelpBox(`
- `EditorGUILayout.IntSlider(`
- `EditorGUILayout.Foldout(`
- `EditorGUILayout.ColorField(`
- `EditorGUILayout.EnumPopup(`

设置页的 `FR2_Unity.DrawToggle("...")` 不用单独钩。它内部就是 `GUILayout.Toggle`，替换之后字符串会进 `T`。

不替换：`GUI.Label`、`GUI.Button`、`new GUIContent`、`menu.AddItem`、`MenuItem`、`EditorGUI.ProgressBar`、`Debug.Log`。

### 5.2 手写钩子

按整行（含换行）匹配。对不上就警告并继续，其余照常打补丁，对不上的那句留英文。

**页签。** `FR2_WindowBase` 里的静态字段：

```csharp
protected static GUIContent[] TOOLBARS =
{
    new GUIContent("Uses"),
    new GUIContent("Used By"),
    new GUIContent("Duplicate"),
    new GUIContent("GUIDs"),
    new GUIContent("Unused Assets"),
    new GUIContent("Uses In Build")
};
```

换成绘制时现取的方法，避免静态初始化时去读词表，也让语言开关能刷新：

```csharp
static GUIContent[] Toolbars()
{
    return new[]
    {
        FR2Loc.C("Uses"),
        FR2Loc.C("Used By"),
        FR2Loc.C("Duplicate"),
        FR2Loc.C("GUIDs"),
        FR2Loc.C("Unused Assets"),
        FR2Loc.C("Uses In Build")
    };
}
```

然后把该文件里剩下的标识符 `TOOLBARS` 换成 `Toolbars()`。方法体里不要出现 `TOOLBARS`。`for` 循环因此变成 `Toolbars().Length` 和 `Toolbars()[i]`。每帧多建 6 个 `GUIContent`，可以接受。

**引用列表分组标题。** `FR2_Ref.DrawGroup`：

```csharp
GUI.Label(r, label + " (" + childCount + ")", EditorStyles.boldLabel);
```

换成：

```csharp
GUI.Label(r, FR2Loc.T(label) + " (" + childCount + ")", EditorStyles.boldLabel);
```

`label` 变量保持英文。后面右键 `GetChildren(label)` 仍用它当键。

**忽略列表分组标题。** `FR2_AssetType` 的 `DrawGroup`：

```csharp
GUI.Label(r, id, EditorStyles.boldLabel);
```

换成：

```csharp
GUI.Label(r, FR2Loc.T(id), EditorStyles.boldLabel);
```

下面的 `x.group == id` 仍用英文 `id`。

**底部提交按钮。** 机械替换之后是拼接字符串，整句对不上词表。把：

```csharp
FR2Loc.Button("Commit Selection [" + FR2_Selection.SelectionCount + "]",
    EditorStyles.toolbarButton)
```

换成：

```csharp
FR2Loc.Button("Commit Selection [{0}]", FR2_Selection.SelectionCount,
    EditorStyles.toolbarButton)
```

这条译文必须保留 `{0}`。

重复列表的 `DrawGroup` 画的是 `asset.assetName`，不挂钩。

## 6. 词表

`table/zh-CN.json` 是普通 JSON，不写注释。结构只有两段：

```json
{
  "strings": {
    "Uses": "引用",
    "Commit Selection [{0}]": "提交选择 [{0}]"
  },
  "enums": {
    "FR2_RefDrawer.Mode": {
      "Dependency": "依赖",
      "None": "不分组"
    },
    "FR2_RefDrawer.Sort": {
      "Type": "类型",
      "Path": "路径",
      "Size": "大小"
    }
  }
}
```

- `strings` 按英文整句匹配。同一个英文键共用一条译文。`Selection` 既是工具栏按钮也是分组标题，用同一个词。
- 按钮 `None`（全不选）在 `strings`。枚举 `None`（不分组）在 `enums`。两处译文可以不同。
- `Mode.Type` 和 `Sort.Type` 各翻各的。
- `*Filter`、`*Ignore` 是独立的键，不是在 `Filter` 前面加星号。
- `Aa`、`X`、`*X` 不进词表。
- 多行 `HelpBox` 整段当一条键，JSON 里用 `\n`，必须和 C# 字符串逐字相同。源码里的拼写错误也照抄，例如折叠标题 `Unsed Asset`。
- `Total : ` 加数量是拼接，不进词表，留英文。

初版 `strings` 至少覆盖这些键：

- 页签：`Uses`、`Used By`、`Duplicate`、`GUIDs`、`Unused Assets`、`Uses In Build`
- 按钮和标签：`FORCE TEXT`、`Scan project`、`Enable`、`Scan`、`Cancel`、`All`、`None`、`Paste`、`Copy`、`Merge Selection To`、`Clear Selection`、`Commit Selection [{0}]`、`Ignores`、`GUID to Object`、`Priority`、`Group`、`Sort`、`Filter`、`*Filter`、`Ignore`、`*Ignore`、`Selection`
- 折叠标题：`Assets`、`Unsed Asset`、`Scene Objects`
- 设置项：`Full Row click to Ping`、`Alternate Odd & Even Row Color`、`Show Usage Count in Project panel`、`Show Selection`、`Show Asset Type in use`、`Duplicate Scan Color`
- 提示：`Compiling scripts, please wait!`、`Importing assets, please wait!`、`FR2 requires serialization mode set to FORCE TEXT!`、`Incompatible cache version found, need a full refresh may take time!`、`Find References 2 is disabled!`
- 缓存不存在那整段，键必须与源码逐字相同：`FR2 cache not found!\nFirst scan may takes quite some time to finish but you would be able to work normally while the scan works in background...`
- 分组和类型名：`Selection`、`Others`、`Direct Usage`、`Indirect Usage`、`Scene`、`Prefab`、`Model`、`Material`、`Texture`、`Video`、`Audio`、`Script`、`Text`、`Shader`、`Animation`、`Unity Asset`

初版 `enums`：

- `FR2_RefDrawer.Mode`：`Dependency`、`Type`、`Extension`、`Folder`、`None`
- `FR2_RefDrawer.Sort`：`Type`、`Path`、`Size`

## 7. 扫描漏译

`extract.ps1 -PluginPath ...` 不修改插件。它同时认识打补丁前和打补丁后的源码，写出：

- `out/extracted.json`：扫到的全部键，结构与词表相同。词表里已有的值照抄译文，没有的值用英文原文
- `out/missing.json`：词表里还没有的键，格式与词表相同，值用英文原文，方便抄进 `table/zh-CN.json`

收集范围：

1. 第 5.1 节那些调用（以及对应的 `FR2Loc.*`）里的字符串字面量
2. `TOOLBARS` 初始化器里的 `new GUIContent("...")`，以及任意位置的 `FR2Loc.C("...")`、`FR2Loc.T("...")`
3. `new AssetType("...")` 的第一个参数
4. `GetGroup` 方法里的 `return "..."` 字面量
5. 传给 `FR2_Unity.DrawToggle` / `DrawToggleToolbar` 的字符串字面量
6. `Lable = "..."` 赋值
7. 枚举：从 `(类型) EditorGUILayout.EnumPopup` 或 `(类型) FR2Loc.EnumPopup` 得到类型名，再去源码里找对应 `enum`，列出成员。v2.4.3 会得到 `FR2_RefDrawer.Mode` 和 `FR2_RefDrawer.Sort`

字面量不在上述位置的界面句子，扫不到。运行时显示英文，直到有人把键补进词表。这是这条方案的上限。

## 8. 升级

1. 覆盖安装新版 Find Reference 2
2. 跑 `extract.ps1`，把 `missing.json` 里的译文补进 `table/zh-CN.json`
3. 跑 `apply.ps1`

新版本若多了未实现的重载，Unity 编译失败。补上对应包装，再发一版补丁。手写钩子那一行被上游改掉时，`apply` 警告，该句留英文。

## 9. 验收

不跑 Unity 界面自动化。

1. `FR2Json.Parse` 不引用 Unity，输入 JSON 文本，返回嵌套字典。`test-table.ps1` 编译 `runtime/FR2Json.cs` 和一段只调用 `Parse` 的驱动，读 `table/zh-CN.json`：能解析；`strings` 和 `enums` 里每条译文都不是空串；`Commit Selection [{0}]` 的译文含 `{0}`。
2. 对 ZenaClient 的 `Assets/FindReference2` 跑 `apply.ps1`，回 Unity 确认编译通过。再跑一次 `apply.ps1`，已改写的文件被跳过，源码不被套两层。
3. 打开 FR2 窗口，看这些是中文：页签、按钮、提示、设置项、类型筛选、分组标题（`Selection` / `Direct Usage` / 类型名）、`Group` 和 `Sort` 下拉。
4. 这些仍是英文：资源名、路径、进度条、`Window/Find Reference 2`、`Assets/FR2` 右键、分组上的右键。
5. 关掉 `中文界面`，立刻恢复英文。再打开，立刻恢复中文。悬停中文标签能看到英文原文。
6. 文件夹分组标题仍是路径。`revert.ps1` 能把插件目录还原成备份。

## 10. 已知上限

文件夹模式下，分组标题是路径，对不上词表就显示路径。文件夹名如果刚好等于词表里的键（例如文件夹就叫 `Scene` 或 `Selection`），标题会被翻成中文。排序仍用英文原词，不受影响。真遇到再给这条加排除。

工具栏 `Filter` / `Ignore` 的按钮宽度维持源码里的 50、60 像素。试的时候如果中文被切掉，再单独加宽，不写进这一版的钩子。
