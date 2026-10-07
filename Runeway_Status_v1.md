# Runeway – Stand Version 1.1 und Übergabe

Diese Datei fasst den kompletten Stand nach Version 1.1 zusammen, damit eine neue Session nahtlos weitermachen kann. Sie ersetzt den Chatverlauf. Vorgaben und Ziele stehen in `Runeway_Prompt_v1.md`, Arbeitsregeln in `CLAUDE.md`.

---

## 1. Kurzüberblick

Runeway ist ein spielerzentriertes, mitdrehendes Karten-Overlay für **WoW Forever** (Interface 16001) im Stil von Path of Exile und Diablo IV.

**Stand 1.0:**
- **Zone:** Tirisfal ist vollständig aus den RAW-Spieldaten gebaut. Die Ruinen von Lordaeron sind als Stadt eingezeichnet.
- **Kartenebenen:** Begehbare Fläche (Braunton), schraffierte nicht begehbare Bereiche (Gebirge, Wasser, Mauern), Geländelinien, Wasserlinien und Wege.
- **Questbereiche:** Exakt dieselben Bereiche wie auf der Weltkarte, als blauer, mitdrehender Rand.
- **Questmarker:** Nur für punktuelle Ziele (Abgabe, Gespräche), im Weltkarten-Stil.
- **Zoom:** Nahtlos durch Überblendung der Kachel-Zoomstufen. Die Karte ist quadratisch und blendet rund aus.

Im Spiel getestet und für Version 1 abgenommen.

**Stand 1.1 (im Spiel getestet und abgenommen):** Punkt 3.4 ist umgesetzt. Dazu gehören die Einstellungsseite im Blizzard-Stil (`Options.lua`), die Aufruf-Modi samt eigener Weltkarten-Tastenbelegung, das automatische Ausblenden und die Fensterbedienung laut Vorgabe.

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
| `media/` | `fade1.tga`–`fade5.tga` (runde Ausblendmasken je Randstärke, erzeugt mit `scripts/make_masks.py`), `arrow.tga` (Spielerpfeil), `edge.tga` (kantengeglättete Linientextur), `dot.tga` (Rückfall-Symbol) |
| `tiles/0/[256/ \| 128/]<c>_<r>_<layer>.tga` | weiße RLE-TGA-Kacheln je Ebene und Zoomstufe (512/256/128 px). Tirisfal: 42 Kacheln, ~22 MB |

`tools/Probe.lua` ist ein Entwicklungswerkzeug und nicht im Release (siehe Abschnitt 6).

### Ebenen (Zeichenreihenfolge, Kennbuchstabe in `Tiles.lua`)
`fill` (f, begehbar) → `hatch` (h, Schraffur nicht begehbar) → `shade` (s, dunkler Saum) → `terrain` (t) → `water` (w) → `roads` (r). Darüber `questAreas` (Linien aus `QuestAreas.lua`), Questmarker und Spielerpfeil.

Kacheln sind weiß. Eingefärbt wird zur Laufzeit per `SetVertexColor`.

### Standardwerte (`RunewayDB`)
| Schlüssel | Standard |
|---|---|
| `w` | 600 (quadratisch, Seitenlänge) |
| `zoom` | 1.5 (0.08–5) |
| `alpha` | 0.7 (nur Kartenebenen; Pfeil, Marker und Questränder immer voll) |
| `rotate`, `locked`, `shown` | true, false, false |
| `colors.fill` | 0.80 / 0.64 / 0.44, a 0.07 |
| `colors.hatch` | 0.80 / 0.84 / 0.88, a 0.22 |
| `colors.shade` | 0.05 / 0.05 / 0.06, a 0.45 |
| `colors.terrain`, `colors.water` | 0.82 / 0.86 / 0.89, a 0.85 |
| `colors.roads` | 0.82 / 0.86 / 0.89, a 0.4 |
| `colors.questAreas` | 0.45 / 0.78 / 1.00, a 1 |
| `layers.*` | alle true |
| `mode` | `"key"` (eigene Taste), `"mapkey"` (Kartentaste M öffnet das Overlay), `"permanent"` |
| `autoHide.combat/instance/mounted/city` | alle false (`city` = ausgeruht, also Städte und Gasthäuser) |
| `hover` | true (Rahmen bei Mausüberfahrt, nur entsperrt) |
| `edge` | 3 (Randstärke 1–5, Breite 0,12 / 0,25 / 0,38 / 0,55 / 0,75 des Radius) |
| `arrowSize`, `pinSize`, `questEdge` | 23, 26, 1 (Faktor für die Breite der Questränder) |
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
  - Der Griff unten rechts ändert die Größe. Sie bleibt quadratisch, die obere linke Ecke bleibt stehen.
  - Shift+Mausrad ändert die Größe.
  - Beim Überfahren erscheint ein Rahmen, abschaltbar.
- **Größenanzeige:** „B × H Zoom“ erscheint beim Verschieben, Größe ändern und Zoomen. Sie blendet nach 1,5 s aus.

