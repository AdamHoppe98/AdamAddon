# AdamAddon

A personal WoW Forever addon. It opens a window from the minimap icon or with `/adam`, and each feature gets its own page in that window.

## Install on the gaming PC (first time)

1. Find the WoW Forever game folder and open `Interface\AddOns` inside it. Create `AddOns` if it doesn't exist.
2. Clone the repo straight into it. The folder must be called `AdamAddon`:

   ```
   cd "<WoW Forever folder>\Interface\AddOns"
   git clone https://github.com/AdamHoppe98/AdamAddon.git AdamAddon
   ```

3. Start the game. On the character screen, open **AddOns** and make sure AdamAddon is enabled. If it says "out of date", tick **Load out of date AddOns** and see the Interface version step below.

## Update

```
cd "<WoW Forever folder>\Interface\AddOns\AdamAddon"
git pull
```

Then type `/reload` in game.

## Interface version

The `## Interface:` number in `AdamAddon.toc` has to match the game. To find it, type this in game:

```
/dump select(4, GetBuildInfo())
```

Put that number in the TOC, or give it to Claude.

## In game

| Command | What it does |
| --- | --- |
| `/adam` | Opens or closes the window |
| `/adam help` | Lists all commands |
| `/adam minimap` | Shows or hides the minimap icon |
| `/adam reset` | Moves the window back to the center |
| `/adam <feature>` | Opens the window on that feature's page, e.g. `/adam welcome` |

Left-click the minimap icon to open the window, and drag it to move it around the minimap. AdamAddon is also listed in Blizzard's addon menu on the minimap.

## Layout

```
AdamAddon.toc          load order and saved settings
Core.lua               namespace, events, feature registry, saved settings
Commands.lua           /adam command router
UI/MainWindow.lua      the window and its feature menu
UI/MinimapButton.lua   minimap icon and addon-menu entry
Features/*.lua         one file per feature (Welcome.lua is the example)
```
