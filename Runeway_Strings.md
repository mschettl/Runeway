# Runeway – sichtbare Texte (Basis für die Lokalisierung)

Alle Texte, die der Spieler sieht. Englisch ist die Quellsprache. Englisch und Deutsch sind von Mario abgestimmt; `scripts/make_locales.py` erzeugt daraus `Runeway/Locales/enUS.lua` und `deDE.lua`. Weitere Sprachen liegen als eigene Dateien in `Runeway/Locales/`. Der Schlüssel wird später im Code verwendet (`L.KEY`); er bleibt in allen Sprachen gleich.

Nicht übersetzt werden: der Addon-Name „Runeway“, Slash-Befehle und ihre Argumente (`/rnw config`, `mode mapkey` …), Ebenen-Namen in Befehlen (`fill`, `hatch` …) sowie reine Entwickler-Ausgaben (Abschnitt 6).

## WoW-Client-Sprachen (`GetLocale()`)

| Code | Sprache | Hinweis |
|---|---|---|
| `enUS` | Englisch | auch für englische EU-Clients (es gibt kein eigenes `enGB`) |
| `deDE` | Deutsch | |
| `frFR` | Französisch | |
| `esES` | Spanisch (Europa) | |
| `esMX` | Spanisch (Lateinamerika) | |
| `itIT` | Italienisch | |
| `ptBR` | Portugiesisch (Brasilien) | auch für portugiesische EU-Clients (`ptPT` meldet `ptBR`) |
| `ruRU` | Russisch | |
| `koKR` | Koreanisch | eigene Schrift; Texte werden länger/kürzer, Layout prüfen |
| `zhCN` | Chinesisch (vereinfacht) | eigene Schrift |
| `zhTW` | Chinesisch (traditionell) | eigene Schrift |

Ob WoW Forever alle Sprachen ausliefert, ist im Client zu prüfen; der Code fällt für unbekannte Sprachen auf Englisch zurück.

Stand: Englisch und Deutsch abgestimmt (Tabellen unten). Die übrigen neun Sprachen sind KI-Übersetzungen in `Runeway/Locales/<code>.lua`, noch ohne Prüfung durch Muttersprachler.

## 1. Optionen – Abschnitte

| Schlüssel | Englisch | Deutsch |
|---|---|---|
| `VERSION` | Version %s | Version %s |
| `INTRO` | Runeway shows a player-centred, rotating overlay map: walkable areas, terrain and water lines, roads, and the quest areas of your current and adjacent zones. Open it with its own key, the map key or permanently. All settings are in the sub-entries on the left. | Runeway zeigt eine spielerzentrierte, mitdrehende Overlay-Karte: begehbare Bereiche, Gelände- und Wasserlinien, Wege sowie die Questbereiche deiner aktuellen und der angrenzenden Zonen. Öffnen lässt sie sich über eine eigene Taste, die Kartentaste oder dauerhaft. Alle Einstellungen findest du in den Unterpunkten links. |
| `MAP_SHOW` | Show map | Karte einblenden |
| `MAP_HIDE` | Hide map | Karte ausblenden |
| `HEADER_COMMANDS` | Quick commands | Schnellbefehle |
| `HEADER_OPEN` | Open with | Öffnen mit |
| `HEADER_AUTOHIDE` | Hide automatically | Automatisch ausblenden |
| `HEADER_WINDOW` | Window | Fenster |
| `HEADER_DISPLAY` | Display | Darstellung |
| `HEADER_LAYERS` | Layers | Ebenen |

## 1a. Optionen – Schnellbefehle

Links steht der Befehl (bleibt in allen Sprachen gleich), rechts die übersetzte Beschreibung.

