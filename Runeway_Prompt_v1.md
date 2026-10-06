# Runeway – Umsetzungsprompt für Version 1

> Name: **Runeway** (vormals ContourMap, kurzzeitig Wayfinder; „Wayfinder“ ist als Addon bereits vergeben). Addon-Ordner `Runeway`, SavedVariables `RunewayDB`, Slash-Befehle `/runeway` und `/rnw` (nicht `/rw`, das ist in WoW die Schlachtzugswarnung). Alte Einstellungen werden nicht übernommen.

> Diesen Prompt zusammen mit `Runeway_Projekt.zip` (Addon 0.5 + Build-Skripte) an Claude geben.
> Kommunikation mit mir: Deutsch. Bitte knapp, technisch präzise, schlanker Code ohne unnötige Abstraktion, iterativ statt Neuentwurf.
> **Entwicklungssprache: Englisch.** Code, Bezeichner, Kommentare, Dateinamen, Chat-Ausgaben, Slash-Befehle und alle Texte der Konfigurationsoberfläche auf Englisch. Bestehende deutsche Kommentare und Texte aus 0.5 (z. B. `Groesse`, `zurueckgesetzt`, Hinweiszeile) dabei ins Englische überführen.

---

## 1. Kontext

Ich (Mario) entwickle mein erstes World-of-Warcraft-Addon **Runeway**: ein transparentes, spielerzentriertes Karten-Overlay im Stil von **Path of Exile / Diablo 4** (seit „Lord of Hatred“ hat D4 ebenfalls eine Overlay-Karte mit einstellbarer Deckkraft und Farbe, Umschalten per M).

Zielclient ist **WoW Forever** (das neue Classic, Interface `16001`). Die API orientiert sich an **Classic Era**, nicht an Retail. Als Referenz für Blizzard-UI-Code daher den Classic-Era-Branch der gespiegelten UI-Quellen verwenden. Später optional Retail zusätzlich (zweite Interface-Nummer kommagetrennt in der `.toc`).

