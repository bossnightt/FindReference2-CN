# Find Reference 2 中文界面补丁 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做一套外置的 Find Reference 2 中文补丁：词表和翻译层与插件源码分开，升级后重跑脚本就能把汉化打回去。

**Architecture:** `FR2Json` 在 Unity 外解析词表。`FR2Loc` 在编辑器里查表并包装 IMGUI。`apply.ps1` 备份插件、拷入翻译层、机械替换绘制入口并打四条手写钩子。`extract.ps1` 从打补丁前后的源码收集键。实验目标是 ZenaClient 的 `Assets/FindReference2`，补丁仓库本身不收 FR2 源码。

**Tech Stack:** C#（`FR2Json` 用 C# 5，给 .NET Framework `csc` 编）、Unity 编辑器 IMGUI（`FR2Loc`）、Windows PowerShell 5.1（脚本只用 ASCII）

**Spec:** `docs/superpowers/specs/2026-09-22-findreference2-cn-design.md`

**Repo:** `e:\软件\1AAAAA插件\Unity\FindReference2-CN`（本计划里的提交都在这个仓库，不在 ZenaClient）

---

## File map

| 文件 | 职责 |
|------|------|
| Create: `runtime/FR2Json.cs` | 不依赖 Unity 的 JSON 解析，`Parse` 返回嵌套字典 |
| Create: `runtime/FR2Loc.cs` | 编辑器翻译层：开关、查表、IMGUI 包装 |
| Create: `table/zh-CN.json` | 译文正本 |
| Create: `tools/common.ps1` | 路径、读写、JSON 写出 |
| Create: `tools/test-table.ps1` | 编译并运行词表测试 |
| Create: `tools/test-table/TableTest.cs` | 解析样例和正式词表 |
| Create: `tools/apply.ps1` | 备份、注入、改写 |
| Create: `tools/extract.ps1` | 扫键，写 `out/extracted.json` 和 `out/missing.json` |
| Create: `tools/revert.ps1` | 用备份 zip 还原插件目录 |
| Create: `tools/test-apply.ps1` | 用临时假工程验证 apply / extract / revert |
| Create: `tools/fixtures/*.cs` | 假插件片段，含钩子和不能改的资源名绘制 |
| Create: `README.md` | 安装、升级、还原、不覆盖的范围 |
| Create: `.gitignore` | 忽略 `out/` |

不修改 ZenaClient 里的 FR2，直到 Task 9。Task 9 才会改 `Assets/FindReference2`。

---

### Task 1: 仓库和 JSON 解析器

**Files:**
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\.gitignore`
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\runtime\FR2Json.cs`
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-table\sample.json`
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-table\TableTest.cs`
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-table.ps1`

- [ ] **Step 1: 建仓库，先只放会失败的测试**

创建目录 `e:\软件\1AAAAA插件\Unity\FindReference2-CN`，在里面 `git init`。

`.gitignore`:

```
out/
```

`tools/test-table/sample.json`（UTF-8，无 BOM）:

```json
{
  "strings": {
    "A": "甲",
    "Line": "上\n下"
  },
  "enums": {
    "FR2_RefDrawer.Mode": { "None": "不分组" }
  }
}
```

`tools/test-table/TableTest.cs`（C# 5，无字符串插值）:

```csharp
using System;
using System.Collections.Generic;
using System.IO;
using vietlabs.fr2;

internal static class TableTest
{
    static int Main(string[] args)
    {
        if (args.Length < 1)
        {
            Console.Error.WriteLine("usage: TableTest.exe <sample.json> [zh-CN.json]");
            return 2;
        }

        var sample = FR2Json.Parse(File.ReadAllText(args[0])) as Dictionary<string, object>;
        if (sample == null)
        {
            Console.Error.WriteLine("sample root is not an object");
            return 1;
        }

        var strings = (Dictionary<string, object>)sample["strings"];
        if ((string)strings["A"] != "甲")
        {
            Console.Error.WriteLine("sample A mismatch");
            return 1;
        }
        if ((string)strings["Line"] != "上\n下")
        {
            Console.Error.WriteLine("sample newline mismatch");
            return 1;
        }

        var enums = (Dictionary<string, object>)sample["enums"];
        var mode = (Dictionary<string, object>)enums["FR2_RefDrawer.Mode"];
        if ((string)mode["None"] != "不分组")
        {
            Console.Error.WriteLine("sample enum mismatch");
            return 1;
        }

        if (args.Length >= 2)
        {
            if (!CheckTable(args[1]))
                return 1;
        }

        Console.WriteLine("OK");
        return 0;
    }

    static bool CheckTable(string path)
    {
        var root = FR2Json.Parse(File.ReadAllText(path)) as Dictionary<string, object>;
        if (root == null)
        {
            Console.Error.WriteLine("table root is not an object");
            return false;
        }
        if (!AllFilled(root, "strings"))
            return false;
        if (!AllFilled(root, "enums"))
            return false;

        var strings = (Dictionary<string, object>)root["strings"];
        object commit;
        if (!strings.TryGetValue("Commit Selection [{0}]", out commit) || ((string)commit).IndexOf("{0}") < 0)
        {
            Console.Error.WriteLine("Commit Selection [{0}] must keep {0}");
            return false;
        }
        return true;
    }

    static bool AllFilled(Dictionary<string, object> root, string section)
    {
        object node;
        if (!root.TryGetValue(section, out node))
        {
            Console.Error.WriteLine("missing section " + section);
            return false;
        }
        return Walk(section, node);
    }

    static bool Walk(string path, object node)
    {
        var map = node as Dictionary<string, object>;
        if (map == null)
        {
            Console.Error.WriteLine(path + " is not an object");
            return false;
        }
        foreach (var kv in map)
        {
            var child = kv.Value as Dictionary<string, object>;
            if (child != null)
            {
                if (!Walk(path + "." + kv.Key, child))
                    return false;
                continue;
            }
            var text = kv.Value as string;
            if (string.IsNullOrEmpty(text))
            {
                Console.Error.WriteLine("empty translation: " + path + "." + kv.Key);
                return false;
            }
        }
        return true;
    }
}
```

`tools/test-table.ps1`（只用 ASCII）:

```powershell
# Compile FR2Json plus TableTest and run them. No Unity.
param(
    [string]$SamplePath,
    [string]$TablePath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $SamplePath) { $SamplePath = Join-Path $PSScriptRoot 'test-table/sample.json' }

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) {
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $csc)) { throw "csc.exe not found" }

$outDir = Join-Path $root 'out'
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$exe = Join-Path $outDir 'TableTest.exe'
$sources = @(
    (Join-Path $root 'runtime/FR2Json.cs'),
    (Join-Path $PSScriptRoot 'test-table/TableTest.cs')
)

& $csc /nologo /target:exe "/out:$exe" $sources
if ($LASTEXITCODE -ne 0) { throw "compile failed (exit $LASTEXITCODE)" }

$argsList = @($SamplePath)
if ($TablePath) { $argsList += $TablePath }
& $exe @argsList
if ($LASTEXITCODE -ne 0) { throw "table test failed (exit $LASTEXITCODE)" }
Write-Host "table test passed"
```

- [ ] **Step 2: 跑测试，确认编译失败**

```powershell
powershell -NoProfile -File "e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-table.ps1"
```

Expected: 失败，提示找不到 `runtime/FR2Json.cs` 或编译错误 `FR2Json` 不存在。

- [ ] **Step 3: 写 `runtime/FR2Json.cs`**

C# 5。`Parse` 为 `public`。支持对象、数组、字符串、`true`/`false`/`null`、数字，以及 `\" \\ \/ \n \t \r \b \f \uXXXX`。词表只用到对象和字符串，数组和字面量留着，避免以后词表多一个数就炸。

