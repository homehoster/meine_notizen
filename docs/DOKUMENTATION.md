# Code-Dokumentation – Meine Notizen

Diese Seite beschreibt, **wie die App aufgebaut ist und was sie im Detail tut**. Eine Einführung für Anwender und die Einrichtung der Entwicklungsumgebung stehen in der **[README](../README.md)**.

## Inhaltsverzeichnis

1. [Überblick und Architektur](#1-überblick-und-architektur)
2. [Projektstruktur](#2-projektstruktur)
3. [Datenmodelle](#3-datenmodelle)
4. [Markdown-Parser für Listen](#4-markdown-parser-für-listen)
5. [Zustandsverwaltung (AppState)](#5-zustandsverwaltung-appstate)
6. [Synchronisation](#6-synchronisation)
7. [Lokale Speicherung](#7-lokale-speicherung)
8. [Memos-API](#8-memos-api)
9. [Bildschirme](#9-bildschirme)
10. [Homescreen-Widget (Android)](#10-homescreen-widget-android)
11. [Einstellungen, Sicherheit und Datenschutz](#11-einstellungen-sicherheit-und-datenschutz)
12. [Logging](#12-logging)
13. [Android-Konfiguration](#13-android-konfiguration)
14. [iOS-Status](#14-ios-status)
15. [Abhängigkeiten](#15-abhängigkeiten)
16. [Bekannte Einschränkungen](#16-bekannte-einschränkungen)

---

## 1. Überblick und Architektur

„Meine Notizen“ ist eine **Offline-first-App**: Die Wahrheit für die Bedienung ist immer der lokale Speicher. Die Verbindung zu einem Memos-Server ist optional und läuft im Hintergrund.

```
┌──────────────────────── Flutter (Dart) ────────────────────────┐
│                                                                │
│  Screens ──► AppState (Provider) ──► LocalStore  (SQLite)      │
│  (UI)            │                                             │
│                  ├──► MemosApi ──► Memos-Server (REST, Bearer) │
│                  ├──► HomeWidget ─────────────┐                │
│                  └──► LogService (Logdatei)   │                │
└───────────────────────────────────────────────┼────────────────┘
                                                ▼
                       ┌──────────── Android (Kotlin) ───────────┐
                       │ NoteWidgetProvider ► NoteWidgetService  │
                       │ MainActivity (Widget-Links per Channel) │
                       └─────────────────────────────────────────┘
```

Grundprinzipien:

- **Eine Quelle der Wahrheit:** `AppState` hält die Notizliste; die Screens lesen sie über `provider`.
- **Markdown als Format:** Eine Notiz ist ein einziger Markdown-Text (`content`). Die Listen-Ansicht ist nur eine bequeme Bearbeitungsoberfläche darüber – gespeichert wird immer Markdown.
- **Lokal zuerst:** Jede Änderung wird zuerst lokal gespeichert und erst danach (verzögert) zum Server gesendet.

---

## 2. Projektstruktur

### Dart (`lib/`)

| Datei | Aufgabe |
|-------|---------|
| `main.dart` | Einstiegspunkt. Initialisiert `AppState` und das Widget, baut `MaterialApp` (Hell/Dunkel/System, Farbschema Teal), verarbeitet Widget-Links (`openWidgetUri`) und leitet App-Lebenszyklus-Ereignisse an `AppState` weiter. |
| `models/note.dart` | Datenmodell `Note` samt Titel-Ermittlung und JSON-/Server-Konvertierung. |
| `models/task_doc.dart` | Markdown-Parser/-Serializer für Listen (`Task`, `TaskSeg`, `TextSeg`), Hilfsfunktionen für Aufgaben und die Widget-Vorschau (`widgetPreview`). |
| `state/app_state.dart` | Zentraler Zustand: Notizen, Einstellungen, Sync, verzögertes Senden, Widget-Aktualisierung. |
| `services/api.dart` | `MemosApi`: HTTP-Zugriff auf die Memos-REST-API. |
| `services/store.dart` | `LocalStore`: lokale SQLite-Datenbank und Offline-Cache. |
| `services/log.dart` | `LogService`: optionale, begrenzte Logdatei; Teilen über das System-Teilen-Menü. |
| `screens/home_screen.dart` | Startseite mit Notizkarten, Seitenmenü, Sync-Anzeige. |
| `screens/note_screen.dart` | Notizansicht und Editor mit Werkzeugleiste. |
| `screens/settings_screen.dart` | Server, Token, HTTPS-Schalter, Darstellung, Logging. |
| `widgets/task_seg_view.dart` | Interaktive Liste (Aufgaben, Aufzählung, Nummerierung) in der Ansicht. |

### Android (`android/app/src/main/`)

| Datei | Aufgabe |
|-------|---------|
| `kotlin/…/MainActivity.kt` | Flutter-Activity. Nimmt `notizapp://`-Links entgegen und reicht sie über einen `MethodChannel` an Flutter weiter. |
| `kotlin/…/NoteWidgetProvider.kt` | Widget-Provider: baut das Layout, verbindet die Liste und setzt die Klick-Aktionen. |
| `kotlin/…/NoteWidgetService.kt` | `RemoteViewsService`: liefert Titel, Vorschau und Bild-Thumbnail je Widget-Zeile. |
| `kotlin/…/WidgetActionActivity.kt` | Kleiner Dialog beim Tippen auf „+“ im Widget („Meine Notizen öffnen“ / „Neue Notiz“). |
| `res/layout/note_widget.xml`, `note_widget_row.xml` | Layout des Widgets und einer Listenzeile. |
| `res/drawable/widget_bg.xml`, `widget_fab_bg.xml` | Hintergrund des Widgets und runder „+“-Knopf. |
| `res/xml/note_widget_info.xml` | Widget-Metadaten (Mindestgröße 110 dp, skalierbar, kein periodisches Update). |
| `res/values/…`, `values-night/…` | Themes und Widget-Farben für den hellen bzw. dunklen Systemmodus. |

---

## 3. Datenmodelle

### `Note`

| Feld | Typ | Bedeutung |
|------|-----|-----------|
| `id` | `String` | Server-ID (Teil nach `memos/`) oder `local-<Zeitstempel>` für noch nie gesendete Notizen. |
| `content` | `String` | Gesamter Markdown-Text der Notiz. |
| `updated` | `DateTime` | Zeitpunkt der letzten Änderung (zur Sortierung). |
| `pinned` | `bool` | „Angeheftet“-Status; angeheftete Notizen stehen oben. |
| `dirty` | `bool` | Lokale Änderung ist noch nicht auf dem Server. |
| `deleted` | `bool` | Zum Löschen markiert, Löschung noch nicht auf dem Server. |
| `state`, `visibility`, `space` | Status und Sichtbarkeit | Normal/archiviert, Memos-Sichtbarkeit und zugeordneter Bereich. |
| `tags`, `attachments` | Listen | Vom Server gelieferte Tags und Dateianhänge. Tags werden bei älteren Serverantworten aus dem Markdown ermittelt. |
| `pendingAttachments`, `location` | lokale Medien | Noch hochzuladende Dateien sowie Standortdaten. |
| `busy` | `bool` | Nur im Speicher: gerade läuft ein Sendevorgang (wird nicht gespeichert). |

`SavedView` speichert Name, Symbol und optionale Filter lokal. Eine Ansicht kann nach Text, Tag, Anheftstatus, Anhängen und Standort filtern; Memos stellt dafür keinen eigenen Ansichts-Endpunkt bereit. `MemoSpace` bildet Name, Titel, Beschreibung und Symbol eines Memos-Bereichs ab.

Wichtige Eigenschaften:

- `isLocal` → `id` beginnt mit `local-`.
- `title` → erste nicht leere Zeile, ohne Markdown-Präfix (`#`, `-`, `* `, `[ ]`). Leere Notiz: „Leere Notiz“.

### Listenmodell (`task_doc.dart`)

Ein Dokument wird in **Segmente** zerlegt:

| Klasse | Bedeutung |
|--------|-----------|
| `TextSeg` | Zusammenhängender Text ohne Listen (wird als Markdown gerendert). |
| `TaskSeg` | Zusammenhängende Liste eines Typs (`TaskListType.task`, `bullet` oder `numbered`) mit Wurzel-Einträgen. |
| `Task` | Ein Listeneintrag: `text`, `done`, `children` (Unteraufgaben). |

---

## 4. Markdown-Parser für Listen

`parseDoc(String)` zerlegt den Text zeilenweise; `serializeDoc(List<Segment>)` schreibt ihn zurück.

**Erkannte Zeilen**

| Typ | Muster | Beispiel |
|-----|--------|----------|
| Aufgabe | `- [ ] Text` / `- [x] Text` (auch `*`) | `- [x] Eier` |
| Aufzählung | `- Text` / `* Text` | `- Brot` |
| Nummerierung | `1. Text` | `2. Milch` |

- **Verschachtelung:** Die Einrückung bestimmt die Ebene (2 Leerzeichen bzw. 1 Tab = 1 Ebene).
- **Segmentwechsel:** Ändert sich der Listentyp oder folgt normaler Text, beginnt ein neues Segment.
- **Rückschreiben:** Pro Ebene werden 2 Leerzeichen eingerückt, Aufgaben als `- [ ]`/`- [x]`, Aufzählungen als `-`, Nummerierungen **neu durchgezählt**. Leere Einträge ohne Unterpunkte werden weggelassen.

**Aufgabenlogik**

| Funktion | Verhalten |
|----------|-----------|
| `toggleTask` | Schaltet einen Eintrag **samt allen Unteraufgaben** um und gleicht danach die Eltern ab. |
| `syncParents` | Eine Elternaufgabe gilt als erledigt, wenn **alle** Kinder erledigt sind. |
| `hasDoneTask` | `true`, wenn der Eintrag oder ein Nachkomme erledigt ist (für den Bereich „Erledigt“). |
| `reopenTask` | Setzt einen Eintrag samt Kindern auf unerledigt. |
| `findTasks` | Sucht Aufgaben in der ganzen Notiz, deren Text die Eingabe enthält (Duplikatsuche). |
| `reorderVisible` | Sortiert um, ohne dass ausgeblendete (erledigte) Einträge durcheinandergeraten. |
| `removeTask` | Entfernt einen Eintrag rekursiv. |
| `widgetPreview` | Baut die Vorschau fürs Widget (siehe [Abschnitt 10](#10-homescreen-widget-android)). |

> **Wann wird umformatiert?** Der Serializer läuft nur, wenn du in der **Ansicht** eine Liste bearbeitest. Text, den du im **Editor** schreibst, bleibt unverändert, bis du in der Ansicht an einer Liste etwas änderst. Siehe auch [Bekannte Einschränkungen](#16-bekannte-einschränkungen).

---

## 5. Zustandsverwaltung (AppState)

`AppState` ist ein `ChangeNotifier` und wird über `provider` bereitgestellt.

**Felder (Auswahl)**

| Feld | Bedeutung |
|------|-----------|
| `baseUrl`, `token` | Zugangsdaten. Die URL liegt in `shared_preferences`, der Token im Keystore/Keychain. |
| `configured` | `true`, wenn URL **und** Token gesetzt sind. |
| `themeMode` | System, Hell oder Dunkel. |
| `notes`, `visible` | Alle Notizen bzw. die sichtbare, sortierte Liste (angeheftet zuerst, dann zuletzt geändert). |
| `navigation`, `selectedNotes` | Aktuelle Hauptansicht und gefilterte Notizen (Alle, Archiv, Bereich, Ansicht oder Tag). |
| `spaces`, `spacesSupported`, `savedViews` | Vom Server geladene Bereiche und deren Verfügbarkeit sowie lokal gespeicherte Ansichten. |
| `widgetIds` | IDs der Notizen, die im Widget erscheinen sollen. |
| `syncing`, `error` | Status und letzte Fehlermeldung der Synchronisation. |
| `notice` | Einmaliger Hinweis, z. B. wenn die lokale Datei wiederhergestellt wurde. |
| `logEnabled` | Logging an/aus (Standard: aus). |

**Wichtige Methoden**

| Methode | Zweck |
|---------|-------|
| `init()` | Lädt Einstellungen, Token und lokale Notizen, aktualisiert das Widget und startet – falls konfiguriert – die Synchronisation. |
| `create()` | Legt eine lokale Notiz (`local-…`) an. |
| `saveContent()` | Speichert Text lokal und plant das Senden. |
| `finishEditing()` | Beim Verlassen einer Notiz: lokal sichern, leere neue Notiz verwerfen, sonst sofort senden. |
| `deleteNote()` | Markiert als gelöscht (lokale Notizen verschwinden sofort) und löscht auf dem Server. |
| `archive()` / `restore()` | Archiviert bzw. stellt eine Notiz wieder her. |
| `setPinned()` / `assignSpace()` | Ändert Anheftstatus bzw. Memos-Bereich. Beim Bereichswechsel werden Bereich und Sichtbarkeit gemeinsam aktualisiert. |
| `saveView()` / `deleteView()` | Speichert oder entfernt eine lokale Filteransicht. |
| `addPendingAttachment()` / `setLocation()` | Speichert Medien lokal für den späteren Upload bzw. hängt den aktuellen Standort an. |
| `toggleWidget()` | Nimmt eine Notiz in die Widget-Auswahl auf bzw. entfernt sie. |
| `sync()` | Vollständiger Abgleich mit dem Server. |
| `saveSettings()` / `testConnection()` | Zugangsdaten speichern bzw. Verbindung prüfen. |
| `clearServerSettings()` | Entfernt Server-URL und Token; lokale Notizen bleiben. |
| `onForeground()` / `onBackground()` | Reaktion auf den App-Lebenszyklus (siehe Abschnitt 6). |

---

## 6. Synchronisation

### Zeitpunkte im Überblick

| Was | Wann |
|-----|------|
| **Lokal speichern** | 600 ms nach der letzten Eingabe |
| **Zum Server senden** | 4 s nach der letzten lokalen Speicherung, **sofort** beim Verlassen der Notiz, **sofort** beim Wechsel in den Hintergrund / Schließen |
| **Vollständiger Sync** | Beim App-Start (wenn konfiguriert), über das Sync-Symbol, per Ziehen nach unten, nach „Testen & speichern“ |
| **Widget aktualisieren** | Beim App-Start, beim Zurückkehren in die App, beim Wechsel in den Hintergrund |

Wird eine Notiz gesendet, während du weitertippst, sendet die App den neueren Stand nach der Ruhezeit erneut.

### Ablauf von `sync()`

1. Alle Notizen mit `dirty` oder `deleted` werden zum Server gesendet (`POST` für neue, `PATCH` für geänderte, `DELETE` für gelöschte).
2. Die Notizliste wird vom Server geladen (seitenweise, 200 pro Seite).
3. **Zusammenführen:**
   - Notiz nur auf dem Server → wird übernommen.
   - Notiz auf beiden Seiten und lokal **unverändert** → der Serverstand wird in das vorhandene Objekt übernommen (ein geöffneter Editor behält so seine Referenz).
   - Notiz auf beiden Seiten und lokal **geändert/gelöscht** → der lokale Stand bleibt.
   - Lokale, noch nie gesendete Notiz → bleibt erhalten.
   - Unveränderte Notiz, die auf dem Server nicht mehr existiert → wird lokal entfernt.
4. Archivierte und normale Notizen werden zusammengeführt; Ergebnis und Bereiche werden lokal gespeichert.

Beim Start bzw. vollständigen Sync liest die App die Serverversion über `GET /api/instance/profile` und prüft unabhängig davon `GET /api/spaces`. Nur bei `404` oder `501` gilt die Spaces-API als nicht verfügbar; dann blendet das Seitenmenü den Bereichsabschnitt aus. Andere Server- oder Netzwerkfehler bleiben als Sync-Fehler sichtbar. Die Profilversion dient der Diagnose und ersetzt den API-Funktionstest nicht.

### Neue Notizen

Eine neue Notiz bekommt zunächst die ID `local-<Mikrosekunden>`. Beim ersten Senden legt der Server sie an (`visibility: PRIVATE`) und die App ersetzt die ID durch die Server-ID (auch in der Widget-Auswahl). **Leere** lokale Notizen werden nie gesendet und beim Verlassen verworfen.

### Konflikte

Es gibt **keine inhaltliche Zusammenführung** („Last write wins“): Wird dieselbe Notiz auf zwei Geräten geändert, überschreibt das Gerät, das zuerst oder zuletzt synchronisiert, den anderen Stand. Das Gerät mit nicht gesendeten Änderungen gewinnt beim nächsten Sync.

### Fehler

Schlägt ein Vorgang fehl, bleibt die Notiz als `dirty` markiert (Wolken-Symbol) und wird beim nächsten Sync erneut gesendet. Auf der Startseite erscheint ein Banner „Sync-Fehler …“ mit der Schaltfläche **Erneut**.

---

## 7. Lokale Speicherung

Der aktive lokale Offline-Cache liegt in `notiz_app.sqlite` im App-Dokumentenordner
(`getApplicationDocumentsDirectory`). Die Datenbank verwendet WAL, Fremdschlüssel und
SQL-Transaktionen. Frühere `notes.json`-Bestände werden nicht automatisch übernommen.

Wichtige Tabellen:

| Tabelle | Inhalt |
|---------|--------|
| `notes` | Notizinhalt, Status, Sichtbarkeit, Bereich, Dirty-State und Sync-Zeitpunkte |
| `attachments` | Server-UID, Dateiname, MIME-Typ, Größe, lokaler Pfad, SHA-256 und Downloadstatus |
| `pending_attachments` | Lokale Hochladedateien, Prüfsumme, Uploadstatus und Fehlerversuche |
| `relations` | Beziehungen zwischen Notizen |
| `saved_views` / `spaces` / `widget_ids` | Lokale Ansichten, Bereiche und Widget-Auswahl |
| `sync_state` | Instanzprofil, Serverversion und Synchronisationsmetadaten |

Anhänge liegen unter `attachments/` als Dateien. Die Datenbank enthält nur Metadaten
und Dateipfade. Nicht mehr zugeordnete oder mindestens 30 Tage nicht verwendete
Anhänge werden regelmäßig bereinigt. Hochzuladende Dateien werden erst nach erfolgreicher
Übertragung entfernt.

**Schreiben (`save`)**

Schreibvorgänge laufen in einer Warteschlange. Zusammengehörige Änderungen werden
in einer SQLite-Transaktion ersetzt. Neue Schemainstanzen werden über eine interne
Schema-Version verwaltet.

**Laden (`load`)**

- Vorhandene SQLite-Daten werden als aktiver Offline-Cache geladen.

Einstellungen (URL, Design, Logging) liegen in `shared_preferences`, der Token
im sicheren Speicher.

### Backup, Export und Import

Export und automatische Sicherungen verwenden eine versionierte ZIP-Datei:

```text
manifest.json
data.json
files/
  attachment-<id>.bin
  pending-<id>.bin
```

`data.json` enthält den lokalen Notiz-, Ansichts-, Bereichs- und Sync-Stand.
Anhangdateien werden separat archiviert; Prüfsummen im Manifest schützen vor
beschädigten oder unvollständigen Imports. Lokale Dateien werden aufgenommen.
Noch nicht lokal heruntergeladene Serveranhänge bleiben als Serverreferenz
erhalten und sind daher ohne Serververbindung nicht verfügbar.

Unter **Einstellungen → Im- und Export** kann ein Backup-Ordner ausgewählt,
ein sofortiger Export erstellt und ein ZIP-Backup importiert werden. Android
verwendet SAF mit dauerhaft gespeicherter Ordnerfreigabe. Auf anderen
Dateisystemen werden die Dateiauswahl-URIs verwendet.
Die App prüft die gespeicherte Lese-/Schreibberechtigung und Erreichbarkeit
beim Start, bei Rückkehr in die App und vor dem Schreiben. Fehlt der Zugriff,
zeigt die Einstellung den Grund an; durch erneute Ordnerauswahl kann die
Berechtigung wieder erteilt werden. Die Option für automatische Backups bleibt
bei fehlendem Zugriff aktiv. Auf dem Homescreen erscheint ein Warnbanner mit
Aktionen zum Erneuern des Ordnerzugriffs oder zum Deaktivieren der Backups; es
verschwindet nach erfolgreicher Wiederherstellung des Zugriffs.

Automatische Backups sind optional und werden nach jedem lokalen Speichern
erstellt. Die Aufbewahrung ist auf 2 bis 10 Versionen einstellbar (Standard: 5).
Sie heißen `notiz_app_backup_1.zip` bis `notiz_app_backup_n.zip`;
`_1` ist das neueste und `_n` das älteste Backup. Manuelle Exporte behalten
einen Zeitstempel im Dateinamen.
Ein Import ersetzt den lokalen Datenbestand, ändert aber keine Daten auf dem
Memos-Server. Er wird vor dem Ersetzen geprüft; ungültige Archive werden
abgewiesen.

---

## 8. Memos-API

`MemosApi` spricht die REST-API der Memos-Instanz an. Authentifizierung per Header `Authorization: Bearer <Token>`. Jede Anfrage hat ein Zeitlimit von 30 Sekunden.

| Zweck | Anfrage |
|-------|---------|
| Verbindung prüfen | `GET /api/memos?pageSize=1` |
| Notizen laden | `GET /api/memos?pageSize=200&state=NORMAL` bzw. `state=ARCHIVED` (seitenweise) |
| Notiz anlegen | `POST /api/memos` mit `{"content": …, "visibility": "PRIVATE"}` |
| Notiz ändern | `PATCH /api/memos/{id}?updateMask=…` für geänderte Felder wie `content`, `state`, `pinned`, `space`, `visibility` oder `location` |
| Notiz löschen | `DELETE /api/memos/{id}` |
| Bereiche | `GET /api/spaces`; Erstellen, Ändern und Löschen über `POST`, `PATCH` und `DELETE /api/spaces/{id}` |
| Anhang hochladen | `POST /api/attachments:upload` (initialisieren und in begrenzten Chunks übertragen), danach `PATCH /api/memos/{id}/attachments` mit der vollständigen Anhangliste als Anhangobjekte (leere Liste entfernt alle Anhänge aus der Notiz) |
| Anhang laden | `GET /file/attachments/{uid}` |

Beim Bereichswechsel setzt die App `space` und `visibility` in einem Update; Memos begrenzt die Zuordnung serverseitig auf einen Bereich pro Notiz. Bereichsnotizen werden mit `SPACE`-Sichtbarkeit für Bereichsmitglieder freigegeben. Die App merkt sich die vorherige Sichtbarkeit lokal und stellt sie beim Entfernen des Bereichs wieder her.

Dateien mit maximal 100 MB werden zuerst im privaten App-Speicher abgelegt und dann in Chunks bis maximal 2 MB übertragen. Schlägt die Verknüpfung nach dem Upload fehl, bleibt die Upload-ID lokal vermerkt, damit der Dateiinhalt nicht erneut übertragen werden muss. Unbekannte Dateitypen werden nicht gestartet; Bilder, Audio und Text/JSON können innerhalb der App angesehen bzw. abgespielt werden.

**Server-URL:** `normalizeBaseUrl` entfernt Leerzeichen und abschließende `/`, ergänzt bei fehlendem Schema `https://` und lehnt ungültige URLs ab.

> 📌 Die App unterstützt Memos ab Version **26.10.0**. Ab dieser Version sind die REST-Pfade ohne `v1`-Präfix gültig, zum Beispiel `/api/memos` und `/api/spaces`. Ältere Memos-Server werden nicht unterstützt. Die Dokumentation der API: <https://usememos.com/docs/api/latest>

---

## 9. Bildschirme

### Startseite (`home_screen.dart`)

- **Notizkarten:** Pro Notiz Überschrift plus Vorschau; erledigte Aufgaben sind ausgeblendet. Angeheftete Notizen stehen oben.
- **Seitenmenü:** Alle Notizen, Archiv, (falls verfügbar) Memos-Bereiche, lokale gespeicherte Ansichten und alle Tags normaler Notizen. Bereich-, Ansichts- und Tag-Listen sind jeweils auf ein Drittel der verfügbaren Menüfläche begrenzt und bei Bedarf scrollbar; leere Listen belegen keinen Listenplatz.
- **Gespeicherte Ansichten:** Name, Symbol und Filter für Text, Tag, Anheftstatus, Anhänge und Standort. Erstellen, Bearbeiten und Löschen über das Plus- bzw. Drei-Punkte-Menü.
- **Bereiche:** Über Memos verwaltet; Erstellen, Bearbeiten und Löschen im Drei-Punkte-Menü. Das Löschen ist serverseitig destruktiv und wird deshalb bestätigt. Das Menü weist darauf hin, dass Memos damit auch alle Bereichsnotizen löscht.
- **Notizaktionen:** Archivieren/Wiederherstellen, Anheften, einem Bereich zuordnen bzw. Zuordnung entfernen und Löschen.
- **Symbole an der Karte:** Wolke (noch nicht synchronisiert), Widget-Symbol (im Widget angezeigt), Menü mit den Notizaktionen.
- **Sync:** Symbol in der Titelleiste und Ziehen nach unten; während des Abgleichs ein Fortschrittskreis.
- **Banner:** Sync-Fehler (mit „Erneut“) und Hinweis zur Wiederherstellung (mit „OK“).
- **Leerer Zustand:** Ohne Konfiguration und ohne Notizen erscheint „Server & Token einrichten“.
- **Seitenmenü:** App-Symbol, „Meine Notizen – für UseMemo“, unten eine kompakte Zeile „Einstellungen“ mit App-Version darunter.
- **Neue Notiz:** Schwebender „+“-Knopf.

### Notiz (`note_screen.dart`)

Zwei Modi, umschaltbar oben:

**Ansicht**

- Text wird als Markdown dargestellt (Überschriften, fett, Links …).
- Listen sind **direkt bearbeitbar** (siehe `TaskSegView`).
- „+“-Knopf mit Auswahl: **Aufgabe**, **Aufzählung** oder **Nummerierung** hinzufügen. Der neue Eintrag wird an die letzte Liste gleichen Typs angehängt oder als neue Liste angelegt.
- Weitere Aktionen über „+“: Datei, Bild aus Galerie, Foto, Zeichnung, Bild markieren, Audioaufnahme und aktueller Standort. Uploads werden offline vorgemerkt.
- Anhänge werden innerhalb der App geöffnet. Unbekannte Dateitypen werden nicht ausgeführt oder an eine externe App übergeben; Standorte öffnen bei Auswahl einen Kartenlink.
- Links öffnen nur, wenn sie mit `http`, `https` oder `mailto` beginnen; andere Link-Arten werden blockiert.

**Editor**

- Reiner Markdown-Text in Festbreitenschrift.
- Werkzeugleiste (scrollbar): **Rückgängig**, **H1**, **H2**, **Abc** (normaler Text), **Fett**, **Kursiv**, **Aufzählung**, **Nummerierung**, **Aufgabe**, **Link**, **Code**, **Zitat**.
- Neue, leere Notizen öffnen direkt im Editor.

**Speichern:** automatisch 600 ms nach der letzten Änderung; beim Verlassen wird sofort gesichert und gesendet. Eine neue Notiz ohne Inhalt wird verworfen.

**Titelleiste:** Widget-Auswahl (Symbol) und Löschen.

### Interaktive Liste (`widgets/task_seg_view.dart`)

- **Zeile:** Griff zum Verschieben (Drag-and-drop), Checkbox (bei Aufgaben; mit „teilweise“-Zustand, wenn nur einige Unteraufgaben erledigt sind), direkt bearbeitbares Textfeld, „+“ für einen Eintrag auf gleicher Ebene, Menü mit **Unteraufgabe hinzufügen** und **Löschen**.
- **Aufzählung/Nummerierung:** Statt der Checkbox erscheint `-` bzw. die laufende Nummer.
- **Eingabe beenden:** Fokusverlust oder Bestätigen. Leere Einträge ohne Unterpunkte werden entfernt.
- **Duplikate vermeiden:** Beim Tippen in einem **neuen** Eintrag zeigt die App bis zu 4 vorhandene Aufgaben mit passendem Text („Bereits vorhanden – antippen statt neu anlegen“). Ein Tipp öffnet den vorhandenen Eintrag wieder (auch erledigte, mit Unteraufgaben) und verwirft den neuen.
- **Bereich „Erledigt (n)“:** Einklappbar, nur bei Aufgabenlisten. Zeigt erledigte Aufgaben, auch verschachtelte; ein Tipp auf die Checkbox öffnet sie wieder.

### Einstellungen (`settings_screen.dart`)

| Element | Funktion |
|---------|----------|
| **HTTPS verwenden** | Schalter setzt `https://` bzw. `http://` in die URL-Zeile. Folgt auch der Eingabe in der URL-Zeile. Bei HTTP erscheint eine Warnung. |
| **Server-URL** | Adresse der Memos-Instanz. |
| **Access Token** | Verdeckte Eingabe (ohne Vorschläge und Autokorrektur). |
| **Testen & speichern** | Prüft die Verbindung und speichert dann URL und Token. |
| **Server-URL & Token löschen** | Nach Rückfrage; lokale Notizen bleiben erhalten. |
| **Darstellung** | System / Hell / Dunkel. |
| **Logging aktivieren** | Standard: aus. |
| **Log teilen** | Öffnet das Teilen-Menü mit einer Kopie der Logdatei. |

Für Kamera, Mikrofon und Standort fragt die App bei Bedarf die Plattformberechtigung an. Dateiauswahl und Galerie verwenden den Systemdialog.

---

## 10. Homescreen-Widget (Android)

### Was das Widget zeigt

- Titelzeile „Notizen“ – Tipp öffnet die App.
- Scrollbare Liste mit **Titel** und **Vorschau** (bis zu 5 Zeilen) je Notiz – Tipp öffnet genau diese Notiz.
- „+“-Knopf: Schwebt unten rechts über der Liste, ohne eine eigene Zeile zu belegen; Dialog mit **Meine Notizen öffnen** und **Neue Notiz**. Die Liste nutzt den Bereich bis zum unteren Rand.
- Leerer Zustand: „Noch keine Notizen“.
- Größe: mindestens 110 × 110 dp, horizontal und vertikal skalierbar.

**Auswahl:** Sind Notizen über das Widget-Symbol markiert, zeigt das Widget nur diese; ist keine markiert, zeigt es alle sichtbaren Notizen.

**Vorschau (`widgetPreview`):** Die erste nicht leere Zeile ist der Titel (separat). Danach werden bis zu 5 Zeilen gebildet; Markdown-Zeichen werden entfernt, Aufgaben erscheinen als `☐ …`, Aufzählungen als `• …`, Nummerierungen als `1. …`. Erledigte Aufgaben fehlen.

### Datenfluss

```
AppState._updateWidget()
   └─ HomeWidget.saveWidgetData('widget_notes', [{id, title, preview}, …])
   └─ HomeWidget.updateWidget('NoteWidgetProvider')
        └─ NoteWidgetProvider.onUpdate()
             ├─ kopiert die JSON-Daten in die eigene Preferences-Datei (note_widget_data)
             ├─ verbindet die Liste mit NoteWidgetService
             └─ setzt Klick-Aktionen
                  └─ NoteWidgetService liest die Daten und liefert die Zeilen
```

### Wann wird das Widget aktualisiert?

Nur beim **App-Start**, beim **Zurückkehren in die App** und beim **Wechsel in den Hintergrund bzw. Schließen** (danach nochmals, falls neue Notizen eine Server-ID bekommen haben). Es gibt **kein** periodisches Update (`updatePeriodMillis="0"`), da die App die Daten selbst liefert.

### Links (`notizapp://…`)

| Link | Wirkung |
|------|---------|
| `notizapp://note/<id>` | Öffnet die Notiz mit dieser ID |
| `notizapp://new-note` | Legt eine neue Notiz an und öffnet sie |
| `notizapp://actions` | Zeigt unten ein Menü („Meine Notizen öffnen“ / „Neue Notiz“) |
| `notizapp://home` | Öffnet die App (Startseite) |

`MainActivity` akzeptiert nur das Schema `notizapp` mit diesen vier Zielen. Trifft ein Link ein, bevor Flutter bereit ist, wird er zwischengespeichert und nach dem „ready“-Signal zugestellt. Das automatische Flutter-Deep-Linking ist abgeschaltet (`flutter_deeplinking_enabled=false`), weil die Links selbst verarbeitet werden.

---

## 11. Einstellungen, Sicherheit und Datenschutz

| Maßnahme | Umsetzung |
|----------|-----------|
| **Token geschützt** | `flutter_secure_storage` (Android Keystore / iOS Keychain), kein Klartext in `shared_preferences`. |
| **HTTPS als Standard** | Der Schalter steht standardmäßig auf HTTPS. HTTP ist möglich, die App warnt vor unverschlüsselter Übertragung. |
| **Klartext-Verkehr (Android)** | `usesCleartextTraffic="true"` ist nötig, damit HTTP überhaupt funktioniert. Die Kontrolle liegt beim Schalter in der App. |
| **Kein Cloud-Backup** | `android:allowBackup="false"` – Notizen und Widget-Daten landen nicht im Geräte-Backup. |
| **Links geprüft** | Nur `http`, `https`, `mailto` werden geöffnet. |
| **Dateianhänge** | Unbekannte Binärdateien werden nicht ausgeführt oder außerhalb der App gestartet. Dateien werden vor dem Upload im App-Privatspeicher abgelegt (maximal 100 MB). |
| **Standort** | Der aktuelle Standort wird erst nach Bestätigung im Kontextmenü und erteilter Betriebssystemberechtigung erfasst. |
| **Widget-Links geprüft** | Nur Schema `notizapp` und vier feste Ziele. |
| **Notizen privat** | Neue Notizen werden in Memos mit `PRIVATE` angelegt. |
| **Datenverlust vermeiden** | Atomares Speichern, Sicherungskopie, beschädigte Dateien werden aufbewahrt statt verworfen. |
| **Log privat** | Die Logdatei liegt im App-Ordner, nicht in `Downloads`, und wird nur über das Teilen-Menü weitergegeben. |

---

## 12. Logging

- **Standard: aus.** Aktivierbar in den Einstellungen.
- Geloggt werden u. a. Sync-Start/-Ende, HTTP-Anfragen (Methode, URL, Statuscode, Dauer) und Fehler.
- **Ort:** App-privater Ordner (`getApplicationSupportDirectory()/logs/notizen.log`) – auf Android und iOS gleich.
- **Größe:** höchstens 5 MB. Wird die Grenze überschritten, bleibt nur der neuere Teil (ca. 3 MB) erhalten, beginnend an einem Zeilenanfang.
- **Schreiben:** Zeilen werden gepuffert und nach spätestens 2 Sekunden bzw. 50 Zeilen in einem Block geschrieben; beim Wechsel in den Hintergrund wird sofort geleert.
- **DNS-Auflösung:** Nur bei aktivem Logging wird zusätzlich der Hostname aufgelöst und protokolliert (Fehlersuche).
- **Teilen:** „Log teilen“ kopiert die Datei in den Cache und öffnet das System-Teilen-Menü.
- Im Release-Build wird nichts in die System-Konsole (Logcat) ausgegeben.

> ℹ️ Die Logdatei enthält Server-Adresse und Fehlermeldungen. Prüfe sie, bevor du sie weitergibst.

---

## 13. Android-Konfiguration

| Einstellung | Wert |
|-------------|------|
| Paket / Application ID | `com.github.homehoster.meine_notizen` |
| App-Name | „Meine Notizen“ |
| Java-Ziel | 17 |
| Android Gradle Plugin / Kotlin | 9.1.0 / 2.4.0 (siehe `settings.gradle.kts`) |
| Berechtigungen | `INTERNET`, `RECORD_AUDIO`, `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION` |
| `allowBackup` | `false` |
| `usesCleartextTraffic` | `true` (für den optionalen HTTP-Modus) |
| `flutter_deeplinking_enabled` | `false` |
| Launch-Modus | `singleTop` |
| Release-Signatur | Debug-Schlüssel (für Veröffentlichung eigenen Schlüssel einrichten) |

Das Widget ist als `receiver` (`NoteWidgetProvider`) und `service` (`NoteWidgetService`, geschützt durch `BIND_REMOTEVIEWS`) registriert; `WidgetActionActivity` ist nicht exportiert.

---

## 14. iOS-Status

Der Dart-Code läuft auf iOS. Noch **nicht** umgesetzt:

- **Widget:** WidgetKit-Erweiterung `NoteWidget` mit App Group `group.com.github.homehoster.meine_notizen` (die App ruft `HomeWidget.setAppGroupId` bereits auf).
- **URL-Schema:** `notizapp` muss in der `Info.plist` registriert werden; außerdem braucht iOS für diese Links eine eigene Verarbeitung, da `MainActivity.kt` nur Android abdeckt.
- **HTTP:** Für unverschlüsselte Verbindungen braucht iOS einen Eintrag in `Info.plist` (`NSAppTransportSecurity`, z. B. `NSAllowsLocalNetworking` für Heimnetz-Adressen).

---

## 15. Abhängigkeiten

| Paket | Wofür |
|-------|-------|
| `provider` | State-Management |
| `http` | Zugriff auf die Memos-API |
| `flutter_secure_storage` | Token im Keystore / in der Keychain |
| `shared_preferences` | Einstellungen (URL, Design, Logging) |
| `path_provider`, `path` | Speicherorte für Notizen und Log |
| `home_widget` | Datenaustausch mit dem Homescreen-Widget |
| `flutter_markdown` | Darstellung von Markdown in der Ansicht |
| `url_launcher` | Öffnen von Links |
| `share_plus` | Teilen der Logdatei |
| `file_picker` | Dateien über den Systemdialog auswählen |
| `sqflite` | Lokale SQLite-Datenbank |
| `archive` | ZIP-Export und -Import |
| `crypto` | SHA-256-Prüfsummen für Anhangdateien |
| `saf_stream`, `saf_util` | Schreiben, Auflisten und Rotieren von Android-SAF-Backups |
| `image_picker` | Bilder auswählen bzw. Kamera verwenden |
| `record`, `audioplayers` | Audio aufnehmen und wiedergeben |
| `geolocator` | Standortberechtigung und aktuelle Koordinaten |

> ℹ️ `flutter_markdown` wird vom Flutter-Team nicht mehr weiterentwickelt. Eine Alternative ist der Nachfolger `flutter_markdown_plus`.

---

## 16. Bekannte Einschränkungen

- **Konflikte:** Kein Zusammenführen von Textänderungen zweier Geräte („Last write wins“, siehe [Abschnitt 6](#6-synchronisation)).
- **Serverwechsel:** Lokale Notizen verweisen auf die IDs des bisherigen Servers. Ungesendete Änderungen würden bei einem anderen Server ins Leere laufen. Vor einem Wechsel sollten alle Notizen synchronisiert sein und die lokalen Notizen gelöscht werden.
- **Listen-Umformatierung:** Beim Bearbeiten in der Ansicht schreibt der Serializer Listen neu: `*` wird zu `-`, Nummerierungen werden neu gezählt, Einrückungen auf 2 Leerzeichen vereinheitlicht. Listenartige Zeilen in Codeblöcken werden als Liste erkannt, mehrzeilige Listeneinträge (Fortsetzungszeilen) werden nicht unterstützt.
- **Bilder:** Bilder aus Markdown (`![](https://…)`) werden vom Rendering-Paket automatisch geladen, auch in den Karten der Startseite.
- **Server-Version:** Spaces, Archiv und Chunk-Uploads erfordern passende Endpunkte der Memos-Instanz. Nur die Spaces-Fähigkeit wird automatisch erkannt; fehlen andere Endpunkte, meldet der Sync den Serverfehler (siehe [Abschnitt 8](#8-memos-api)).
- **Gespeicherte Ansichten:** Ansichten sind lokal und werden nicht zwischen Geräten oder über Memos synchronisiert.
- **Standort:** Standortdaten sind plattformspezifisch und setzen eine Berechtigung voraus. Die Synchronisation erfordert eine Memos-Version, die das `location`-Feld unterstützt.
- **Widget:** Nur Android; Aktualisierung nur beim Öffnen und beim Verlassen der App.
- **iOS:** Widget und Link-Verarbeitung fehlen noch (siehe [Abschnitt 14](#14-ios-status)).
