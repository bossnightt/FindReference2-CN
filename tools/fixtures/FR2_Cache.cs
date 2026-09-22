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