```csharp
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace vietlabs.fr2
{
    public static class FR2Json
    {
        public static object Parse(string json)
        {
            int index = 0;
            return ParseValue(json, ref index);
        }

        static void SkipWhitespace(string s, ref int i)
        {
            while (i < s.Length && char.IsWhiteSpace(s[i]))
                i++;
        }

        static object ParseValue(string s, ref int i)
        {
            SkipWhitespace(s, ref i);
            if (i >= s.Length)
                throw new FormatException("Unexpected end of JSON");
            switch (s[i])
            {
                case '{': return ParseObject(s, ref i);
                case '[': return ParseArray(s, ref i);
                case '"': return ParseString(s, ref i);
                default: return ParseLiteral(s, ref i);
            }
        }

        static Dictionary<string, object> ParseObject(string s, ref int i)
        {
            var result = new Dictionary<string, object>();
            i++;
            while (true)
            {
                SkipWhitespace(s, ref i);
                if (i >= s.Length)
                    throw new FormatException("Unclosed object");
                if (s[i] == '}')
                {
                    i++;
                    return result;
                }
                if (s[i] == ',')
                {
                    i++;
                    continue;
                }
                var key = ParseString(s, ref i);
                SkipWhitespace(s, ref i);
                if (i >= s.Length || s[i] != ':')
                    throw new FormatException("Missing colon");
                i++;
                result[key] = ParseValue(s, ref i);
            }
        }

        static List<object> ParseArray(string s, ref int i)
        {
            var result = new List<object>();
            i++;
            while (true)
            {
                SkipWhitespace(s, ref i);
                if (i >= s.Length)
                    throw new FormatException("Unclosed array");
                if (s[i] == ']')
                {
                    i++;
                    return result;
                }
                if (s[i] == ',')
                {
                    i++;
                    continue;
                }
                result.Add(ParseValue(s, ref i));
            }
        }

        static string ParseString(string s, ref int i)
        {
            SkipWhitespace(s, ref i);
            if (i >= s.Length || s[i] != '"')
                throw new FormatException("Expected string");
            i++;
            var sb = new StringBuilder();
            while (i < s.Length)
            {
                char c = s[i++];
                if (c == '"')
                    return sb.ToString();
                if (c != '\\')
                {
                    sb.Append(c);
                    continue;
                }
                if (i >= s.Length)
                    break;
                char e = s[i++];
                switch (e)
                {
                    case 'n': sb.Append('\n'); break;
                    case 't': sb.Append('\t'); break;
                    case 'r': sb.Append('\r'); break;
                    case 'b': sb.Append('\b'); break;
                    case 'f': sb.Append('\f'); break;
                    case 'u':
                        if (i + 4 > s.Length)
                            throw new FormatException("Bad unicode escape");
                        sb.Append((char)Convert.ToInt32(s.Substring(i, 4), 16));
                        i += 4;
                        break;
                    default:
                        sb.Append(e);
                        break;
                }
            }
            throw new FormatException("Unclosed string");
        }

        static object ParseLiteral(string s, ref int i)
        {
            int start = i;
            while (i < s.Length && s[i] != ',' && s[i] != '}' && s[i] != ']' && !char.IsWhiteSpace(s[i]))
                i++;
            var token = s.Substring(start, i - start);
            if (token == "true") return true;
            if (token == "false") return false;
            if (token == "null") return null;
            double d;
            if (double.TryParse(token, NumberStyles.Float, CultureInfo.InvariantCulture, out d))
                return d;
            throw new FormatException("Bad literal");
        }
    }
}
```

- [ ] **Step 4: 再跑测试**

```powershell
powershell -NoProfile -File "e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-table.ps1"
```

Expected: 输出 `table test passed`，退出码 0。这一步不传正式词表。

- [ ] **Step 5: 提交**

```powershell
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" add .gitignore runtime/FR2Json.cs tools/test-table.ps1 tools/test-table/sample.json tools/test-table/TableTest.cs
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" commit -m "Add a Unity-free JSON parser for the localization table."
```

---

### Task 2: 正式词表

