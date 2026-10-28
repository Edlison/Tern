# Interface behavior

- Hover is the only expansion trigger. Completion updates a compact review indicator, without moving focus or expanding the notch.
- AppKit owns window size and a display-linked spring transition. The top edge stays fixed while width/height change. SwiftUI adds blur/fade/soft flip to the content, without a second window-position animation.
- The workspace and expanded list contain Current and History. Each row navigates directly; there are no nested delivery panels or full-delivery pages.
- Idle and active layouts are independent. Configured widths are 120–240 pt and 240–360 pt, respectively. Each widget has a fixed slot; strings and counts cannot change the frame. A physical camera cutout reserves extra safety space.
- Idle dots form a slowly drifting asymmetric field. Running dots stream in the active providers' colors. Reduce Motion freezes the field at a deterministic frame. Neither idle nor completed states create a green cross.
- Green points indicate pending review only. Provider colors are independent from the selected application theme.
- The Touch Bar-style editor supports drag, reorder, cross-zone movement, removal, cancellation, and immediate preview. Editing cannot mark sessions read.

Visual QA should use the labeled synthetic demo. Real agent titles, replies, paths, and hostnames must not appear in public screenshots. Test an empty list, multiple running providers, a review item, the four width boundaries, Reduce Motion, large fonts and a physical notch when that hardware is available.
