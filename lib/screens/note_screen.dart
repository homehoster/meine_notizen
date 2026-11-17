import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/note.dart';
import '../models/space.dart';
import '../models/task_doc.dart';
import '../state/app_state.dart';
import '../widgets/markdown_image_blocker.dart';
import '../widgets/task_seg_view.dart';

enum _AddAction {
  task,
  bullet,
  numbered,
  file,
  image,
  camera,
  drawing,
  markImage,
  audio,
  location,
}

class NoteScreen extends StatefulWidget {
  final Note note;
  const NoteScreen({super.key, required this.note});
  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  late final TextEditingController c;
  late final AppState s;
  late final TaskEditCtx edit;
  final UndoHistoryController _undo = UndoHistoryController();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<Segment> segs = [];
  int mode = 0; // 0 Ansicht, 1 Editor (Markdown)
  Timer? _t;

  @override
  void initState() {
    super.initState();
    s = context.read<AppState>();
    c = TextEditingController(text: widget.note.content);
    segs = parseDoc(c.text);
    edit = TaskEditCtx(segments: () => segs, reuse: _reuse);
    mode = c.text.trim().isEmpty ? 1 : 0;
    s.onBeforeBackground = _saveNow;
  }

  @override
  void dispose() {
    _t?.cancel();
    if (s.onBeforeBackground == _saveNow) s.onBeforeBackground = null;
    // Lokal sichern, leere neue Notiz verwerfen, sonst sofort zum Server senden.
    s.finishEditing(widget.note, c.text);
    c.dispose();
    _undo.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// Speichert den aktuellen Text sofort lokal (z. B. beim Wechsel in den Hintergrund).
  Future<void> _saveNow() {
    _t?.cancel();
    return s.saveContent(widget.note, c.text);
  }

  /// Öffnet nur http, https und mailto; alles andere (intent:, file:, tel: …) wird blockiert.
  Future<void> _openLink(String? href) async {
    final msg = ScaffoldMessenger.of(context);
    final uri = href == null ? null : Uri.tryParse(href.trim());
    if (uri == null ||
        !const {'http', 'https', 'mailto'}.contains(uri.scheme)) {
      msg.showSnackBar(
        const SnackBar(
          content: Text(
            'Dieser Link-Typ wird aus Sicherheitsgründen nicht geöffnet',
          ),
        ),
      );
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        msg.showSnackBar(
          const SnackBar(content: Text('Link konnte nicht geöffnet werden')),
        );
      }
    } catch (_) {
      msg.showSnackBar(
        const SnackBar(content: Text('Link konnte nicht geöffnet werden')),
      );
    }
  }