**Sichtbarkeit (`UpdateVisibility`):**
- **Grundregel:** Angezeigt wird, wenn `mode == "permanent"` oder `shown` gesetzt ist und keine Bedingung zum automatischen Ausblenden greift.
- **Ausblend-Bedingungen:** Sie werden alle 0,25 s abgefragt, Kampfbeginn und Kampfende zusätzlich per Event.
- **Umschalten:** Während einer Ausblend-Bedingung oder im Modus „Permanent“ setzt das Umschalten eine Übersteuerung. Sie gilt, bis sich der Ausblend-Zustand ändert.

**Tastenmodi (`ApplyBindings`):**
- **Mechanik:** Nur Override-Bindings, damit kein Taint entsteht. Im Kampf wird die Anwendung bis `PLAYER_REGEN_ENABLED` verschoben.
- **Modus `mapkey`:** Die Tasten von `TOGGLEWORLDMAP` (Rückfall `M`) lösen `RUNEWAY_TOGGLE` aus. Die Tasten der Belegung `RUNEWAY_WORLDMAP` („World map (map key mode)“) lösen per Override `TOGGLEWORLDMAP` aus. Gesetzt wird sie als normale Tastenbelegung, direkt auf der Runeway-Seite. `UPDATE_BINDINGS` wendet alles neu an; `/rnw keys` zeigt den Stand.

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
python scripts/build_raw.py               # Zonen aus scripts/zones.txt (aktuell: Tirisfal Glades)
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
- **Wege:** Texturen mit „road“ oder „path“ im Namen, ab Gewicht 0.3, als Mittellinie (Skelett).
- **Zonen-Zuschnitt:** über AreaTable (Unterzonen → Hauptzone). Meeres-Chunks zählen nur in Küstennähe der Zone, denn „The Great Sea“ ist in der AreaTable eine Unterzone von Tirisfal.
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
4. **Überlappende Quests:** Sie werden zusätzlich gemeinsam abgetastet und bekommen einen einzigen Umriss (`groups`).
5. **Neu abtasten:** nur, wenn sich die Signatur ändert (Anzahl Teilbereiche, Questpunkt, Zielfortschritt). Auslöser: `QUEST_LOG_UPDATE` (0,3 s gebündelt), `QUEST_POI_UPDATE`, Zonenwechsel. Ergebnisse werden je Karte in `RunewayDB.questAreaCache` gespeichert und sind nach `/reload` sofort da.
6. **Zeichnen:**
   - Linien-Objekte mit `media/edge.tga` (WoW glättet Linienkanten nicht, die Textur schon).
   - Am Bildschirm per Catmull-Rom in Stücke von etwa 6 px unterteilt.
   - Breite = Kachelgröße ÷ 140 (2–7 px), folgt also dem Zoom.
   - Segmente überlappen nur bei voller Deckkraft um 1 px.
   - Ausblendung zum Rand pro Segment über `SetVertexColor`.
7. **Questmarker (`Core.lua`):**
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
| 3.1 RAW-Daten (Begehbarkeit aus Steigung, Wasser aus MH2O, Wege aus Texturen, Zonen-Zuschnitt, Tirisfal) | **erledigt** für Tirisfal; weitere Zonen offen |
| 3.2 Einfärbbare Ebenen | **erledigt**, erweitert um `fill` und `hatch` |
| 3.3 Questgebiete | **erledigt**, über das Abtasten statt DB2 (die Tabellen sind leer) |
| 3.4 Konfigurationsoberfläche und Bedienung | **erledigt** in 1.1, im Spiel getestet |
| 3.5 Abschluss (Lua-Prüfung, Simulation, Version 1.0, ZIP) | **erledigt** (Tests mit Lua 5.1, `simulate.py`, Release-ZIP) |
| Zusätzlich | Diablo-IV-Stil, quadratische runde Karte, nahtloser Zoom, Ruinen von Lordaeron, Questmarker im Weltkarten-Stil |

---

## 8. Offene Punkte und nächste Schritte

### Nächste Schritte
- **Questmarker einfärbbar** (optional): Sie sind Atlas-Symbole und bisher nicht einfärbbar.
- **Questbereiche angrenzender Zonen:** aktuell nur die aktuelle Zone.

### Später
- **Weitere Zonen der Östlichen Königreiche:** Zonen in `scripts/zones.txt` ergänzen und `build_raw.py` laufen lassen. Für jede Zone die Vorschau prüfen (Steigung, Wege, Wasser, Zonengrenze).
  - Größenschätzung: Tirisfal sind ~22 MB, alle Östlichen Königreiche grob 300–500 MB. Bei Bedarf die Schraffur über dem offenen Meer auf einen Küstenstreifen begrenzen oder Fläche und Schraffur nicht in 512 px speichern.
- **Weitere Städte:**
  - WMO als OBJ exportieren (wow.export, „Split WMO Groups“, ohne Texturen) und auf `data` legen.
  - Turm- oder Mauer-M2 in `M2_BLOCKERS` eintragen.
  - Die Ausrichtung je Stadt gegen die Minimap prüfen, weil die Drehrichtung erst nahe 0° kalibriert ist.
