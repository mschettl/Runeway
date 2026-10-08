# Runeway – Stand Version 1.2 und Übergabe

Diese Datei fasst den kompletten Stand nach Version 1.2 zusammen, damit eine neue Session nahtlos weitermachen kann. Sie ersetzt den Chatverlauf. Vorgaben und Ziele stehen in `Runeway_Prompt_v1.md`, Arbeitsregeln in `CLAUDE.md`.

---

## 1. Kurzüberblick

Runeway ist ein spielerzentriertes, mitdrehendes Karten-Overlay für **WoW Forever** (Interface 16001) im Stil von Path of Exile und Diablo IV.

**Stand 1.0:**
- **Zone:** Tirisfal ist vollständig aus den RAW-Spieldaten gebaut. Die Ruinen von Lordaeron sind als Stadt eingezeichnet.
- **Kartenebenen:** Begehbare Fläche (leicht abgedunkelt), schraffierte nicht begehbare Bereiche (Gebirge, Wasser, Mauern), Geländelinien, Wasserlinien und Wege.
- **Questbereiche:** Exakt dieselben Bereiche wie auf der Weltkarte, als blauer, mitdrehender Rand.
- **Questmarker:** Nur für punktuelle Ziele (Abgabe, Gespräche), im Weltkarten-Stil.
- **Zoom:** Nahtlos durch Überblendung der Kachel-Zoomstufen. Breite und Höhe sind frei einstellbar (Standard 800 × 600), die Karte blendet oval aus.

Im Spiel getestet und für Version 1 abgenommen.

**Stand 1.1 (im Spiel getestet und abgenommen):** Punkt 3.4 ist umgesetzt. Dazu gehören die Einstellungsseite im Blizzard-Stil (`Options.lua`), die Aufruf-Modi samt eigener Weltkarten-Tastenbelegung, das automatische Ausblenden und die Fensterbedienung laut Vorgabe.

**Stand 1.2 (gebaut, Test im Spiel offen):** Etappe 1 des Pakets „weitere Zonen“ (Abschnitt 8).
- **Zonen:** Tirisfal, Silverpine Forest, Western Plaguelands, Hillsbrad Foothills, Alterac Mountains in einem Mosaik (Kacheln 26–38 / 24–36). Alterac ist dabei, weil es zwischen den anderen liegt; ohne es entstünde ein ausgeblendetes Loch.
- **Questbereiche und Questmarker angrenzender Zonen:** siehe Abschnitt 5, „Nachbarzonen“.

---

## 2. Repository und Branches