  Future<void> _markImage() async {
    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;
      final source = await File(image.path).readAsBytes();
      if (!mounted) return;
      final marked = await showDialog<Uint8List>(
        context: context,
        useSafeArea: true,
        builder: (_) => _DrawingDialog(backgroundBytes: source),
      );
      if (marked == null || !mounted) return;
      await s.addPendingBytes(
        widget.note,
        bytes: marked,
        filename: 'markierung-${DateTime.now().millisecondsSinceEpoch}.png',
        type: 'image/png',
      );
    } catch (e) {
      await _showError('Bild konnte nicht markiert werden: $e');
    }
  }

  void _schedule() {
    _t?.cancel();
    _t = Timer(
      const Duration(milliseconds: 600),
      () => s.saveContent(widget.note, c.text),
    );
  }

  void _changed() {
    c.text = serializeDoc(segs);
    _schedule();
  }

  void _setMode(int m) {
    if (m == 0) {
      segs = parseDoc(c.text);
      edit.fresh = null;
    }
    setState(() => mode = m);
  }

  /// Neuer Eintrag ist ein Duplikat: bestehenden Eintrag wieder öffnen, neuen verwerfen.
  void _reuse(Task fresh, Task existing) {
    setState(() {
      for (final sg in segs) {
        if (sg is TaskSeg) removeTask(sg.roots, fresh);
      }
      reopenTask(segs, existing);
      edit.fresh = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    _changed();
  }

  void _addListItem(TaskListType type) {
    final t = Task('');
    setState(() {
      if (segs.isNotEmpty &&
          segs.last is TaskSeg &&
          (segs.last as TaskSeg).type == type) {
        (segs.last as TaskSeg).roots.add(t);
      } else {
        segs.add(TaskSeg([t], type: type));
      }
      edit.fresh = t;
    });
    _changed();
  }

  String _mimeType(String filename) {
    final extension = p.extension(filename).toLowerCase();
    return switch (extension) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.svg' => 'image/svg+xml',
      '.pdf' => 'application/pdf',
      '.txt' => 'text/plain',
      '.md' => 'text/markdown',
      '.json' => 'application/json',
      '.m4a' => 'audio/mp4',
      '.mp3' => 'audio/mpeg',
      '.wav' => 'audio/wav',
      '.ogg' => 'audio/ogg',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _showAddMenu() async {
    final action = await showModalBottomSheet<_AddAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_box_outlined),
              title: const Text('Aufgabe hinzufügen'),
              onTap: () => Navigator.pop(context, _AddAction.task),
            ),
            ListTile(
              leading: const Icon(Icons.format_list_bulleted),
              title: const Text('Aufzählung hinzufügen'),
              onTap: () => Navigator.pop(context, _AddAction.bullet),
            ),
            ListTile(
              leading: const Icon(Icons.format_list_numbered),
              title: const Text('Nummerierung hinzufügen'),
              onTap: () => Navigator.pop(context, _AddAction.numbered),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Datei anhängen'),
              onTap: () => Navigator.pop(context, _AddAction.file),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Bild auswählen'),
              onTap: () => Navigator.pop(context, _AddAction.image),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Foto aufnehmen'),
              onTap: () => Navigator.pop(context, _AddAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: const Text('Zeichnung / Markierung'),
              onTap: () => Navigator.pop(context, _AddAction.drawing),
            ),
            ListTile(
              leading: const Icon(Icons.brush_outlined),
              title: const Text('Bild markieren'),
              onTap: () => Navigator.pop(context, _AddAction.markImage),
            ),
            ListTile(
              leading: const Icon(Icons.mic_none),
              title: const Text('Audio aufnehmen'),
              onTap: () => Navigator.pop(context, _AddAction.audio),
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Aktuellen Standort hinzufügen'),
              onTap: () => Navigator.pop(context, _AddAction.location),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _AddAction.task:
        _addListItem(TaskListType.task);
      case _AddAction.bullet:
        _addListItem(TaskListType.bullet);
      case _AddAction.numbered:
        _addListItem(TaskListType.numbered);
      case _AddAction.file:
        await _pickFile();
      case _AddAction.image:
        await _pickImage(ImageSource.gallery);
      case _AddAction.camera:
        await _pickImage(ImageSource.camera);
      case _AddAction.drawing:
        await _drawImage();
      case _AddAction.markImage:
        await _markImage();
      case _AddAction.audio:
        await _recordAudio();
      case _AddAction.location:
        await _addLocation();
    }
  }

  Future<void> _showError(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _attachFile(String path, String filename, String type) async {
    try {
      await s.addPendingAttachment(
        widget.note,
        sourcePath: path,
        filename: filename,
        type: type,
      );
      await _showError(
        'Anhang hinzugefügt und für die Synchronisierung vorgemerkt',
      );
    } catch (e) {
      await _showError('Anhang konnte nicht hinzugefügt werden: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null || !mounted) return;
      final path = file.path;
      if (path != null) {
        await _attachFile(path, file.name, _mimeType(file.name));
      } else {
        await s.addPendingStream(
          widget.note,
          stream: file.readAsByteStream(),
          filename: file.name,
          type: _mimeType(file.name),
        );
      }
    } catch (e) {
      await _showError('Dateiauswahl fehlgeschlagen: $e');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _imagePicker.pickImage(source: source);
      if (image == null || !mounted) return;
      await _attachFile(
        image.path,
        p.basename(image.path),
        _mimeType(image.name),
      );
    } catch (e) {
      await _showError('Bild konnte nicht ausgewählt werden: $e');
    }
  }

  Future<void> _drawImage() async {
    final bytes = await showDialog<Uint8List>(
      context: context,
      useSafeArea: true,
      builder: (_) => const _DrawingDialog(),
    );
    if (bytes == null || !mounted) return;
    try {
      await s.addPendingBytes(
        widget.note,
        bytes: bytes,
        filename: 'zeichnung-${DateTime.now().millisecondsSinceEpoch}.png',
        type: 'image/png',
      );
    } catch (e) {
      await _showError('Zeichnung konnte nicht gespeichert werden: $e');
    }
  }

  Future<void> _recordAudio() async {
    final recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        await _showError('Mikrofonberechtigung wurde nicht erteilt.');
        return;
      }
      final directory = await Directory.systemTemp.createTemp('notiz_audio_');
      final path = p.join(directory.path, 'aufnahme.m4a');
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) {
        await recorder.stop();
        return;
      }
      final savedPath = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Audioaufnahme'),
          content: const Text('Die Aufnahme läuft.'),
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.stop),
              label: const Text('Aufnahme beenden'),
              onPressed: () async {
                final recorded = await recorder.stop();
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, recorded);
                }
              },
            ),
          ],
        ),
      );
      if (savedPath != null && mounted) {
        await _attachFile(
          savedPath,
          'aufnahme-${DateTime.now().millisecondsSinceEpoch}.m4a',
          'audio/mp4',
        );
      }
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (e) {
      await _showError('Audioaufnahme fehlgeschlagen: $e');
    } finally {
      await recorder.dispose();
    }
  }

  Future<void> _addLocation() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Standort hinzufügen?'),
        content: const Text(
          'Der aktuelle Standort wird an diese Notiz angehängt und mit dem Memos-Server synchronisiert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Fortfahren'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await _showError('Bitte aktiviere zuerst den Standortdienst.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await _showError(
          permission == LocationPermission.deniedForever
              ? 'Standortzugriff dauerhaft verweigert. Du kannst ihn in den Systemeinstellungen freigeben.'
              : 'Standortberechtigung wurde nicht erteilt.',
        );
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      await s.setLocation(
        widget.note,
        NoteLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          placeholder: 'Aktueller Standort',
        ),
      );
    } catch (e) {
      await _showError('Standort konnte nicht gelesen werden: $e');
    }
  }

  Future<void> _chooseSpace() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: const Text('Keinem Bereich zuordnen'),
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final space in s.spaces)
              ListTile(
                leading: Text(space.emoji.isEmpty ? '📁' : space.emoji),
                title: Text(space.title),
                selected: widget.note.space == space.name,
                onTap: () => Navigator.pop(context, space.name),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    MemoSpace? space;
    for (final candidate in s.spaces) {
      if (candidate.name == selected) space = candidate;
    }
    if (space != null && widget.note.space != space.name) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Notiz in Bereich verschieben?'),
          content: Text(
            'Die Notiz wird für Mitglieder des Bereichs „${space!.title}“ '
            'sichtbar. Ihre bisherige Sichtbarkeit wird dabei auf „Bereich“ gesetzt.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Verschieben'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await s.assignSpace(widget.note, space);
  }

  Future<void> _openAttachment(NoteAttachment attachment) async {
    try {
      final bytes = await s.fetchAttachment(attachment.name);
      if (!mounted) return;
      if (attachment.type.startsWith('audio/')) {
        await _audioPlayer.play(BytesSource(Uint8List.fromList(bytes)));
        return;
      }
      if (attachment.type.startsWith('image/')) {
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: InteractiveViewer(
              child: Image.memory(
                Uint8List.fromList(bytes),
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
        return;
      }
      if (attachment.type.startsWith('text/') ||
          attachment.type == 'application/json') {
        final text = utf8.decode(bytes, allowMalformed: true);
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(attachment.filename),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(child: SelectableText(text)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Schließen'),
              ),
            ],
          ),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(attachment.filename),
          content: Text(
            '${attachment.type}\n${_formatSize(attachment.size)}\n\n'
            'Dieser Dateityp wird nicht ausgeführt oder außerhalb der App geöffnet.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
    } catch (e) {
      await _showError('Anhang konnte nicht geöffnet werden: $e');
    }
  }

  String _formatSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _attachments() {
    final note = widget.note;
    if (note.attachments.isEmpty &&
        note.pendingAttachments.isEmpty &&
        note.location == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final attachment in note.attachments)
          ListTile(
            leading: Icon(
              attachment.type.startsWith('image/')
                  ? Icons.image_outlined
                  : attachment.type.startsWith('audio/')
                  ? Icons.audiotrack
                  : Icons.insert_drive_file_outlined,
            ),
            title: Text(attachment.filename),
            subtitle: Text(
              '${attachment.type} · ${_formatSize(attachment.size)}',
            ),
            trailing: PopupMenuButton<String>(
              tooltip: 'Anhang öffnen',
              onSelected: (_) => _openAttachment(attachment),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('In der App öffnen')),
              ],
            ),
            onTap: () => _openAttachment(attachment),
          ),
        for (final pending in note.pendingAttachments)
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: Text(pending.filename),
            subtitle: Text(
              pending.uploadedName == null
                  ? 'Wird synchronisiert'
                  : 'Hochgeladen, Verknüpfung ausstehend',
            ),
            trailing: const Icon(Icons.more_vert),
          ),
        if (note.location case final location?)
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(
              location.placeholder.isEmpty ? 'Standort' : location.placeholder,
            ),
            subtitle: Text(
              '${location.latitude.toStringAsFixed(5)}, '
              '${location.longitude.toStringAsFixed(5)}',
            ),
            onTap: () => _openLink(
              'https://maps.google.com/?q=${location.latitude},${location.longitude}',
            ),
          ),
        const Divider(),
      ],
    );
  }

  void _wrap(String a, String b) {
    final sel = c.selection;
    final t = c.text;
    if (!sel.isValid) {
      c.text = '$t$a$b';
    } else {
      final mid = t.substring(sel.start, sel.end);
      c.value = TextEditingValue(
        text: t.replaceRange(sel.start, sel.end, '$a$mid$b'),
        selection: TextSelection(
          baseOffset: sel.start + a.length,
          extentOffset: sel.start + a.length + mid.length,
        ),
      );
    }
    _schedule();
  }

  void _linePrefix(String p) {
    final t = c.text;
    final pos = c.selection.isValid ? c.selection.start : t.length;
    final ls = pos == 0 ? 0 : t.lastIndexOf('\n', pos - 1) + 1;
    c.value = TextEditingValue(
      text: t.replaceRange(ls, ls, p),
      selection: TextSelection.collapsed(offset: pos + p.length),
    );
    _schedule();
  }

  /// level 0 = normaler Text, 1 = H1, 2 = H2. Ersetzt eine vorhandene Überschrift der Zeile.
  void _setHeading(int level) {
    final t = c.text;
    final pos = c.selection.isValid ? c.selection.start : t.length;
    final ls = pos == 0 ? 0 : t.lastIndexOf('\n', pos - 1) + 1;
    var le = t.indexOf('\n', ls);
    if (le == -1) le = t.length;
    final line = t.substring(ls, le);
    final m = RegExp(r'^#{1,6}\s*').firstMatch(line);
    final stripped = m == null ? line : line.substring(m.end);
    final newLine = '${level == 0 ? '' : '${'#' * level} '}$stripped';
    final offset = (pos + newLine.length - line.length)
        .clamp(ls, ls + newLine.length)
        .toInt();
    c.value = TextEditingValue(
      text: t.replaceRange(ls, le, newLine),
      selection: TextSelection.collapsed(offset: offset),
    );
    _schedule();
  }

  Widget _toolbar() {
    Widget b(IconData i, String tip, VoidCallback f) =>
        IconButton(icon: Icon(i), tooltip: tip, onPressed: f);
    Widget h(String label, String tip, VoidCallback f, {bool bold = true}) =>
        Tooltip(
          message: tip,
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: f,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ValueListenableBuilder<UndoHistoryValue>(
            valueListenable: _undo,
            builder: (_, v, _) => IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Rückgängig',
              onPressed: v.canUndo ? _undo.undo : null,
            ),
          ),
          h('H1', 'Überschrift 1', () => _setHeading(1)),
          h('H2', 'Überschrift 2', () => _setHeading(2)),
          h('Abc', 'Normaler Text', () => _setHeading(0), bold: false),
          b(Icons.format_bold, 'Fett', () => _wrap('**', '**')),
          b(Icons.format_italic, 'Kursiv', () => _wrap('*', '*')),
          b(Icons.format_list_bulleted, 'Aufzählung', () => _linePrefix('- ')),
          b(Icons.format_list_numbered, 'Nummeriert', () => _linePrefix('1. ')),
          b(Icons.check_box_outlined, 'Aufgabe', () => _linePrefix('- [ ] ')),
          b(Icons.link, 'Link', () => _wrap('[', '](https://)')),
          b(Icons.code, 'Code', () => _wrap('`', '`')),
          b(Icons.format_quote, 'Zitat', () => _linePrefix('> ')),
        ],
      ),
    );
  }

  Widget _body(bool blockMarkdownImages) {
    if (mode == 0) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _attachments(),
          for (final seg in segs)
            if (seg is TextSeg)
              (seg.text.trim().isEmpty
                  ? const SizedBox.shrink()
                  : MarkdownBody(
                      data: seg.text,
                      onTapLink: (t, href, title) => _openLink(href),
                      imageBuilder: blockMarkdownImages
                          ? blockedMarkdownImage
                          : null,
                    ))
            else
              TaskSegView(
                key: ObjectKey(seg),
                seg: seg as TaskSeg,
                edit: edit,
                onChanged: _changed,
              ),
        ],
      );
    }
    return Column(
      children: [
        _toolbar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: c,
              undoController: _undo,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              onChanged: (_) => _schedule(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Notiz schreiben …',
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final blockMarkdownImages = app.blockMarkdownImages;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note.isLocal ? 'Neue Notiz' : 'Notiz'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'pin':
                  s.setPinned(widget.note, !widget.note.pinned);
                case 'archive':
                  s.archive(widget.note);
                case 'restore':
                  s.restore(widget.note);
                case 'space':
                  _chooseSpace();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'pin',
                child: Text(widget.note.pinned ? 'Lösen' : 'Anpinnen'),
              ),
              if (widget.note.state == NoteState.normal)
                const PopupMenuItem(
                  value: 'archive',
                  child: Text('Archivieren'),
                )
              else
                const PopupMenuItem(
                  value: 'restore',
                  child: Text('Wiederherstellen'),
                ),
              if (app.spacesSupported == true)
                const PopupMenuItem(
                  value: 'space',
                  child: Text('Bereich zuordnen'),
                ),
            ],
          ),
          IconButton(
            icon: Icon(
              s.widgetIds.contains(widget.note.id)
                  ? Icons.widgets
                  : Icons.widgets_outlined,
            ),
            tooltip: 'Im Widget anzeigen',
            onPressed: () async {
              await s.toggleWidget(widget.note);
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final nav = Navigator.of(context);
              _t?.cancel();
              await s.deleteNote(widget.note);
              nav.pop();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.checklist),
                  label: Text('Ansicht'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.edit),
                  label: Text('Editor'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (v) => _setMode(v.first),
            ),
          ),
          Expanded(child: _body(blockMarkdownImages)),
        ],
      ),
      floatingActionButton: mode == 0
          ? FloatingActionButton(
              onPressed: _showAddMenu,
              tooltip: 'Eintrag oder Anhang hinzufügen',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _DrawingDialog extends StatefulWidget {
  final Uint8List? backgroundBytes;

  const _DrawingDialog({this.backgroundBytes});

  @override
  State<_DrawingDialog> createState() => _DrawingDialogState();
}

class _DrawingDialogState extends State<_DrawingDialog> {
  final _boundaryKey = GlobalKey();
  final List<Offset?> _points = [];
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final boundary =
          _boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted || data == null) return;
      Navigator.pop(context, data.buffer.asUint8List());
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Zeichnung konnte nicht exportiert werden: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Zeichnung / Markierung'),
    content: SizedBox(
      width: 360,
      height: 360,
      child: RepaintBoundary(
        key: _boundaryKey,
        child: GestureDetector(
          onPanStart: (details) =>
              setState(() => _points.add(details.localPosition)),
          onPanUpdate: (details) =>
              setState(() => _points.add(details.localPosition)),
          onPanEnd: (_) => setState(() => _points.add(null)),
          child: CustomPaint(
            foregroundPainter: _DrawingPainter(List.of(_points)),
            child: widget.backgroundBytes == null
                ? const ColoredBox(
                    color: Colors.white,
                    child: SizedBox.expand(),
                  )
                : Image.memory(
                    widget.backgroundBytes!,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                  ),
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => setState(_points.clear),
        child: const Text('Leeren'),
      ),
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Speichere …' : 'Anhängen'),
      ),
    ],
  );
}

class _DrawingPainter extends CustomPainter {
  final List<Offset?> points;

  const _DrawingPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < points.length - 1; index++) {
      final start = points[index];
      final end = points[index + 1];
      if (start != null && end != null) {
        canvas.drawLine(start, end, paint);
      } else if (start != null) {
        canvas.drawCircle(start, paint.strokeWidth / 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) => true;
}
