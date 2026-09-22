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