| Schlüssel | Befehl | Englisch | Deutsch |
|---|---|---|---|
| `CMD_TOGGLE` | /rnw | Show or hide the overlay | Overlay ein- oder ausblenden |
| `CMD_CONFIG` | /rnw config | Open these settings | Diese Einstellungen öffnen |
| `CMD_LOCK` | /rnw lock \| unlock | Lock (clicks pass through) or unlock the map | Karte sperren (Klicks gehen durch) oder entsperren |
| `CMD_ALPHA` | /rnw alpha 5-100 | Map opacity in percent | Kartendeckkraft in Prozent |
| `CMD_ZOOM` | /rnw zoom 0-100 | Zoom | Zoom |
| `CMD_SIZE` | /rnw size W [H] | Map width and height in pixels (200-1400) | Kartenbreite und -höhe in Pixeln (200-1400) |
| `CMD_ROTATE` | /rnw rotate | Rotate with the player or north up | Mit dem Spieler drehen oder Norden oben |
| `CMD_EDGE` | /rnw edge 0-100 | Soft edge strength | Stärke des weichen Rands |
| `CMD_MODE` | /rnw mode key \| mapkey \| permanent | How the overlay opens | Wie das Overlay geöffnet wird |
| `CMD_LAYER` | /rnw layer NAME | Show or hide a layer: fill, hatch, shade, terrain, water, roads, questareas | Ebene ein- oder ausblenden: fill, hatch, shade, terrain, water, roads, questareas |
| `CMD_COLOR` | /rnw color NAME R G B [A] | Layer colour and opacity, values 0-1 | Farbe und Deckkraft einer Ebene, Werte 0-1 |
| `CMD_KEYS` | /rnw keys | Show what the map key triggers | Anzeigen, was die Kartentaste auslöst |
| `CMD_POS` | /rnw pos | Position and map ID to copy | Position und Karten-ID zum Kopieren |
| `CMD_VIEW` | /rnw view [ZONE \| N W] | View mode at an area or position, drag to pan; without a value on/off at the player | Ansichtsmodus bei einem Gebiet oder einer Position, Ziehen verschiebt; ohne Angabe ein/aus beim Spieler |
| `CMD_RESET` | /rnw reset | Reset all settings | Alle Einstellungen zurücksetzen |

## 2. Optionen – Öffnen mit

| Schlüssel | Englisch | Deutsch |
|---|---|---|
| `OPEN_WITH` | Open with | Öffnen mit |
| `MODE_KEY` | Own key | Eigene Taste |
| `MODE_KEY_TIP` | Overlay on its own key binding (Toggle overlay map). The map key stays the world map. | Overlay auf eigener Tastenbelegung („Overlay-Karte ein/aus“). Die Kartentaste bleibt die Weltkarte. |
| `MODE_MAPKEY` | Map key (M) | Kartentaste (M) |
| `MODE_MAPKEY_TIP` | The world map key opens the overlay. The world map moves to the key bound to "World map". | Die Weltkarten-Taste öffnet das Overlay. Die Weltkarte liegt dann auf der Taste der Belegung „Weltkarte“. |
| `MODE_PERMANENT` | Permanent | Dauerhaft |
| `MODE_PERMANENT_TIP` | The overlay is always shown (except when auto-hidden). | Das Overlay ist immer sichtbar (außer beim automatischen Ausblenden). |

## 3. Optionen – Automatisch ausblenden, Fenster, Darstellung

