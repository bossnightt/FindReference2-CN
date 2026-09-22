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
