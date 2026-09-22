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
