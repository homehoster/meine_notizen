import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppLanguage {
  final String code;
  final String name;

  const AppLanguage(this.code, this.name);

  Locale get locale {
    final parts = code.split('-');
    if (parts.length == 1) return Locale(parts.first);
    if (parts[1].length == 4) {
      return Locale.fromSubtags(
        languageCode: parts.first,
        scriptCode: parts[1],
      );
    }
    return Locale(parts.first, parts[1]);
  }
}

const appLanguages = <AppLanguage>[
  AppLanguage('ar', 'العربية'),
  AppLanguage('az', 'Azərbaycanca'),
  AppLanguage('bg', 'Български'),
  AppLanguage('ca', 'Català'),
  AppLanguage('cs', 'Čeština'),
  AppLanguage('da', 'Dansk'),
  AppLanguage('de', 'Deutsch'),
  AppLanguage('el', 'Ελληνικά'),
  AppLanguage('en-GB', 'English (UK)'),
  AppLanguage('en', 'English'),
  AppLanguage('es', 'Español'),
  AppLanguage('et', 'Eesti'),
  AppLanguage('fa', 'فارسی'),
  AppLanguage('fi', 'Suomi'),
  AppLanguage('fr', 'Français'),
  AppLanguage('gl', 'Galego'),
  AppLanguage('he', 'עברית'),
  AppLanguage('hi', 'हिन्दी'),
  AppLanguage('hr', 'Hrvatski'),
  AppLanguage('hu', 'Magyar'),
  AppLanguage('id', 'Bahasa Indonesia'),
  AppLanguage('it', 'Italiano'),
  AppLanguage('ja', '日本語'),
  AppLanguage('ka-GE', 'ქართული'),
  AppLanguage('ko', '한국어'),
  AppLanguage('lt', 'Lietuvių'),
  AppLanguage('lv', 'Latviešu'),
  AppLanguage('mr', 'मराठी'),
  AppLanguage('nb', 'Norsk bokmål'),
  AppLanguage('nl', 'Nederlands'),
  AppLanguage('nn', 'Norsk nynorsk'),
  AppLanguage('pl', 'Polski'),
  AppLanguage('pt-BR', 'Português (Brasil)'),
  AppLanguage('pt-PT', 'Português (Portugal)'),
  AppLanguage('ro', 'Română'),
  AppLanguage('ru', 'Русский'),
  AppLanguage('sk', 'Slovenčina'),
  AppLanguage('sl', 'Slovenščina'),
  AppLanguage('sr', 'Српски'),
  AppLanguage('sv', 'Svenska'),
  AppLanguage('th', 'ไทย'),
  AppLanguage('tr', 'Türkçe'),
  AppLanguage('uk', 'Українська'),
  AppLanguage('vi', 'Tiếng Việt'),
  AppLanguage('zh-Hans', '简体中文'),
  AppLanguage('zh-Hant', '繁體中文'),
];

Locale localeForCode(String code) {
  for (final language in appLanguages) {
    if (language.code == code) return language.locale;
  }
  return const Locale('en');
}

Locale? resolveAppLocale(Locale? requested, Iterable<Locale> supported) {
  if (requested == null) return const Locale('en');
  final tag = requested.toLanguageTag().toLowerCase();
  for (final locale in supported) {
    if (locale.toLanguageTag().toLowerCase() == tag) return locale;
  }
  for (final locale in supported) {
    if (locale.languageCode == requested.languageCode &&
        locale.countryCode == null &&
        locale.scriptCode == null) {
      return locale;
    }
  }
  for (final locale in supported) {
    if (locale.languageCode == requested.languageCode) return locale;
  }
  return const Locale('en');
}

class AppLocalizations {
  AppLocalizations._(this._catalog);

  static const assetPath = 'asset/locales/memos_terms.json';
  static AppLocalizations? _instance;

  final Map<String, dynamic> _catalog;

  static Future<void> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid Memos locale catalog');
    }
    _instance = AppLocalizations._(decoded);
  }

  static AppLocalizations get instance {
    final value = _instance;
    if (value == null) {
      throw StateError(
        'AppLocalizations.load() must run before the app starts',
      );
    }
    return value;
  }

  String translate(String source, Locale locale) {
    final code = locale.toLanguageTag();
    final path = _memosKeys[source];
    if (path != null) {
      final language = _catalog[code] ?? _catalog[locale.languageCode];
      final translated = language is Map<String, dynamic>
          ? language[path]
          : null;
      if (translated is String && translated.isNotEmpty) return translated;
    }
    if (locale.languageCode == 'de') return source;
    return _englishFallback[source] ?? source;
  }
}

