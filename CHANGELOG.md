# Changelog

## 0.1.18 - 2026-08-27

Opening Skills and Connectors no longer stalls the window.

- Catalog load moved off the main thread, with a 90s memory cache and `~/.grok/desktop/catalog-cache.json`.
- Switching back to the page reuses the cache instead of running `grok inspect` again.
- Skill cards render in lazy rows instead of building the whole grid at once.

## 0.1.17 - 2026-08-27

Skills, connectors, workflows, and the inspector now follow what grok actually loads.

- Skills page reads `grok inspect` (user, bundled, and plugin skills), not only `~/.grok/skills`. Clicking a skill sends `/slug`.
- Connectors list inherited Claude/plugin MCP servers. Those are view-only; only grok-native servers can be toggled or removed.
- Add project is a `+` on the Projects header.
- Workflows open on Saved. Creating a script no longer auto-runs. Runs reconcile session `workflows/` folders and live tasks, so stale "running" rows complete.
- Inspector keeps this turn, context, tasks, terminals, and diffs. Workflows and personas left the right rail. Live work is one Now list.

## 0.1.16 - 2026-08-26

- Drag-select or double-click text in a Build conversation copies it and flashes Copied.

## 0.1.15 - 2026-08-24

- Sidebar history groups chats under project folders.
