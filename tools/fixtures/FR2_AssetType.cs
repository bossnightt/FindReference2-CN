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
