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
            EditorGUILayout.HelpBox(T(message), type);
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
