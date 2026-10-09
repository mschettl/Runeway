# Runeway – Stand Version 0.6 und Übergabe

Diese Datei fasst den kompletten Stand zusammen, damit eine neue Session nahtlos weitermachen kann. Sie ersetzt den Chatverlauf. Vorgaben und Ziele stehen in `Runeway_Prompt_v1.md`, Arbeitsregeln in `CLAUDE.md`, alle sichtbaren Texte in `Runeway_Strings.md`.

---

## 1. Kurzüberblick

Runeway ist ein spielerzentriertes, mitdrehendes Karten-Overlay für **WoW Forever** (Interface 16001) im Stil von Path of Exile und Diablo IV.

**Funktionen (Stand 0.6, im Spiel getestet):**
- **Karte:** alle 27 Gebiete der Östlichen Königreiche aus den RAW-Spieldaten (Etappen 1–4, Abschnitt 8) mit begehbarer Fläche, Schraffur für nicht begehbare Bereiche, Gelände-, Wasser- und Weglinien; Ruinen von Lordaeron als Stadt. Angrenzende Zonen gedimmt, nahtloser Zoom, frei einstellbare Breite und Höhe, ovale Randausblendung.
- **Quests:** Questbereiche wie auf der Weltkarte (auch aus angrenzenden Zonen), Questmarker für Punktziele, Tooltips und Hervorhebung beim Überfahren.
- **Leichnam-Marker** im Tod, am Kartenrand in Richtung des Leichnams, wenn er außerhalb liegt.
- **Flugmeister** (0.6): aus `C_TaxiMap.GetTaxiNodesForMap` der nahen Zonenkarten (wie die Weltkarte), eigene Fraktion und neutral, auf der Oberfläche zusätzlich die Karten der Innenbereiche (Fledermausführer von Unterstadt liegt auf 1458), Icon (Mario per `/rnw taxi icons` gewählt): entdeckt `Taxi_Frame_Gray`, unentdeckt `Taxi_Frame_Green` (Knoten der Flugkarte); fehlt der Atlas: entdeckt Blizzards Weltkarten-Atlas des Knotens, unentdeckt grünes Taxi-Icon. Entdeckt: `isUndiscovered` ist im Client immer `false` (Spieltest: alle 36 Knoten der Östlichen Königreiche, auch fremde). Runeway merkt sich daher beim Öffnen der Flugkarte (`TAXIMAP_OPENED`) die bekannten Knoten (`TaxiNodeGetType` = "CURRENT"/"REACHABLE"; "DISTANT" sind Zwischenstationen fremder Routen, die Blizzards Flugkarte ausblendet: Spieltest Tarrens Mühle und Das Grabmal fälschlich als entdeckt; "DISTANT"/"NONE" löschen ältere Einträge) pro Charakter nach Name (`RunewayDB.taxiKnown["Name-Realm"]`); vorher gelten alle als unentdeckt. `GetTaxiNodesForMap(18)` ist leer, 1458 liefert den ganzen Kontinent; „zzOLD…“-Knoten werden ausgelassen. Nicht über `ShouldMapShowTaxiNodes` gefiltert (sagt nur, ob Blizzards Weltkarte sie auf dieser Karte zeigt). `SetAtlas` meldet einen unbekannten Atlas nicht (kein Rückgabewert, Textur bleibt leer), daher prüft `SetAtlasOr` vorher `C_Texture.GetAtlasInfo`. Diagnose: `/rnw taxi` (abgefragte Karten, Anzahl, bekannte Knoten, die fünf nächsten mit Entfernung, Status und Atlas). Tooltip mit Name (deDE: erster Buchstabe nach dem Komma groß, `TaxiName`; die Client-Daten schreiben „östliche Pestländer“) und bei unentdeckten Blizzards Text „Unentdeckter Flugpunkt“. Zeile „Flugmeister“ (`showTaxi` + Größe `taxiSize`, Standard 20 px) unter Display; aktualisiert bei `TAXIMAP_OPENED`/`TAXI_NODE_STATUS_CHANGED`.
- **Bedienung:** drei Aufruf-Modi (eigene Taste, Kartentaste M, dauerhaft), automatisches Ausblenden, gesperrt/klickdurchlässig oder verschiebbar, Mausrad-Zoom abschaltbar, Ansichtsmodus (`/rnw view`) zum Betrachten anderer Orte, Slash-Befehle.
- **Einstellungen** im Blizzard-Stil mit Unterpunkten, Profil-Export/-Import als Text, Lokalisierung in allen elf Client-Sprachen.

**Versionen:**

| Version | Inhalt |
|---|---|
| 0.0 | Tirisfal aus RAW-Daten, Ebenen, Questbereiche, Diablo-Look, Ruinen von Lordaeron |
| 0.1 | Einstellungsseite, Aufruf-Modi, automatisches Ausblenden, Fensterbedienung (Prompt 3.4) |
| 0.2 | Etappe 1 (fünf Zonen), Questbereiche und Dimmung angrenzender Zonen, kleinere Kacheln, glatte Wege, Leichnam-Marker, Tooltips, Breite/Höhe, neue Einstellungsstruktur, Englisch/Deutsch |
| 0.3 | Lokalisierung in elf Sprachen (außer Deutsch KI-Übersetzungen, Französisch im Spiel geprüft) |
| 0.4 | Profil-Export und -Import |
| 0.4.1 | Aufräumen (u. a. Fehler beim Hervorheben des Leichnams behoben), Version im Chat beim Login und oben in den Einstellungen |
| 0.5 | Östliche Königreiche komplett (27 Gebiete, Etappen 2–4), Block-Build, Kachelliste pro Karten-ID, Schraffur-Maske und Saum nur in 128 px, offenes Meer ausgeblendet, Ansichtsmodus `/rnw view` |
| 0.6 | Datenpakete (`Runeway_EasternKingdoms`, LoadOnDemand) mit Meldung bei fehlenden Kartendaten (Login/Reload/Zonenwechsel getrennt); Unterstadt und Zwischenmap der Ruinen als Innen-Kachelsätze mit eigenem Zoom; Flugmeister (entdeckt/unentdeckt); Questsymbole neu („?“ modern, „…“, klassisch per Option), Questbereiche kartenübergreifend gebündelt, Füllung beim Überfahren, Tooltips; Optionen: Kartenform (Rechteck–Oval–Kreis), weicher Rand in %, Marker-Zeilen mit Schalter und Größe, breitere Beschriftungen, neue Standardwerte; Rahmen beim Entsperren mit runden Ecken |
| 0.6.1 | Questbereiche: gebündelte Umrisse zerfallen im Kampf und beim Abschließen einer Quest der Gruppe nicht mehr in Einzelumrisse; nach dem Tod verschwindet kein Questbereich mehr (leeres Abtastergebnis wird wiederholt statt gespeichert, keine Abtastung im Tod) |

**Versionierung (seit 0.6, Mario):** drei Stellen. Vor dem Release 0.x.y: zweite Stelle = abgeschlossener, im Spiel getesteter Schritt, der nach `main` geht; dritte Stelle = Korrekturen ohne neue Funktion. Die früheren Versionen 1.0–1.6 heißen jetzt 0.0–0.6 (die Titel der alten PRs und Squash-Commits auf `main` tragen noch die alten Nummern). **1.0.0 = erstes öffentliches Release** (z. B. CurseForge); 2.0 = Route zum Questziel. Geplant: 0.7 Kalimdor, 0.8+ Städte, Höhlen/Minen, Dungeons.

---

## 2. Repository und Branches

| Branch | Inhalt |
|---|---|
| `main` | Freigegebener Stand, je Version ein PR (zuletzt 0.5). |
| `dev` | Entwicklungsbranch (Addon, Build-Skripte, Tests, diese Datei). |
| `data` (orphan) | Rohdaten aus wow.export, nie auf `main`. ~1,6 GB. |

**Inhalt von `data`** (Ordner `Wow export files/`):
- `maps/azeroth/`: ADT-Export der Östlichen Königreiche (736 Kacheln: Root, `_tex0`, `_obj0/1`, `_lod`), WDT/WDL, Minimap-PNGs von Tirisfal (26–34 / 26–29), `adt_<c>_<r>_ModelPlacementInformation.csv` (Modellplatzierungen).
- `AreaTable.csv`, `QuestPOIBlob.csv`, `QuestPOIPoint.csv`. Die beiden QuestPOI-Tabellen sind für Questbereiche unbrauchbar, siehe Abschnitt 6.
- `world/`: kompletter `world`-Ordner (WMO, M2, BLP). Genutzt werden bisher nur:
  - `world/wmo/autogen-names/undercity/` (OBJ-Export mit „Split WMO Groups“, 215 Gruppen, plus `20736.json`)
  - `world/generic/undead/passivedoodads/lordaerontowers/*.m2` (Türme der Stadtmauer)

**Daten holen** (in einem Checkout des Entwicklungsbranchs):
```bash
git fetch origin data
git restore --source=origin/data --worktree -- "Wow export files"
```
Der Ordner ist auf allen Code-Branches per `.gitignore` ausgeschlossen. Daten pflegen geht lokal mit `scripts/update_data_branch.ps1` oder über ein Worktree auf `data`.

---

## 3. Addon (Ordner `Runeway/`) und Datenpakete (`Runeway_<Kontinent>/`)

Seit 0.6 besteht das Release aus zwei Ordnern, die beide nach `Interface\AddOns` gehören: das Kern-Addon `Runeway` (Code, Medien, Texte) und je Kontinent ein Datenpaket, bisher `Runeway_EasternKingdoms` (Karte 0, ~78 MB).