extension AppLocalizationContext on BuildContext {
  String tr(String source) =>
      AppLocalizations.instance.translate(source, Localizations.localeOf(this));
}

const _memosKeys = <String, String>{
  'Abbrechen': 'common.cancel',
  'Alle': 'common.all',
  'Anhänge': 'common.attachments',
  'Bearbeiten': 'common.edit',
  'Beschreibung': 'common.description',
  'Einstellungen': 'common.settings',
  'Erneut versuchen': 'common.retry',
  'Hinzufügen': 'common.add',
  'Löschen': 'common.delete',
  'Name': 'common.name',
  'Notiz': 'common.memo',
  'Notizen': 'common.memos',
  'Ort auswählen': 'common.choose-location',
  'Sichtbarkeit': 'common.visibility',
  'Sprache': 'common.language',
  'Speichern': 'common.save',
  'Teilen': 'common.share',
  'Titel': 'common.title',
  'Suche': 'common.search',
  'Öffnen': 'common.open',
  'Archivieren': 'common.archive',
  'Markieren': 'editor.insert-menu.drawing',
  'Standort hinzufügen': 'editor.insert-menu.add-location',
};

const _englishFallback = <String, String>{
  'Meine Notizen öffnen': 'Open My Notes',
  'Meine Notizen': 'My Notes',
  'Neue Notiz': 'New note',
  'Fehler': 'Error',
  'Server-URL und Token werden von diesem Gerät entfernt. Lokal gespeicherte Notizen bleiben erhalten, werden aber nicht mehr synchronisiert.': 'The server URL and token will be removed from this device. Locally stored notes will remain, but will no longer sync.',
  'Verbunden & gespeichert': 'Connected and saved',
  'Zugangsdaten löschen?': 'Delete credentials?',
  'Token und Notizen werden im Klartext übertragen und können mitgelesen werden. Nur in vertrauenswürdigen Netzwerken (z. B. Heimnetz) verwenden.': 'Your token and notes are sent without encryption and can be intercepted. Use only on trusted networks (for example, your home network).',
  'Sprache konnte nicht gespeichert werden': 'Could not save language',
  'Logdatei löschen': 'Delete log file',
  'Anmeldung fehlgeschlagen: Das Token ist ungültig oder abgelaufen.':
      'Sign-in failed: The token is invalid or expired.',
  'Symbol / Emoji': 'Icon / emoji',
  'Version': 'Version',
  'Server-URL und Token gelöscht': 'Server URL and token deleted',
  'Logdatei löschen?': 'Delete log file?',
  'Das gespeicherte Diagnoseprotokoll wird gelöscht.':
      'The saved diagnostic log will be deleted.',
  'Logdatei gelöscht': 'Log file deleted',
  'Logdatei konnte nicht gelöscht werden': 'Could not delete log file',
  'Synchronisation': 'Synchronization',
  'Verbindung': 'Connection',
  'HTTPS verwenden': 'Use HTTPS',
  'Verschlüsselte Verbindung (empfohlen)': 'Encrypted connection (recommended)',
  'Unverschlüsselt (HTTP)': 'Unencrypted (HTTP)',
  'Server-URL': 'Server URL',
  'Testen & speichern': 'Test and save',
  'Prüfe …': 'Checking…',
  'Zugangsdaten': 'Credentials',
  'Server-URL & Token löschen': 'Delete server URL and token',
  'Lokale Notizen bleiben erhalten': 'Local notes will be kept',
  'Darstellung': 'Appearance',
  'Anzeigesprache': 'Display language',
  'Hell': 'Light',
  'Dunkel': 'Dark',
  'Wie Systemeinstellung': 'System default',
  'Bearbeitung': 'Editing',
  'Unterstützte Bearbeitung': 'Assisted editing',
  'Erledigte Aufgaben ausblenden sowie Listen direkt bearbeiten, ergänzen und verschieben':
      'Hide completed tasks and edit, add, and move list items directly',
  'Datenschutz': 'Privacy',
  'Markdown-Bilder blockieren': 'Block Markdown images',
  'Verhindert, dass eingebettete Bilder automatisch geladen werden':
      'Prevents embedded images from loading automatically',
  'Diagnose': 'Diagnostics',
  'Logging aktivieren': 'Enable logging',
  'Schreibt Sync- und Fehlerprotokolle (max. 5 MB, nur in der App gespeichert)':
      'Writes sync and error logs (max. 5 MB, stored only in the app)',
  'Log teilen': 'Share log',
  'Vorhandene Logdatei teilen': 'Share existing log file',
  'Noch keine Logs vorhanden': 'No logs available yet',
  'Gespeichertes Diagnoseprotokoll entfernen': 'Remove saved diagnostic log',
  'Info': 'About',
  'Notizen erfassen – optional mit Memos synchronisiert.':
      'Capture notes and optionally sync them with Memos.',
  'Keine gültige Server-URL eingerichtet': 'No valid server URL configured',
  'Notiz-Link konnte nicht geteilt werden': 'Could not share note link',
  'Bereich anlegen': 'Create space',
  'Bereich bearbeiten': 'Edit space',
  'Bereich löschen?': 'Delete space?',
  'Bereich und Notizen löschen': 'Delete space and notes',
  'Bereich konnte nicht gelöscht werden': 'Could not delete space',
  'Memos löscht mit dem Bereich auch alle darin abgelegten Notizen dauerhaft.': 'Memos permanently deletes all notes in this space when the space is deleted.',
  'In der lokalen Liste sind': 'The local list contains',
  'Notizen zugeordnet.': 'assigned notes.',
  'Diese Aktion kann nicht rückgängig gemacht werden.':
      'This action cannot be undone.',
  'Ansicht anlegen': 'Create view',
  'Ansicht bearbeiten': 'Edit view',
  'Text enthält (optional)': 'Text contains (optional)',
  'Tag (optional)': 'Tag (optional)',
  'Anpinnen': 'Pin',
  'Beliebig': 'Any',
  'Nur angepinnte': 'Pinned only',
  'Nicht angepinnt': 'Not pinned',
  'Mit Anhängen': 'With attachments',
  'Ohne Anhänge': 'Without attachments',
  'Standort': 'Location',
  'Mit Standort': 'With location',
  'Ohne Standort': 'Without location',
  'Keinem Bereich zuordnen': 'No space',
  'Notiz in Bereich verschieben?': 'Move note to space?',
  'Verschieben': 'Move',
  'Bereiche': 'Spaces',
  'Bereich': 'Space',
  'Ansichten': 'Views',
  'Tags': 'Tags',
  'für UseMemo': 'for UseMemos',
  'Alle Notizen': 'All notes',
  'Archiv': 'Archive',
  'Bereichsoptionen': 'Space options',
  'Bereiche anlegen': 'Create spaces',
  'Ansichten anlegen': 'Create views',
  'Ansichtsoptionen': 'View options',
  'Suche schließen': 'Close search',
  'Notizen suchen': 'Search notes',
  'Vollständig synchronisieren': 'Sync now',
  'Erneut': 'Retry',
  'Suche löschen': 'Clear search',
  'Server & Token einrichten': 'Set up server and token',
  'Aufgabe hinzufügen': 'Add task',
  'Aufzählung hinzufügen': 'Add bullet list',
  'Nummerierung hinzufügen': 'Add numbered list',
  'Datei anhängen': 'Attach file',
  'Bild auswählen': 'Choose image',
  'Foto aufnehmen': 'Take photo',
  'Bild markieren': 'Mark up image',
  'Zeichnung / Markierung': 'Drawing / markup',
  'Audio aufnehmen': 'Record audio',
  'Aktuellen Standort hinzufügen': 'Add current location',
  'Verknüpfte Notiz hinzufügen': 'Add linked note',
  'Link konnte nicht geöffnet werden': 'Could not open link',
  'Dieser Link-Typ wird aus Sicherheitsgründen nicht geöffnet':
      'This link type is not opened for security reasons',
  'Audioaufnahme': 'Audio recording',
  'Die Aufnahme läuft.': 'Recording in progress.',
  'Aufnahme beenden': 'Stop recording',
  'Standort hinzufügen?': 'Add location?',
  'Der aktuelle Standort wird an diese Notiz angehängt und mit dem Memos-Server synchronisiert.': 'Your current location will be attached to this note and synced with the Memos server.',
  'Fortfahren': 'Continue',
  'Die Notiz wird für Mitglieder des Bereichs':
      'The note will be visible to members of the space',
  'sichtbar. Ihre bisherige Sichtbarkeit wird dabei auf „Bereich“ gesetzt.':
      'Your current visibility will be changed to "Space".',
  'Die lokale Datei wird gelöscht.': 'The local file will be deleted.',
  'Die Datei wird dadurch nicht global vom Server gelöscht.':
      'This will not delete the file from the server.',
  'Anhang entfernen?': 'Remove attachment?',
  'Entfernen': 'Remove',
  'Verknüpfung entfernen': 'Remove link',
  'Typ': 'Type',
  'Anhang hinzugefügt und für die Synchronisierung vorgemerkt':
      'Attachment added and queued for sync',
  'Anhang konnte nicht hinzugefügt werden': 'Could not add attachment',
  'Dateiauswahl fehlgeschlagen': 'File selection failed',
  'Bild konnte nicht ausgewählt werden': 'Could not select image',
  'Bild konnte nicht markiert werden': 'Could not mark image',
  'Zeichnung konnte nicht gespeichert werden': 'Could not save drawing',
  'Mikrofonberechtigung wurde nicht erteilt.':
      'Microphone permission was denied.',
  'Audioaufnahme fehlgeschlagen': 'Audio recording failed',
  'Bitte aktiviere zuerst den Standortdienst.':
      'Please enable location services first.',
  'Standortzugriff dauerhaft verweigert. Du kannst ihn in den Systemeinstellungen freigeben.': 'Location access was permanently denied. You can enable it in system settings.',
  'Standortberechtigung wurde nicht erteilt.':
      'Location permission was denied.',
  'Aktueller Standort': 'Current location',
  'Standort konnte nicht gelesen werden': 'Could not read location',
  'Anhang konnte nicht geöffnet werden': 'Could not open attachment',
  'Keine passende App zum Öffnen gefunden.':
      'No compatible app found to open it.',
  'Öffnen fehlgeschlagen': 'Could not open',
  'wird aus dieser Notiz entfernt.': 'will be removed from this note.',
  'Anhang konnte nicht entfernt werden': 'Could not remove attachment',
  'Standort konnte nicht entfernt werden': 'Could not remove location',
  'Die Notiz muss zuerst synchronisiert werden.':
      'The note must be synced first.',
  'Verknüpfung konnte nicht hinzugefügt werden': 'Could not add link',
  'Verknüpfung konnte nicht entfernt werden': 'Could not remove link',
  'Bild konnte nicht geladen werden': 'Could not load image',
  'Erneut laden': 'Reload',
  'Wird synchronisiert': 'Syncing',
  'Hochgeladen, Verknüpfung ausstehend': 'Uploaded, linking pending',
  'Anhang entfernen': 'Remove attachment',
  'Standort entfernen': 'Remove location',
  'Rückgängig': 'Undo',
  'Notiz schreiben …': 'Write a note…',
  'Sichtbarkeit:': 'Visibility:',
  'Öffentlich': 'Public',
  'Privat': 'Private',
  'Für Mitglieder': 'For members',
  'Für Bereichsmitglieder': 'For space members',
  'Im Widget anzeigen': 'Show in widget',
  'Aus Widget entfernen': 'Remove from widget',
  'Lösen': 'Unpin',
  'Link teilen': 'Share link',
  'Wiederherstellen': 'Restore',
  'Bereich zuordnen': 'Assign to space',
  'Ansicht': 'View',
  'Editor': 'Editor',
  'Eintrag oder Anhang hinzufügen': 'Add item or attachment',
  'Notiz verknüpfen': 'Link note',
  'Memo': 'Memo',
  'Keine Notizen verfügbar': 'No notes available',
  'Keine passenden Notizen': 'No matching notes',
  'Zeichnung konnte nicht exportiert werden': 'Could not export drawing',
  'Leere Notiz': 'Empty note',
  'Bild blockiert': 'Image blocked',
  'OK': 'OK',
  'Sync-Fehler': 'Sync error',
  'Memos → Settings → My Account': 'Memos → Settings → My Account',
  'Leeren': 'Clear',
  'Speichere …': 'Saving…',
  'Anhängen': 'Attach',
  'Erledigt': 'Completed',
  'Neuer Eintrag': 'New item',
  'Aufgabe auf dieser Ebene hinzufügen': 'Add task at this level',
  'Unteraufgabe hinzufügen': 'Add subtask',
  'Bereits vorhanden – antippen statt neu anlegen':
      'Already exists—tap to reuse instead',
  'erledigt – wird wieder geöffnet': 'completed—will be reopened',
  'Bereich konnte nicht gespeichert werden': 'Could not save space',
};