| Schlüssel | Englisch | Deutsch |
|---|---|---|
| `HIDE_COMBAT` | In combat | Im Kampf |
| `HIDE_INSTANCE` | In instances | In Instanzen |
| `HIDE_MOUNTED` | Mounted, flying or on a taxi | Beritten, fliegend oder auf Flugroute |
| `HIDE_CITY` | In cities and inns (resting) | In Städten und Gasthäusern (erholt) |
| `ROTATE` | Rotate with the player | Mit dem Spieler drehen |
| `LOCKED` | Locked (clicks pass through) | Gesperrt (Klicks gehen durch) |
| `LOCKED_TIP` | Unlocked: drag to move, corner grip to resize. | Entsperrt: ziehen zum Verschieben, Ecke zum Vergrößern. |
| `WHEEL_ZOOM` | Zoom with the mouse wheel | Zoomen mit dem Mausrad |
| `WHEEL_ZOOM_TIP` | Scrolling over the map changes the zoom (with Shift and unlocked: the size). Off: the mouse wheel goes to the game camera. | Scrollen über der Karte ändert den Zoom (mit Shift und entsperrt: die Größe). Aus: Das Mausrad steuert die Spielkamera. |
| `HEIGHT` | Height | Höhe |
| `WIDTH` | Width | Breite |
| `MAP_OPACITY` | Map opacity | Kartendeckkraft |
| `ZOOM` | Zoom (outdoors) | Zoom (Außenbereiche) |
| `ZOOM_INSIDE` | Zoom (interiors) | Zoom (Innenbereiche) |
| `ZOOM_INSIDE_TIP` | Zoom inside cities, caves and other interior maps. The mouse wheel changes the zoom of the area you are in. | Zoom in Städten, Höhlen und anderen Innenkarten. Das Mausrad ändert den Zoom des Bereichs, in dem du gerade bist. |
| `NEIGHBOUR_ZONES` | Adjacent zones opacity | Deckkraft angrenzender Zonen |
| `NEIGHBOUR_ZONES_TIP` | Opacity of the adjacent zones, relative to the zone you are in. | Deckkraft der angrenzenden Zonen, bezogen auf die Zone, in der du bist. |
| `MAP_SHAPE` | Map shape | Kartenform |
| `MAP_SHAPE_TIP` | 0 %: the map fills the window, 50 %: oval, 100 %: circle. Follows the width and height of the window. | 0 %: Die Karte füllt das Fenster, 50 %: oval, 100 %: Kreis. Richtet sich nach Breite und Höhe des Fensters. |
| `SOFT_EDGE` | Soft edge | Weicher Rand |
| `SOFT_EDGE_TIP` | How softly the map fades out at its edge. 0 %: hard edge. | Wie weich die Karte an ihrem Rand ausläuft. 0 %: harte Kante. |
| `PLAYER_ARROW` | Player arrow | Spielerpfeil |
| `QUEST_MARKS` | Quest icons | Questsymbole |
| `CORPSE_MARKER` | Corpse | Leichnam |
| `FLIGHT_MASTERS` | Flight masters | Flugmeister |
| `MARKER_SIZE` | %s size | %s – Größe |
| `QUEST_CLASSIC` | Classic quest icons | Klassische Questsymbole |
| `QUEST_CLASSIC_TIP` | Quest icons in the classic look: symbol on a round badge. Off: the modern icons with their own ring. | Questsymbole im klassischen Aussehen: Symbol auf rundem Hintergrund. Aus: die modernen Symbole mit eigenem Ring. |
| `QUEST_EDGE` | Quest area edge | Rand des Questbereichs |
| `QUEST_MERGE` | Merge overlapping areas | Überlagerte Bereiche bündeln |
| `QUEST_MERGE_TIP` | Quests whose areas overlap get one shared outline. Off: every quest keeps its own outline. | Quests mit überlappenden Bereichen erhalten einen gemeinsamen Umriss. Deaktiviert: jede Quest behält ihren eigenen Umriss. |

Werte-Formate (bleiben meist gleich): `%d px`, `%d %%`, `%.2f`, `%.2f x`.

## 3a. Optionen – Profil