| Datei | Inhalt |
|---|---|
| `Runeway.toc` | Interface 16001, Version 0.6.0, SavedVariables `RunewayDB`; lädt `Locales/*.lua`, `Core.lua`, `QuestAreas.lua`, `Profile.lua`, `Options.lua`, `Options.xml` |
| `Locales/` | Texte je Client-Sprache (`ns.L`): `enUS.lua` (Basis) und `deDE.lua` aus `Runeway_Strings.md` erzeugt, die übrigen neun von Hand gepflegt |
| `Core.lua` | Fenster, Kacheln, Zoom, Drehung, Zonen-Dimmung, Questmarker, Leichnam, Mouse-over, Sichtbarkeit und Aufruf-Modi, Slash-Befehle, Standardwerte |
| `QuestAreas.lua` | Questbereiche: Abtasten, Umriss, Zeichnen, Trefferprüfung für Mouse-over |
| `Profile.lua` | Profil-Export/-Import und sein Dialog; Pfad-Hilfen `ns.GetPath`/`ns.SetPath` |
| `Options.lua`, `Options.xml` | Einstellungen im Blizzard-Stil (`Settings.RegisterVerticalLayoutCategory` mit Proxy-Settings), eigene Zeilenvorlagen; wird bei `PLAYER_LOGIN` aufgebaut, weil die Tastenbelegungs-Zeilen `GetNumBindings` brauchen |
| `Runeway_<Paket>/Runeway_<Paket>.toc` | generiert von `build_raw.py` (`--toc` schreibt nur die `.toc`): `## Title`/`## Notes` mit `-<Locale>`-Varianten in allen elf Sprachen (offizielle Blizzard-Namen der Kontinente, `PACKS`), `## LoadOnDemand: 1`, `## Dependencies: Runeway`, `## X-Runeway-Maps: <Karten-ID>`, Interface und Version wie `Runeway.toc`; lädt `tiles\<id>\Tiles.lua` |
| `Runeway_<Paket>/tiles/<Karten-ID>/Tiles.lua` | generiert, je Karte: `RunewayTiles[id]` (Kacheln mit ihren Ebenen, `["31_28"] = "fhstwr"`, Grenzkacheln als Zonenteile `"c_r_z<zone>"`) und `RunewayZones[id]` |
| `Bindings.xml` | Tastenbelegungen `RUNEWAY_TOGGLE` und `RUNEWAY_WORLDMAP` |
| `media/` | `hatch512/256/128.tga` (gemeinsames Schraffurmuster je Zoomstufe, erzeugt von `build_raw.py`), `mask/s<0-5>f<0-10>.tga` (66 Ausblendmasken je Form- und Randstufe, `scripts/make_masks.py`, ~5,6 MB; geladen ist nur die aktive), `arrow.tga` (Spielerpfeil), `edge.tga` (kantengeglättete Linientextur), `dot.tga` (Rückfall-Symbol) |
| `Runeway_<Paket>/tiles/0/[256/ \| 128/]<key>_<layer>.tga` | weiße RLE-TGA-Kacheln je Ebene und Zoomstufe (512/256/128 px). Speicherbedarf siehe „Dateigröße“ unten |

`tools/Probe.lua` ist ein Entwicklungswerkzeug und nicht im Release (siehe Abschnitt 6).

### Innenraum-Kachelsätze (`Core.lua`, `TileSet`)
- Neben dem Kachelsatz der Karte (`tiles/0`) kann ein Paket Innenraum-Sätze `tiles/<set>/` enthalten, gleiche Weltkoordinaten und Kachelraster wie die Oberfläche, eigene `RunewayTiles[set]`/`RunewayZones[set]`. Bisher: `0-1458` = Undercity, `0-1458-ruins` = Thronsaal, Mausoleum, Aufzugsschächte, Torhaus, Glockentürme und Kanalisationsabgänge der Ruinen (Innen-Gruppen „Ruins of Lordaeron“).
- Regeln je Satz in `RunewayZones[set]`: `ui` (uiMap), `subzones` (nur in diesen Unterzonen und innerhalb des Grundrisses `inside`), `notSubzones` (nie in diesen), `inside` (Grundriss als Zellraster, `res` Zellen je Kachelseite: Undercity 16 ≈ 33 yd, Ruinen 64 ≈ 8 yd). `TileSet` nimmt den ersten Satz der uiMap, dessen Regeln gelten (Sätze mit `subzones` zuerst), sonst die Oberfläche. Index `SetsFor`, neu aufgebaut nach jedem Paket-Laden.
- Grund: Hof, Thronsaal, Aufzug und Stadt melden alle uiMap 1458 und Zone „Undercity“; `UnitPosition` liefert keine Höhe, die WMO-Gruppe ist für Addons nicht abfragbar. Unterzone „Ruins of Lordaeron“ (Area 153) + Position im Grundriss der Innen-Gruppen trennt Thronsaal/Aufzug (Zwischenkarte) vom Hof (Oberfläche); andere Unterzonen = Undercity. Im Spieltest schaltet die Minimap am Eingang des Thronsaals (66.0 32.8) um.
- Unterzonen-Vergleich: Name über `C_Map.GetAreaInfo(id)`, enthält-Prüfung ohne Groß-/Kleinschreibung, weil der Client „Die Ruinen von Lordaeron“ meldet. Die Satzwahl wird 0,2 s zwischengespeichert.
- Unten am Aufzug meldet der Client außerhalb des Schachts weiter die Unterzone „Ruinen“ (dauerhaft, z. B. beim Warten auf den Aufzug bei 65.9 54.1). Eine Höhe gibt es für Addons nicht (`UnitPosition` z = 0). Darum gilt `notSubzones` von Undercity nur auf der Außenfläche der Ruinen (`surfaceArea`: Bodenflächen der Außen-Gruppen „Ruins of Lordaeron“ = Hof, Rosengang, Außeneingang, Raster 64) oder außerhalb des Undercity-Grundrisses; sonst Undercity.
- Questbereiche und -marker (`NearbyMaps`): In einem Innenraum-Satz nur die uiMap des Innenraums, an der Oberfläche alle Zonen außer denen mit Innenraum-Sätzen. Die uiMap 1458 listet auch Tirisfal-Quests mit Gebiet (370/374): Im Innenraum gelten Bereiche und die Marker von Quests mit Gebiet nur innerhalb des Grundrisses (`ns.InChunks`); Abgabe- und Ansprech-Marker immer.
- `/rnw pos` zeigt den aktiven Satz (`set=`).

### Datenpakete laden (`Core.lua`, `PackOf`/`LoadPack`)
- **Zuordnung:** Beim ersten Bedarf liest der Kern alle installierten Addons (`C_AddOns.GetNumAddOns`/`GetAddOnInfo`) und deren Feld `X-Runeway-Maps` (Karten-IDs, durch Leerzeichen oder Komma getrennt). Paketnamen sind damit nicht im Code festgelegt; ein späteres Retail-Paket bräuchte zusätzlich eine Unterscheidung nach Spieltyp.
- **Laden:** `C_AddOns.LoadAddOn(paket)` einmal je Paket, sobald eine Karte gebraucht wird: bei `PLAYER_ENTERING_WORLD` (hinter dem Ladebildschirm), sonst beim ersten Kachelzugriff (`TileIndex`) bzw. bei `/rnw view <Gebiet>`. Kachelpfade: `Interface\AddOns\<paket>\tiles\<id>\…`.
- **Fehler:** Lädt das Paket der aktuellen Karte nicht (z. B. in der Addon-Liste deaktiviert), meldet der Chat „Data from pack <Name> not found. Map data could not be loaded for <Area>.“ (`L.PACK_FAILED`; Name = Titel des Pakets in der Client-Sprache ohne „Runeway - “, z. B. „Östliche Königreiche“). Der Name ist ein Addon-Link (`|Haddon:Runeway:pack:<Paket>|h[<Name>]|h`, Runeway-Blau); ein Klick zeigt im `ItemRefTooltip` Paket, Grund (Blizzard-Text `ADDON_<REASON>`) und Hinweis zur Behebung, ein zweiter Klick schließt ihn (`EventRegistry` „SetItemRef“). Im Spieltest öffnet der Client bei keinem Chat-Link einen Tooltip, auch ohne Runeway; Link-Darstellung (blau, eckige Klammern) reicht, Tooltip-Code bleibt für Clients, in denen Links funktionieren, beim Laden und bei jedem Öffnen der Karte. Die Karte bleibt ausgeblendet (`MissingPack` in `UpdateVisibility` und `Runeway_Toggle`), also auch keine Questbereiche, Marker oder Spielerpfeil; auf einer Karte mit Daten erscheint sie wieder. Bekanntes, aber nicht installiertes Paket (`KNOWN_PACKS` in Core.lua: Karte → Paket, Kontinent-uiMap für den Namen): wie ein nicht ladendes Paket (`PACK_FAILED`, Status `ADDON_MISSING`). Ohne Daten für die Karte (Kalimdor, Instanzen ohne Position): Karte ausgeblendet, einmal pro Karte dieselbe Meldung; Paketname = Name des Kontinents (`ContinentName`; in Instanzen der zuletzt besuchte Kontinent, da Dungeon-Karten nicht zum Kontinent führen – Flammenschlund hängt unter Orgrimmar). Gebiet in Instanzen = Instanzname (`GetInstanceInfo()`), aber nur wenn die Position auf der Karte dieser Instanz liegt und sie kein Kontinent ist (`WORLD_MAPS` 0/1/530/571): nach dem Verlassen nennen Name und Typ noch eine Weile den Dungeon (Spieltest), die Position ist schon zurück auf dem Kontinent. Die Meldung nach einem Kartenwechsel kommt nie während eines Ladebildschirms (`LOADING_SCREEN_ENABLED`/`_DISABLED`) und unterscheidet den letzten Ladebildschirm (`PLAYER_ENTERING_WORLD` isInitialLogin/isReloadingUi, Mario): Login = warten auf einen echten Zonennamen (kurz leer bzw. Kontinentname), Reload = sofort (0,5 s), Zonenwechsel (Dungeon rein/raus, Portal) = 1 s, echter Zonenname (auch hier kurz leer, Kontinentname oder noch der Name des verlassenen Dungeons, die Spielerkarte noch der Dungeon; Spieltest: je nach Ladezeit mal richtig, mal Ragefire) und bis die Instanz-ID aus `GetInstanceInfo()` zur Position passt; Name der Spielerkarte nur als Rückfall nach Ablauf; höchstens 15 s (`SayNoData`). `/rnw pos` zeigt die Werte beim letzten Hinweis. Umschalten meldet sofort. **Entscheidung (Mario, 0.6):** Dungeons und Raids kommen ins Paket ihres Kontinents (eigene Karten-IDs in `X-Runeway-Maps` und `KNOWN_PACKS`), kein eigenes Dungeon-Paket. Eine Meldung für alle Fälle (`L.PACK_FAILED`): „Daten aus Paket [Paket] nicht gefunden. Kartendaten konnten für [Gebiet] nicht geladen werden.“ (Gebiet = `GetZoneText()`), ein Umschalten wiederholt den Hinweis (Spieltest 0.6: vorher blieb die Karte mit Questgebieten und „No contours …“ sichtbar). „No contours for this area yet“ bleibt nur für Lücken innerhalb einer Karte mit Paket.

### Ebenen (Zeichenreihenfolge, Kennbuchstabe in `Tiles.lua`)
`fill` (f, begehbar) → `hatch` (h, Schraffur nicht begehbar) → `shade` (s, dunkler Saum) → `terrain` (t) → `water` (w) → `roads` (r). Darüber `questAreas` (Linien aus `QuestAreas.lua`), Questmarker und Spielerpfeil.

Kacheln sind weiß. Eingefärbt wird zur Laufzeit per `SetVertexColor`.

### Dateigröße
- **Gespeicherte Zoomstufen je Ebene** (`FILE_LODS` in `build_raw.py`, `FILE_LOD` in `Core.lua`): Linien (`terrain`, `water`, `roads`) in 512/256/128, `shade`, `hatch`-Maske und `fill` nur in 128 (weiche Flächen; seit Etappe 2, −34 % Dateigröße; bei starkem Zoom ist der Saum etwas breiter und weicher). Fallen zwei Zoomstufen auf dieselbe Datei, wird nicht überblendet.
- **Schraffur:** Die Kachel `128/<c>_<r>_hatch.tga` ist nur noch die Maske der nicht begehbaren Fläche. Die Linien kommen aus `media/hatch<lod>.tga` (ganze Zahl Linien pro Kachel: 57 / 43 / 32, daher über Kachelgrenzen fortlaufend). Die Maske ist eine `MaskTexture`, die wie die Kachel platziert und gedreht wird; jede Schraffur-Textur hat damit zwei Masken (Randausblendung + Fläche). Ohne Masken-Unterstützung entfällt die Schraffur.
- **Ergebnis:** 5 Zonen 17,3 MB Kacheln + 0,8 MB Muster (vorher 68,5 MB, also −75 %). Hochrechnung: Östliche Königreiche ≈ 70 MB, beide Kontinente ≈ 140 MB. Im Spiel belegen nur die Kacheln im Sichtfeld Speicher (Freigabe nach ~20 s), unabhängig von der Zahl der Zonen.

