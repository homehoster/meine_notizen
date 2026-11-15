# Notiz-App (Flutter) für Memos

## 1. Voraussetzungen
- Flutter SDK >= 3.22 (`flutter doctor` muss grün sein)
- Android Studio (Android) bzw. Xcode auf einem Mac (iOS)

## 2. Projekt erzeugen
```bash
flutter create --org com.github.homehoster --project-name notiz_app --platforms=android,ios notiz_app
flutter pub add http provider shared_preferences flutter_secure_storage path_provider flutter_markdown home_widget url_launcher
```

## 3. Android: AndroidManifest.xml
Datei: `android/app/src/main/AndroidManifest.xml`

a) Im `<activity android:name=".MainActivity" ...>` zusätzlich:
```xml
<intent-filter>
    <action android:name="es.antonborri.home_widget.action.LAUNCH" />
</intent-filter>
```
b) Direkt vor `</application>`:
```xml
<receiver android:name=".NoteWidgetProvider" android:exported="true">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
    </intent-filter>
    <meta-data android:name="android.appwidget.provider"
               android:resource="@xml/note_widget_info" />
</receiver>
```
c) Nur falls dein Server per `http://` (ohne TLS) läuft: im `<application ...>`-Tag
`android:usesCleartextTraffic="true"` ergänzen.

d) `android/app/build.gradle(.kts)`: `minSdk` mindestens 23
(`flutter_secure_storage`). Neuere Flutter-Vorlagen erfüllen das oft schon.

## 4. iOS (nur auf dem Mac)
```bash
cd ios && pod install && cd ..
open ios/Runner.xcworkspace
```
In Xcode:
1. Runner → Signing & Capabilities → **+ Capability → App Groups** → `group.com.github.homehoster.meine_notizen`
2. File → New → Target → **Widget Extension** (Name `NoteWidget`, "Include Live Activity/Configuration" abwählen)
3. Dort ebenfalls App Group `group.com.github.homehoster.meine_notizen` hinzufügen
4. Generierte Swift-Dateien des Targets löschen, `ios_widget_source/NoteWidget.swift` hinzufügen
5. Runner → Info → **URL Types** → URL Scheme `notizapp`

## 5. Starten
```bash
flutter run                 # Gerät/Emulator
flutter build apk --release # Android-APK
```

## 6. Token erzeugen
Memos → Settings → My Account → Access Tokens → neuen Token anlegen.
In der App: Seitenmenü links → Einstellungen → Server-URL + Token → "Testen & speichern".
Die App verwendet die aktuelle Memos-REST-API unter `/api/...`; ältere Server,
die nur `/api/v1/...` unterstützen, sind damit nicht kompatibel.

## Bedienung
- Notiz → Reiter **Ansicht** (Markdown gerendert + interaktive Aufgaben), **Editor** (Toolbar für Fett, Liste, Link, Aufgabe …), **Markdown** (roh).
- Aufgaben: Ziehgriff = Reihenfolge, Menü ⋮ = Unteraufgabe/Löschen, Haken auf Hauptaufgabe setzt alle Unteraufgaben mit; erledigte landen im Bereich "Erledigt".
- Widget: in der Liste (⋮) oder in der Notiz das Widget-Symbol → bis zu 5 Notizen, Tipp öffnet die Notiz.
- Lokal gespeichert wird in `notes.json`; Änderungen offline werden beim nächsten Sync hochgeladen.

## Ereignisprotokoll
- Die App protokolliert Aufrufe der Fachfunktionen und Ereignisse automatisch, z. B. Start, Synchronisation, Notizänderungen und Fehler.
- Protokolliert werden Funktionsnamen, keine Funktionsargumente. Die interne Log-Infrastruktur wird nicht selbst protokolliert.
- Android: `Downloads/notizen.log` (auf Android 9 und älter wird dafür eine Speicherberechtigung benötigt).
- iOS: App-Dokumente im Unterordner `logs`.
- Alle Einträge werden in dieselbe Datei `notizen.log` geschrieben. Notiztexte und Zugangstokens werden nicht protokolliert.
