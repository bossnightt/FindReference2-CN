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
            Lable = "Unsed Asset";
            var vvv = (FR2_RefDrawer.Sort) EditorGUILayout.EnumPopup("Sort", s);
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