| Schlüssel | Englisch | Deutsch |
|---|---|---|
| `HEADER_PROFILE` | Profile | Profil |
| `PROFILE_INTRO` | Export your settings as text, for example before a reinstall, and import them again later. An import replaces all current settings. Key bindings are not part of the profile. | Exportiere deine Einstellungen als Text, zum Beispiel vor einer Neuinstallation, und importiere sie später wieder. Ein Import ersetzt alle aktuellen Einstellungen. Tastenbelegungen sind nicht Teil des Profils. |
| `PROFILE_EXPORT_TITLE` | Export profile | Profil exportieren |
| `PROFILE_IMPORT_TITLE` | Import profile | Profil importieren |
| `PROFILE_EXPORT` | Export | Exportieren |
| `PROFILE_IMPORT` | Import | Importieren |
| `PROFILE_EXPORT_HINT` | Copy the text with Ctrl+C and keep it somewhere safe. | Kopiere den Text mit Strg+C und bewahre ihn sicher auf. |
| `PROFILE_IMPORT_HINT` | Paste a profile text with Ctrl+V and click Import. All current settings are replaced. | Füge einen Profiltext mit Strg+V ein und klicke auf Importieren. Alle aktuellen Einstellungen werden ersetzt. |
| `PROFILE_IMPORTED` | Profile imported (%d settings). | Profil importiert (%d Einstellungen). |
| `PROFILE_INVALID` | This is not a valid Runeway profile. | Das ist kein gültiges Runeway-Profil. |

## 4. Optionen – Ebenen

Je Ebene eine Zeile: Name mit Häkchen, Farbfeld und Deckkraft-Regler. „… opacity“ und „… colour“ erscheinen als Tooltip von Regler und Farbfeld.

| Schlüssel | Englisch | Deutsch |
|---|---|---|
| `LAYER_FILL` | Walkable area | Begehbare Bereiche |
| `LAYER_HATCH` | Not walkable (hatching) | Nicht begehbar (Schraffur) |
| `LAYER_SHADE` | Dark edge | Dunkle Kante |
| `LAYER_TERRAIN` | Terrain lines | Geländelinien |
| `LAYER_WATER` | Water lines | Wasserlinien |
| `LAYER_ROADS` | Roads | Wege |
| `LAYER_QUESTAREAS` | Quest areas | Questbereiche |
| `LAYER_OPACITY` | %s opacity | %s – Deckkraft |
| `LAYER_COLOUR` | %s colour | %s – Farbe |

## 5. Tastenbelegung, Karte, Chat