### Standardwerte (`RunewayDB`)
| Schlüssel | Standard |
|---|---|
| `w`, `h` | 800, 600 (Breite, Höhe; je 200–1400) |
| `zoom` | 0.66 (0.1–1.5, in Optionen und `/rnw zoom` als 0–100 %; 0.66 = 40 %) |
| `zoomInside` | 0.8 (= 50 %; eigener Zoom in Innenkarten/Tile-Sets wie Unterstadt, wie Blizzards Minimap drinnen; Mausrad und `/rnw zoom` ändern den Zoom der aktuellen Ebene, `ZoomKey()`) |
| `alpha` | 0.5 (0–100 %, nur Kartenebenen; Pfeil, Marker und Questränder immer voll) |
| `rotate`, `locked`, `shown` | true, false, false |
| `colors.fill` | #000000, a 0.10 |
| `colors.hatch` | #CCD6E0, a 0.20 |
| `colors.shade` | #000000, a 0.45 |
| `colors.terrain` / `colors.water` | #D1DBE3, a 0.85 / 0.80 |
| `colors.roads` | #EBB748, a 0.65 |
| `colors.questAreas` | #73C7FF, a 0.90 |
| `layers.*` | alle true |
| `mode` | `"key"` (eigene Taste), `"mapkey"` (Kartentaste M öffnet das Overlay), `"permanent"` |
| `autoHide.combat/instance/mounted/city` | alle false (`city` = ausgeruht, also Städte und Gasthäuser) |
| `wheelZoom` | true (Mausrad über der Karte zoomt) |
| `shape` | 0.5 (Kartenform in 10-%-Schritten: 0 Rechteck, Superellipse mit Exponent 20 → 2 bis 50 % Oval, darüber schrumpft das Oval zur kürzeren Fensterseite = Kreis bei 100 %; `ShapeParams`/`ns.ShapeFn` für Questlinien, Hover und Leichnam) |
| `edgeSoft` | 0.5 (weicher Rand in 10-%-Schritten: Verlaufsbreite = Wert × 0,75 des Radius; 0 = harte Kante, 100 % = frühere Stufe 5; alte Stufen 1–5 werden beim Laden umgerechnet) |
| `arrowSize`, `pinSize`, `corpseSize`, `taxiSize`, `questEdge` | 20, 20, 20, 20, 1.0 (Faktor für die Breite der Questränder, 0,5–1,5, in den Optionen als 0–100 %; Standard 50 %) |
| `questMerge` | true: überlappende Questbereiche bekommen einen gemeinsamen Umriss |
| `zoneDim` | 0.5: Deckkraft-Faktor der angrenzenden Zonen (Option „Adjacent zones opacity“) |
| `questAreaCache` | `[mapID] = { areas, groups }`, Version über `questAreaCacheVersion` (2) |
| `style` | 6. Migrationszähler: setzt bei Stiländerungen einzelne Farben einmalig zurück (siehe `ADDON_LOADED` in `Core.lua`) |

### Slash-Befehle (`/runeway`, `/rnw`)
| Befehl | Wirkung |
|---|---|
| `/rnw` oder `/rnw toggle` | Overlay ein/aus |
| `/rnw config` | Einstellungsseite öffnen |
| `/rnw lock` / `unlock` | gesperrt = klickdurchlässig |
| `/rnw alpha 5-100` | Deckkraft der Kartenebenen |
| `/rnw zoom 0-100` | Zoom in % setzen (0 % = Faktor 0.1, 100 % = 1.5) |
| `/rnw size W [H]` | Breite und Höhe 200–1400 px (ohne H: beide gleich) |
| `/rnw rotate` | mitdrehen oder Norden oben |
| `/rnw edge 0-100` | Weicher Rand in % (10-%-Schritte) |
| `/rnw mode key\|mapkey\|permanent` | Aufruf-Modus |
| `/rnw layer NAME` | Ebene ein/aus (`fill`, `hatch`, `shade`, `terrain`, `water`, `roads`, `questareas`) |
| `/rnw color NAME R G B [A]` | Farbe und optional Deckkraft (0–1) |
| `/rnw keys` | Tastenübernahme neu anwenden und anzeigen, was die Kartentaste auslöst |
| `/rnw pos` | Position, Instanz und Karten-ID zum Kopieren |
| `/rnw view [ZONE \| N W]` | Ansichtsmodus: Karte auf ein kartiertes Gebiet (Namensteil, englisch wie in `zones_<id>.txt`) oder Weltkoordinaten zentrieren, Norden oben, Ziehen verschiebt (auch gesperrt); Dimmung nach der Zone in der Kartenmitte. Ohne Angabe: ein (an der eigenen Position) bzw. aus (zurück zum Spieler). Nicht gespeichert. Gedacht zum Prüfen von Gebieten, die die Figur nicht erreicht |
| `/rnw reset` | Einstellungen zurücksetzen |

Zusätzlich gibt es den Knopf „Overlay“ auf der Weltkarte und den Knopf „Karte ein-/ausblenden“ im Kopf der Einstellungen.

**Bedienung:**
- **Mausrad:** zoomt gesperrt wie entsperrt, abschaltbar über „Zoom with the mouse wheel“ (`wheelZoom`, dann `EnableMouseWheel(false)` und das Mausrad steuert die Kamera). `EnableMouse` nur entsperrt.
- **Nur entsperrt:**
  - Ziehen verschiebt die Karte.
  - Der Griff unten rechts (6 px eingerückt, innerhalb der runden Rahmenecke) ändert Breite und Höhe unabhängig; die obere linke Ecke bleibt stehen.
  - Shift+Mausrad ändert die Größe.
  - Beim Überfahren erscheint ein Rahmen (seit 0.6 immer, ohne Option): Rechteck mit runden Ecken (Radius 16 px), dünne weiche Linie (1 px, 55 %) über einem schwachen Glow (8 px, 10 %), helles Grau der Kartenlinien, Segmente mit `edge.tga`; statt der früheren harten 1-px-Linien.

**Sichtbarkeit (`UpdateVisibility`):**
- **Grundregel:** Angezeigt wird, wenn `mode == "permanent"` oder `shown` gesetzt ist und keine Bedingung zum automatischen Ausblenden greift.
- **Ausblend-Bedingungen:** Sie werden alle 0,25 s abgefragt, Kampfbeginn und Kampfende zusätzlich per Event.
- **Umschalten:** Während einer Ausblend-Bedingung oder im Modus „Permanent“ setzt das Umschalten eine Übersteuerung. Sie gilt, bis sich der Ausblend-Zustand ändert.

**Tastenmodi (`ApplyBindings`):**
- **Mechanik:** Nur Override-Bindings, damit kein Taint entsteht. Im Kampf wird die Anwendung bis `PLAYER_REGEN_ENABLED` verschoben.
- **Modus `mapkey`:** Die Tasten von `TOGGLEWORLDMAP` (Rückfall `M`) lösen `RUNEWAY_TOGGLE` aus. Die Tasten der Belegung `RUNEWAY_WORLDMAP` („World map (map key mode)“) lösen per Override `TOGGLEWORLDMAP` aus. Gesetzt wird sie als normale Tastenbelegung, direkt auf der Runeway-Seite. `UPDATE_BINDINGS` wendet alles neu an; `/rnw keys` zeigt den Stand.

### Zonen-Dimmung
- **Daten:** `tiles/<id>/Tiles.lua` enthält `RunewayZones[id]`: Zonennamen (Nummer = Reihenfolge in `zones_<id>.txt`), die Zone je Kachel-Schlüssel und für Grenzkacheln die Zone jedes ihrer 16 × 16 Chunks (ein Zeichen je Chunk aus `1-9A-Za-z`, also bis 61 Zonen je Karte).
- **Grenzkacheln:** werden beim Bauen pro Zone in Teile zerlegt (`<c>_<r>_z<zone>_<layer>.tga`), weich gewichtet über ~1 Chunk (`ZONE_FEATHER`); die Teile ergeben zusammen die Kachel. Chunks außerhalb der gebauten Zonen (Meer, Randausblendung) gehören zur nächstgelegenen gebauten Zone. Kosten: +4 MB für die 5 Zonen.
- **Laufzeit:** Die aktive Zone kommt aus der Spielerposition (Chunk-Raster), nicht aus der API; damit passt sie exakt zur Karte. Alle anderen Zonen werden mit `zoneDim` multipliziert, beim Zonenwechsel über ~0,4 s übergeblendet. Außerhalb der gebauten Zonen wird nichts gedimmt. Questbereiche werden nicht gedimmt.

### Leichnam-Marker
- Solange der Spieler tot bzw. Geist ist (`UnitIsDeadOrGhost`), zeigt die Karte die Position des Leichnams mit Blizzards Weltkarten-Symbol (`Interface\Minimap\POIIcons`, Texturkoordinaten wie `CorpsePinTemplate`), Größe über die Option „Corpse marker“ (`corpseSize`, Standard 25 px wie Spieler- und Questmarker).
- Position: `C_DeathInfo.GetCorpseMapPosition` auf der Spielerkarte, sonst auf deren Elternkarten (Friedhof in anderer Zone); einmal pro Sekunde gesucht, bis sie bekannt ist.
- Liegt der Leichnam außerhalb des Sichtfelds, sitzt der Marker am Kartenrand in seiner Richtung.