| Branch | Inhalt |
|---|---|
| `main` | Version 1.0 (PR mschettl/Runeway#1), 1.1 per Folge-PR. |
| `claude/dreamy-lovelace-efolxg` | Entwicklungsbranch (Addon, Build-Skripte, Tests, diese Datei). |
| `data` (orphan) | Rohdaten aus wow.export, nie auf `main`. ~1,6 GB. |

**Inhalt von `data`** (Ordner `Wow export files/`):
- `maps/azeroth/`: ADT-Export der Östlichen Königreiche (736 Kacheln: Root, `_tex0`, `_obj0/1`, `_lod`), WDT/WDL, Minimap-PNGs von Tirisfal (26–34 / 26–29), `adt_<c>_<r>_ModelPlacementInformation.csv` (Modellplatzierungen).
- `AreaTable.csv`, `QuestPOIBlob.csv`, `QuestPOIPoint.csv`. Die beiden QuestPOI-Tabellen sind für Questbereiche unbrauchbar, siehe Abschnitt 6.
- `world/`: kompletter `world`-Ordner (WMO, M2, BLP). Für 1.0 wird nur genutzt:
  - `world/wmo/autogen-names/undercity/` (OBJ-Export mit „Split WMO Groups“, 215 Gruppen, plus `20736.json`)
  - `world/generic/undead/passivedoodads/lordaerontowers/*.m2` (Türme der Stadtmauer)

**Daten holen** (in einem Checkout des Entwicklungsbranchs):
```bash
git fetch origin data
git restore --source=origin/data --worktree -- "Wow export files"
```
Der Ordner ist auf allen Code-Branches per `.gitignore` ausgeschlossen. Daten pflegen geht lokal mit `scripts/update_data_branch.ps1` oder über ein Worktree auf `data`.

---

## 3. Addon (Ordner `Runeway/`)

| Datei | Inhalt |
|---|---|
| `Runeway.toc` | Interface 16001, Version 1.1, SavedVariables `RunewayDB`; lädt `Tiles.lua`, `Core.lua`, `QuestAreas.lua`, `Options.lua` |
| `Core.lua` | Fenster, Kacheln, Zoom, Drehung, Questmarker, Sichtbarkeit und Aufruf-Modi, Slash-Befehle, Einstellungen |
| `Options.lua` | Einstellungen im Blizzard-Stil (`Settings.RegisterVerticalLayoutCategory` mit Proxy-Settings) unter Optionen → AddOns → Runeway, Layer als eigener Abschnitt auf derselben Seite; auch über `/rnw config`. Wird bei `PLAYER_LOGIN` aufgebaut, weil die Tastenbelegungs-Zeilen `GetNumBindings` brauchen |
| `QuestAreas.lua` | Questbereiche: Abtasten, Umriss, Zeichnen |
| `Tiles.lua` | generiert: vorhandene Kacheln und Ebenen je Kachel, z. B. `["31_28"] = "fhstwr"` |
| `Bindings.xml` | Tastenbelegung `RUNEWAY_TOGGLE` |
| `media/` | `hatch512/256/128.tga` (gemeinsames Schraffurmuster je Zoomstufe, erzeugt von `build_raw.py`), `fade1.tga`–`fade5.tga` (runde Ausblendmasken je Randstärke, erzeugt mit `scripts/make_masks.py`), `arrow.tga` (Spielerpfeil), `edge.tga` (kantengeglättete Linientextur), `dot.tga` (Rückfall-Symbol) |
| `tiles/0/[256/ \| 128/]<c>_<r>_<layer>.tga` | weiße RLE-TGA-Kacheln je Ebene und Zoomstufe (512/256/128 px). Speicherbedarf siehe „Dateigröße“ unten |

`tools/Probe.lua` ist ein Entwicklungswerkzeug und nicht im Release (siehe Abschnitt 6).

### Ebenen (Zeichenreihenfolge, Kennbuchstabe in `Tiles.lua`)
`fill` (f, begehbar) → `hatch` (h, Schraffur nicht begehbar) → `shade` (s, dunkler Saum) → `terrain` (t) → `water` (w) → `roads` (r). Darüber `questAreas` (Linien aus `QuestAreas.lua`), Questmarker und Spielerpfeil.

Kacheln sind weiß. Eingefärbt wird zur Laufzeit per `SetVertexColor`.

### Dateigröße (1.2)
- **Gespeicherte Zoomstufen je Ebene** (`FILE_LODS` in `build_raw.py`, `FILE_LOD` in `Core.lua`): Linien (`terrain`, `water`, `roads`) in 512/256/128, `shade` in 256/128 (die 512-Stufe nutzt 256), `fill` nur in 128. Fallen zwei Zoomstufen auf dieselbe Datei, wird nicht überblendet.
- **Schraffur:** Die Kachel `256/<c>_<r>_hatch.tga` ist nur noch die Maske der nicht begehbaren Fläche. Die Linien kommen aus `media/hatch<lod>.tga` (ganze Zahl Linien pro Kachel: 57 / 43 / 32, daher über Kachelgrenzen fortlaufend). Die Maske ist eine `MaskTexture`, die wie die Kachel platziert und gedreht wird; jede Schraffur-Textur hat damit zwei Masken (Randausblendung + Fläche). Ohne Masken-Unterstützung entfällt die Schraffur.
- **Ergebnis:** 5 Zonen 17,3 MB Kacheln + 0,8 MB Muster (vorher 68,5 MB, also −75 %). Hochrechnung: Östliche Königreiche ≈ 70 MB, beide Kontinente ≈ 140 MB. Im Spiel belegen nur die Kacheln im Sichtfeld Speicher (Freigabe nach ~20 s), unabhängig von der Zahl der Zonen.

### Standardwerte (`RunewayDB`)
| Schlüssel | Standard |
|---|---|
| `w`, `h` | 800, 600 (Breite, Höhe; je 200–1400) |
| `zoom` | 0.3 (0.08–5) |
| `alpha` | 0.7 (nur Kartenebenen; Pfeil, Marker und Questränder immer voll) |
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
| `hover` | true (Rahmen bei Mausüberfahrt, nur entsperrt) |
| `edge` | 3 (Randstärke 1–5, Breite 0,12 / 0,25 / 0,38 / 0,55 / 0,75 des Radius) |
| `arrowSize`, `pinSize`, `corpseSize`, `questEdge` | 25, 25, 25, 0.8 (Faktor für die Breite der Questränder) |
| `questMerge` | true: überlappende Questbereiche bekommen einen gemeinsamen Umriss |
| `zoneDim` | 0.3: Deckkraft-Faktor der angrenzenden Zonen (Option „Neighbouring zones“) |
| `questAreaCache` | `[mapID] = { areas, groups }`, Version über `questAreaCacheVersion` (2) |
| `style` | 6. Migrationszähler: setzt bei Stiländerungen einzelne Farben einmalig zurück (siehe `ADDON_LOADED` in `Core.lua`) |

### Slash-Befehle (`/runeway`, `/rnw`)
| Befehl | Wirkung |
|---|---|
| `/rnw` oder `/rnw toggle` | Overlay ein/aus |
| `/rnw config` | Einstellungsseite öffnen |
| `/rnw lock` / `unlock` | gesperrt = klickdurchlässig |
| `/rnw alpha 5-100` | Deckkraft der Kartenebenen |
| `/rnw zoom 0.08-5` | Zoom setzen |
| `/rnw size N` | Seitenlänge 200–1400 px |
| `/rnw rotate` | mitdrehen oder Norden oben |
| `/rnw edge 1-5` | Stärke des weichen Rands |
| `/rnw mode key\|mapkey\|permanent` | Aufruf-Modus |
| `/rnw layer NAME` | Ebene ein/aus (`fill`, `hatch`, `shade`, `terrain`, `water`, `roads`, `questareas`) |
| `/rnw color NAME R G B [A]` | Farbe und optional Deckkraft (0–1) |
| `/rnw keys` | Tastenübernahme neu anwenden und anzeigen, was die Kartentaste auslöst |
| `/rnw pos` | Position, Instanz und Karten-ID zum Kopieren |
| `/rnw reset` | Einstellungen zurücksetzen |

Zusätzlich gibt es den Button „Overlay“ auf der Weltkarte.

**Bedienung:**
- **Mausrad:** zoomt gesperrt wie entsperrt (`EnableMouseWheel` immer an, `EnableMouse` nur entsperrt).
- **Nur entsperrt:**
  - Ziehen verschiebt die Karte.
  - Der Griff unten rechts ändert Breite und Höhe unabhängig; die obere linke Ecke bleibt stehen.
  - Shift+Mausrad ändert die Größe.
  - Beim Überfahren erscheint ein Rahmen, abschaltbar.

**Sichtbarkeit (`UpdateVisibility`):**
- **Grundregel:** Angezeigt wird, wenn `mode == "permanent"` oder `shown` gesetzt ist und keine Bedingung zum automatischen Ausblenden greift.
- **Ausblend-Bedingungen:** Sie werden alle 0,25 s abgefragt, Kampfbeginn und Kampfende zusätzlich per Event.
- **Umschalten:** Während einer Ausblend-Bedingung oder im Modus „Permanent“ setzt das Umschalten eine Übersteuerung. Sie gilt, bis sich der Ausblend-Zustand ändert.

**Tastenmodi (`ApplyBindings`):**
- **Mechanik:** Nur Override-Bindings, damit kein Taint entsteht. Im Kampf wird die Anwendung bis `PLAYER_REGEN_ENABLED` verschoben.
- **Modus `mapkey`:** Die Tasten von `TOGGLEWORLDMAP` (Rückfall `M`) lösen `RUNEWAY_TOGGLE` aus. Die Tasten der Belegung `RUNEWAY_WORLDMAP` („World map (map key mode)“) lösen per Override `TOGGLEWORLDMAP` aus. Gesetzt wird sie als normale Tastenbelegung, direkt auf der Runeway-Seite. `UPDATE_BINDINGS` wendet alles neu an; `/rnw keys` zeigt den Stand.

### Zonen-Dimmung
- **Daten:** `Tiles.lua` enthält `RunewayZones[inst]`: Zonennamen (Nummer = Reihenfolge in `zones.txt`), die Zone je Kachel-Schlüssel und für Grenzkacheln die Zone jedes ihrer 16 × 16 Chunks.
- **Grenzkacheln:** werden beim Bauen pro Zone in Teile zerlegt (`<c>_<r>_z<zone>_<layer>.tga`), weich gewichtet über ~1 Chunk (`ZONE_FEATHER`); die Teile ergeben zusammen die Kachel. Chunks außerhalb der gebauten Zonen (Meer, Randausblendung) gehören zur nächstgelegenen gebauten Zone. Kosten: +4 MB für die 5 Zonen.
- **Laufzeit:** Die aktive Zone kommt aus der Spielerposition (Chunk-Raster), nicht aus der API; damit passt sie exakt zur Karte. Alle anderen Zonen werden mit `zoneDim` multipliziert, beim Zonenwechsel über ~0,4 s übergeblendet. Außerhalb der gebauten Zonen wird nichts gedimmt. Questbereiche werden nicht gedimmt.

### Leichnam-Marker
- Solange der Spieler tot bzw. Geist ist (`UnitIsDeadOrGhost`), zeigt die Karte die Position des Leichnams mit Blizzards Weltkarten-Symbol (`Interface\Minimap\POIIcons`, Texturkoordinaten wie `CorpsePinTemplate`), Größe über die Option „Corpse marker“ (`corpseSize`, Standard 25 px wie Spieler- und Questmarker).
- Position: `C_DeathInfo.GetCorpseMapPosition` auf der Spielerkarte, sonst auf deren Elternkarten (Friedhof in anderer Zone); einmal pro Sekunde gesucht, bis sie bekannt ist.
- Liegt der Leichnam außerhalb des Sichtfelds, sitzt der Marker am Kartenrand in seiner Richtung.

### Aufbau der Einstellungen
- **Hauptseite „Runeway“:** Einleitungstext (`L.INTRO`, Zeilenvorlage `RunewayTextRowTemplate` mit fester Höhe über `GetExtent`) und darunter „Quick commands“.
- **Live-Werte:** Änderungen außerhalb des Fensters (Mausrad-Zoom, Griff, Shift+Mausrad, `/rnw zoom`, `/rnw size`) erscheinen sofort in den Reglern (`Settings.NotifyUpdate`).
- **Knopf „Karte ein-/ausblenden“:** im Kopf des Einstellungsfensters links neben „Standard“, nur auf den Runeway-Seiten (`Settings.CategoryChanged` über `EventRegistry`); Text wechselt zwischen „Show map“ und „Hide map“.
- **Ebenen:** eine Zeile je Ebene mit Häkchen, Farbfeld und Deckkraft-Regler (`RunewayLayerRowTemplate`, baut auf Blizzards Häkchen-plus-Regler-Zeile auf; die Farbe ist ein eigenes Proxy-Setting, „Standard“ setzt sie mit zurück).
- **Unterpunkte im Baum links** (Runeway aufklappbar, `RegisterVerticalLayoutSubcategory`): Open with, Hide automatically, Window, Display, Layers. Jeder Unterpunkt hat eigene Proxy-Settings, „Standard“ setzt nur diesen Unterpunkt zurück.

### Schnellbefehle
- Auf der Hauptseite („Quick commands“): alle Slash-Befehle mit Beschreibung. Eigene Zeilenvorlage `RunewayCommandRowTemplate` (`Options.xml`, erbt `SettingsListElementTemplate`): Befehl links, Beschreibung rechts. Der frühere Bedienhinweis oben auf der entsperrten Karte ist entfernt.

### Mouse-over: Tooltips und Hervorhebung
- Funktioniert auch auf der gesperrten, klickdurchlässigen Karte: Die Cursorposition wird pro Update abgefragt (`view:IsMouseOver`, `GetCursorPosition`), keine Mausereignisse. Nur innerhalb des sichtbaren Ovals und nur, wenn kein anderer Frame darüber liegt (`GetMouseFoci`: WorldFrame, die Karte selbst oder UIParent).
- Reihenfolge: Spielerpfeil, Leichnam, Questmarker, dann Questbereiche. Marker unter dem Cursor werden um 30 % vergrößert; Questbereiche werden breiter, heller und voll deckend gezeichnet.
- Tooltips wie auf der Minimap: Questtitel (gelb) und Ziele (`C_QuestLog.GetQuestObjectives`, erledigte grau), bei überlappenden Bereichen alle betroffenen Quests untereinander. Leichnam: Blizzards Text `CORPSE_RED`. Der Spielerpfeil hat keinen Tooltip.
- Trefferprüfung Questbereich: Punkt-in-Polygon (gerade/ungerade über alle Umrisse) in Weltkoordinaten (`ns.QuestAreasAt`), gleiche Auswahl wie beim Zeichnen (`ForEachShown`, inkl. Option „Combine overlapping quest areas“).

### Lokalisierung
- **Quelle:** `Runeway_Strings.md` enthält alle sichtbaren Texte mit Schlüssel, Englisch und Deutsch (von Mario abgestimmt). `python scripts/make_locales.py` erzeugt daraus `Runeway/Locales/enUS.lua` und `deDE.lua` – nicht von Hand ändern, sondern die Liste pflegen und neu erzeugen.
- **Laufzeit:** `enUS.lua` legt `ns.L` mit allen englischen Texten an; jede weitere Sprachdatei prüft `GetLocale()` und überschreibt nur ihre Schlüssel. Fehlt ein Schlüssel, bleibt der englische Text. Code verwendet nur `L.KEY`.
- **Weitere Sprachen:** je eine Datei `Runeway/Locales/<locale>.lua` (Aufbau wie `deDE.lua`), in der `.toc` nach `enUS.lua` eintragen. Nicht übersetzt: Befehle, Ebenen-Namen in Befehlen, Entwickler-Ausgaben.
- **Prüfung:** `python tests/check_locales.py` – keine unbekannten Schlüssel, gleiche Platzhalter wie Englisch, Liste der noch englischen Texte je Sprache.

### Wichtige Laufzeit-Mechanik
- **Weltkoordinaten:** `UnitPosition` liefert (Nord, West). Eine ADT-Kachel ist 1600/3 Yards groß. Kachelmitte: `nord = (32 - zeile) * T - T/2`, `west = (32 - spalte) * T - T/2`.
- **Nahtloser Zoom:** Pro Kachel und Ebene gibt es eine Textur je Zoomstufe, einmal geladen und dann behalten. Um die Umschaltpunkte (Kachelgröße 160 / 360 px, ±25 %) werden zwei Stufen per Vertex-Alpha überblendet. Eine Stufe, die noch lädt (`IsObjectLoaded`), gibt ihr Gewicht an eine geladene ab. Texturen, die etwa 20 s unbenutzt sind, werden freigegeben.
- **Ausblendrand:** Kacheln über eine `MaskTexture` (`fade<edge>.tga`). Linien nehmen keine Masken an, deshalb bekommen die Questlinien dieselbe ovale Ausblendung rechnerisch pro Segment.
- **Pixelraster:** Bewegte Texturen und Linien rasten nicht ein (`SetSnapToPixelGrid(false)`, `SetTexelSnappingBias(0)`), sonst springen sie beim Gehen.
- **Achsen:** Die Achsenreihenfolge von `C_Map.GetWorldPosFromMapPos` wird je Karte einmal gegen die Spielerposition geprüft (`MapToWorld` in `Core.lua`).

---

## 4. Kartendaten-Pipeline (Python, Ordner `scripts/`)

**Voraussetzungen:** Python 3, `numpy`, `opencv-python-headless`, `scikit-image`, `pillow`, `lupa` (für die Tests). Außerdem die `data`-Daten (siehe Abschnitt 2).

**Bauen:**
```bash
python scripts/build_raw.py               # Zonen aus scripts/zones.txt (aktuell: Etappe 1, 5 Zonen)
python scripts/build_raw.py "Zone Name"   # einzelne Zone(n), Namen wie in AreaTable (AreaName_lang)
```
Das schreibt `Runeway/tiles/0/…`, `Runeway/Tiles.lua` und Vorschauen nach `build/` (`preview_lines.png`, `preview_over_minimap.png`). Die Community-Listfile (`listfile.csv`) wird beim ersten Lauf geladen. Der Bereichsindex der ADTs wird in `build/area_index.npz` zwischengespeichert.

| Datei | Aufgabe |
|---|---|
| `adt.py` | ADT-Parser (split files): MCVT-Höhen, MH2O-Wasser, MCNK-Löcher und Bereichs-IDs, `_tex0` MDID/MCLY/MCAL (Big-Alpha, RLE) |
| `raw_mosaic.py` | setzt Kacheln zu Rastern zusammen; exaktes Dreiecksnetz → 512 px pro Kachel (~1,04 yd/px); Texturgewichte |
| `structures.py` | Gebäude: Wände platzierter WMOs (OBJ-Export) und ausgewählte M2 (Türme) werden „nicht begehbar“ |
| `build_raw.py` | Masken, Zonen-Zuschnitt, Linien je Zoomstufe, Schraffur, Kacheln, `Tiles.lua`, Vorschauen |
| `roads.py` | `prune` (Skelett entgraten), von `build_raw.py` genutzt |
| `simulate.py` | rendert die Lua-Darstellung aus den Kacheln (`build/sim.png`) |
| `probe_view.py` | wertet `/rnw probe`-SavedVariables aus (Entwicklung) |
| `make_masks.py` | erzeugt die Randmasken `media/fade1–5.tga` (Breiten wie `FADE_WIDTH` in `Core.lua`) |
| `zones.txt` | zu bauende Zonen, wird etappenweise erweitert |
| `update_data_branch.ps1` | lokale Rohdaten als Commit auf `data` |

**Algorithmus in Kürze:**
- **Begehbar:** Steigung unter 50° und kein Wasser. Zerklüftete Hänge werden zu Blöcken geschlossen (`BLOCK_CLOSE`). Kleine begehbare Inseln mitten im Gebirge werden entfernt (`MIN_WALK`), außer sie grenzen an Wasser (`MIN_ISLAND`, z. B. die Insel im Brightwater Lake).
- **Wasser:** MH2O-Oberfläche liegt über dem Gelände.
- **Wege:** Texturen mit „road“ oder „path“ im Namen, ab Gewicht 0.3, als Mittellinie (Skelett). Das Skelett wird in Linienzüge zerlegt (`trace_paths`: zwischen Endpunkten und Kreuzungen, Schein-Kreuzungen an Pixeltreppen wieder verbunden), vereinfacht, per Chaikin geglättet und pro Zoomstufe mit derselben Strichbreite wie die Umrisse gezeichnet (`draw_lines`). Kein Mindestlängen-Filter je Zoomstufe, weil Wegstücke an Kreuzungen enden.
- **Zonen-Zuschnitt:** über AreaTable (Unterzonen → Hauptzone). Zonennamen gelten nur für `ContinentID` 0; die AreaTable enthält gleichnamige Zonen anderer Kontinente (z. B. „Hillsbrad Foothills“ ID 16562, „Eastern Plaguelands“ ID 16028), die sonst die richtige ID überschrieben. Meeres-Chunks zählen nur in Küstennähe der Zone, denn „The Great Sea“ ist in der AreaTable eine Unterzone von Tirisfal.
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
   - Zeitbudget 3 ms pro Frame, nächste Quests zuerst, Pause im Kampf und bei verstecktem Overlay.
3. **Umriss:**
   - Treffer-Raster weichzeichnen, Marching Squares mit interpolierter 0,5-Isolinie, Douglas-Peucker (0,35 Zellen), 2× Chaikin.
   - Umrechnung in Weltkoordinaten über die Kartenecken.
   - Je Umriss wird gespeichert, auf welcher Seite die Fläche liegt (`inward`).
4. **Überlappende Quests:** Sie werden zusätzlich gemeinsam abgetastet und bekommen einen einzigen Umriss (`groups`). Abschaltbar über die Option „Combine overlapping quest areas“ (`questMerge`); dann wird nicht gemeinsam abgetastet und jede Quest behält ihren Umriss.
5. **Neu abtasten:** nur, wenn sich die Signatur ändert (Anzahl Teilbereiche, Questpunkt, Zielfortschritt). Auslöser: `QUEST_LOG_UPDATE` (0,3 s gebündelt), `QUEST_POI_UPDATE`, Zonenwechsel. Ergebnisse werden je Karte in `RunewayDB.questAreaCache` gespeichert und sind nach `/reload` sofort da.
6. **Zeichnen:**
   - Linien-Objekte mit `media/edge.tga` (WoW glättet Linienkanten nicht, die Textur schon).
   - Am Bildschirm per Catmull-Rom in Stücke von etwa 6 px unterteilt.
   - Breite = Kachelgröße ÷ 140 (2–7 px), folgt also dem Zoom.
   - Segmente überlappen nur bei voller Deckkraft um 1 px.
   - Ausblendung zum Rand pro Segment über `SetVertexColor`.
7. **Nachbarzonen (1.2):**
   - `ns.NearbyMaps()` (`Core.lua`): Karte des Spielers zuerst, dann die Zonen desselben Kontinents (`C_Map.GetMapInfo` bis `mapType` 2, `C_Map.GetMapChildrenInfo(Kontinent, 3)`), deren Kartenrechteck (Weltkoordinaten der Ecken, je Karte zwischengespeichert) näher als die Sichtweite + 200 yd liegt, nach Abstand sortiert.
   - `QuestAreas.lua` hält den Zustand je Karte (`state[mapID]`: Bereiche, Gruppen, Kartenecken). Die Warteschlange enthält Quests aller nahen Karten (Karte für Karte, je Karte nächste zuerst). `SetMapID` wechselt nur bei einem Kartenwechsel des Jobs (dann 1 s Wartezeit).
   - Jede Sekunde wird geprüft, ob sich die Liste naher Karten geändert hat (Bewegung, Zoom); dann werden Bereiche und Questmarker neu abgefragt.
   - **Doppelte Quests:** Erscheint eine Quest auf mehreren Karten, wird nur ein Umriss gezeichnet (`owner`): bevorzugt einer, der den Kartenrand nicht berührt (`cut`, also nicht abgeschnitten), sonst der der näheren Karte. Questmarker: die erste (nächste) Karte gewinnt.
   - Achsenreihenfolge (`MapToWorld`) für Karten, auf denen der Spieler nicht steht: von einer bereits geprüften Karte übernommen.
   - Cache-Version 3 (`cut` neu); alte Einträge werden einmal verworfen.
8. **Questmarker (`Core.lua`):**
   - Nur Quests ohne Umriss bekommen einen Marker (punktuelle Ziele).
   - Atlas `UI-QuestPoi-QuestNumber` (Kreis mit Goldrand) plus `UI-QuestIcon-TurnIn-Normal` (Abgabe) bzw. `Quest-In-Progress-Icon-yellow` (läuft), 26 px.

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
| 3.1 RAW-Daten (Begehbarkeit aus Steigung, Wasser aus MH2O, Wege aus Texturen, Zonen-Zuschnitt, Tirisfal) | **erledigt** für Tirisfal; Etappe 1 (Silverpine, Western Plaguelands, Hillsbrad, Alterac) gebaut, Spieltest offen; weitere Zonen offen |
| 3.2 Einfärbbare Ebenen | **erledigt**, erweitert um `fill` und `hatch` |
| 3.3 Questgebiete | **erledigt**, über das Abtasten statt DB2 (die Tabellen sind leer) |
| 3.4 Konfigurationsoberfläche und Bedienung | **erledigt** in 1.1, im Spiel getestet |
| 3.5 Abschluss (Lua-Prüfung, Simulation, Version 1.0, ZIP) | **erledigt** (Tests mit Lua 5.1, `simulate.py`, Release-ZIP) |
| Zusätzlich | Diablo-IV-Stil, quadratische runde Karte, nahtloser Zoom, Ruinen von Lordaeron, Questmarker im Weltkarten-Stil |

---

## 8. Offene Punkte und nächste Schritte

### Roadmap (Langfristziel)

**Ziel:** Alles, was sich kartieren lässt, in dieser Darstellung: alle Gebiete der Östlichen Königreiche, Kalimdor, Städte, Höhlen und Minen, Dungeons und Raids.

**Architektur-Grundsätze:**
- **Laufzeit bleibt kachelbasiert:** Kacheln in Weltkoordinaten, geladen nach Sichtfeld, keine Zonen im Addon. Zonen-Maps zur Laufzeit zusammenzusetzen ist ausdrücklich verworfen (doppelte Texturen und Überblend-Artefakte an Grenzen).
- **Pro Karten-ID ein Kachelsatz:** `tiles/<mapID>/…` (heute `tiles/0` = Östliche Königreiche). Die Instanz-ID kommt aus `UnitPosition` (4. Wert); `Tiles.lua` führt die Kachelliste pro Karten-ID.
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
1. **Fundament:** Block-Build mit Überlappung, Schraffur in Weltkoordinaten, Kachelliste pro Karten-ID im Addon.
2. **Östliche Königreiche:** alle Gebiete in Etappen (Tabelle unten), plus Questbereiche angrenzender Zonen.
3. **Daten-Addons:** Aufteilung in Pakete, die beim Betreten geladen werden.
4. **Kalimdor:** dieselbe Pipeline.
5. **WMO-Grundriss-Pipeline mit Etagen:** zuerst Städte (Ironforge, Stormwind), Undercity unterirdisch, dann Höhlen und Minen.
6. **Dungeons und Raids.**
7. **Version 2:** Route zum Questziel (A* auf dem Begehbarkeitsraster).

**Gebiete der Östlichen Königreiche** (AreaTable-Hauptzonen mit Gelände-Chunks im ADT-Export; 1 Chunk ≈ 33 × 33 yd). 27 Gebiete; fertig (1.2): Tirisfal, Silverpine Forest, Western Plaguelands, Hillsbrad Foothills, Alterac Mountains; 22 offen. Fläche gesamt ≈ 9 × Tirisfal; mit der Kachel-Optimierung aus 1.2 hochgerechnet ≈ 70 MB.

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
- Eversong Woods, Ghostlands und Isle of Quel'Danas liegen auf einer eigenen Karte und sind nicht im ADT-Export.
- Nicht gezählt: Chunks ohne Gebiet (ID 0) und „Shark-Infested Waters“ (Meer).
- Neu erzeugen: AreaTable-Hauptzonen (`ParentAreaID` 0, `ContinentID` 0) gegen `build/area_index.npz` zählen, siehe `zone_of_area()`/`area_index()` in `build_raw.py`.

**Retail (mögliche spätere Erweiterung):**
- **Code:** Forever ist ein Retail-Ableger mit praktisch identischer UI-API. Der Addon-Code läuft weitgehend unverändert; nötig sind die Interface-Version für Retail in der `.toc` und eine Erkennung des Spieltyps (z. B. `WOW_PROJECT_ID`, `GetBuildInfo`), um das passende Datenpaket zu laden.
- **Daten:** Kacheln sind spielversionsabhängig, weil sich Gebiete geändert haben (z. B. Brachland durch Cataclysm geteilt, Tausend Nadeln geflutet, Dunkelküste, Undercity in Retail zerstört). Gleiche Karten-ID heißt nicht gleiches Gelände. Daher je Spielversion eigene Datenpakete (z. B. `Runeway_Forever_EasternKingdoms`, `Runeway_Retail_EasternKingdoms`) und auf `data` getrennte Ordner je Version.
- **Phasen:** Retail hat phasenabhängiges Gelände (z. B. Kriegsfronten, Chromiezeit), teils als eigene Karten-IDs. Die Kachelliste pro Karten-ID deckt das ab, solange jede Phase ihre eigene ID hat.
- **Pipeline:** unverändert nutzbar (gleiches Split-ADT- und WMO-Format), Eingabe ist der wow.export-Export des jeweiligen Clients. Die Parameter (Steigung, Wege-Texturen) brauchen eventuell Feinjustierung für neuere Gebiete.
- **Konsequenz schon jetzt:** Datenpfade und Paketnamen nicht fest an „Forever“ binden, sondern über Spielversion und Karten-ID auflösen; dann ist Retail nur ein weiterer Datensatz.

### Nächstes Paket (neue Session): Fundament + weitere Zonen + Questbereiche angrenzender Zonen

**Reihenfolge in der Session:** zuerst das Fundament (Roadmap Schritt 1: Block-Build, Schraffur in Weltkoordinaten, Kachelliste pro Karten-ID), dann Etappe 1.

**Hinweis:** Etappe 1 (5 Zonen) und die Kachel-Optimierung wurden vor dem Fundament umgesetzt (1.2); das Fundament (Block-Build) folgt vor weiteren Etappen.

**Ziel:** Die Karte wächst über Tirisfal hinaus, nahtlos über Zonengrenzen. Questbereiche benachbarter Zonen erscheinen, sobald sie im Sichtfeld liegen.

**Ausgangslage:**
- Die ADTs der kompletten Östlichen Königreiche (736 Kacheln, inkl. `_tex0`, `_obj0/1`) liegen bereits auf `data`. Für die Kartenebenen ist **kein neuer Export** nötig.
- Minimap-PNGs gibt es nur für Tirisfal (Kacheln 26–34 / 26–29). Sie dienen nur der Vorschau `preview_over_minimap.png`. Für neue Zonen braucht es dafür einen Minimap-Export aus wow.export (Mario).
- `build_raw.py` baut alle Zonen eines Laufs als **ein Mosaik**. Gemeinsame Grenzen sind damit nahtlos; die weiche Ausblendung (`EDGE_FADE`) liegt nur am Außenrand der gebauten Zonen. Deshalb immer alle gewünschten Zonen zusammen bauen (über `zones.txt`), nie einzeln nacheinander, sonst überschreiben sich Grenzkacheln.

**Stand Etappe 1 (1.2):** gebaut und im Stub getestet, Spieltest offen (Testliste 1.2 in Abschnitt 9).
- `build_raw.py` braucht für die 5 Zonen (13 × 13 Kacheln) wenige GB RAM; die Texturgewichte der ~570 Weg-Texturen werden direkt in ein Raster summiert (vorher ein Raster je Textur).
- Die Parameter sind unverändert (an Tirisfal kalibriert). Die Vorschau zeigt plausible Ergebnisse; ohne Minimap-Export der neuen Zonen ist der Abgleich aber nur grob möglich.
- Questbereiche angrenzender Zonen: umgesetzt (Abschnitt 5, Punkt 7). Ob `C_QuestLog.GetQuestsOnMap(Nachbarzone)` und `QuestPOIFrame:SetMapID(Nachbarzone)` in Forever liefern, ist im Spiel zu prüfen.

**Vorgehen in Etappen:**
1. **Etappe 1 (erledigt, siehe oben):** Nachbarn von Tirisfal: `Silverpine Forest`, `Western Plaguelands`, ggf. `Hillsbrad Foothills` (Namen exakt wie `AreaName_lang` in `AreaTable.csv` prüfen). In `zones.txt` eintragen, `build_raw.py` laufen lassen.
2. **Pro Zone prüfen** (Vorschauen in `build/`): Steigung bzw. Begehbarkeit, Wege, Wasser, Zonengrenze, Meeresküste. Die Parameter (`BLOCK_CLOSE`, `MIN_WALK`, `MIN_ISLAND`, Weg-Gewicht 0.3) sind an Tirisfal kalibriert und können je Landschaft (z. B. Pestländer, Gebirge in Hillsbrad) Nachjustieren brauchen.
3. **Im Spiel testen:** Übergang über die Zonengrenze ohne Kante oder Lücke, Zoom, Ladezeiten.
4. Weitere Etappen danach: restliche Östliche Königreiche.

**Risiken / offene Fragen:**
- **Speicher beim Bauen:** Das Mosaik hat 512 px pro Kachel und mehrere Ebenen. Für viele Zonen auf einmal wird das groß (ganze Östliche Königreiche ≈ mehrere GB RAM). Gelöst durch den Block-Build (Roadmap Schritt 1).
- **Addon-Größe:** seit 1.2 optimiert (Abschnitt 3, „Dateigröße“), Hochrechnung ≈ 70 MB für die Östlichen Königreiche. Größe je Etappe messen (Ausgabe von `build_raw.py`). Falls zwei Masken pro Textur im Spiel nicht funktionieren: Schraffur wieder als Bild in 256 px (≈ +10 MB für 5 Zonen).
- **`Tiles.lua`:** wird bei jedem Lauf komplett neu geschrieben; Kacheln nicht mehr gebauter Zonen bleiben sonst als Dateien liegen (vor einem Lauf `Runeway/tiles/0` leeren).
- **Städte:** Undercity bzw. Ruinen von Lordaeron bleiben über `structures.py` erhalten. Andere Städte (z. B. Ironforge, Stormwind) brauchen eigene WMO-Exporte, siehe unten „Weitere Städte“.

**Questbereiche angrenzender Zonen (`QuestAreas.lua`):**
- **Heute:** Abgefragt und abgetastet werden nur die Quests der aktuellen Zonenkarte (`C_Map.GetBestMapForUnit`). Bereiche jenseits der Grenze fehlen, grenzüberschreitende Bereiche werden an der Grenze abgeschnitten, weil die Weltkarte jeder Zone nur ihren Ausschnitt liefert.
- **Plan:**
  1. Nachbarzonen bestimmen, deren Kartenrechteck das Sichtfeld schneidet: Kinder der Kontinentkarte (`C_Map.GetMapChildrenInfo`) mit ihren Weltrechtecken (`C_Map.GetWorldPosFromMapPos` an den Ecken bzw. `C_Map.GetMapRectOnMap`).
  2. Pro Nachbarzone die Quests (`C_QuestLog.GetQuestsOnMap`) holen und mit demselben `QuestPOIFrame`-Abtasten verarbeiten (`SetMapID` je Zone, Budget 3 ms pro Frame, aktuelle Zone zuerst).
  3. Ergebnisse liegen bereits in Weltkoordinaten vor und sind je Karte in `questAreaCache` gespeichert; beim Zeichnen die Bereiche aller relevanten Karten zusammenführen. Dieselbe Quest auf zwei Karten nur einmal zeichnen bzw. Teilbereiche zusammenführen.
  4. Questmarker (Punktziele) ebenso aus den Nachbarzonen übernehmen.
- **Prüfen:** ob `C_QuestLog.GetQuestsOnMap(Nachbarzone)` in Forever die Quests der Nachbarzone liefert, solange der Spieler nicht dort ist (Abschnitt 6: Bereiche kommen vom Server, nach dem Login auch ohne geöffnete Karte). Betroffen sind `QuestAreas.lua` (~Zeile 396) und die Questmarker in `Core.lua` (~Zeile 371).

### Später
- **Weitere Städte:**
  - WMO als OBJ exportieren (wow.export, „Split WMO Groups“, ohne Texturen) und auf `data` legen.
  - Turm- oder Mauer-M2 in `M2_BLOCKERS` eintragen.
  - Die Ausrichtung je Stadt gegen die Minimap prüfen, weil die Drehrichtung erst nahe 0° kalibriert ist.
- **Undercity unterirdisch (optional):** Ein Prototyp des Grundrisses aus den 197 Innen-Gruppen ist gezeigt, aber nicht eingebaut. Dafür bräuchte es eine eigene Ebene, die über die Karten-ID umschaltet; die ID per `/rnw pos` in Undercity ermitteln.
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
python tests/run_stub.py                      # lädt das Addon (Lua 5.1) gegen einen WoW-API-Stub, prüft Kacheln/Questbereiche/Zoom-Laden
python tests/render_quest_outlines.py <SavedVariables/Runeway.lua>   # Questumrisse aus Probe-Daten mit dem Addon-Code
python scripts/simulate.py                    # Darstellung aus den Kacheln
cd <repo> && zip -r build/Runeway-1.2.zip Runeway
```

**Testwerkzeug `/rnw probe`:** Nur in Entwicklungsbuilds; dazu `tools/Probe.lua` in den Addon-Ordner kopieren und in der `.toc` eintragen. Es tastet die Questbereiche der aktuellen Zone ab und speichert sie in `RunewayDB.probe`. Die Auswertung macht `scripts/probe_view.py`.

**Installation:** Alten Ordner `Interface\AddOns\Runeway` löschen, `Runeway-1.2.zip` dort entpacken und WoW komplett neu starten. Neue Texturdateien (hier die Kacheln der neuen Zonen) lädt WoW erst nach einem Neustart, `/reload` reicht nicht.

**Testliste 1.2 (Etappe 1, offen):**
1. **Neue Zonen:** Silverpine, Western Plaguelands, Hillsbrad, Alterac ablaufen: Begehbarkeit, Wasser, Wege, Küste plausibel? Auffällige Stellen mit `/rnw pos` und Screenshot melden.
2. **Zonengrenzen:** Übergang Tirisfal ↔ Silverpine und Tirisfal ↔ Western Plaguelands ohne Kante, Lücke oder Flackern, in allen Zoomstufen. Außenrand (z. B. Richtung Eastern Plaguelands) blendet weich aus.
3. **Ladezeit:** spürbare Ruckler beim Zoomen oder an Zonengrenzen?
4. **Schraffur (neu als Muster + Maske):** nur auf nicht begehbaren Flächen, beim Drehen deckungsgleich mit den Geländelinien, weicher Rand zum Kartenrand wie bisher, keine Nähte zwischen Kacheln, Zoomstufen-Wechsel ohne Springen.
5. **Questbereiche Nachbarzone:** In Tirisfal nahe der Grenze eine Quest aus Silverpine im Log haben: Ihr Bereich erscheint (nach etwa 1 s), auch wenn man noch in Tirisfal steht. Beim Herauszoomen kommen weitere Zonen hinzu.
6. **Questmarker Nachbarzone:** Abgabe-Marker einer Quest der Nachbarzone erscheint, ohne doppelt zu sein.
7. **Grenzüberschreitender Bereich:** Ein Bereich über die Zonengrenze wird nicht an der Grenze abgeschnitten und nicht doppelt gezeichnet.
8. **Zonen-Dimmung:** In Tirisfal ist Tirisfal voll, die Nachbarzonen gedimmt („Other zones“, Standard 30 %). Beim Überschreiten der Grenze tauschen die Zonen weich (~0,4 s). Kein Flackern direkt auf der Grenze, keine sichtbaren Kachelkanten im Übergang.
9. **Wege, Standardwerte, Kombinieren-Option:** Wege glatt und gleich breit wie Geländelinien; „Standard“ setzt die neuen Werte; „Combine overlapping quest areas“ aus → jede Quest eigener Umriss.
10. **Leichnam:** Sterben, Geist freigeben: der Leichnam ist auf der Karte markiert, außerhalb des Sichtfelds am Rand in seiner Richtung; nach der Wiederbelebung verschwindet der Marker.

**Testliste 1.1 (Punkt 3.4, alle Punkte im Spiel bestanden):**
1. **Optionen:** Optionen → AddOns → Runeway und `/rnw config` öffnen die Seite. Alle Regler, Häkchen und Farbfelder wirken sofort. „Standard“ setzt die jeweilige Seite zurück.
2. **Farbe:** Ein Farbfeld öffnet den Farbwähler. „Abbrechen“ stellt die alte Farbe wieder her.
3. **Rand:** Die Stufen 1–5 sind sichtbar unterschiedlich. Die Questränder blenden passend dazu aus.
4. **Mausrad gesperrt:** Über der Karte wird gezoomt, Klicks gehen durch die Karte hindurch.
5. **Entsperrt:** Ziehen verschiebt. Der Griff unten rechts ändert Breite und Höhe unabhängig. Der Rahmen erscheint beim Überfahren.
6. **Taste M:** M öffnet und schließt das Overlay, die Belegung „World map (map key mode)“ öffnet die Weltkarte. Auch nach einem Kampf und nach `/reload` prüfen.
7. **Permanent:** Das Overlay ist nach dem Login sichtbar.
8. **Ausblenden:** Kampf, Instanz, Reittier oder Flug und Stadt einzeln prüfen. Nach dem Ende der Bedingung erscheint das Overlay wieder.

**Abnahme-Checkliste (für spätere Builds):**
1. **Look:** Kartenstil wie im Diablo-Screenshot.
2. **Zoom:** nahtlos, ohne Flackern und ohne Kachelkanten.
3. **Quest areas:** durchgehend in jeder Zoomstufe, weich ausgeblendet zum Kartenrand, korrekt bei Fortschritt.
4. **Quest marks:** nur für Punktziele, ohne Springen beim Gehen.
5. **City:** Ruinen von Lordaeron erkennbar, auch herausgezoomt.
6. **Window:** Position, Breite und Höhe bleiben über Logout erhalten.

---

## 10. Start-Prompt für die nächste Session

```text
Projekt Runeway (WoW-Forever-Addon). Repo mschettl/Runeway, Entwicklungsbranch claude/dreamy-lovelace-efolxg.
Lies zuerst CLAUDE.md, Runeway_Status_v1.md und Runeway_Prompt_v1.md.
Version 1.1 ist abgeschlossen und in main gemergt (PR #2), 1.2 (Etappe 1, Kachel-Optimierung) auf dem Entwicklungsbranch.
Langfristziel und Architektur: Runeway_Status_v1.md, Abschnitt 8 „Roadmap“.
Aufgabe dieser Session: Fundament (Block-Build, Schraffur in Weltkoordinaten, Kachelliste pro Karten-ID),
danach weitere Etappen der Östlichen Königreiche, siehe Abschnitt 8.
Rohdaten liegen auf dem Branch data (git fetch origin data, siehe Abschnitt 2). Kommunikation Deutsch, Code Englisch.
```
