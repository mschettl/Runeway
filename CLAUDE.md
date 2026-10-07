# Runeway – working conventions

- Communication with Mario: German, short and technically precise.
- Development language: English. Code, identifiers, comments, file names, commit messages,
  chat output, slash commands and UI texts are English.
- This includes test tooling: test/probe commands, their chat output, saved test data,
  file and folder names for test results, and test step names use English terms.
- Tests run on Lua 5.1 (lupa.lua51) like the game: no goto, no integer division, use loadstring.
- Textures: SetAlpha overwrites the SetVertexColor alpha; set opacity only through SetVertexColor.
- Named movable frames: WoW restores size/position from its layout cache; RunewayFrame uses
  SetDontSavePosition and re-applies RunewayDB size/position on PLAYER_ENTERING_WORLD.
- Lean code, iterate on the existing code instead of rewriting.
- Target client: WoW Forever (game type "camelot", Interface 16001), retail-based UI.
  Reference UI source: Gethe/wow-ui-source, branch `forever`.
- Raw wow.export data lives on the orphan branch `data` (folder `Wow export files/`), never on `main`.