### Aufbau der Einstellungen
- **Hauptseite „Runeway“:** ganz oben die Version (`L.VERSION`, aus der `.toc` über `ns.Version()`), darunter Einleitungstext (`L.INTRO`, Zeilenvorlage `RunewayTextRowTemplate` mit fester Höhe über `GetExtent`) und darunter „Quick commands“.
- **Live-Werte:** Änderungen außerhalb des Fensters (Mausrad-Zoom, Griff, Shift+Mausrad, `/rnw zoom`, `/rnw size`) erscheinen sofort in den Reglern (`Settings.NotifyUpdate`).
- **Knopf „Karte ein-/ausblenden“:** im Kopf des Einstellungsfensters links neben „Standard“, nur auf den Runeway-Seiten (`Settings.CategoryChanged` über `EventRegistry`); Text wechselt zwischen „Show map“ und „Hide map“.
- **Ebenen:** eine Zeile je Ebene mit Häkchen, Farbfeld und Deckkraft-Regler (`RunewayLayerRowTemplate`, baut auf Blizzards Häkchen-plus-Regler-Zeile auf; die Farbe ist ein eigenes Proxy-Setting, „Standard“ setzt sie mit zurück).
- **Unterpunkte im Baum links** (Runeway aufklappbar, `RegisterVerticalLayoutSubcategory`): Open with, Hide automatically, Window, Display, Layers. Jeder Unterpunkt hat eigene Proxy-Settings, „Standard“ setzt nur diesen Unterpunkt zurück.
- **Zeilen mit breiterer Beschriftung:** Runeways Checkbox-, Regler- und Checkbox+Regler-Zeilen nutzen eigene Vorlagen (`RunewayCheckboxTemplate`, `RunewaySliderTemplate`, `RunewayCheckboxSliderTemplate`, Options.xml), die Blizzards Mixins erweitern: Steuerelemente 60 px weiter rechts (`WIDE`), Text entsprechend breiter; Blizzards Zeilen anderer Seiten bleiben unverändert. Auswahlliste „Öffnen mit“ und Tastenbelegungen sind Blizzards Zeilen.
- **Display:** Kartendeckkraft, Zoom (Außenbereiche), Zoom (Innenbereiche), Deckkraft angrenzender Zonen, Kartenform, Weicher Rand, dann Marker-Zeilen wie die Ebenen (Schalter + Größe, `CreateSettingsCheckboxSliderInitializer`): Spielerpfeil (`showArrow`), Leichnam (`showCorpse`), Flugmeister (`showTaxi`), Questsymbole (`showQuests`, aus: weder Questsymbole noch Questbereiche); danach Rand des Questbereichs, Überlagerte Questbereiche bündeln und Klassische Questsymbole (`questClassic`), alle drei über `SetParentInitializer` am Questmarker-Schalter (ausgegraut, wenn aus; dafür `row.data.setting = cb`, sonst meldet die Checkbox-Slider-Zeile keine Änderung).

### Schnellbefehle
- Auf der Hauptseite („Quick commands“): alle Slash-Befehle mit Beschreibung. Eigene Zeilenvorlage `RunewayCommandRowTemplate` (`Options.xml`, erbt `SettingsListElementTemplate`): Befehl links, Beschreibung rechts. Der frühere Bedienhinweis oben auf der entsperrten Karte ist entfernt.

### Profil (Export / Import)
- Unterpunkt „Profile“: Einleitung, Knöpfe „Export“ und „Import“; Dialog mit mehrzeiligem Textfeld (`Profile.lua`, `BasicFrameTemplateWithInset` + `InputScrollFrameTemplate`, Escape schließt).
- Format: eine Zeile `RNW1;pfad=wert;…` mit allen Einstellungen aus den Standardwerten plus Position (`x`, `y`); Zahlen mit `%.17g` (exakte Rückwandlung). Nicht enthalten: Questbereich-Cache, interne Werte, Tastenbelegungen (gehören WoW).
- Import nimmt nur bekannte Pfade mit passendem Typ (Zahl, true/false, Wort; `mode` nur key/mapkey/permanent) und führt nie Code aus. Danach `ApplyAll` und alle Regler aktualisiert (`ns.NotifyAllSettings`).

### Mouse-over: Tooltips und Hervorhebung
- Funktioniert auch auf der gesperrten, klickdurchlässigen Karte: Die Cursorposition wird pro Update abgefragt (`view:IsMouseOver`, `GetCursorPosition`), keine Mausereignisse. Nur innerhalb des sichtbaren Ovals und nur, wenn kein anderer Frame darüber liegt (`GetMouseFoci`: WorldFrame, die Karte selbst oder UIParent).
- Reihenfolge: Spielerpfeil, Leichnam, Questmarker, dann Questbereiche. Marker unter dem Cursor werden um 30 % vergrößert; Questbereiche werden breiter, heller und voll deckend gezeichnet.
- Tooltips wie auf der Minimap: Questtitel (gelb) und Ziele (`C_QuestLog.GetQuestObjectives`, erledigte grau), bei überlappenden Bereichen alle betroffenen Quests untereinander. Leichnam: Blizzards Text `CORPSE_RED`. Der Spielerpfeil hat keinen Tooltip.
- Trefferprüfung Questbereich: Punkt-in-Polygon (gerade/ungerade über alle Umrisse) in Weltkoordinaten (`ns.QuestAreasAt`), gleiche Auswahl wie beim Zeichnen (`ForEachShown`, inkl. Option „Combine overlapping quest areas“).
- Zusammengefasste Umrisse: Gruppen entstehen über sich überlappende Begrenzungsrechtecke und können daher mehrere getrennte Teile (Loops) haben. Der Tooltip listet die Quests des Teils unter dem Cursor: jede Quest der Gruppe, deren eigener Umriss in diesem Loop liegt (`LoopQuests`, am Loop gecacht). Hervorgehoben wird nur dieser Loop: breiterer, hellerer Rand und eine schwache Füllung in der Bereichsfarbe (Alpha 0,15, `FillLoop`: waagerechte Streifen à 2 px je Zeile, gerade/ungerade Schnittpunkte, ohne Pixel-Snapping, Rand-Ausblendung über die Maske der Karte). Die erste Tooltip-Zeile bekommt die normale Schrift (`GameTooltipText`), ihre Farbe bleibt erhalten (`SetFontObject` setzt sonst Weiß).

### Lokalisierung
- **Quelle:** `Runeway_Strings.md` enthält alle sichtbaren Texte mit Schlüssel, Englisch und Deutsch (von Mario abgestimmt). `python scripts/make_locales.py` erzeugt daraus `Runeway/Locales/enUS.lua` und `deDE.lua` – nicht von Hand ändern, sondern die Liste pflegen und neu erzeugen.
- **Laufzeit:** `enUS.lua` legt `ns.L` mit allen englischen Texten an; jede weitere Sprachdatei prüft `GetLocale()` und überschreibt nur ihre Schlüssel. Fehlt ein Schlüssel, bleibt der englische Text. Code verwendet nur `L.KEY`.
- **Weitere Sprachen:** je eine Datei `Runeway/Locales/<locale>.lua` (Aufbau wie `deDE.lua`), in der `.toc` nach `enUS.lua` eintragen. Nicht übersetzt: Befehle, Ebenen-Namen in Befehlen, Entwickler-Ausgaben.
- **Sprachen:** enUS (Quelle), deDE (von Mario abgestimmt, aus `Runeway_Strings.md` erzeugt) sowie frFR, esES, esMX, itIT, ptBR, ruRU, koKR, zhCN, zhTW (KI-Übersetzung, von Muttersprachlern noch nicht geprüft; Dateien von Hand gepflegt). Die Befehlshilfe (`USAGE`, `USAGE_COLOR`) bleibt in allen Sprachen englisch.
- **Neue oder geänderte Texte:** in `Runeway_Strings.md` (Englisch, Deutsch) ändern, `make_locales.py` laufen lassen, dann die neun anderen Dateien ergänzen; `check_locales.py` meldet fehlende Schlüssel je Sprache.
- **Prüfung:** `python tests/check_locales.py` – keine unbekannten Schlüssel, gleiche Platzhalter wie Englisch, Liste der noch englischen Texte je Sprache.

### Anmeldemeldung
- Einmal pro Login bzw. `/reload` (`PLAYER_ENTERING_WORLD`): „Runeway: v<Version> geladen.“; die Version kommt aus der `.toc` (`C_AddOns.GetAddOnMetadata`).

### Wichtige Laufzeit-Mechanik
- **Weltkoordinaten:** `UnitPosition` liefert (Nord, West). Eine ADT-Kachel ist 1600/3 Yards groß. Kachelmitte: `nord = (32 - zeile) * T - T/2`, `west = (32 - spalte) * T - T/2`.
- **Nahtloser Zoom:** Pro Kachel und Ebene gibt es eine Textur je gespeicherter Zoomstufe. Um die Umschaltpunkte (Kachelgröße 160 / 360 px, ±25 %) werden zwei Stufen per Vertex-Alpha überblendet. Eine Stufe, die noch lädt (`IsObjectLoaded`), gibt ihr Gewicht an eine geladene ab. Texturen, die etwa 20 s unbenutzt sind, werden freigegeben.
- **Ausblendrand:** Kacheln über eine `MaskTexture` (`fade<edge>.tga`). Linien nehmen keine Masken an, deshalb bekommen die Questlinien dieselbe ovale Ausblendung rechnerisch pro Segment.
- **Pixelraster:** Bewegte Texturen und Linien rasten nicht ein (`SetSnapToPixelGrid(false)`, `SetTexelSnappingBias(0)`), sonst springen sie beim Gehen.
- **Achsen:** Die Achsenreihenfolge von `C_Map.GetWorldPosFromMapPos` wird je Karte einmal gegen die Spielerposition geprüft (`MapToWorld` in `Core.lua`).

---

## 4. Kartendaten-Pipeline (Python, Ordner `scripts/`)

**Voraussetzungen:** Python 3, `numpy`, `opencv-python-headless`, `scikit-image`, `pillow`, `lupa` (für die Tests). Außerdem die `data`-Daten (siehe Abschnitt 2).

**Bauen:**
```bash
python scripts/build_raw.py               # Karte 0, Zonen aus scripts/zones_0.txt
python scripts/build_raw.py --map 1       # andere Karte (1 = Kalimdor, Ordner kalimdor), Zonen aus zones_1.txt
python scripts/build_wmo.py               # Innenraum-Sätze (Undercity), nach build_raw.py; schreibt auch die Paket-.toc
python scripts/build_raw.py "Zone Name"   # einzelne Zone(n), Namen wie in AreaTable (AreaName_lang)
```
Das schreibt `<Paket>/tiles/<id>/…` samt `Tiles.lua` und `<Paket>/<Paket>.toc` (Paket je Karte in `PACKS`, `build_raw.py`: 0 = `Runeway_EasternKingdoms`, 1 = `Runeway_Kalimdor`) und Vorschauen nach `build/` (`preview_lines.png`, `preview_over_minimap.png`). Die Community-Listfile (`listfile.csv`) wird beim ersten Lauf geladen. Der Bereichsindex der ADTs wird in `build/area_index_<id>.npz` zwischengespeichert.

**Block-Build:** Das Mosaik ist eine logische Gesamtkarte, gerechnet in Blöcken von 8 × 8 Kacheln (`BLOCK`) mit 1 Kachel Überlappung (`MARGIN`); behalten wird nur das Innere. Gleitkomma-Raster (Höhen, Steigung, Texturgewichte, Weichzeichnen, Linien, Randausblendung) gibt es nur je Block. Nicht-lokale Schritte (Entfernen kleiner Inseln und Flecken, Wege-Skelett und -Linienzüge, Umrisse) laufen auf 1-Byte-Masken der ganzen Karte; Umrisse und Wege werden einmal global vereinfacht und je Block nur gezeichnet. Ergebnis für Etappe 1 bitgleich zum früheren Gesamtbau (1241 Kacheln), Spitzen-RAM 3,8 → 1,7 GB, Laufzeit 146 → 108 s. Der RAM betrifft nur den Build auf dem Entwicklungsrechner, nicht das Addon.

