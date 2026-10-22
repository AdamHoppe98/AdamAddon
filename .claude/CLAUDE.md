# AdamAddon — ground rules

A World of Warcraft addon for **WoW Forever**. Development happens on a Mac that cannot run the game; the addon is tested on a Windows PC at home. Every change reaches the game via `git push` here → `git pull` on the PC → `/reload` in game.

## The game client

- **WoW Forever** is Blizzard's "Camelot" project: `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` (18). Its UI source lives on the **`forever` branch** of wow-ui-source, not `live`.
- It is built on the **Mainline (retail) UI family**: Blizzard's `[Family]` files resolve to `Mainline/`, with `[Game]` overrides in `Camelot/` folders. Use the modern retail API.
- **Midnight addon restrictions apply.** The client has secret values (`issecretvalue`, `canaccessvalue`) and the API docs carry `SecretArguments`/`SecretReturns`. Assume combat, unit and chat data can be secret in restricted contexts; never do arithmetic, comparisons or string ops on a value that may be secret without checking first. No combat automation, no protected calls from insecure code, nothing that touches secure frames in combat.

## Verify every API against wow-ui-source

Do not write a WoW API call, template, mixin, event or atlas from memory. Check it exists on the `forever` branch first:

- Repo: https://github.com/Gethe/wow-ui-source/tree/forever
- Version of the snapshot: `version.txt` at the branch root.
- Function signatures, events, secret-value flags: `Interface/AddOns/Blizzard_APIDocumentationGenerated/*Documentation.lua`
- Templates and mixins: grep `Interface/AddOns/` for `name="TemplateName"` / `function SomeMixin:`. When a file has both `Mainline/` and `Camelot/` versions, the Camelot one wins.
- A TOC line tagged `[AllowLoadGameType mainline] [ExcludeLoadGameType camelot]` means **not** loaded in WoW Forever.

Fastest route: a local shallow clone next to this repo, then grep it.

```sh
git clone --depth 1 --single-branch --branch forever https://github.com/Gethe/wow-ui-source.git ../wow-ui-source
git -C ../wow-ui-source pull   # refresh when a patch lands
```

If the clone is missing, fetch single files from `https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/<path>`.

When something can't be verified, say so in the reply instead of guessing.

## Output rules

- Always write **complete** `.toc` and `.lua` files. No `-- ... rest unchanged ...`, no fragments, no "add this to X". The user copies files to another machine; a partial file is a broken addon.
- Every new `.lua` file must be listed in `AdamAddon.toc`, in load order. Mention the TOC change in the reply.
- The TOC `## Interface:` number must match the client. It can only be read in game: `/dump select(4, GetBuildInfo())`. If it is unknown, keep the current value and remind the user to check.

## Code conventions

- One shared namespace: every file starts with `local addonName, ns = ...`. No new globals except the SavedVariables table, `SLASH_*`, and functions the TOC must name (e.g. `AddonCompartmentFunc`).
- Lua 5.1 as WoW ships it. No `goto`, no integer division `//`, no `table.unpack` (use `unpack`).
- Saved settings live in `AdamAddonDB` (declared in the TOC) and are only read after `ADDON_LOADED` for this addon.
- New features go in `Features/<Name>.lua` and plug into the existing core (module registry, slash router, main window) rather than adding their own frames, events and slash commands from scratch. Follow the pattern of the existing feature files.
- Prefer Blizzard templates and mixins over hand-built textures when one fits and is verified.

## How the template works (read before adding a feature)

Load order (`AdamAddon.toc`): `Core.lua` → `Commands.lua` → `UI/*` → `Features/*`.

- `Core.lua` — `ns:Print`, `ns:RegisterEvent/UnregisterEvent`, `ns:RegisterModule`, saved variables (`ns.db`). On `ADDON_LOADED` it fills defaults, gives each module its `module.db`, calls `OnInit`, then builds the window and minimap button. `OnLogin` runs on `PLAYER_LOGIN`.
- `Commands.lua` — `/adam` router. `ns:RegisterCommand(name, desc, func(args))`. `/adam <featurename>` opens that feature's page automatically.
- `UI/MainWindow.lua` — `ns.MainWindow:Show/Hide/Toggle/ShowPage(name)`. Every module with `CreatePage` gets a menu entry; the page frame is built lazily and `OnPageShown` fires each time it becomes visible.
- `UI/MinimapButton.lua` — minimap icon (angle saved in `ns.db.minimap`) and the TOC `AddonCompartmentFunc` global.

A new feature is one file, `Features/<Name>.lua`, added to the TOC under `# Features`:

```lua
local addonName, ns = ...

local Feature = ns:RegisterModule("Name", {
	title = "Menu label",
	order = 10,
	defaults = { },                 -- becomes Feature.db
	commands = { sub = { desc = "...", func = function(module, args) end } },
})

function Feature:OnInit() end       -- optional
function Feature:OnLogin() end      -- optional
function Feature:CreatePage(page) end   -- optional: gives it a page in the window
function Feature:OnPageShown(page) end  -- optional
-- Feature:RegisterEvent("EVENT_NAME", "MethodName" or function(module, event, ...) end)
```

`Features/Welcome.lua` is the working example.

## Testing

Nothing runs on the Mac. After a change, tell the user exactly what to try in game (`/reload`, which command, what they should see). If a Lua error appears in game, ask them to paste the full error text, including the stack.
