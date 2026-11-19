# LiDAR Studio

Native iOS‑26‑App mit **Liquid Glass** zum Scannen, Vermessen und Exportieren mit dem LiDAR‑Sensor von iPhone Pro und iPad Pro.

<p align="center"><img src="LidarStudio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="160" alt="App-Icon"></p>

## Funktionen

| Modus | Technik | Export |
|---|---|---|
| **Raum scannen** | RoomPlan: Wände, Türen, Fenster, Öffnungen, Möbel; Bodenfläche, Wandlänge, Raumhöhe, Volumen | USDZ (parametrisch), JSON |
| **Objekt erfassen** | Object Capture + Photogrammetrie direkt auf dem Gerät, mehrere Durchgänge, Wenden | USDZ mit Texturen |
| **3D‑Mesh** | ARKit Scene Reconstruction mit Live‑Drahtgitter und Klassifizierungsfarben (Wand, Boden, Decke, Tisch, Sitz, Fenster, Tür) | USDZ, OBJ (Vertex‑Farben), PLY |
| **Punktwolke** | LiDAR‑Tiefenkarte + Kamerafarbe, Voxel‑Deduplizierung, Live‑Vorschau | PLY (binär), XYZ |
| **Messen** | Strecke, Pfad, Fläche (3D‑Polygon), Punkte speichern; Live‑Abstand, Einrasten zum Schließen | JSON, CSV (Punkte & Strecken) |

Außerdem:

- Öffnungsanimation mit Laser‑Scan über ein Punktraster und Glas‑Emblem
- Durchgehend natives Liquid Glass: `glassEffect`, `GlassEffectContainer`, `glassEffectID`, `.glass`/`.glassProminent`‑Buttons, Tab‑Bar mit `tabBarMinimizeBehavior` und `tabViewBottomAccessory`
- Bibliothek mit Suche, Filtern, Favoriten, 3D‑Vorschaubildern
- Interaktiver 3D‑Viewer (Orbit/Zoom) und **AR Quick Look** für USDZ
- Alle Dateien auch in der **Dateien‑App** sichtbar
- Einstellungen: metrisch/imperial, Haptik, Punktdichte, Konfidenz, maximale Tiefe

## Voraussetzungen

- iOS 26 oder neuer
- Gerät mit LiDAR (iPhone 12 Pro und neuer Pro‑Modelle, iPad Pro ab 2020) für Raum‑, Mesh‑, Punktwolken‑ und Objekt‑Scans. Messen geht auch ohne LiDAR, dann ungenauer.

## Build über GitHub Actions

Der Workflow `.github/workflows/build-ios.yml` läuft bei jedem Push:

1. macOS‑26‑Runner, neuestes Xcode 26
2. `xcodegen generate` erzeugt das Xcode‑Projekt aus `project.yml`
3. Release‑Build für `iphoneos` ohne Signierung
4. Das **unsignierte IPA** liegt als Artifact `LidarStudio-unsigned-ipa` am Workflow‑Lauf

Bei einem Tag `v*` (z. B. `v1.0.0`) wird zusätzlich ein GitHub‑Release mit dem IPA erstellt.

### Installieren

Das IPA ist unsigniert. Signiere es mit deiner Apple‑ID, z. B. über **Sideloadly**, **AltStore** oder **SideStore**, oder baue lokal:

```bash
brew install xcodegen
xcodegen generate
open LidarStudio.xcodeproj   # Team auswählen, auf dem iPhone ausführen
```

## Projektstruktur

```
LidarStudio/
├── App/            App-Einstieg, Tabs, Öffnungsanimation
├── Design/         Theme, Liquid-Glass-Komponenten
├── Models/         Scan-Modelle, Speicher, Messungen
├── Services/       3D-Laden, Mesh/PLY-Export, Punktwolke, Hilfen
└── Features/
    ├── Home/           Startseite
    ├── Room/           RoomPlan
    ├── ObjectCapture/  Object Capture + Photogrammetrie
    ├── LidarCapture/   3D-Mesh & Punktwolke
    ├── Measure/        Messwerkzeug
    ├── Library/        Bibliothek
    ├── Detail/         3D-Viewer & Details
    └── Settings/       Einstellungen
```