| Datei | Aufgabe |
|---|---|
| `adt.py` | ADT-Parser (split files): MCVT-Höhen, MH2O-Wasser, MCNK-Löcher und Bereichs-IDs, `_tex0` MDID/MCLY/MCAL (Big-Alpha, RLE) |
| `raw_mosaic.py` | setzt Kacheln zu Rastern zusammen; exaktes Dreiecksnetz → 512 px pro Kachel (~1,04 yd/px); Texturgewichte |
| `structures.py` | Gebäude: Wände platzierter WMOs (OBJ-Export) und ausgewählte M2 (Türme) werden „nicht begehbar“ |
| `build_raw.py` | Masken, Zonen-Zuschnitt, Linien je Zoomstufe, Schraffur, Kacheln, `Tiles.lua`, Vorschauen |
| `build_wmo.py` | Innenraum-Kachelsätze aus WMO-Exporten (`SETS`, bisher Undercity `0-1458` und Ruinen `0-1458-ruins`; Gruppen per `skip`/`only`, Regeln `subzones`/`not_subzones`, Grundriss `margin`/`res`): Grundriss von oben, gleiche Ebenen und Funktionen wie `build_raw.py`; Vorschau `build/preview_<set>.png` |
| `roads.py` | `prune` (Skelett entgraten), von `build_raw.py` genutzt |
| `simulate.py` | rendert die Lua-Darstellung aus den Kacheln (`build/sim.png`) |
| `probe_view.py` | wertet `/rnw probe`-SavedVariables aus (Entwicklung) |
| `make_masks.py` | erzeugt die Randmasken `media/mask/s<Form>f<Rand>.tga` (Formel wie `ShapeParams` in `Core.lua`) |
| `zones_<id>.txt` | zu bauende Zonen je Karte, wird etappenweise erweitert |
| `update_data_branch.ps1` | lokale Rohdaten als Commit auf `data` |

**Algorithmus in Kürze:**
- **Begehbar:** Steigung unter 50° und kein Wasser. Zerklüftete Hänge werden zu Blöcken geschlossen (`BLOCK_CLOSE`). Kleine begehbare Inseln mitten im Gebirge werden entfernt (`MIN_WALK`), außer sie grenzen an Wasser (`MIN_ISLAND`, z. B. die Insel im Brightwater Lake).
- **Wasser:** MH2O-Oberfläche liegt über dem Gelände.
- **Wege:** Texturen mit „road“ oder „path“ im Namen, ab Gewicht 0.3, als Mittellinie (Skelett). Das Skelett wird in Linienzüge zerlegt (`trace_paths`: zwischen Endpunkten und Kreuzungen, Schein-Kreuzungen an Pixeltreppen wieder verbunden), vereinfacht, per Chaikin geglättet und pro Zoomstufe mit derselben Strichbreite wie die Umrisse gezeichnet (`draw_lines`). Kein Mindestlängen-Filter je Zoomstufe, weil Wegstücke an Kreuzungen enden.
- **Zonen-Zuschnitt:** über AreaTable (Unterzonen → Hauptzone). Offenes Wasser einer Zone (Chunks ohne trockenen Boden, die mit dem Mosaikrand verbunden sind) zählt wie Meer und bleibt nur in Küstennähe; eingeschlossene Seen bleiben. Zonennamen gelten nur für `ContinentID` 0; die AreaTable enthält gleichnamige Zonen anderer Kontinente (z. B. „Hillsbrad Foothills“ ID 16562, „Eastern Plaguelands“ ID 16028), die sonst die richtige ID überschrieben. Meeres-Chunks zählen nur in Küstennähe der Zone, denn „The Great Sea“ ist in der AreaTable eine Unterzone von Tirisfal.
- **Weicher Kartenrand:** `EDGE_FADE` = 160 px (~165 yd), mittig auf der Zonengrenze, also überwiegend nach außen. Kacheln, in die die Ausblendung reicht, werden mitgeschrieben.
- **Linien je Zoomstufe:** aus den Umrissen neu gezeichnet, nicht verkleinert (`LINE_LOD`). Bei 512 px 2 px breit, bei 256/128 px 1 px kantengeglättet, stärker vereinfacht, ohne Kleinstteile.
- **Schraffur:** Linienabstand je Stufe 9 / 6 / 4 px, über Kachelgrenzen fortlaufend.
- **Gebäude (`structures.py`):**
  - Platzierung: `nord = 32*T - PositionZ`, `west = 32*T - PositionX`, Höhe = PositionY. Modell-x → Nord, Modell-y → West. Kalibriert an Undercity (Rotation y = 179,5) über Geländelöcher und Minimap. Die Drehrichtung ist nur nahe 0° geprüft.
  - OBJ von wow.export ist y-oben: (x, z, −y).
  - Steile Flächen, die 0,5–2,5 yd über dem Gelände liegen, werden zu Wänden.
  - M2-Blocker per Namensliste `M2_BLOCKERS` (bisher `undercitytower`), Grundfläche aus dem M2-Bounding-Box-Header (MD20 + 0xA0) × Skalierung.

---

## 5. Questbereiche (`QuestAreas.lua`)

1. **Zeichnen lassen:** Ein unsichtbarer `QuestPOIFrame` (derselbe Frame-Typ wie die Weltkarte) bekommt `SetMapID(Zone)` und `DrawBlob(questID)`.
2. **Abtasten:** `UpdateMouseOverTooltip(x, y)` meldet, ob ein Kartenpunkt im Bereich liegt.
   - Grob über die ganze Karte (48×48), dann fein um die Treffer (Schritt 1/640 der Karte, höchstens 112×112).
   - Hat der grobe Durchgang keinen Treffer, wird ein Fenster um den Questpunkt abgetastet.
   - 1 s Wartezeit nach `SetMapID`, 0,2 s zwischen Quests, ein zweiter Versuch bei 0 Treffern.
   - Zeitbudget 3 ms pro Frame, nächste Quests zuerst, Pause im Kampf, im Tod (seit 0.6.1) und bei verstecktem Overlay.
   - **Im Tod (0.6.1):** `RefreshMap` ändert nichts, solange der Spieler tot oder Geist ist: keine Bereiche löschen, nichts einreihen; die bekannten Bereiche bleiben sichtbar. Erst `PLAYER_ALIVE`/`PLAYER_UNGHOST` gleichen wieder mit dem Questlog ab. Spieltest mit dem ersten 0.6.1-Build: als Geist verschwanden alle Bereiche, nur Questmarker blieben (vermutlich meldet der Client im Tod keine Teilbereiche, dann wurden die Bereiche gelöscht; im Spiel noch nicht bestätigt).
   - **Leeres Ergebnis (0.6.1):** Liefert eine Quest mit Teilbereichen (`GetQuestPOIBlobCount` > 0) keinen Treffer, bleibt ein vorhandener Umriss stehen und die Quest wird nach 5 s erneut abgetastet, höchstens 3-mal je Sitzung und Karte (`emptyTries`); erst dann gilt der Bereich als leer. Bereits leer gespeicherte Bereiche werden ebenso erneut abgetastet, `PLAYER_ALIVE`/`PLAYER_UNGHOST` geben neue Versuche. Spieltest 0.6: nach dem Tod fehlte ein Questbereich dauerhaft (Questmarker statt Umriss), weil ein leeres Ergebnis mit der aktuellen Signatur gespeichert wurde und nie neu abgetastet wurde.
3. **Umriss:**
   - Treffer-Raster weichzeichnen, Marching Squares mit interpolierter 0,5-Isolinie, Douglas-Peucker (0,35 Zellen), 2× Chaikin.
   - Umrechnung in Weltkoordinaten über die Kartenecken.
   - Je Umriss wird gespeichert, auf welcher Seite die Fläche liegt (`inward`).
4. **Überlappende Quests:** Sie werden zusätzlich gemeinsam abgetastet und bekommen einen einzigen Umriss (`groups`). Abschaltbar über die Option „Combine overlapping quest areas“ (`questMerge`); dann wird nicht gemeinsam abgetastet und jede Quest behält ihren Umriss.
   - **Anzeige (`Publish`):** Die gezeigten Umrisse sind eine feste Liste, neu aufgebaut erst, wenn die Abtastung fertig ist (keine Warteschlange, keine offene Gruppe) oder spätestens nach 3 s Arbeit. Neue Bereiche erscheinen dadurch gemeinsam und schon zusammengefasst statt einzeln.
   - **Gruppen zerfallen nicht (0.6.1):** Wird ein Mitglied neu abgetastet (Zielfortschritt, auch im Kampf, wo nicht abgetastet wird), bleibt die alte Gruppe erhalten und gezeichnet, bis der neue gemeinsame Umriss fertig ist; der ersetzt dann alle älteren Gruppen seiner Mitglieder (`Finish`). Fehlt die Gruppe zum aktuellen Schlüssel noch, zeigt `Publish` die älteren Gruppen ihrer Mitglieder. Verworfen wird eine Gruppe nur, wenn weniger als zwei Mitglieder einen Umriss haben. Mitglieder ohne Umriss (abgeschlossene Quest) blockieren die alte Gruppe in `Publish` nicht; sie wird für die übrigen Mitglieder gezeichnet, bis deren neuer gemeinsamer Umriss fertig ist. Abgeschlossene Quests (`IsComplete`/`ReadyForTurnIn`) werden bei leerem Ergebnis nicht wiederholt. Spieltest 0.6.1: nach dem Abschließen einer Quest einer Gruppe zerfielen die übrigen in Einzelumrisse.
   - **Globale Regel (0.6.1, `Publish`):** Gebündelte Umrisse werden nur ersetzt, nie aufgeteilt. Solange der neue gemeinsame Umriss einer Menge fehlt (egal warum), bleibt zuerst der zuletzt gezeigte gebündelte Umriss für ihre Mitglieder, sonst eine ältere Gruppe aus dem Cache (nach `/reload`). Einzeln wird eine Quest nur gezeichnet, wenn sie in keiner Menge mehr liegt. Test: Zufallsfolge aus Fortschritt, Abschließen, neuer Quest, Kampf, Tod und Zoom (300 Schritte); nach jedem Schritt darf keine zuvor gebündelte Quest einzeln erscheinen, solange sie noch in einer Menge liegt. Mit 0.6.0 schlägt er in 20 von 20 Zufallsfolgen fehl.
   - **Tooltip gebündelter Umrisse (0.6.1, `LoopQuests`):** Ein Teil (Loop) listet die Quests, deren eigener Umriss einen Punkt in ihm hat oder deren eigener Bereich einen Punkt des Loops enthält; trifft keine zu, alle Quests des Umrisses (ein leeres Ergebnis wird nicht zwischengespeichert). Grund: Ein stehen gebliebener älterer gemeinsamer Umriss passt nicht mehr zu den neu abgetasteten eigenen Umrissen. Spieltest 0.6.1: nach dem Verkleinern eines gebündelten Bereichs kein Tooltip mehr für ihn. Spieltest 0.6: im Kampf brachen gebündelte Bereiche in Einzelumrisse auf, weil die Gruppe beim Einreihen des Mitglieds gelöscht und nach 3 s ohne sie veröffentlicht wurde.
   - **Jede Quest genau einmal, Gruppen kartenübergreifend (`Resolve`):** Quests, deren Bereiche sich auf einer Karte überlappen (Begrenzungsrechtecke, auch über andere), bilden eine Menge. Sie wird als ein Umriss von der Karte gezeichnet, die die meisten dieser Quests listet (dann wenigste abgeschnittene Umrisse, dann nächste Karte); der Rest ebenso. Vorher bildete jede Karte eigene Gruppen; kam beim Rauszoomen eine Nachbarkarte mit einem Teil derselben Quests dazu, blockierte deren Gruppe die große und deren übrige Quests wurden einzeln gezeichnet (Spieltest: Merge je nach Zoomstufe nur teilweise).
   - Neue Karten in Sichtweite werden alle 0,25 s geprüft (vorher 1 s).
