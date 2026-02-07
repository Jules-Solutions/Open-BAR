# Feature: Widget Sidebar Toggle (KSP-style)

## Concept

A vertical sidebar on the screen edge with icon buttons for each TotallyLegal widget. Like Kerbal Space Program's toolbar - click icons to show/hide individual overlays and panels.

## Why

Currently there's no easy way to toggle individual overlays on/off during gameplay. You have to go into the Spring widget list. A sidebar gives instant access to show/hide any TotallyLegal widget without breaking game flow.

## Design

### Layout
```
┌──┐
│ T│  <- TotallyLegal logo / collapse toggle
├──┤
│OV│  <- Overlay (resource info)
├──┤
│GL│  <- Goals panel
├──┤
│TL│  <- Timeline graph
├──┤
│TH│  <- Threat display
├──┤
│PR│  <- Priority highlights
├──┤
│DG│  <- Auto-dodge status
├──┤
│SK│  <- Skirmish status
├──┤
│RZ│  <- Rezbot status
├──┤
│CF│  <- Config panel
├──┤
│MZ│  <- Map zones panel
├──┤
│  │  <- Level indicator (color-coded: grey/green/blue/gold)
└──┘
```

### Behavior
- Docked to right or left screen edge (configurable)
- Each button toggles visibility of the corresponding widget's UI
- Active widgets have lit/colored icons, inactive are dimmed
- The sidebar itself can collapse to just the TL logo
- Hover shows widget name tooltip
- Level indicator at bottom shows current automation level with color

### Widget Categories (visual grouping)
1. **Info** (always available): Overlay, Goals, Timeline, Threat, Priority
2. **Micro** (Level 1+): Dodge, Skirmish, Rezbot
3. **Macro** (Level 1+): Config, MapZones
4. Separator lines between categories

### Implementation Approach

**Option A: Single sidebar widget**
- New `gui_totallylegal_sidebar.lua` widget
- Reads WG.TotallyLegal to discover which widgets are loaded
- Each widget exposes a `visible` flag in its WG state section
- Sidebar toggles the flag; each widget checks it in DrawScreen/DrawInMiniMap

**Option B: Use Spring's widget:TweakMode**
- Spring has a built-in tweak mode for widget visibility
- But it's clunky and not game-flow friendly

**Recommendation: Option A** - gives us full control over UX.

### Required Changes

1. **New file:** `gui_totallylegal_sidebar.lua` (layer 99, below other GUIs)
2. **Each gui_* widget:** Add `visible` field to WG state, check in DrawScreen
3. **Each engine widget with UI:** Same pattern (config, mapzones)
4. **Core library:** Optionally expose widget registry for sidebar to discover

### State Contract Addition

```lua
-- Each widget with UI adds:
WG.TotallyLegal.Overlay = {
    visible = true,     -- sidebar toggles this
    -- ... existing state
}

-- Sidebar reads:
WG.TotallyLegal.WidgetRegistry = {
    { key = "Overlay",   name = "Resource Overlay",  icon = "OV", category = "info" },
    { key = "Goals",     name = "Goal Queue",        icon = "GL", category = "info" },
    -- etc.
}
```

### Open Questions
- Exact icon/label for each widget (2-char abbreviation? mini icon?)
- Screen edge: left or right? (right avoids conflict with BAR's build menu on left)
- Should it also control engine widgets (toggle on/off entirely)?
- Drag to reorder buttons?
- Keyboard shortcut to toggle sidebar itself?

## Priority

Nice-to-have for Phase 3 (when we have multiple working widgets to toggle). Could implement a basic version earlier as it's independent of the engine fixes.