Mein PC ist über den Claude Desktop-App-Link verbunden. Dateien unter `C:\Users\MarioSchettler\wow.export\` und `C:\Projekte\Runeway\` kannst du selbst holen (Ordnerzugriff anfragen).

**Benötigte Eingangsdaten (Voraussetzung für Abschnitt 3.1):**
- Minimap-Kacheln (bereits vorhanden, Tirisfal): `C:\Users\MarioSchettler\wow.export\maps\azeroth\minimap\map<spalte>_<zeile>.png`
- **RAW-Kacheln (ADT) der Östlichen Königreiche:** `C:\Projekte\Runeway\Wow export files` (Unterordner je nach wow.export-Struktur selbst ermitteln, Ordnerzugriff anfragen). Ohne diese Daten mit 3.1 nicht beginnen, sondern danach fragen. Bis dahin können 3.2 (Ebenen-Trennung auf Basis der Minimap-Pipeline) und 3.4 (Konfiguration) vorgezogen werden.
- Heightmaps 512×512 und die CSVs `QuestPOIBlob` / `QuestPOIPoint`: optional, ebenfalls unter `C:\Projekte\Runeway\Wow export files`.

## 2. Aktueller Stand (Version 0.5)

Ordnerstruktur:

```
Runeway/
├── Runeway.toc      (Interface 16001, SavedVariables: RunewayDB)
├── Tiles.lua           (automatisch erzeugt: Liste vorhandener Kacheln je Instanz)
├── Core.lua            (gesamte Logik)
├── Bindings.xml        (Tastenbelegung RUNEWAY_TOGGLE)
├── media/fade.tga      (ovale Ausblendmaske), dot.tga (runder Quest-Marker), arrow.tga (blau leuchtender Pfeil)
└── tiles/0/<c>_<r>.tga (512 px) + tiles/0/256/ + tiles/0/128/ (Zoomstufen)
```

Funktioniert bereits:
- Spielerzentriert, Karte dreht mit Blickrichtung (`/rnw rotate` schaltet auf Norden oben)
- Linienbilder je ADT-Kachel in Weltkoordinaten: Gelände-Konturen (lila), Wasser (blau), Wege (beige), dunkler Kontrast-Saum
- Weiches Ausblenden zum Rand per `MaskTexture`, kein Rahmen
- Zoom 0,08–5 (Mausrad), drei Auflösungsstufen je nach Zoom
- Quest-Marker (runde gelbe Punkte) über `C_QuestLog.GetQuestsOnMap` → `C_Map.GetWorldPosFromMapPos`, Achsenreihenfolge wird am Spieler automatisch geprüft
- Deckkraft, Größe, Position, Sperre (gesperrt = klickdurchlässig), Button „Overlay“ auf der Weltkarte
- Slash-Befehle `/rnw`, `lock`, `unlock`, `alpha`, `zoom`, `size`, `rotate`, `pos`, `reset`
- Bisher nur Tirisfal + Umgebung (Kacheln 26–34 / 26–29)

Wichtige technische Fakten (bereits verifiziert):
- `UnitPosition("player")` liefert `(Nord, West, _, instanzID)`. Östliche Königreiche = Instanz 0.
- ADT-Kachel = 1600/3 Yards. Kachelmitte: `nord = (32 - zeile) * T - T/2`, `west = (32 - spalte) * T - T/2`. Minimap-Dateien heißen `map<spalte>_<zeile>.png`. Geprüft: Position 1917,6 / 84,9 liegt in Kachel 31_28 (nordöstlich von Undercity).
- Forever liefert bei `C_MapExplorationInfo` kein `numTexturesWide/Tall` → aus Texturgröße berechnen (Classic-Verhalten).
- TGAs mit `orientation=1` (Ursprung unten links) speichern. Neue Texturdateien brauchen einen kompletten WoW-Neustart, `/reload` reicht nicht.
- Bekannte Unschärfe: Silberwald und Hügel von Hillsbrad erzeugen Gekrakel bei der Wege-Erkennung, der große See bei Brill wird nur halb als Wasser erkannt.
- Offen zu prüfen: Ist der Rahmen in 0.5 im Spiel wirklich weg? Unterstützt Forever `CreateMaskTexture` (sonst Chat-Hinweis beim Login)?

Build-Pipeline (Python, OpenCV, scikit-image, Pillow): `build_tiles.py` setzt Minimap-Kacheln zusammen, erkennt Wasser (Farbe), Fels/Klippen (Orange) → begehbare Fläche, Wege (Top-Hat-Filter + Skelett + Pruning, `roads.py`), zeichnet Linien und schneidet sie in Kacheln.

## 3. Aufgaben für Version 1

### 3.1 Daten aus dem RAW-Export
Ich exportiere mit wow.export die **Östlichen Königreiche** als:
- **RAW** (ADT-Dateien), ohne Modell-Haken (WMO, M2, Foliage, G-Objects aus)
- **Heightmaps** 512×512, 32-Bit
- falls möglich die DB2-Tabellen **QuestPOIBlob** und **QuestPOIPoint** als CSV

Daraus:
1. ADT-Parser in Python (Chunks MCNK/MCVT für Höhen, MH2O für Wasser, MTEX/MCLY/MCAL für Bodentexturen).
2. **Begehbarkeit aus Steigung** statt Farbschätzung → Gelände-Konturen.
3. **Wasser** aus MH2O mit exakten Rändern.
4. **Wege** aus Bodentexturen mit Namen wie Road, Dirt, Path → inklusive Feldwege.
5. Auf Zonengrenzen zuschneiden, Gekrakel entfernen.
6. Zuerst Tirisfal als Test, dann alle Zonen der Östlichen Königreiche in Etappen.
7. Ergebnis jeweils als Vorschau-PNG prüfen, bevor Kacheln gebaut werden.

### 3.2 Kacheln mit einfärbbaren Ebenen
- Pro Kachel und Zoomstufe getrennte, **weiße** Ebenen: `terrain`, `water`, `roads`, plus neutrale Ebene `shade` (dunkler Kontrast-Saum).
- Das Addon färbt zur Laufzeit per `SetVertexColor`.
- `Tiles.lua` entsprechend erweitern (welche Ebenen pro Kachel existieren).
- Dateigröße im Blick behalten, ggf. Ebenen kombinieren (z. B. ein RGBA-Bild pro Kachel mit je einem Kanal pro Ebene ist in WoW nicht direkt einfärbbar → getrennte Dateien bevorzugen).

### 3.3 Questgebiete
- Aus QuestPOIBlob/QuestPOIPoint Umrisse je Quest und Ziel in Weltkoordinaten.
- Nur für aktive Quests im Questlog einblenden, im Stil des Overlays (Umriss, keine Füllung, eigene Farbe, konfigurierbar).
- Falls die Tabellen im Forever-Client fehlen: sagen, Alternative vorschlagen.

### 3.4 Konfigurationsoberfläche
Einhängen unter **Optionen → AddOns → Runeway** (Classic-kompatible API prüfen: `Settings.RegisterCanvasLayoutCategory` bzw. `InterfaceOptions_AddCategory`) und zusätzlich über `/rnw config` öffnen. Alle Werte in `RunewayDB`.

**Darstellung**
- Farbe getrennt für Gelände, Wasser, Wege, Quest-Marker, Questgebiete (Blizzard-Farbwähler `ColorPickerFrame`)
- Deckkraft global und optional pro Ebene
- Ebenen einzeln ein-/ausblendbar
- Stärke des weichen Rands
- Mitdrehen ein/aus
- Zoomstufe als Wert

**Aufruf und Verhalten**
- Modus **„Taste M“**: M schaltet das Overlay statt der Weltkarte (per `SetOverrideBinding`, taint-sicher). Die normale Weltkarte bleibt über eine frei belegbare Taste erreichbar.
- Modus **„Eigene Taste“**: M unverändert, Overlay über eigene Belegung.
- Modus **„Permanent“**: Overlay immer an.
- **Automatisch ausblenden**, einzeln wählbar: im Kampf, in Instanzen, beim Reiten/Fliegen, in Städten.

**Bedienung des Fensters** (festgelegtes Verhalten)
- **Zoom per Mausrad** nur, wenn die Maus direkt über der Karte ist, und zwar **gesperrt wie entsperrt**. Technisch: `EnableMouseWheel(true)` immer, `EnableMouse` nur im entsperrten Zustand, damit Klicks im gesperrten Zustand durchgehen.
- **Verschieben** nur im entsperrten Zustand.
- **Größe ziehen** über einen **Griff unten rechts**, **ausschließlich im entsperrten Zustand**. Der Griff ändert nur die Fenstergröße, **der Zoom bleibt getrennt**. Im gesperrten Zustand ist der Griff unsichtbar und die Größe fix. Shift + Mausrad bleibt als Zweitweg für die Größe (nur entsperrt).
- **Hover-Rahmen:** Im entsperrten Zustand erscheint beim Überfahren mit der Maus ein dezenter Rahmen und blendet beim Verlassen wieder aus. Gesperrt bleibt die Karte rahmenlos. Der Hover-Effekt ist in der Konfiguration abschaltbar.
- **Größenanzeige:** Beim Ziehen, Verschieben und Zoomen wird „Breite × Höhe“ in Pixeln plus Zoomstufe eingeblendet und blendet nach kurzer Zeit ohne Aktion wieder aus.

### 3.5 Abschluss
- Lua-Syntax prüfen (z. B. per `lupa`), Darstellung mit derselben Mathematik in Python simulieren.
- Version auf **1.0** setzen, ZIP bauen und mir senden, Installationshinweis (alten Ordner löschen, WoW komplett neu starten).
- Testliste für mich: Was ich im Spiel prüfen und als Screenshot zurückmelden soll.

## 4. Version 2 (noch nicht umsetzen)

- **Route zum Questziel** als hervorgehobene Linie: Raster „begehbar / nicht begehbar“ aus den RAW-Höhendaten, Wege mit Bonus, klassische Wegsuche (A*). Grenzen: Höhlen, mehrstöckige Gebäude, unsichtbare Barrieren.
- Weitere Kontinente (Kalimdor) und Instanzen.

## 5. Arbeitsweise

- Mit einer Aufgabenliste arbeiten, Zwischenstände früh zeigen (Vorschau-Bilder), damit ich korrigieren kann.
- Bei Unsicherheit über die Forever-API: Classic-Era-Quellcode prüfen statt raten.
- Erst fragen, wenn eine Entscheidung wirklich offen ist. Sonst die naheliegende Lösung wählen und kurz sagen, welche.