5. **Neu abtasten:** nur, wenn sich die Signatur ändert (Anzahl Teilbereiche, Questpunkt, Zielfortschritt). Auslöser: `QUEST_LOG_UPDATE` (0,3 s gebündelt), `QUEST_POI_UPDATE`, Zonenwechsel. Ergebnisse werden je Karte in `RunewayDB.questAreaCache` gespeichert und sind nach `/reload` sofort da.
6. **Zeichnen:**
   - Linien-Objekte mit `media/edge.tga` (WoW glättet Linienkanten nicht, die Textur schon).
   - Am Bildschirm per Catmull-Rom in Stücke von etwa 6 px unterteilt.
   - Breite = Kachelgröße ÷ 140 (2–7 px), folgt also dem Zoom.
   - Segmente überlappen nur bei voller Deckkraft um 1 px.
   - Ausblendung zum Rand pro Segment über `SetVertexColor`.
7. **Nachbarzonen (0.2):**
   - `ns.NearbyMaps()` (`Core.lua`): Karte des Spielers zuerst, dann die Zonen desselben Kontinents (`C_Map.GetMapInfo` bis `mapType` 2, `C_Map.GetMapChildrenInfo(Kontinent, 3)`), deren Kartenrechteck (Weltkoordinaten der Ecken, je Karte zwischengespeichert) näher als die Sichtweite + 200 yd liegt, nach Abstand sortiert.
   - `QuestAreas.lua` hält den Zustand je Karte (`state[mapID]`: Bereiche, Gruppen, Kartenecken). Die Warteschlange enthält Quests aller nahen Karten (Karte für Karte, je Karte nächste zuerst). `SetMapID` wechselt nur bei einem Kartenwechsel des Jobs (dann 1 s Wartezeit).
   - Jede Sekunde wird geprüft, ob sich die Liste naher Karten geändert hat (Bewegung, Zoom); dann werden Bereiche und Questmarker neu abgefragt.
   - **Doppelte Quests:** Erscheint eine Quest auf mehreren Karten, wird nur ein Umriss gezeichnet (`owner`): bevorzugt einer, der den Kartenrand nicht berührt (`cut`, also nicht abgeschnitten), sonst der der näheren Karte. Questmarker: die erste (nächste) Karte gewinnt.
   - Achsenreihenfolge (`MapToWorld`) für Karten, auf denen der Spieler nicht steht: von einer bereits geprüften Karte übernommen.
   - Cache-Version 3 (`cut` neu); alte Einträge werden einmal verworfen.
8. **Questmarker (`Core.lua`):**
   - Nur Quests ohne Umriss bekommen einen Marker (punktuelle Ziele).
   - Seit 0.6 (Mario, aus `interface/minimap/objecticonsatlas.blp`): Abgabe `quest-campaign-turnin` („?“, eigener Ring, ohne Hintergrund). In Bearbeitung (Punktziel ohne Gebiet) wie auf der Retail-Weltkarte immer rund `Quest-In-Progress-Icon-yellow` („…“) auf dem Hintergrund; „!“ bleibt verfügbaren Quests vorbehalten.
   - **Verfügbare Quests („!“): nicht möglich.** `C_QuestLine.GetAvailableQuestLines` liefert im Forever-Client 0 (Spieltest direkt vor einem Questgeber, nach `RequestQuestLinesForMap`); die Weltkarte zeigt keine, nur die Minimap (Server-Blips, für Addons nicht lesbar). Bliebe nur eine eigene Questgeber-Datenbank (wie Questie), eigenes Projekt. Option „Classic quest icons“ (`questClassic`, Standard aus, nach „Zusammenfassen“, folgt dem Questmarker-Schalter) oder fehlender Atlas: wie bisher `UI-QuestPoi-QuestNumber` (Kreis mit Goldrand) plus `UI-QuestIcon-TurnIn-Normal` bzw. `Quest-In-Progress-Icon-yellow`. Vorschau weiterer Kandidaten: `/rnw quest icons`.

---

## 6. Erkenntnisse und Fallstricke (verifiziert)

- **Forever ist ein Retail-Ableger:** Spieltyp „camelot“ aus der Mainline-Familie. Die UI-Referenz ist `Gethe/wow-ui-source`, Branch `forever`, nicht `classic_era`. Weltkarte und Questbereich-Code sind praktisch identisch mit Retail 12.x.
- **Questbereiche liegen nicht in den Client-Dateien:** `QuestPOIBlob/Point` enthalten nur 54 Einträge zu 22 Event-Quests. Die Bereiche schickt der Server zur Laufzeit; nach dem Login sind sie ohne geöffnete Karte vorhanden. Es gibt keine Lua-API, die die Polygonpunkte liefert, deshalb das Abtasten. Im Spiel bestätigt: Das Abtasten stimmt an der Spielerposition zu 100 % mit `C_Minimap.IsInsideQuestBlob` überein.
- **Rotation:** Frames lassen sich nicht drehen. Deshalb werden die Questbereiche selbst gezeichnet und nicht als `QuestPOIFrame` eingeblendet.
- **`SetAlpha` auf Texturen** überschreibt das Alpha aus `SetVertexColor`. Deckkraft nur über `SetVertexColor` setzen.
- **Layout-Cache:** Benannte, verschiebbare Frames bekommen von WoW Größe und Position aus dem Layout-Cache zurück. Deshalb `SetDontSavePosition`, `SetUserPlaced(false)` und erneutes Anwenden bei `PLAYER_ENTERING_WORLD`.
- **Lua 5.1:** kein `goto`, `loadstring` statt `load`. Die Tests laufen mit `lupa.lua51`.
- **Linien (`CreateLine`):**
  - keine Kantenglättung, also eine Textur mit weichen Rändern nutzen;
  - keine Masken;
  - Segmente kürzer als etwa 1 px werden nicht gezeichnet (Mindestlänge 5 px);
  - halbtransparente Überlappungen und breite weiche Striche zeigen jede Stoßstelle;
  - `SetGradient` richtet sich bei Linien nicht entlang der Linie aus.
- **Neue Texturdateien** brauchen einen kompletten WoW-Neustart, `/reload` reicht nicht.
- **TGA:** RLE-komprimiert mit `orientation=1` funktioniert im Spiel.
- **ADT-Platzierung, Achsen und OBJ-Konvention:** siehe Abschnitt 4. Undercity liegt bei Nord ≈ 1648, West ≈ 240, Höhe 62,5.
- **Hilfsmittel:** Die AreaTable-CSV ist mit `;` getrennt. Die Texturnamen aus `_tex0` kommen nur als FileDataIDs, aufgelöst über die wowdev-Listfile.

---

## 7. Abgleich mit `Runeway_Prompt_v1.md`

| Punkt | Status |
|---|---|
| 3.1 RAW-Daten (Begehbarkeit aus Steigung, Wasser aus MH2O, Wege aus Texturen, Zonen-Zuschnitt, Tirisfal) | **erledigt** für Tirisfal; Etappe 1 (Silverpine, Western Plaguelands, Hillsbrad, Alterac) in 0.2 erledigt und im Spiel getestet; alle Östlichen Königreiche (Etappen 2–4) in 0.5 |
| 3.2 Einfärbbare Ebenen | **erledigt**, erweitert um `fill` und `hatch` |
| 3.3 Questgebiete | **erledigt**, über das Abtasten statt DB2 (die Tabellen sind leer) |
| 3.4 Konfigurationsoberfläche und Bedienung | **erledigt** in 0.1, im Spiel getestet |
| 3.5 Abschluss (Lua-Prüfung, Simulation, Version 0.0, ZIP) | **erledigt** (Tests mit Lua 5.1, `simulate.py`, Release-ZIP) |
| Zusätzlich | Diablo-IV-Stil, frei skalierbare ovale Karte, nahtloser Zoom, Ruinen von Lordaeron, Questmarker im Weltkarten-Stil, angrenzende Zonen, Leichnam-Marker, Mouse-over-Tooltips, Profil-Export/-Import, Lokalisierung |

---

## 8. Offene Punkte und nächste Schritte

### Roadmap (Langfristziel)

**Ziel:** Alles, was sich kartieren lässt, in dieser Darstellung: alle Gebiete der Östlichen Königreiche, Kalimdor, Städte, Höhlen und Minen, Dungeons und Raids.

**Architektur-Grundsätze:**
- **Laufzeit bleibt kachelbasiert:** Kacheln in Weltkoordinaten, geladen nach Sichtfeld, keine Zonen im Addon. Zonen-Maps zur Laufzeit zusammenzusetzen ist ausdrücklich verworfen (doppelte Texturen und Überblend-Artefakte an Grenzen).
- **Pro Karten-ID ein Kachelsatz:** `<Paket>/tiles/<mapID>/…` (heute `Runeway_EasternKingdoms/tiles/0`). Die Instanz-ID kommt aus `UnitPosition` (4. Wert); `Tiles.lua` führt die Kachelliste pro Karten-ID.
- **Bauen als logische Gesamtkarte, gerechnet in Blöcken:** z. B. 8×8 Kacheln mit 1–2 Kacheln Überlappungsrand, geschrieben wird nur das Innere. Das Ergebnis ist identisch zu einem Gesamtbau, der RAM-Bedarf bleibt konstant. Schraffur-Phase an Weltkoordinaten statt am Mosaik-Ursprung ausrichten. Nicht-lokal und deshalb mit breitem Rand oder global auf grobem Raster: das Entfernen kleiner Inseln (`MIN_WALK`, `MIN_ISLAND`) und das Zusammensetzen der Wegstücke.
- **Zwei Pipelines, ein Kachelformat:**

  | Art | Quelle | Pipeline |
  |---|---|---|
  | Kontinente (Östliche Königreiche, Kalimdor) | ADT-Gelände | RAW-Pipeline (`build_raw.py`), in Blöcken |
  | Städte, Höhlen, Minen | WMO in oder unter dem Gelände | WMO-Grundriss (Ansatz wie Undercity, `structures.py`) |
  | Dungeons, Raids | meist reine WMO-Karten, oft mehrstöckig | WMO-Grundriss mit Etagen |