**Files:**
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\table\zh-CN.json`

- [ ] **Step 1: 用缺词表的检查确认失败**

```powershell
powershell -NoProfile -File "e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-table.ps1" -TablePath "e:\软件\1AAAAA插件\Unity\FindReference2-CN\table\zh-CN.json"
```

Expected: 失败，文件不存在。

- [ ] **Step 2: 写入 `table/zh-CN.json`**

UTF-8，无 BOM，无注释。`strings` 里「缓存不存在」那条的 `\n` 是 JSON 换行，解析后的键必须和运行时 C# 字符串一致（源码里写的是反斜杠加 `n`，编译后是真换行）。

```json
{
  "strings": {
    "Uses": "引用",
    "Used By": "被引用",
    "Duplicate": "重复",
    "GUIDs": "GUID",
    "Unused Assets": "未使用资源",
    "Uses In Build": "构建中引用",
    "FORCE TEXT": "强制文本",
    "Scan project": "扫描工程",
    "Enable": "启用",
    "Scan": "扫描",
    "Cancel": "取消",
    "All": "全部",
    "None": "全不选",
    "Paste": "粘贴",
    "Copy": "复制",
    "Merge Selection To": "将选择合并到",
    "Clear Selection": "清除选择",
    "Commit Selection [{0}]": "提交选择 [{0}]",
    "Ignores": "忽略列表",
    "GUID to Object": "GUID 转对象",
    "Priority": "优先级",
    "Group": "分组",
    "Sort": "排序",
    "Filter": "筛选",
    "*Filter": "*筛选",
    "Ignore": "忽略",
    "*Ignore": "*忽略",
    "Selection": "选择",
    "Assets": "资源",
    "Unsed Asset": "未使用资源",
    "Scene Objects": "场景对象",
    "Full Row click to Ping": "点击整行以定位",
    "Alternate Odd & Even Row Color": "奇偶行交替颜色",
    "Show Usage Count in Project panel": "在 Project 面板显示引用计数",
    "Show Selection": "显示选择",
    "Show Asset Type in use": "显示被使用的资源类型",
    "Duplicate Scan Color": "重复扫描颜色",
    "Compiling scripts, please wait!": "正在编译脚本，请稍候",
    "Importing assets, please wait!": "正在导入资源，请稍候",
    "FR2 requires serialization mode set to FORCE TEXT!": "FR2 需要把序列化模式设为 Force Text",
    "Incompatible cache version found, need a full refresh may take time!": "缓存版本不兼容，需要完整刷新，可能要花一些时间",
    "Find References 2 is disabled!": "Find References 2 已禁用",
    "FR2 cache not found!\nFirst scan may takes quite some time to finish but you would be able to work normally while the scan works in background...": "FR2 缓存不存在！\n首次扫描可能需要较长时间，扫描会在后台进行，期间可以正常工作。",
    "Others": "其他",
    "Direct Usage": "直接引用",
    "Indirect Usage": "间接引用",
    "Scene": "场景",
    "Prefab": "预制体",
    "Model": "模型",
    "Material": "材质",
    "Texture": "贴图",
    "Video": "视频",
    "Audio": "音频",
    "Script": "脚本",
    "Text": "文本",
    "Shader": "着色器",
    "Animation": "动画",
    "Unity Asset": "Unity 资源"
  },
  "enums": {
    "FR2_RefDrawer.Mode": {
      "Dependency": "依赖",
      "Type": "类型",
      "Extension": "扩展名",
      "Folder": "文件夹",
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

`Ignores` 译成「忽略列表」，和按钮 `Ignore` 的「忽略」分开。按钮 `None` 是「全不选」，枚举 `None` 是「不分组」。`Aa`、`X`、`*X` 不收。

- [ ] **Step 3: 再跑词表测试**

```powershell
powershell -NoProfile -File "e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-table.ps1" -TablePath "e:\软件\1AAAAA插件\Unity\FindReference2-CN\table\zh-CN.json"
```

Expected: `table test passed`。

- [ ] **Step 4: 提交**

```powershell
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" add table/zh-CN.json
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" commit -m "Add the Chinese string and enum table for FR2 2.4.3."
```

---

### Task 3: 翻译层 `FR2Loc`

**Files:**
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\runtime\FR2Loc.cs`

这一层要进 Unity 才编得过，本任务不单独跑编译。Task 9 回 Unity 验。

- [ ] **Step 1: 写入 `runtime/FR2Loc.cs`**

命名空间 `vietlabs.fr2`。菜单、`EditorPrefs` 键、查表失败时的警告按规格。包装只实现规格第 4 节列出的重载。字符串画出时：译文和原文不同才把原文放进 tooltip。`GUIContent` 参数原样转发，不查表。

枚举键：`DeclaringType.Name + "." + Name`，所以是 `FR2_RefDrawer.Mode`，不是带 `+` 的 `FullName`。成员没有译文就显示英文成员名。下拉始终用 `EditorGUILayout.Popup`。

格式化按钮先 `T(format)` 再 `string.Format`。译文丢了 `{0}` 时 `string.Format` 会抛，这是词表测试已经挡住的情况，这里不再吞掉。

```csharp
using System;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

namespace vietlabs.fr2
{
    public static class FR2Loc
    {
        const string EnabledPrefKey = "FindReference2.Localization.zhCN";
        const string TableAssetName = "fr2-zh-CN";
        const string MenuToggle = "Tools/Find Reference 2/中文界面";
        const string MenuReload = "Tools/Find Reference 2/重新载入中文词表";

        static bool enabledCache;
        static bool enabledCacheValid;
        static bool tableLoaded;
        static Dictionary<string, string> stringTable;
        static Dictionary<string, Dictionary<string, string>> enumTable;

        public static bool Enabled
        {
            get
            {
                if (!enabledCacheValid)
                {
                    enabledCache = EditorPrefs.GetBool(EnabledPrefKey, true);
                    enabledCacheValid = true;
                }
                return enabledCache;
            }
            set
            {
                enabledCache = value;
                enabledCacheValid = true;
                EditorPrefs.SetBool(EnabledPrefKey, value);
            }
        }

        [MenuItem(MenuToggle, false, 1000)]
        static void ToggleLanguage()
        {
            Enabled = !Enabled;
            RepaintAll();
        }

        [MenuItem(MenuToggle, true)]
        static bool ToggleLanguageValidate()
        {
            Menu.SetChecked(MenuToggle, Enabled);
            return true;
        }

        [MenuItem(MenuReload, false, 1001)]
        static void ReloadTable()
        {
            tableLoaded = false;
            EnsureTable();
            RepaintAll();
        }

        static void RepaintAll()
        {
            var windows = Resources.FindObjectsOfTypeAll<EditorWindow>();
            for (int i = 0; i < windows.Length; i++)
                windows[i].Repaint();
        }

        static void EnsureTable()
        {
            if (tableLoaded)
                return;
            tableLoaded = true;
            stringTable = new Dictionary<string, string>();
            enumTable = new Dictionary<string, Dictionary<string, string>>();
            try
            {
                var text = LoadTableText();
                if (string.IsNullOrEmpty(text))
                {
                    Debug.LogWarning("[FindReference2-CN] 未找到词表 fr2-zh-CN.json，界面保持英文。");
                    return;
                }
                var root = FR2Json.Parse(text) as Dictionary<string, object>;
                if (root == null)
                {
                    Debug.LogWarning("[FindReference2-CN] 词表根节点不是 JSON 对象，界面保持英文。");
                    return;
                }
                ReadStrings(root);
                ReadEnums(root);
            }
            catch (Exception e)
            {
                Debug.LogWarning("[FindReference2-CN] 词表解析失败，界面保持英文: " + e.Message);
            }
        }

        static string LoadTableText()
        {
            var guids = AssetDatabase.FindAssets(TableAssetName + " t:TextAsset");
            for (int i = 0; i < guids.Length; i++)
            {
                var path = AssetDatabase.GUIDToAssetPath(guids[i]);
                if (!path.EndsWith(TableAssetName + ".json", StringComparison.OrdinalIgnoreCase))
                    continue;
                var asset = AssetDatabase.LoadAssetAtPath<TextAsset>(path);
                if (asset != null)
                    return asset.text;
            }
            return null;
        }

        static void ReadStrings(Dictionary<string, object> root)
        {
            object node;
            if (!root.TryGetValue("strings", out node))
                return;
            var map = node as Dictionary<string, object>;
            if (map == null)
                return;
            foreach (var kv in map)
            {
                var s = kv.Value as string;
                if (!string.IsNullOrEmpty(s))
                    stringTable[kv.Key] = s;
            }
        }

        static void ReadEnums(Dictionary<string, object> root)
        {
            object node;
            if (!root.TryGetValue("enums", out node))
                return;
            var map = node as Dictionary<string, object>;
            if (map == null)
                return;
            foreach (var scope in map)
            {
                var members = scope.Value as Dictionary<string, object>;
                if (members == null)
                    continue;
                var memberMap = new Dictionary<string, string>();
                foreach (var kv in members)
                {
                    var s = kv.Value as string;
                    if (!string.IsNullOrEmpty(s))
                        memberMap[kv.Key] = s;
                }
                enumTable[scope.Key] = memberMap;
            }
        }

        public static string T(string text)
        {
            if (string.IsNullOrEmpty(text) || !Enabled)
                return text;
            EnsureTable();
            string zh;
            return stringTable.TryGetValue(text, out zh) ? zh : text;
        }

        public static GUIContent C(string text)
        {
            var zh = T(text);
            return zh == text ? new GUIContent(text) : new GUIContent(zh, text);
        }

        static GUIContent LabelContent(string text)
        {
            return C(text);
        }

        public static bool Button(string text, params GUILayoutOption[] options)
        {
            return GUILayout.Button(LabelContent(text), options);
        }

        public static bool Button(string text, GUIStyle style, params GUILayoutOption[] options)
        {
            return GUILayout.Button(LabelContent(text), style, options);
        }

        public static bool Button(GUIContent content, GUIStyle style, params GUILayoutOption[] options)
        {
            return GUILayout.Button(content, style, options);
        }

        public static bool Button(string format, object arg0, GUIStyle style, params GUILayoutOption[] options)
        {
            var pattern = T(format);
            var shown = string.Format(pattern, arg0);
            var english = string.Format(format, arg0);
            var content = pattern == format ? new GUIContent(shown) : new GUIContent(shown, english);
            return GUILayout.Button(content, style, options);
        }

        public static void Label(string label, params GUILayoutOption[] options)
        {
            GUILayout.Label(LabelContent(label), options);
        }

        public static void Label(string label, GUIStyle style, params GUILayoutOption[] options)
        {
            GUILayout.Label(LabelContent(label), style, options);
        }

        public static bool Toggle(bool value, string text, params GUILayoutOption[] options)
        {
            return GUILayout.Toggle(value, LabelContent(text), options);
        }

        public static bool Toggle(bool value, string text, GUIStyle style, params GUILayoutOption[] options)
        {
            return GUILayout.Toggle(value, LabelContent(text), style, options);
        }

        public static bool Toggle(bool value, GUIContent content, GUIStyle style, params GUILayoutOption[] options)
        {
            return GUILayout.Toggle(value, content, style, options);
        }

        public static void HelpBox(string message, MessageType type)
        {
            EditorGUILayout.HelpBox(LabelContent(message), type);
        }

        public static int IntSlider(string label, int value, int left, int right, params GUILayoutOption[] options)
        {
            return EditorGUILayout.IntSlider(LabelContent(label), value, left, right, options);
        }

        public static bool Foldout(bool foldout, string content)
        {
            return EditorGUILayout.Foldout(foldout, LabelContent(content));
        }

        public static Color ColorField(Color value, params GUILayoutOption[] options)
        {
            return EditorGUILayout.ColorField(value, options);
        }

        public static Color ColorField(string label, Color value, params GUILayoutOption[] options)
        {
            return EditorGUILayout.ColorField(LabelContent(label), value, options);
        }

        public static Enum EnumPopup(string label, Enum selected, params GUILayoutOption[] options)
        {
            if (selected == null)
                return selected;
            var names = Enum.GetNames(selected.GetType());
            var shown = new GUIContent[names.Length];
            var typeKey = EnumTypeKey(selected.GetType());
            for (int i = 0; i < names.Length; i++)
            {
                string zh;
                if (Enabled && TryEnum(typeKey, names[i], out zh))
                    shown[i] = new GUIContent(zh, names[i]);
                else
                    shown[i] = new GUIContent(names[i]);
            }
            int current = Array.IndexOf(names, selected.ToString());
            int next = EditorGUILayout.Popup(LabelContent(label), current, shown, options);
            if (next < 0 || next >= names.Length)
                return selected;
            return (Enum)Enum.Parse(selected.GetType(), names[next]);
        }

        static string EnumTypeKey(Type type)
        {
            if (type.DeclaringType != null)
                return type.DeclaringType.Name + "." + type.Name;
            return type.Name;
        }

        static bool TryEnum(string typeKey, string member, out string zh)
        {
            zh = null;
            EnsureTable();
            Dictionary<string, string> members;
            if (!enumTable.TryGetValue(typeKey, out members))
                return false;
            return members.TryGetValue(member, out zh);
        }
    }
}
```

`HelpBox(GUIContent, MessageType)` 在 Unity 2022 里存在。如果目标编辑器更老、没有这个重载，Task 9 编译失败时改成 `EditorGUILayout.HelpBox(T(message), type)`，tooltip 这一个控件可以不要，其余不动。

- [ ] **Step 2: 提交**

```powershell
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" add runtime/FR2Loc.cs
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" commit -m "Add the editor localization layer for Find Reference 2."
```

---

### Task 4: `apply.ps1`

**Files:**
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\common.ps1`
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\apply.ps1`

- [ ] **Step 1: 写 `tools/common.ps1`**

只用 ASCII。职责：确认插件根（里面要有 `Editor\Script`）、找 Unity 工程根（同时有 `Assets` 和 `ProjectSettings`）、按字节读写以保留 BOM、把嵌套字符串字典写成 JSON。

```powershell
# Shared helpers. ASCII only: Windows PowerShell 5.1 reads a BOM-less
# ps1 as the system ANSI code page.

function Resolve-PluginPath {
    param([string]$PluginPath)
    if ([string]::IsNullOrWhiteSpace($PluginPath)) { throw 'PluginPath is required.' }
    $full = (Resolve-Path -LiteralPath $PluginPath -ErrorAction Stop).Path
    $scriptDir = Join-Path $full 'Editor\Script'
    if (-not (Test-Path -LiteralPath $scriptDir)) {
        throw "Not a Find Reference 2 root (missing Editor\Script): $full"
    }
    return $full
}

function Find-UnityProjectRoot {
    param([string]$Start)
    $dir = Get-Item -LiteralPath $Start
    while ($null -ne $dir) {
        $assets = Join-Path $dir.FullName 'Assets'
        $settings = Join-Path $dir.FullName 'ProjectSettings'
        if ((Test-Path -LiteralPath $assets) -and (Test-Path -LiteralPath $settings)) {
            return $dir.FullName
        }
        $dir = $dir.Parent
    }
    return $null
}

function Read-SourceFile {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
    return [PSCustomObject]@{ Text = $text; HasBom = $hasBom }
}

function Write-SourceFile {
    param([string]$Path, [string]$Text, [bool]$HasBom)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $enc = New-Object System.Text.UTF8Encoding($HasBom)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Get-PluginScriptFiles {
    param([string]$PluginRoot)
    $scriptDir = Join-Path $PluginRoot 'Editor\Script'
    $list = @()
    foreach ($file in (Get-ChildItem -LiteralPath $scriptDir -Recurse -File -Filter *.cs)) {
        $rel = $file.FullName.Substring($PluginRoot.Length).TrimStart('\', '/')
        if ($rel -match '(^|[\\/])Localization[\\/]') { continue }
        $list += [PSCustomObject]@{ Rel = $rel; Full = $file.FullName }
    }
    return $list
}

function Escape-JsonString {
    param([string]$Text)
    if ($null -eq $Text) { return '""' }
    $s = $Text.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
    return '"' + $s + '"'
}

function Write-StringMapJson {
    param([string]$Path, $Strings, $Enums)
    $nl = "`n"
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('{')
    [void]$sb.Append($nl)
    [void]$sb.Append('  "strings": {')
    [void]$sb.Append($nl)
    $keys = @($Strings.Keys | Sort-Object)
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $comma = $(if ($i -lt $keys.Count - 1) { ',' } else { '' })
        [void]$sb.Append('    ' + (Escape-JsonString $keys[$i]) + ': ' + (Escape-JsonString $Strings[$keys[$i]]) + $comma + $nl)
    }
    [void]$sb.Append('  },')
    [void]$sb.Append($nl)
    [void]$sb.Append('  "enums": {')
    [void]$sb.Append($nl)
    $ekeys = @($Enums.Keys | Sort-Object)
    for ($i = 0; $i -lt $ekeys.Count; $i++) {
        [void]$sb.Append('    ' + (Escape-JsonString $ekeys[$i]) + ': {')
        [void]$sb.Append($nl)
        $members = $Enums[$ekeys[$i]]
        $mkeys = @($members.Keys | Sort-Object)
        for ($j = 0; $j -lt $mkeys.Count; $j++) {
            $comma = $(if ($j -lt $mkeys.Count - 1) { ',' } else { '' })
            [void]$sb.Append('      ' + (Escape-JsonString $mkeys[$j]) + ': ' + (Escape-JsonString $members[$mkeys[$j]]) + $comma + $nl)
        }
        $comma = $(if ($i -lt $ekeys.Count - 1) { ',' } else { '' })
        [void]$sb.Append('    }' + $comma + $nl)
    }
    [void]$sb.Append('  }')
    [void]$sb.Append($nl)
    [void]$sb.Append('}')
    [void]$sb.Append($nl)
    Write-SourceFile $Path $sb.ToString() $false
}
```

- [ ] **Step 2: 写 `tools/apply.ps1`**

流程：备份 zip 到工程上一级的 `FindReference2-CN-backups`（找不到工程根就用插件上一级）；把 `FR2Loc.cs`、`FR2Json.cs` 以 UTF-8 BOM 写入 `Editor\Script\Localization\`，把词表写成 `fr2-zh-CN.json`（无 BOM）；然后改写脚本。已含 `FR2Loc.` 的文件整份跳过。先做调用名替换，再做手写钩子。钩子用正则，只放宽空白，记号必须一致；对不上就 `Write-Warning` 并继续。

不替换 `GUI.Label`、`new GUIContent`、`MenuItem`、`EditorGUI.ProgressBar`。`Localization` 目录不进改写列表。

```powershell
# Inject FindReference2-CN into a Find Reference 2 install.
#   .\apply.ps1 -PluginPath "D:\...\Assets\FindReference2"
param(
    [Parameter(Mandatory = $true)][string]$PluginPath,
    [switch]$NoBackup
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')

$pluginRoot = Resolve-PluginPath $PluginPath

if (-not $NoBackup) {
    $projectRoot = Find-UnityProjectRoot $pluginRoot
    $backupBase = if ($projectRoot) { Split-Path -Parent $projectRoot } else { Split-Path -Parent $pluginRoot }
    $backupDir = Join-Path $backupBase 'FindReference2-CN-backups'
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $zip = Join-Path $backupDir "FindReference2_$stamp.zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Write-Host "Backup : $zip"
    Compress-Archive -Path $pluginRoot -DestinationPath $zip -CompressionLevel Optimal
}

$locDir = Join-Path $pluginRoot 'Editor\Script\Localization'
if (-not (Test-Path -LiteralPath $locDir)) {
    New-Item -ItemType Directory -Path $locDir -Force | Out-Null
}
foreach ($name in @('FR2Loc.cs', 'FR2Json.cs')) {
    $src = Join-Path $root "runtime/$name"
    if (-not (Test-Path -LiteralPath $src)) { throw "Missing runtime/$name" }
    Write-SourceFile (Join-Path $locDir $name) (Read-SourceFile $src).Text $true
}
$tableSrc = Join-Path $root 'table/zh-CN.json'
if (-not (Test-Path -LiteralPath $tableSrc)) { throw 'Missing table/zh-CN.json' }
Write-SourceFile (Join-Path $locDir 'fr2-zh-CN.json') (Read-SourceFile $tableSrc).Text $false
Write-Host "Runtime: $locDir"

$api = @(
    @{ From = 'GUILayout.Button('; To = 'FR2Loc.Button(' },
    @{ From = 'GUILayout.Label('; To = 'FR2Loc.Label(' },
    @{ From = 'GUILayout.Toggle('; To = 'FR2Loc.Toggle(' },
    @{ From = 'EditorGUILayout.HelpBox('; To = 'FR2Loc.HelpBox(' },
    @{ From = 'EditorGUILayout.IntSlider('; To = 'FR2Loc.IntSlider(' },
    @{ From = 'EditorGUILayout.Foldout('; To = 'FR2Loc.Foldout(' },
    @{ From = 'EditorGUILayout.ColorField('; To = 'FR2Loc.ColorField(' },
    @{ From = 'EditorGUILayout.EnumPopup('; To = 'FR2Loc.EnumPopup(' }
)

$script:toolbarsMethod = @'
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
'@

function Apply-Hooks {
    param([string]$Rel, [string]$Text)
    $count = 0
    $leaf = Split-Path -Leaf $Rel
    if ($leaf -eq 'FR2_WindowBase.cs') {
        $toolbarRe = '(?s)protected static GUIContent\[\] TOOLBARS\s*=\s*\{.*?\};'
        $next = [regex]::Replace($Text, $toolbarRe, { param($m) $script:toolbarsMethod }, 1)
        if ($next -eq $Text) { Write-Warning "Hook not found in ${Rel}: TOOLBARS field" }
        else { $Text = $next; $count++ }
        $idNext = [regex]::Replace($Text, '(?<![\w])TOOLBARS(?![\w])', 'Toolbars()')
        if ($idNext -eq $Text) { Write-Warning "Hook not found in ${Rel}: TOOLBARS uses" }
        else { $Text = $idNext; $count++ }
        $commitRe = 'FR2Loc\.Button\(\s*"Commit Selection \[" \+ FR2_Selection\.SelectionCount \+ "\]"\s*,\s*EditorStyles\.toolbarButton\s*\)'
        $commitTo = 'FR2Loc.Button("Commit Selection [{0}]", FR2_Selection.SelectionCount, EditorStyles.toolbarButton)'
        $cNext = [regex]::Replace($Text, $commitRe, $commitTo, 1)
        if ($cNext -eq $Text) { Write-Warning "Hook not found in ${Rel}: Commit Selection button" }
        else { $Text = $cNext; $count++ }
    }
    if ($leaf -eq 'FR2_Ref.cs') {
        $re = 'GUI\.Label\(r, label \+ " \(" \+ childCount \+ "\)", EditorStyles\.boldLabel\);'
        $to = 'GUI.Label(r, FR2Loc.T(label) + " (" + childCount + ")", EditorStyles.boldLabel);'
        $n = [regex]::Replace($Text, $re, $to, 1)
        if ($n -eq $Text) { Write-Warning "Hook not found in ${Rel}: ref group label" }
        else { $Text = $n; $count++ }
    }
    if ($leaf -eq 'FR2_AssetType.cs') {
        $from = 'GUI.Label(r, id, EditorStyles.boldLabel);'
        $to = 'GUI.Label(r, FR2Loc.T(id), EditorStyles.boldLabel);'
        if ($Text.Contains($from)) { $Text = $Text.Replace($from, $to); $count++ }
        else { Write-Warning "Hook not found in ${Rel}: ignore group label" }
    }
    return [PSCustomObject]@{ Text = $Text; Count = $count }
}

$patched = 0
$skipped = 0
$edits = 0
foreach ($t in (Get-PluginScriptFiles $pluginRoot)) {
    $file = Read-SourceFile $t.Full
    if ($file.Text.Contains('FR2Loc.')) {
        Write-Host ("  skip   {0} (already patched)" -f $t.Rel)
        $skipped++
        continue
    }
    $text = $file.Text
    $count = 0
    foreach ($r in $api) {
        $hits = ([regex]::Matches($text, [regex]::Escape($r.From))).Count
        if ($hits -gt 0) {
            $text = $text.Replace($r.From, $r.To)
            $count += $hits
        }
    }
    $hooked = Apply-Hooks $t.Rel $text
    $text = $hooked.Text
    $count += $hooked.Count
    if ($count -eq 0) {
        Write-Host ("  skip   {0} (nothing to rewrite)" -f $t.Rel)
        $skipped++
        continue
    }
    Write-SourceFile $t.Full $text $file.HasBom
    Write-Host ("  patch  {0}  ({1} edits)" -f $t.Rel, $count)
    $patched++
    $edits += $count
}

Write-Host ''
Write-Host '--- apply result ---'
Write-Host ("patched files : {0}" -f $patched)
Write-Host ("skipped files : {0}" -f $skipped)
Write-Host ("total edits   : {0}" -f $edits)
```

`Apply-Hooks` 里的 `$toolbarsMethod` 必须是脚本作用域变量，函数才读得到。上面的写法在 PowerShell 里函数读父作用域变量是可以的。不要把 `$toolbarsMethod` 放进函数里面又在外面赋值。

页签方法体里不能出现标识符 `TOOLBARS`，否则替换剩余标识符时会把方法名搞坏。上面的方法体用的是 `Toolbars`，符合规格。

- [ ] **Step 3: 提交**

```powershell
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" add tools/common.ps1 tools/apply.ps1
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" commit -m "Add the idempotent apply script and its shared helpers."
```

Task 5 才跑它。这一步还不要对 ZenaClient 执行。

---

### Task 5: 用假工程验证 apply

**Files:**
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\fixtures\FR2_WindowBase.cs`
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\fixtures\FR2_Ref.cs`
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\fixtures\FR2_AssetType.cs`
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\fixtures\FR2_Cache.cs`
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-apply.ps1`

- [ ] **Step 1: 写夹具**

夹具不是合法的完整插件，只保留 apply 要认的文本。`ProjectSettings` 由测试脚本创建。

`tools/fixtures/FR2_WindowBase.cs`:

```csharp
namespace vietlabs.fr2
{
    public class FR2_WindowBase
    {
        protected static GUIContent[] TOOLBARS =
        {
            new GUIContent("Uses"),
            new GUIContent("Used By"),
            new GUIContent("Duplicate"),
            new GUIContent("GUIDs"),
            new GUIContent("Unused Assets"),
            new GUIContent("Uses In Build")
        };

        void Draw()
        {
            for (var i = 0; i < TOOLBARS.Length; i++)
            {
                GUILayout.Toggle(false, TOOLBARS[i], EditorStyles.toolbarButton);
            }
            GUILayout.Button("Scan project");
            GUI.Label(r, assetName, EditorStyles.boldLabel);
            menu.AddItem(new GUIContent("Open"), false, Open);
            if (GUILayout.Button("Commit Selection [" + FR2_Selection.SelectionCount + "]",
                    EditorStyles.toolbarButton))
            {
                FR2_Selection.Commit();
            }
        }
    }
}
```

`tools/fixtures/FR2_Ref.cs` 含分组标题和 `GetGroup` 返回值：

```csharp
namespace vietlabs.fr2
{
    public class FR2_RefDrawer
    {
        void DrawGroup(Rect r, string label, int childCount)
        {
            GUI.Label(r, label + " (" + childCount + ")", EditorStyles.boldLabel);
        }

        private string GetGroup()
        {
            return "Direct Usage";
        }
    }
}
```

`tools/fixtures/FR2_AssetType.cs`:

```csharp
namespace vietlabs.fr2
{
    public class AssetType
    {
        void Init()
        {
            var scene = new AssetType("Scene", ".unity");
        }

        void DrawGroup(Rect r, string id, int childCound)
        {
            GUI.Label(r, id, EditorStyles.boldLabel);
        }
    }
}
```

`tools/fixtures/FR2_Cache.cs`:

```csharp
namespace vietlabs.fr2
{
    public class FR2_Cache
    {
        void DrawSettings()
        {
            FR2_Unity.DrawToggle(ref pingRow, "Full Row click to Ping");
            EditorGUI.ProgressBar(rect, p, "Refreshing ...");
        }
    }
}
```

- [ ] **Step 2: 写 `tools/test-apply.ps1`**

Task 6 和 Task 7 会往这个脚本末尾加 extract / revert 断言。这一版只覆盖 apply。

```powershell
# Build a fake Unity project, apply the patch, and check the rewrite.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([System.IO.Path]::GetTempPath()) 'fr2cn-apply-test'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
$project = Join-Path $work 'Proj'
$plugin = Join-Path $project 'Assets\FindReference2'
$scriptDir = Join-Path $plugin 'Editor\Script'
New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $project 'ProjectSettings') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $project 'ProjectSettings\ProjectVersion.txt') -Value 'm_EditorVersion: 2022.3.0f1' -Encoding ASCII
Copy-Item -Path (Join-Path $PSScriptRoot 'fixtures\*.cs') -Destination $scriptDir

function Assert-Has {
    param([string]$Path, [string]$Needle)
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle) -lt 0) { throw "Missing [$Needle] in $Path" }
}
function Assert-Lacks {
    param([string]$Path, [string]$Needle)
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle) -ge 0) { throw "Unexpected [$Needle] in $Path" }
}

& (Join-Path $PSScriptRoot 'apply.ps1') -PluginPath $plugin
$backupDir = Join-Path $work 'FindReference2-CN-backups'
$zips = @(Get-ChildItem -LiteralPath $backupDir -Filter 'FindReference2_*.zip' -File)
if ($zips.Count -lt 1) { throw 'backup zip was not written next to the fake project' }

$loc = Join-Path $scriptDir 'Localization'
$locBytes = [System.IO.File]::ReadAllBytes((Join-Path $loc 'FR2Loc.cs'))
if ($locBytes.Length -lt 3 -or $locBytes[0] -ne 0xEF -or $locBytes[1] -ne 0xBB -or $locBytes[2] -ne 0xBF) {
    throw 'FR2Loc.cs was not written with a UTF-8 BOM'
}
$jsonBytes = [System.IO.File]::ReadAllBytes((Join-Path $loc 'fr2-zh-CN.json'))
if ($jsonBytes.Length -ge 3 -and $jsonBytes[0] -eq 0xEF -and $jsonBytes[1] -eq 0xBB -and $jsonBytes[2] -eq 0xBF) {
    throw 'fr2-zh-CN.json must not start with a BOM'
}

$window = Join-Path $scriptDir 'FR2_WindowBase.cs'
Assert-Has $window 'static GUIContent[] Toolbars()'
Assert-Has $window 'FR2Loc.C("Uses")'
Assert-Has $window 'FR2Loc.Button("Scan project")'
Assert-Has $window 'FR2Loc.Button("Commit Selection [{0}]", FR2_Selection.SelectionCount, EditorStyles.toolbarButton)'
Assert-Has $window 'Toolbars().Length'
Assert-Has $window 'Toolbars()[i]'
Assert-Has $window 'GUI.Label(r, assetName, EditorStyles.boldLabel)'
Assert-Has $window 'new GUIContent("Open")'
Assert-Lacks $window 'FR2Loc.C("Open")'

$ref = Join-Path $scriptDir 'FR2_Ref.cs'
Assert-Has $ref 'FR2Loc.T(label)'
Assert-Has $ref 'return "Direct Usage"'

$assetType = Join-Path $scriptDir 'FR2_AssetType.cs'
Assert-Has $assetType 'FR2Loc.T(id)'
Assert-Has $assetType 'new AssetType("Scene"'

$cache = Join-Path $scriptDir 'FR2_Cache.cs'
Assert-Has $cache 'FR2_Unity.DrawToggle(ref pingRow, "Full Row click to Ping")'
Assert-Has $cache 'EditorGUI.ProgressBar'
Assert-Lacks $cache 'FR2Loc.ProgressBar'

$once = [System.IO.File]::ReadAllText($window)
$log = & (Join-Path $PSScriptRoot 'apply.ps1') -PluginPath $plugin -NoBackup 2>&1 | Out-String
if ([System.IO.File]::ReadAllText($window) -ne $once) { throw 'second apply changed an already patched file' }
if ($log -notmatch 'already patched') { throw 'second apply did not skip patched files' }

Write-Host 'apply test passed'
```

- [ ] **Step 3: 跑测试**

```powershell
powershell -NoProfile -File "e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-apply.ps1"
```

Expected: `apply test passed`。失败就改 `apply.ps1`，不要改断言去迁就错误替换。

- [ ] **Step 4: 提交**

```powershell
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" add tools/fixtures tools/test-apply.ps1 tools/apply.ps1 tools/common.ps1
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" commit -m "Test apply against a fake plugin and keep re-runs idempotent."
```

---

### Task 6: `extract.ps1`

**Files:**
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\extract.ps1`
- Modify: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-apply.ps1`（在 apply 断言之后加 extract 断言）

- [ ] **Step 1: 先让测试失败**

先做 Step 3 里对 `test-apply.ps1` 的修改（拷贝 Before、插入 extract 断言），先不要写 `extract.ps1`。然后跑：

```powershell
powershell -NoProfile -File "e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-apply.ps1"
```

Expected: 失败，因为 `tools\extract.ps1` 还不存在。然后再写 Step 2。

- [ ] **Step 2: 写 `tools/extract.ps1`**

脚本只用 ASCII。不修改插件。C# 字符串要反转义后再当键，这样和运行时传给 `T()` 的值一致。调用参数里的全部字符串字面量都收集（`Toggle` 的标签不是第一个参数）。括号配对时跳过字符串，避免把字符串里的括号算进去。`GetGroup` 用花括号深度截方法体，一个文件里可以有多个。

```powershell
# Scan Find Reference 2 editor scripts for localization keys.
#   .\extract.ps1 -PluginPath "D:\...\Assets\FindReference2"
param(
    [Parameter(Mandatory = $true)][string]$PluginPath,
    [string]$TablePath,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not $TablePath) { $TablePath = Join-Path $root 'table\zh-CN.json' }
if (-not $OutDir) { $OutDir = Join-Path $root 'out' }

$pluginRoot = Resolve-PluginPath $PluginPath
$files = @(Get-PluginScriptFiles $pluginRoot)

function ConvertFrom-CSharpString {
    param([string]$Raw)
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Raw.Length; $i++) {
        $c = $Raw[$i]
        if ($c -ne '\') { [void]$sb.Append($c); continue }
        if ($i + 1 -ge $Raw.Length) { [void]$sb.Append($c); break }
        $i++
        switch ($Raw[$i]) {
            'n' { [void]$sb.Append("`n") }
            'r' { [void]$sb.Append("`r") }
            't' { [void]$sb.Append("`t") }
            '\' { [void]$sb.Append('\') }
            '"' { [void]$sb.Append('"') }
            default { [void]$sb.Append($Raw[$i]) }
        }
    }
    return $sb.ToString()
}

function Get-StringLiterals {
    param([string]$Text)
    $found = @()
    foreach ($m in [regex]::Matches($Text, '"((?:\\.|[^"\\])*)"')) {
        $found += (ConvertFrom-CSharpString $m.Groups[1].Value)
    }
    return $found
}

function Get-Balanced {
    param([string]$Text, [int]$OpenIndex, [char]$Open, [char]$Close)
    $depth = 0
    for ($i = $OpenIndex; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($c -eq '"') {
            $i++
            while ($i -lt $Text.Length) {
                if ($Text[$i] -eq '\') { $i += 2; continue }
                if ($Text[$i] -eq '"') { break }
                $i++
            }
            continue
        }
        if ($c -eq $Open) { $depth++ }
        elseif ($c -eq $Close) {
            $depth--
            if ($depth -eq 0) {
                return $Text.Substring($OpenIndex + 1, $i - $OpenIndex - 1)
            }
        }
    }
    return $null
}

function Add-CallStrings {
    param($Set, [string]$Text, [string]$CallPattern)
    foreach ($m in [regex]::Matches($Text, $CallPattern)) {
        $open = $m.Index + $m.Length - 1
        $body = Get-Balanced $Text $open '(' ')'
        if ($null -eq $body) { continue }
        foreach ($lit in (Get-StringLiterals $body)) {
            if ($lit.Length -gt 0) { [void]$Set.Add($lit) }
        }
    }
}

$strings = New-Object 'System.Collections.Generic.HashSet[string]'
$enums = @{}

$callPatterns = @(
    '(?:GUILayout|FR2Loc)\.(?:Button|Label|Toggle)\(',
    '(?:EditorGUILayout|FR2Loc)\.(?:HelpBox|IntSlider|ColorField|Foldout|EnumPopup)\(',
    'FR2Loc\.[CT]\(',
    'DrawToggle(?:Toolbar)?\('
)

foreach ($f in $files) {
    $text = (Read-SourceFile $f.Full).Text
    foreach ($pat in $callPatterns) { Add-CallStrings $strings $text $pat }

    foreach ($m in [regex]::Matches($text, 'new\s+AssetType\(')) {
        $open = $m.Index + $m.Length - 1
        $body = Get-Balanced $text $open '(' ')'
        if ($body) {
            $first = [regex]::Match($body, '"((?:\\.|[^"\\])*)"')
            if ($first.Success) {
                $lit = ConvertFrom-CSharpString $first.Groups[1].Value
                if ($lit.Length -gt 0) { [void]$strings.Add($lit) }
            }
        }
    }

    foreach ($m in [regex]::Matches($text, '(?s)GUIContent\[\]\s+TOOLBARS\s*=\s*\{')) {
        $open = $text.IndexOf('{', $m.Index)
        $body = Get-Balanced $text $open '{' '}'
        if ($body) {
            foreach ($lit in (Get-StringLiterals $body)) {
                if ($lit.Length -gt 0) { [void]$strings.Add($lit) }
            }
        }
    }

    foreach ($m in [regex]::Matches($text, '\bstring\s+GetGroup\s*\(')) {
        $open = $text.IndexOf('{', $m.Index)
        if ($open -lt 0) { continue }
        $body = Get-Balanced $text $open '{' '}'
        if ($body) {
            foreach ($lit in (Get-StringLiterals $body)) {
                if ($lit.Length -gt 0) { [void]$strings.Add($lit) }
            }
        }
    }

    foreach ($m in [regex]::Matches($text, 'Lable\s*=\s*"((?:\\.|[^"\\])*)"')) {
        $lit = ConvertFrom-CSharpString $m.Groups[1].Value
        if ($lit.Length -gt 0) { [void]$strings.Add($lit) }
    }

    foreach ($m in [regex]::Matches($text, '\(([\w\.]+)\)\s*(?:EditorGUILayout|FR2Loc)\.EnumPopup')) {
        $typeName = $m.Groups[1].Value
        $enumName = $typeName
        $outer = ''
        $dot = $typeName.LastIndexOf('.')
        if ($dot -ge 0) {
            $outer = $typeName.Substring(0, $dot)
            $enumName = $typeName.Substring($dot + 1)
        }
        if ($outer -and $text.IndexOf($outer) -lt 0) { continue }
        $em = [regex]::Match($text, "enum\s+$enumName\b[^{]*\{")
        if (-not $em.Success) { continue }
        $open = $text.IndexOf('{', $em.Index)
        $body = Get-Balanced $text $open '{' '}'
        if (-not $body) { continue }
        $body = [regex]::Replace($body, '//[^\r\n]*', '')
        $members = @{}
        foreach ($part in ($body -split ',')) {
            $id = (($part -split '=')[0]).Trim()
            if ($id -match '^[A-Za-z_][A-Za-z0-9_]*$') { $members[$id] = $true }
        }
        if ($members.Count -eq 0) { continue }
        if (-not $enums.ContainsKey($typeName)) { $enums[$typeName] = @{} }
        foreach ($id in $members.Keys) { $enums[$typeName][$id] = $true }
    }
}

$table = Get-Content -LiteralPath $TablePath -Raw -Encoding UTF8 | ConvertFrom-Json
function Get-TableString {
    param($Name)
    $p = $table.strings.PSObject.Properties[$Name]
    if ($p) { return [string]$p.Value }
    return $null
}
function Get-TableEnum {
    param($TypeName, $Member)
    $scope = $table.enums.PSObject.Properties[$TypeName]
    if (-not $scope) { return $null }
    $p = $scope.Value.PSObject.Properties[$Member]
    if ($p) { return [string]$p.Value }
    return $null
}

$extractedStrings = @{}
$missingStrings = @{}
foreach ($key in $strings) {
    $zh = Get-TableString $key
    if ($zh) { $extractedStrings[$key] = $zh }
    else {
        $extractedStrings[$key] = $key
        $missingStrings[$key] = $key
    }
}
$extractedEnums = @{}
$missingEnums = @{}
foreach ($typeName in $enums.Keys) {
    $extractedEnums[$typeName] = @{}
    $missingEnums[$typeName] = @{}
    foreach ($member in $enums[$typeName].Keys) {
        $zh = Get-TableEnum $typeName $member
        if ($zh) { $extractedEnums[$typeName][$member] = $zh }
        else {
            $extractedEnums[$typeName][$member] = $member
            $missingEnums[$typeName][$member] = $member
        }
    }
    if ($missingEnums[$typeName].Count -eq 0) { $missingEnums.Remove($typeName) }
}

if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}
Write-StringMapJson (Join-Path $OutDir 'extracted.json') $extractedStrings $extractedEnums
Write-StringMapJson (Join-Path $OutDir 'missing.json') $missingStrings $missingEnums
Write-Host ("strings: {0}   missing strings: {1}" -f $extractedStrings.Count, $missingStrings.Count)
```

`GetGroup` 只收方法体里的字符串，比较用的 `"Others"` 如果写在 `SortGroup` 里不会进来。类型名走 `new AssetType`。这和规格第 7 节一致。

- [ ] **Step 3: 在 `test-apply.ps1` 里断言**

在 Task 5 的 `FR2_WindowBase` 夹具 `Draw()` 里加上：

```csharp
Lable = "Unsed Asset";
```

新建 `tools/fixtures/FR2_RefEnums.cs`：

```csharp
namespace vietlabs.fr2
{
    public class FR2_RefDrawer
    {
        public enum Mode
        {
            Dependency,
            Type,
            None
        }

        void Pick()
        {
            var vv = (FR2_RefDrawer.Mode) EditorGUILayout.EnumPopup("Group", selected);
        }
    }
}
```

在 `test-apply.ps1` 里，`Copy-Item` 夹具之后、第一次 `apply.ps1` 之前插入：

```powershell
$beforeAssets = Join-Path $work 'Before\Assets'
New-Item -ItemType Directory -Path $beforeAssets -Force | Out-Null
Copy-Item -LiteralPath $plugin -Destination $beforeAssets -Recurse
$before = Join-Path $beforeAssets 'FindReference2'
```

在 `Write-Host 'apply test passed'` 之前插入。词表里已有的键必须出现在 `extracted.json`，不能出现在 `missing.json`。

```powershell
$extract = Join-Path $PSScriptRoot 'extract.ps1'
$beforeOut = Join-Path $work 'extract-before'
& $extract -PluginPath $before -OutDir $beforeOut
$missing = Get-Content -LiteralPath (Join-Path $beforeOut 'missing.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$extracted = Get-Content -LiteralPath (Join-Path $beforeOut 'extracted.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($key in @('Scan project', 'Uses', 'Direct Usage', 'Scene', 'Full Row click to Ping', 'Unsed Asset', 'Group')) {
    if (-not $extracted.strings.PSObject.Properties[$key]) { throw "extracted missing $key" }
    if ($missing.strings.PSObject.Properties[$key]) { throw "table key landed in missing.json: $key" }
}
foreach ($banned in @('Open', 'Refreshing ...', '.unity')) {
    if ($extracted.strings.PSObject.Properties[$banned]) { throw "extracted unexpectedly contains $banned" }
}
$mode = $extracted.enums.PSObject.Properties['FR2_RefDrawer.Mode']
if (-not $mode) { throw 'extracted enums missing FR2_RefDrawer.Mode' }
foreach ($member in @('Dependency', 'Type', 'None')) {
    if (-not $mode.Value.PSObject.Properties[$member]) { throw "Mode missing $member" }
}
if ($mode.Value.PSObject.Properties['Extension']) { throw 'fixture Mode must not invent Extension' }

$afterOut = Join-Path $work 'extract-after'
& $extract -PluginPath $plugin -OutDir $afterOut
$afterMissing = Get-Content -LiteralPath (Join-Path $afterOut 'missing.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($key in @('Scan project', 'Uses')) {
    if ($afterMissing.strings.PSObject.Properties[$key]) { throw "patched missing.json still has $key" }
}
```

- [ ] **Step 4: 跑测试**

```powershell
powershell -NoProfile -File "e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-apply.ps1"
powershell -NoProfile -File "e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-table.ps1" -TablePath "e:\软件\1AAAAA插件\Unity\FindReference2-CN\table\zh-CN.json"
```

Expected: 两个都通过。

- [ ] **Step 5: 提交**

```powershell
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" add tools/extract.ps1 tools/test-apply.ps1 tools/fixtures/FR2_RefEnums.cs
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" commit -m "Scan patched and unpatched sources for missing translations."
```

---

### Task 7: `revert.ps1`

**Files:**
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\revert.ps1`
- Modify: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-apply.ps1`

- [ ] **Step 1: 写 `tools/revert.ps1`**

```powershell
# Restore a Find Reference 2 folder from a FindReference2-CN backup zip.
#   .\revert.ps1 -PluginPath "D:\...\Assets\FindReference2"
#   .\revert.ps1 -PluginPath "..." -BackupZip "D:\...\FindReference2_20260922_180000.zip"
param(
    [Parameter(Mandatory = $true)][string]$PluginPath,
    [string]$BackupZip
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$pluginRoot = Resolve-PluginPath $PluginPath
$projectRoot = Find-UnityProjectRoot $pluginRoot
$backupBase = if ($projectRoot) { Split-Path -Parent $projectRoot } else { Split-Path -Parent $pluginRoot }
$backupDir = Join-Path $backupBase 'FindReference2-CN-backups'

if (-not $BackupZip) {
    $latest = Get-ChildItem -LiteralPath $backupDir -Filter 'FindReference2_*.zip' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { throw "No backup zip in $backupDir" }
    $BackupZip = $latest.FullName
}
if (-not (Test-Path -LiteralPath $BackupZip)) { throw "Backup zip not found: $BackupZip" }

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("fr2cn-revert-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    Expand-Archive -LiteralPath $BackupZip -DestinationPath $temp -Force
    $child = @(Get-ChildItem -LiteralPath $temp -Directory)
    if ($child.Count -ne 1) { throw "Expected one root folder in $BackupZip" }
    $parent = Split-Path -Parent $pluginRoot
    $destName = Split-Path -Leaf $pluginRoot
    if ($child[0].Name -ne $destName) { throw "Zip root '$($child[0].Name)' is not '$destName'" }
    Remove-Item -LiteralPath $pluginRoot -Recurse -Force
    Move-Item -LiteralPath $child[0].FullName -Destination (Join-Path $parent $destName)
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Write-Host "Restored $pluginRoot from $BackupZip"
```

`Compress-Archive -Path $pluginRoot` 会把文件夹名放进 zip 根上。还原时要求这个名字和当前插件目录名一致，避免把别的目录盖进来。

- [ ] **Step 2: 扩展 `test-apply.ps1`**

第二次 apply 必须带 `-NoBackup`（Task 5 的脚本已经这样写）。否则第二次备份会把已打补丁的目录压成最新 zip，默认还原就会还原成中文版。

在 extract 断言之后、`Write-Host 'apply test passed'` 之前插入：

```powershell
Assert-Has $window 'FR2Loc.Button("Scan project")'
& (Join-Path $PSScriptRoot 'revert.ps1') -PluginPath $plugin
Assert-Has $window 'protected static GUIContent[] TOOLBARS'
Assert-Lacks $window 'FR2Loc'
if (Test-Path -LiteralPath (Join-Path $scriptDir 'Localization')) {
    throw 'revert left the Localization folder in place'
}
```

备份是在写入 Localization 之前打的。如果还原后 Localization 还在，说明 `apply.ps1` 先注入后压缩了，把压缩挪到注入前面。

- [ ] **Step 3: 跑测试**

```powershell
powershell -NoProfile -File "e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-apply.ps1"
```

Expected: `apply test passed`，并且假工程被还原成未打补丁的样子。

- [ ] **Step 4: 提交**

```powershell
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" add tools/revert.ps1 tools/test-apply.ps1
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" commit -m "Restore the plugin directory from the newest backup zip."
```

---

### Task 8: README

**Files:**
- Create: `e:\软件\1AAAAA插件\Unity\FindReference2-CN\README.md`

- [ ] **Step 1: 写 README**

用中文，覆盖这些事实，不要写还没做的 GitHub 地址：

- 这是 Find Reference 2 v2.4.3 编辑器窗口的中文补丁，不含插件源码
- 安装：`.\tools\apply.ps1 -PluginPath "<工程>\Assets\FindReference2"`
- 会先在 Unity 工程外的 `FindReference2-CN-backups` 做 zip
- 开关在 `Tools/Find Reference 2/中文界面`，重载词表在旁边那一项
- 覆盖：窗口页签、按钮、提示、设置、类型筛选、分组标题、Group/Sort 下拉。悬停看英文
- 不覆盖：资源名、路径、GUID、进度条、`Window/Find Reference 2`、`Assets/FR2` 右键、分组标题上的右键
- 升级：覆盖安装新版后 `extract.ps1`，把 `out\missing.json` 补进 `table\zh-CN.json`，再 `apply.ps1`
- 还原：`revert.ps1 -PluginPath ...`
- 词表测试：`test-table.ps1 -TablePath table\zh-CN.json`
- 已知上限：文件夹名如果刚好等于 `Scene`、`Selection` 这类键，分组标题会被译成中文；`Filter` / `Ignore` 按钮宽度仍是 50 和 60
- 工具脚本是 ASCII。PowerShell 5.1 会把无 BOM 的 ps1 当 GBK 读

- [ ] **Step 2: 再跑一遍自动测试，确认 README 没有被脚本误扫**

```powershell
powershell -NoProfile -File "e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-table.ps1" -TablePath "e:\软件\1AAAAA插件\Unity\FindReference2-CN\table\zh-CN.json"
powershell -NoProfile -File "e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\test-apply.ps1"
```

Expected: 都通过。

- [ ] **Step 3: 提交**

```powershell
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" add README.md
git -C "e:\软件\1AAAAA插件\Unity\FindReference2-CN" commit -m "Document how to apply, refresh, and revert the Chinese patch."
```

不要 `git push`。

---

### Task 9: 打进 ZenaClient 并人工看窗口

**Files:**
- Modify: `d:\Unityfile\Pet\ZenaClient\Assets\FindReference2\Editor\Script\*.cs`（由 apply 改写）
- Create: `d:\Unityfile\Pet\ZenaClient\Assets\FindReference2\Editor\Script\Localization\*`（由 apply 拷入）

这一步会改游戏工程里的插件。自动测试已经过了才做。备份 zip 会出现在 `d:\Unityfile\Pet\FindReference2-CN-backups\`，不在 Assets 里。

- [ ] **Step 1: 对真插件先扫一遍漏译**

```powershell
powershell -NoProfile -File "e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\extract.ps1" -PluginPath "d:\Unityfile\Pet\ZenaClient\Assets\FindReference2"
```

打开 `out\missing.json`。规格第 6 节列出的键如果出现在 missing 里，先补进 `table\zh-CN.json` 并再跑 `test-table.ps1`，然后再 apply。进度条、菜单、资源名如果出现，说明 extract 扫宽了，收紧 extract，不要为了清掉 missing 去翻译它们。打补丁前，提交按钮是拼接的，extract 会扫出残片 `Commit Selection [`。这条不要当漏译去翻译，词表里已经有 `Commit Selection [{0}]`。

- [ ] **Step 2: 打补丁**

```powershell
powershell -NoProfile -File "e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\apply.ps1" -PluginPath "d:\Unityfile\Pet\ZenaClient\Assets\FindReference2"
```

Expected: 日志里 `FR2_WindowBase.cs`、`FR2_Ref.cs`、`FR2_AssetType.cs` 被 patch。四条钩子都没有 `Hook not found`。然后立刻再跑一次同一条命令。Expected: 这些文件变成 `already patched`，`Localization` 里的三个文件被覆盖拷贝，但插件脚本的 `FR2Loc.Button` 没有变成 `FR2Loc.FR2Loc.Button`。

抽查 `FR2_WindowBase.cs` 仍含 `menu.AddItem(new GUIContent("Refresh")` 这种原文，右键菜单没被改。`FR2_Asset.cs` 里 `GUI.Label` 画资源名的调用仍然是 `GUI.Label`。

- [ ] **Step 3: 回 Unity 看编译和界面**

打开 ZenaClient，等编译结束。Console 没有 `FR2Loc` 相关的 CS 错误。

然后对着窗口看：

- 中文：页签、`扫描工程` / `启用`、提示、设置项、类型筛选（场景、预制体）、分组标题（选择、直接引用、类型名）、分组和排序下拉
- 英文：资源名、路径、进度条、`Window/Find Reference 2`、`Assets/FR2` 右键、分组标题上的右键
- `Tools/Find Reference 2/中文界面` 关掉后立刻全英文，再打开立刻中文。悬停中文页签能看到 `Uses` 这类英文
- 文件夹分组标题仍是路径

`HelpBox` 如果因为没有 `GUIContent` 重载而编译失败，按 Task 3 的退路改 `FR2Loc.HelpBox`，只对这个控件去掉 tooltip，然后重新拷贝 `FR2Loc.cs`（再跑一次 apply，它会覆盖 Localization，已改写的插件文件会跳过）。

- [ ] **Step 4: 确认能还原，然后决定要不要重新打上**

```powershell
powershell -NoProfile -File "e:\软件\1AAAAA插件\Unity\FindReference2-CN\tools\revert.ps1" -PluginPath "d:\Unityfile\Pet\ZenaClient\Assets\FindReference2"
```

确认 `FR2_WindowBase.cs` 回到 `new GUIContent("Uses")`。界面验收要用中文的话，再跑一次 `apply.ps1`。不要提交 ZenaClient 里的插件改动，除非用户另外要求。

- [ ] **Step 5: 不推 GitHub**

补丁仓库停在本地。用户明确说要推之后再推。