| Schlüssel | Wo | Englisch | Deutsch |
|---|---|---|---|
| `BINDING_TOGGLE` | Tastenbelegung | Toggle overlay map | Overlay-Karte ein/aus |
| `BINDING_WORLDMAP` | Tastenbelegung | World map (map key mode) | Weltkarte (Modus Kartentaste) |
| `WORLDMAP_BUTTON` | Knopf auf der Weltkarte | Overlay | Overlay |
| `LOADED` | Chat beim Login | v%s loaded. | v%s geladen. |
| `NO_POSITION` | Statuszeile der Karte | No position (instance?) | Keine Position (Instanz?) |
| `NO_DATA` | Statuszeile der Karte | No contours for this area yet | Für dieses Gebiet gibt es noch keine Karte |
| `PACK_FAILED` | Chat, wenn für die aktuelle Karte keine Daten geladen werden können (Paket fehlt, ist deaktiviert oder existiert noch nicht); 1. %s = Paketname (Titel in der Client-Sprache ohne „Runeway - “, sonst Name des Kontinents), 2. %s = Gebiet; die Karte bleibt dann ausgeblendet | Data from pack %s not found. Map data could not be loaded for %s. | Daten aus Paket %s nicht gefunden. Kartendaten konnten für %s nicht geladen werden. |
| `PACK_TIP_ADDON` | Tooltip des Paket-Links im Chat (Ordnername des Pakets) | Data pack: %s | Datenpaket: %s |
| `PACK_TIP_STATUS` | Tooltip des Paket-Links (Grund in der Client-Sprache von Blizzard) | Status: %s | Status: %s |
| `PACK_TIP_HINT` | Tooltip des Paket-Links, Hinweis zur Behebung (Ordnername) | Install the folder %s in Interface\AddOns, enable it in the addon list (character selection > AddOns) and restart WoW. | Ordner %s in Interface\AddOns installieren, in der Addon-Liste aktivieren (Charakterauswahl > AddOns) und WoW neu starten. |
| `VIEW_MODE` | Statuszeile der Karte im Ansichtsmodus | View mode: drag to pan, /rnw view returns to the player | Ansichtsmodus: Ziehen verschiebt, /rnw view kehrt zum Spieler zurück |
| `NO_MASKS` | Chat beim Laden | Note: this client does not support mask textures, the edge is clipped hard. | Hinweis: Dieser Client unterstützt keine Maskentexturen, der Rand wird hart abgeschnitten. |
| `MSG_LOCKED` | Chat `/rnw lock` | locked (clicks pass through) | gesperrt (Klicks gehen durch) |
| `MSG_UNLOCKED` | Chat `/rnw unlock` | unlocked | entsperrt |
| `MSG_OPACITY` | Chat `/rnw alpha` | Opacity %d %% | Deckkraft %d %% |
| `MSG_ZOOM` | Chat `/rnw zoom` | Zoom %d %% | Zoom %d %% |
| `MSG_SIZE` | Chat `/rnw size` | Size %d x %d | Größe %d x %d |
| `MSG_ROTATE_ON` | Chat `/rnw rotate` | map rotates with the player | Karte dreht mit dem Spieler |
| `MSG_ROTATE_OFF` | Chat `/rnw rotate` | north up | Norden oben |
| `MSG_EDGE` | Chat `/rnw edge` | Soft edge %d %% | Weicher Rand %d %% |
| `MSG_MODE` | Chat `/rnw mode` | mode %s | Modus %s |
| `MSG_LAYER_SHOWN` | Chat `/rnw layer` | %s shown | %s eingeblendet |
| `MSG_LAYER_HIDDEN` | Chat `/rnw layer` | %s hidden | %s ausgeblendet |
| `MSG_COLOUR` | Chat `/rnw color` | %s colour %.2f %.2f %.2f, opacity %.2f | %s Farbe %.2f %.2f %.2f, Deckkraft %.2f |
| `MSG_RESET` | Chat `/rnw reset` | settings reset | Einstellungen zurückgesetzt |
| `MSG_VIEW` | Chat `/rnw view` | view mode at %s | Ansichtsmodus bei %s |
| `MSG_VIEW_OFF` | Chat `/rnw view` | back to the player | zurück zum Spieler |
| `MSG_VIEW_UNKNOWN` | Chat `/rnw view` | unknown area. Mapped areas: %s | Unbekanntes Gebiet. Kartierte Gebiete: %s |
| `USAGE_COLOR` | Chat, Hilfe | /rnw color fill\|hatch\|shade\|terrain\|water\|roads\|questareas R G B [A]   (0-1) | (Befehl bleibt, nur ggf. „(0-1)“) |
| `USAGE` | Chat, Hilfe | /rnw [toggle] \| config \| lock \| unlock \| alpha 5-100 \| zoom 0-100 \| size W [H] \| rotate \| edge 0-100 \| mode key\|mapkey\|permanent \| layer NAME \| color NAME R G B [A] \| keys \| pos \| view [ZONE \| N W] \| reset | (Befehle bleiben englisch) |

Das Leichnam-Symbol selbst zeigt keinen Text; das Symbol stammt aus dem Spiel.

## 6. Entwickler-Ausgaben (bleiben Englisch)

- `/rnw keys`: „mode %s, world map key %s“, „TOGGLEWORLDMAP keys: …“, „%s -> %s (without overrides: %s)“
- Taint-Diagnose: „ADDON_ACTION_BLOCKED: %s“ / „ADDON_ACTION_FORBIDDEN: %s“
- `/rnw probe`: „probe is a dev tool (tools/Probe.lua), not loaded“ und alle Ausgaben von `tools/Probe.lua`
- `/rnw pos`: Positionszeile zum Kopieren