- **Etagen und Innenräume:** umschaltbare Ebenen. Erkennung über `C_Map.GetBestMapForUnit`: Minen, Höhlen und Dungeon-Etagen haben eigene uiMap-IDs. Verallgemeinerung des Undercity-Prototyps.
- **Daten-Addons nach Bedarf laden:** Kern-Addon `Runeway` (Code) plus Datenpakete mit `## LoadOnDemand: 1`, z. B. `Runeway_EasternKingdoms`, `Runeway_Kalimdor`, `Runeway_Dungeons`, geladen beim Betreten per `C_AddOns.LoadAddOn`. Gesamtgröße für alles grob 1 GB oder mehr.
- **Rohdaten:** Kalimdor-ADTs, Instanz-WDTs und WMO-Exporte etappenweise per wow.export auf `data`. Größe des `data`-Branchs im Blick behalten (heute ~1,6 GB).

**Reihenfolge:**
1. **Fundament:** Block-Build mit Überlappung, Schraffur in Weltkoordinaten, Kachelliste pro Karten-ID im Addon. **Erledigt**, siehe unten.
2. **Östliche Königreiche:** alle Gebiete in Etappen (Tabelle unten), plus Questbereiche angrenzender Zonen. **Erledigt** (0.5).
3. **Daten-Addons:** Aufteilung in Pakete, die beim Betreten geladen werden. **Erledigt** (0.6).
4. **Kalimdor:** dieselbe Pipeline. **In Arbeit** (0.7), wartet auf die ADT-Daten, siehe „Kalimdor“ unten.
5. **WMO-Grundriss-Pipeline mit Etagen:** zuerst Städte (Ironforge, Stormwind), Undercity unterirdisch, dann Höhlen und Minen.
6. **Dungeons und Raids.**
7. **Version 2:** Route zum Questziel (A* auf dem Begehbarkeitsraster).

**Gebiete der Östlichen Königreiche** (AreaTable-Hauptzonen mit Gelände-Chunks im ADT-Export; 1 Chunk ≈ 33 × 33 yd). 27 Gebiete; fertig (0.2): Tirisfal, Silverpine Forest, Western Plaguelands, Hillsbrad Foothills, Alterac Mountains; 22 offen. Fläche gesamt ≈ 9 × Tirisfal; mit der Kachel-Optimierung aus 0.2 hochgerechnet ≈ 70 MB.

| Chunks | Gebiet | | Chunks | Gebiet |
|---:|---|---|---:|---|
| 20 505 | Stranglethorn Vale (inkl. Meer) | | 3 298 | Burning Steppes |
| 19 206 | Tirisfal Glades (**fertig**) | | 2 920 | Loch Modan |
| 18 845 | Wetlands (inkl. Meer) | | 2 698 | Searing Gorge |
| 16 097 | Eastern Plaguelands | | 2 643 | Duskwood |
| 11 790 | Westfall | | 2 347 | Badlands |
| 11 498 | Riverglades (Forever-spezifisch) | | 2 270 | Gilneas (Forever-spezifisch) |
| 9 972 | Silverpine Forest (**fertig**) | | 2 197 | Alterac Mountains (**fertig**) |
| 7 836 | The Hinterlands | | 2 082 | Blasted Lands |
| 7 631 | Swamp of Sorrows | | 2 081 | Redridge Mountains |
| 6 294 | Arathi Highlands | | 1 754 | Stormwind City (Stadt) |
| 6 096 | Dun Morogh | | 1 536 | Gillijim's Isle |
| 4 276 | Hillsbrad Foothills (**fertig**) | | 855 | Deadwind Pass |
| 3 672 | Elwynn Forest | | 295 | Ruins of Gilneas |
| 3 616 | Western Plaguelands (**fertig**) | | | |

- Ironforge und Undercity sind eigene Hauptzonen ohne Gelände-Chunks (reine WMO-Innenräume) → WMO-Pipeline.
- Eversong Woods, Ghostlands und Isle of Quel'Danas: kommen erst mit Burning Crusade (Karte 530) und gibt es in WoW Forever nicht (Mario) – entfällt.
- Nicht gezählt: Chunks ohne Gebiet (ID 0) und „Shark-Infested Waters“ (Meer).
- Neu erzeugen: AreaTable-Hauptzonen (`ParentAreaID` 0, `ContinentID` 0) gegen `build/area_index.npz` zählen, siehe `zone_of_area()`/`area_index()` in `build_raw.py`.

**Retail (mögliche spätere Erweiterung):**
- **Code:** Forever ist ein Retail-Ableger mit praktisch identischer UI-API. Der Addon-Code läuft weitgehend unverändert; nötig sind die Interface-Version für Retail in der `.toc` und eine Erkennung des Spieltyps (z. B. `WOW_PROJECT_ID`, `GetBuildInfo`), um das passende Datenpaket zu laden.
- **Daten:** Kacheln sind spielversionsabhängig, weil sich Gebiete geändert haben (z. B. Brachland durch Cataclysm geteilt, Tausend Nadeln geflutet, Dunkelküste, Undercity in Retail zerstört). Gleiche Karten-ID heißt nicht gleiches Gelände. Daher je Spielversion eigene Datenpakete (z. B. `Runeway_Forever_EasternKingdoms`, `Runeway_Retail_EasternKingdoms`) und auf `data` getrennte Ordner je Version.
- **Phasen:** Retail hat phasenabhängiges Gelände (z. B. Kriegsfronten, Chromiezeit), teils als eigene Karten-IDs. Die Kachelliste pro Karten-ID deckt das ab, solange jede Phase ihre eigene ID hat.
- **Pipeline:** unverändert nutzbar (gleiches Split-ADT- und WMO-Format), Eingabe ist der wow.export-Export des jeweiligen Clients. Die Parameter (Steigung, Wege-Texturen) brauchen eventuell Feinjustierung für neuere Gebiete.
- **Konsequenz schon jetzt:** Datenpfade und Paketnamen nicht fest an „Forever“ binden, sondern über Spielversion und Karten-ID auflösen; dann ist Retail nur ein weiterer Datensatz.

### Fundament (erledigt) und Etappen der Östlichen Königreiche

**Fundament:**
- **Block-Build:** siehe Abschnitt 4. Etappe 1 bitgleich zum alten Gesamtbau. Probelauf mit allen 27 Gebieten in einem Lauf: 9,6 min, 4,7 GB Spitzen-RAM (alter Gesamtbau hochgerechnet ~22 GB), 769 Kacheln, 106,5 MB.
- **Schraffur in Weltkoordinaten:** unverändert gültig. Das Muster hat eine ganze Zahl Linien pro Kachel und ist damit an Kachelgrenzen (= Weltkoordinaten) ausgerichtet; Blöcke beginnen immer an Kachelgrenzen.
- **Kachelliste pro Karten-ID:** `tiles/<id>/Tiles.lua` setzt `RunewayTiles[id]` und `RunewayZones[id]`; Build mit `--map <id>` und `zones_<id>.txt`. Die Laufzeit indiziert die Liste einmal nach `"c_r"` und besucht pro Frame nur die Kacheln um den Spieler. Zonen-Chunks: ein Zeichen je Chunk (`1-9A-Za-z`), bis 61 Zonen je Karte.
- **Kalimdor (0.7, in Arbeit; Version bleibt bis zum Spieltest 0.6.1):** vorbereitet: `scripts/zones_1.txt` (25 Gebiete in 4 Etappen, alle Namen in der AreaTable mit `ContinentID` 1 geprüft), `KNOWN_PACKS[1] = Runeway_Kalimdor` (Kontinent-uiMap 1414; ohne installiertes Paket kommt jetzt `PACK_FAILED` mit Status `ADDON_MISSING`), `simulate.py --map <id>`. **Blockiert:** auf `data` fehlen die Kalimdor-ADTs (nur `maps/azeroth`). Export wie für die Östlichen Königreiche: wow.export, Karte Kalimdor, RAW (Root, `_tex0`, `_obj0/1`, `_lod`, WDT/WDL) mit WMO/M2 an (nur dann entstehen die `ModelPlacementInformation.csv` für `structures.py`), Foliage, G-Objects und Heightmaps aus, nach `Wow export files/maps/kalimdor/`, optional Minimap-PNGs (`maps/kalimdor/minimap/`, nur für `preview_over_minimap.png`); dann auf `data` committen und `python scripts/build_raw.py --map 1`.
  - Zonenwahl: Top-Level-Gebiete, die in anderen liegen, sind eigene Zonen, sonst blieben dort Löcher: `Southfury River` (Fluss zwischen Durotar und Brachland), `Caverns of Time` (Tanaris), `Gates of Ahn'Qiraj` (Silithus); Städte Orgrimmar, Thunder Bluff, Darnassus wie Stormwind City. `Shen'dralas` ist Forever-spezifisch (Unterzonen aus Desolace/Feralas). Nicht gebaut: Mount Hyjal (in Forever nicht erreichbar), GM Island, UNUSEDAlcaz Island. Nach dem ersten Lauf Chunk-Zahlen je Gebiet prüfen (wie Tabelle oben) und die Liste ggf. anpassen.

**Etappen** (Gruppen von Nord nach Süd; immer alle Zonen aus `zones_0.txt` zusammen bauen, neue Zonen unten anhängen, weil die Zeilennummer die Zonennummer ist):

| Etappe | Gebiete | Stand |
|---|---|---|
| 1 | Tirisfal Glades, Silverpine Forest, Western Plaguelands, Hillsbrad Foothills, Alterac Mountains | im Spiel getestet (0.2) |
| 2 (Norden) | Eastern Plaguelands, The Hinterlands, Arathi Highlands, Gilneas, Ruins of Gilneas | gebaut (285 Kacheln, 28,2 MB, 3,3 min, 2,3 GB RAM), im Spiel per Ansichtsmodus geprüft |
| 3 (Mitte) | Wetlands, Dun Morogh, Loch Modan, Searing Gorge, Badlands, Burning Steppes, Riverglades | gebaut (Etappen 1–3: 499 Kacheln, 50,2 MB, 5,9 min, 3,2 GB RAM), im Spiel per Ansichtsmodus geprüft |
| 4 (Süden) | Elwynn Forest, Stormwind City, Westfall, Redridge Mountains, Duskwood, Deadwind Pass, Swamp of Sorrows, Blasted Lands, Stranglethorn Vale, Gillijim's Isle | gebaut (alle 27 Gebiete: 692 Kacheln, 69,7 MB, 8,7 min, 4,7 GB RAM), im Spiel per Ansichtsmodus geprüft |

**Test Etappen 2–4:** Mit Stufe-10-Charakter über den Ansichtsmodus (`/rnw view`) geprüft, Ergebnis insgesamt positiv; Verschieben per Ziehen funktioniert. Nicht vor Ort geprüft: Questbereiche und Ladezeiten beim Laufen in diesen Gebieten.

**Im Spiel prüfen (Etappe 2):** Übergänge Western Plaguelands ↔ Eastern Plaguelands, Hillsbrad ↔ Arathi, Arathi ↔ Hinterlands, Silverpine ↔ Gilneas; Dimmung beim Grenzübertritt; Küste im Norden der Eastern Plaguelands (weicher Rand statt Schraffur auf offenem Meer); Ladezeiten.

