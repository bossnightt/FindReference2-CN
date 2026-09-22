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