- **Undercity unterirdisch (optional):** Ein Prototyp des Grundrisses aus den 197 Innen-Gruppen ist gezeigt, aber nicht eingebaut. Dafür bräuchte es eine eigene Ebene, die über die Karten-ID umschaltet; die ID per `/rnw pos` in Undercity ermitteln.
- **Questbereiche (optional):** Innenschein bzw. Schraffur wie auf der Minimap. Mit Linien gab es Artefakte an den Stoßstellen, das bräuchte gefüllte Flächen, z. B. Dreiecks-Texturen.
- **Prompt Version 2:** Route zum Questziel (A* auf dem Begehbarkeitsraster), Kalimdor, Instanzen.

### Bekannte Einschränkungen
- **Feldwege:** Erdwege mit Dirt-Texturen werden nicht erkannt, weil Dirt in Tirisfal normaler Untergrund ist.
- **Questbereiche:** Sie erscheinen beim ersten Mal nach Login oder Zonenwechsel mit etwa 1 s Verzögerung; danach kommen sie aus dem Zwischenspeicher. Gezeigt werden nur die Bereiche der Quests auf der aktuellen Zonenkarte.
- **Gebäude:** Außer Undercity und den Stadttürmen sind keine Gebäude eingezeichnet. Kleine Gebäude, z. B. in Brill, sind nicht berücksichtigt.

---

## 9. Testen und Release

```bash
python tests/run_stub.py                      # lädt das Addon (Lua 5.1) gegen einen WoW-API-Stub, prüft Kacheln/Questbereiche/Zoom-Laden
python tests/render_quest_outlines.py <SavedVariables/Runeway.lua>   # Questumrisse aus Probe-Daten mit dem Addon-Code
python scripts/simulate.py                    # Darstellung aus den Kacheln
cd <repo> && zip -r build/Runeway-1.1.zip Runeway
```

**Testwerkzeug `/rnw probe`:** Nur in Entwicklungsbuilds; dazu `tools/Probe.lua` in den Addon-Ordner kopieren und in der `.toc` eintragen. Es tastet die Questbereiche der aktuellen Zone ab und speichert sie in `RunewayDB.probe`. Die Auswertung macht `scripts/probe_view.py`.

**Installation:** Alten Ordner `Interface\AddOns\Runeway` löschen, `Runeway-1.1.zip` dort entpacken und WoW komplett neu starten. Wegen der neuen Masken `fade1–5.tga` und der neuen Tastenbelegung in `Bindings.xml` reicht `/reload` nicht.

**Testliste 1.1 (Punkt 3.4, alle Punkte im Spiel bestanden):**
1. **Optionen:** Optionen → AddOns → Runeway und `/rnw config` öffnen die Seite. Alle Regler, Häkchen und Farbfelder wirken sofort. „Standard“ setzt die jeweilige Seite zurück.
2. **Farbe:** Ein Farbfeld öffnet den Farbwähler. „Abbrechen“ stellt die alte Farbe wieder her.
3. **Rand:** Die Stufen 1–5 sind sichtbar unterschiedlich. Die Questränder blenden passend dazu aus.
4. **Mausrad gesperrt:** Über der Karte wird gezoomt, Klicks gehen durch die Karte hindurch.
5. **Entsperrt:** Ziehen verschiebt. Der Griff unten rechts ändert die Größe, die Karte bleibt quadratisch. Die Größenanzeige blendet aus. Der Rahmen erscheint beim Überfahren.
6. **Taste M:** M öffnet und schließt das Overlay, die Belegung „World map (map key mode)“ öffnet die Weltkarte. Auch nach einem Kampf und nach `/reload` prüfen.
7. **Permanent:** Das Overlay ist nach dem Login sichtbar.
8. **Ausblenden:** Kampf, Instanz, Reittier oder Flug und Stadt einzeln prüfen. Nach dem Ende der Bedingung erscheint das Overlay wieder.

**Abnahme-Checkliste (für spätere Builds):**
1. **Look:** Kartenstil wie im Diablo-Screenshot.
2. **Zoom:** nahtlos, ohne Flackern und ohne Kachelkanten.
3. **Quest areas:** durchgehend in jeder Zoomstufe, weich ausgeblendet zum Kartenrand, korrekt bei Fortschritt.
4. **Quest marks:** nur für Punktziele, ohne Springen beim Gehen.
5. **City:** Ruinen von Lordaeron erkennbar, auch herausgezoomt.
6. **Window:** quadratisch, Position und Größe bleiben über Logout erhalten.

---

## 10. Start-Prompt für die nächste Session

```text
Projekt Runeway (WoW-Forever-Addon). Repo mschettl/Runeway, Entwicklungsbranch claude/dreamy-lovelace-efolxg.
Lies zuerst CLAUDE.md, Runeway_Status_v1.md und Runeway_Prompt_v1.md.
Version 1.1 ist abgeschlossen (inkl. 3.4 Konfiguration). Nächste Schritte siehe Runeway_Status_v1.md, Abschnitt 8. Kommunikation Deutsch, Code Englisch.
```