**Im Spiel prüfen (Etappe 3):** Übergänge Arathi ↔ Wetlands (Thandol-Brücke), Wetlands ↔ Dun Morogh / Loch Modan, Dun Morogh ↔ Searing Gorge, Searing Gorge ↔ Burning Steppes, Badlands ↔ Riverglades; Lava in Searing Gorge und Burning Steppes (zählt bisher als Gelände); Ironforge (Innenraum, nicht kartiert); Saum unter den Linien bei starkem Zoom (seit der 128-px-Umstellung etwas weicher).

**Im Spiel prüfen (Etappe 4):** Übergänge Dun Morogh / Burning Steppes ↔ Elwynn und Redridge, Elwynn ↔ Westfall / Duskwood / Redridge, Duskwood ↔ Deadwind Pass ↔ Swamp of Sorrows, Swamp of Sorrows ↔ Blasted Lands, Duskwood / Westfall ↔ Stranglethorn; Stormwind City (ohne Gebäudewände); Küsten von Westfall und Stranglethorn; Gillijim's Isle.

**Dateigröße:** Alle 27 Gebiete 69,7 MB (Probelauf vor den Optimierungen: 106,5 MB). Werte des Probelaufs: Anteile: Linien `terrain` 32 MB, `shade` 31 MB, `hatch`-Maske 21 MB, `water` 13 MB, `roads` 5 MB, `fill` 4 MB; nach Stufe 512: 34 MB, 256: 55 MB, 128: 18 MB. Umgesetzt: `hatch`-Maske und `shade` nur in 128 (Etappen 1+2: 42,9 → 28,2 MB) und offenes Meer weggelassen (s. Zonen-Zuschnitt).

**Bekannt aus der Vorschau:**
- Stormwind City hat (wie andere Städte außer Undercity) keine Gebäude-Wände; dafür braucht es den WMO-Export (siehe „Weitere Städte“).
- Lava (MH2O-Typ Magma, Searing Gorge, Burning Steppes) wird übersprungen und zählt damit als Gelände; ggf. als nicht begehbar markieren.

### Später
- **Weitere Städte:**
  - WMO als OBJ exportieren (wow.export, „Split WMO Groups“, ohne Texturen) und auf `data` legen.
  - Turm- oder Mauer-M2 in `M2_BLOCKERS` eintragen.
  - Die Ausrichtung je Stadt gegen die Minimap prüfen, weil die Drehrichtung erst nahe 0° kalibriert ist.
- **Undercity unterirdisch:** erledigt (0.6, `build_wmo.py`). Grundriss: Bodenflächen (Normale > 0,75) der Innen-Gruppen (Flag 0x2000) ohne „Ruins of Lordaeron“, je Pixel und Höhe ein Knoten; Nachbarn mit < 1,2 yd Höhenunterschied sind verbunden (Treppen, Rampen). Das größte Netz ist die begehbare Stadt, die übrigen 929 Netze sind Mauerkronen, Bögen und Deckenträger. Je Pixel zählt der höchste Boden des Netzes; Wasser = WMO-Flüssigkeit (MLIQ, Kachel-Flag & 0xF ≠ 0xF), wo sie darüber liegt (Kanäle; Brücken bleiben begehbar). Mehrere Ebenen erscheinen übereinander von oben gesehen; Etagen-Umschaltung später.
- **Questbereiche (optional):** Innenschein bzw. Schraffur wie auf der Minimap. Mit Linien gab es Artefakte an den Stoßstellen, das bräuchte gefüllte Flächen, z. B. Dreiecks-Texturen.
- **Version 2, Kalimdor, Instanzen:** siehe Roadmap oben.

### Bekannte Einschränkungen
- **Feldwege:** Erdwege mit Dirt-Texturen werden nicht erkannt, weil Dirt in Tirisfal normaler Untergrund ist.
- **Questbereiche:** Sie erscheinen beim ersten Mal nach Login oder Zonenwechsel mit etwa 1 s Verzögerung (je Karte); danach kommen sie aus dem Zwischenspeicher.
- **Gebäude:** Außer Undercity und den Stadttürmen sind keine Gebäude eingezeichnet. Kleine Gebäude, z. B. in Brill, sind nicht berücksichtigt.

---

## 9. Testen und Release

```bash
python tests/check_locales.py                 # Sprachdateien: Schlüssel und Platzhalter wie enUS
RUNEWAY_LOCALE=ruRU python tests/run_stub.py  # derselbe Test mit anderer Client-Sprache (Standard enUS)
python tests/run_stub.py                      # lädt das Addon (Lua 5.1) gegen einen WoW-API-Stub: Kacheln, Questbereiche, Optionen, Profil, Mouse-over; meldet versehentliche globale Variablen
python tests/render_quest_outlines.py <SavedVariables/Runeway.lua>   # Questumrisse aus Probe-Daten mit dem Addon-Code
python scripts/simulate.py                    # Darstellung aus den Kacheln
cd <repo> && zip -r build/Runeway-<version>.zip Runeway Runeway_EasternKingdoms
```

**Testwerkzeug `/rnw probe`:** Nur in Entwicklungsbuilds; dazu `tools/Probe.lua` in den Addon-Ordner kopieren und in der `.toc` eintragen. Es tastet die Questbereiche der aktuellen Zone ab und speichert sie in `RunewayDB.probe`. Die Auswertung macht `scripts/probe_view.py`.

**Installation:** Alte Ordner `Interface\AddOns\Runeway` und `Runeway_*` löschen, das ZIP dort entpacken (beide Ordner) und WoW komplett neu starten. Neue Dateien (Kacheln, Einträge in der `.toc`, `Bindings.xml`) lädt WoW erst nach einem Neustart; reine Lua-Änderungen an bestehenden Dateien reichen mit `/reload`.

**Im Spiel geprüft (0.6):** beide Ordner installiert; Paket lädt beim Betreten; deaktiviertes Paket, Kalimdor und Dungeons → Karte ausgeblendet, Chat-Meldung mit Paket und Gebiet (Login, Reload, Dungeon rein/raus mehrfach geprüft); keine Lua-Fehler.

**Im Spiel geprüft (0.6.1):** gebündelte Questbereiche bleiben im Kampf zusammen und beim Abschließen einer Quest der Gruppe (Wechsel zum kleineren Umriss nahtlos, Tooltip danach korrekt), nach zweimal Sterben (Geist, Wiederbeleben) bleiben alle Bereiche sichtbar; keine Lua-Fehler (`scriptErrors` an). Hinweis: Bis dahin lief bei Mario ein Zwischenstand von 0.6 (09:12, noch `fade1-5.tga` statt `media/mask`); der gemergte 0.6-Stand wurde erst mit diesem Test im Spiel geprüft. Ein über den alten Ordner entpacktes ZIP zeigte keine Questbereiche, sauber installiert (Ordner löschen, WoW neu starten) lief es.

**Regressionsliste (vor jedem Release im Spiel prüfen, Stand 0.4 alles bestanden; 0.5: Punkte 1–2 für Etappen 2–4 über den Ansichtsmodus geprüft):**
1. **Karte:** Look wie im Diablo-Screenshot; Zoom nahtlos ohne Flackern oder Kachelkanten; Schraffur deckungsgleich mit den Geländelinien; Ruinen von Lordaeron erkennbar.
2. **Zonen:** Übergänge zwischen den gebauten Zonen ohne Kante oder Lücke; angrenzende Zonen gedimmt, beim Grenzübertritt weicher Tausch; Außenrand blendet weich aus.
3. **Questbereiche:** durchgehend in jeder Zoomstufe, weich zum Kartenrand, korrekt bei Fortschritt; auch aus angrenzenden Zonen, grenzüberschreitende nicht abgeschnitten oder doppelt; Option „Combine overlapping quest areas“ an/aus.
4. **Questmarker und Mouse-over:** Marker nur für Punktziele, kein Springen beim Gehen; Tooltips wie auf der Minimap, alle Questtitel in normaler Schrift (keine größere erste Zeile); ein zusammengefasster Bereich listet überall alle seine Quests; Hervorhebung von Pfeil, Leichnam, Markern und Bereichen.
5. **Leichnam:** im Tod markiert, außerhalb am Rand in seiner Richtung, nach der Wiederbelebung weg.
6. **Fenster:** Gesperrt = klickdurchlässig; entsperrt verschieben, Griff ändert Breite und Höhe; Mausrad-Zoom an/aus; Position und Größe bleiben über Logout; Regler zeigen Änderungen per Mausrad/Griff sofort.
7. **Aufruf-Modi:** eigene Taste; Kartentaste M (Weltkarte über „World map (map key mode)“, auch nach Kampf und `/reload`); dauerhaft; automatisches Ausblenden (Kampf, Instanz, Reittier/Flug, Stadt).
8. **Einstellungen:** Hauptseite mit Einleitung und Schnellbefehlen, Unterpunkte; Ebenen-Zeilen (Häkchen, Farbe, Deckkraft); „Standard“ je Seite; Knopf „Karte ein-/ausblenden“ neben „Standard“.
9. **Profil:** Export, Einstellungen ändern, Import stellt alles wieder her; ungültiger Text wird abgelehnt.
10. **Ansichtsmodus:** `/rnw view` ein/aus an der eigenen Position, `/rnw view <Gebiet>`, Ziehen verschiebt (auch gesperrt), Dimmung nach Kartenmitte, zurück zum Spieler.
11. **Sprache:** mit deutschem und einem weiteren Client (z. B. Französisch) alle Texte übersetzt; keine Lua-Fehler, keine blockierten Aktionen („Runeway wurde geblockt“) beim Durchklicken der Blizzard-Menüs.

---

## 10. Start-Prompt für die nächste Session

```text
Projekt Runeway (WoW-Forever-Addon). Repo mschettl/Runeway, Entwicklungsbranch dev (Push mit git push -u origin dev).
Lies zuerst CLAUDE.md, Runeway_Status_v1.md und Runeway_Prompt_v1.md.
Version 0.6 (früher 1.6; Nummerierung siehe „Versionierung“) ist im Spiel getestet und in main gemergt (PR #10): Datenpaket Runeway_EasternKingdoms, Meldung bei fehlenden Kartendaten, Unterstadt/Ruinen als Innen-Kachelsätze mit eigenem Zoom, Flugmeister, Questsymbole, Kartenform und weicher Rand.
Langfristziel, Architektur und Versionsplan: Runeway_Status_v1.md, Abschnitte 1 und 8.
Aufgabe dieser Session: Kalimdor (Roadmap Schritt 4, Version 0.7) als Datenpaket Runeway_Kalimdor; Dungeons und Raids kommen später ins Paket ihres Kontinents (KNOWN_PACKS in Core.lua mitpflegen).
Rohdaten liegen auf dem Branch data (git fetch origin data, siehe Abschnitt 2). Tests: python tests/run_stub.py, andere Sprache mit RUNEWAY_LOCALE=deDE.
Kommunikation Deutsch, Code Englisch. PR und Merge nur auf Marios Anweisung (Squash-Merge).
```
