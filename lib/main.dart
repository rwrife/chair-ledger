import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:path_provider/path_provider.dart';

import 'book.dart';
import 'schedule.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationSupportDirectory();
  final book = Book.open('${directory.path}/chair-ledger.db');
  runApp(ChairLedgerApp(book: book));
}

class ChairLedgerApp extends StatefulWidget {
  const ChairLedgerApp({super.key, this.book, this.initialDate});
  final Book? book;
  final DateTime? initialDate;

  @override
  State<ChairLedgerApp> createState() => _ChairLedgerAppState();
}

class _ChairLedgerAppState extends State<ChairLedgerApp> {
  int tab = 0;
  bool editing = false;
  bool serviceEditor = false;
  Service? selectedService;
  Appointment? selected;
  String? error;
  late DateTime day = widget.initialDate ?? DateTime.now();
  final client = TextEditingController();
  final note = TextEditingController();
  final time = TextEditingController(text: '09:00');
  final serviceName = TextEditingController();
  final duration = TextEditingController(text: '30');
  final buffer = TextEditingController(text: '0');
  final open = TextEditingController(text: '09:00');
  final close = TextEditingController(text: '17:00');
  String? serviceId;
  int? selectedWeekday;

  bool get ios => defaultTargetPlatform == TargetPlatform.iOS;
  bool get windows => defaultTargetPlatform == TargetPlatform.windows;
  Book get book => widget.book!;

  @override
  void dispose() {
    for (final c in [
      client,
      note,
      time,
      serviceName,
      duration,
      buffer,
      open,
      close,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget button(String label, VoidCallback action, {Key? key}) => ios
      ? CupertinoButton(key: key, onPressed: action, child: Text(label))
      : windows
      ? fluent.Button(key: key, onPressed: action, child: Text(label))
      : TextButton(key: key, onPressed: action, child: Text(label));

  Widget field(String label, TextEditingController controller, {Key? key}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ios
            ? CupertinoTextField(
                key: key,
                controller: controller,
                placeholder: label,
                padding: const EdgeInsets.all(12),
              )
            : windows
            ? fluent.TextBox(
                key: key,
                controller: controller,
                placeholder: label,
              )
            : TextField(
                key: key,
                controller: controller,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                ),
              ),
      );

  void startAppointment([Appointment? value]) {
    setState(() {
      editing = true;
      selected = value;
      error = null;
      serviceId =
          value?.serviceId ??
          (book.services.isEmpty ? null : book.services.first.id);
      client.text = value?.clientLabel ?? '';
      note.text = value?.note ?? '';
      time.text = value == null
          ? '09:00'
          : _clock(value.startLocal.hour * 60 + value.startLocal.minute);
      if (value != null) day = value.startLocal;
    });
  }

  String _clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  int _minute(String input) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(input.trim());
    if (match == null) throw const FormatException('Enter time as HH:MM');
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) throw const FormatException('Invalid time');
    return hour * 60 + minute;
  }

  void saveAppointment() {
    try {
      final service = book.services.firstWhere((s) => s.id == serviceId);
      final minute = _minute(time.text);
      final start = parseLocalMinute(
        day.year,
        day.month,
        day.day,
        minute ~/ 60,
        minute % 60,
      );
      final value = Appointment(
        id:
            selected?.id ??
            '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}',
        serviceId: service.id,
        startLocal: start,
        durationMinutes: selected?.serviceId == service.id
            ? selected!.durationMinutes
            : service.durationMinutes,
        bufferMinutes: selected?.serviceId == service.id
            ? selected!.bufferMinutes
            : service.bufferMinutes,
        clientLabel: client.text.trim().isEmpty ? null : client.text.trim(),
        note: note.text.trim().isEmpty ? null : note.text.trim(),
        status: selected?.status ?? BookingStatus.booked,
      );
      book.saveAppointment(value);
      setState(() {
        editing = false;
        error = null;
      });
    } catch (e) {
      setState(
        () => error = e is SlotRejected
            ? 'Slot ${e.reason.name}: choose another time. Your entry is preserved.'
            : 'Could not save: $e',
      );
    }
  }

  void startServiceEditor([Service? s]) {
    setState(() {
      serviceEditor = true;
      selectedService = s;
      error = null;
      serviceName.text = s?.name ?? '';
      duration.text = s?.durationMinutes.toString() ?? '30';
      buffer.text = s?.bufferMinutes.toString() ?? '0';
    });
  }

  void saveService() {
    try {
      book.saveService(
        Service(
          id:
              selectedService?.id ??
              '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}',
          name: serviceName.text.trim(),
          durationMinutes: int.parse(duration.text),
          bufferMinutes: int.parse(buffer.text),
        ),
      );
      setState(() {
        serviceEditor = false;
        selectedService = null;
        error = null;
      });
    } catch (e) {
      setState(() => error = 'Could not save service: $e');
    }
  }

  void saveHours(int weekday) {
    try {
      final proposed = book.windows.where((w) => w.weekday != weekday).toList();
      if (open.text.trim().isNotEmpty && close.text.trim().isNotEmpty) {
        proposed.add(
          WorkingWindow(
            weekday: weekday,
            openMinute: _minute(open.text),
            closeMinute: _minute(close.text),
          ),
        );
      } else if (open.text.trim().isNotEmpty || close.text.trim().isNotEmpty) {
        throw const FormatException('Set both times or leave both empty');
      }
      book.setWindows(proposed);
      setState(() => error = null);
    } catch (e) {
      setState(() => error = 'Could not save hours: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Chair Ledger';
    final content = SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.book == null) ...[
            const Text('Chair Ledger', style: TextStyle(fontSize: 28)),
            const Text('Your private appointment book starts here.'),
          ] else ...[
            Wrap(
              spacing: 12,
              children: [
                button(
                  'Appointments',
                  () => setState(() {
                    tab = 0;
                    editing = false;
                  }),
                  key: const Key('tab-appointments'),
                ),
                button(
                  'Services & hours',
                  () => setState(() {
                    tab = 1;
                    editing = false;
                  }),
                  key: const Key('tab-services'),
                ),
              ],
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Color(0xffb00020))),
            if (tab == 0) ...appointmentContent() else ...serviceContent(),
          ],
        ],
      ),
    );
    if (ios) {
      return CupertinoApp(
        title: title,
        home: CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(middle: Text(title)),
          child: content,
        ),
      );
    }
    if (windows) {
      return fluent.FluentApp(
        title: title,
        home: fluent.NavigationView(
          titleBar: fluent.TitleBar(title: const Text(title)),
          content: fluent.ScaffoldPage(content: content),
        ),
      );
    }
    return MaterialApp(
      title: title,
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        appBar: widget.book == null ? null : AppBar(title: const Text(title)),
        body: content,
      ),
    );
  }

  Future<void> chooseDate() async {
    if (ios) {
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (context) => Container(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          height: 300,
          child: Column(
            children: [
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: day,
                  minimumDate: DateTime(2000),
                  maximumDate: DateTime(2100),
                  onDateTimeChanged: (value) => setState(() => day = value),
                ),
              ),
              CupertinoButton(
                child: const Text('Done'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
    } else {
      final picked = await showDatePicker(
        context: context,
        initialDate: day,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked != null) setState(() => day = picked);
    }
  }

  List<Widget> appointmentContent() {
    if (editing) {
      return [
        Text(
          selected == null ? 'New appointment' : 'Edit appointment',
          style: const TextStyle(fontSize: 22),
        ),
        Text(
          'Date: ${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
        ),
        button('Choose date', chooseDate),
        field('Time (HH:MM)', time, key: const Key('time-field')),
        if (book.services.isEmpty)
          const Text('Add a service first')
        else ...[
          const Text('Service'),
          for (final s in book.services)
            button(
              '${s.name}${serviceId == s.id ? ' ✓' : ''}',
              () => setState(() => serviceId = s.id),
            ),
        ],
        field(
          'Client label (optional; pseudonyms welcome)',
          client,
          key: const Key('client-label-field'),
        ),
        field('Private note (optional)', note, key: const Key('note-field')),
        button(
          'Save appointment',
          saveAppointment,
          key: const Key('save-appointment-button'),
        ),
        button(
          'Discard changes',
          () => setState(() {
            editing = false;
            error = null;
          }),
        ),
      ];
    }
    final items = book.appointments
        .where(
          (a) =>
              a.startLocal.year == day.year &&
              a.startLocal.month == day.month &&
              a.startLocal.day == day.day,
        )
        .toList();
    return [
      Wrap(
        children: [
          button(
            'Previous day',
            () => setState(() => day = day.subtract(const Duration(days: 1))),
          ),
          Text(
            '${day.year}-${day.month}-${day.day}',
            style: const TextStyle(fontSize: 22),
          ),
          button(
            'Next day',
            () => setState(() => day = day.add(const Duration(days: 1))),
          ),
        ],
      ),
      button(
        'New appointment',
        () => startAppointment(),
        key: const Key('new-appointment-button'),
      ),
      if (items.isEmpty) const Text('No appointments yet'),
      for (final a in items) ...[
        const Divider(),
        Text('${_clock(a.startMinute)} · ${a.clientLabel ?? 'Private client'}'),
        Text(book.services.where((s) => s.id == a.serviceId).first.name),
        Text(a.status.name),
        button('Edit', () => startAppointment(a)),
        if (a.status == BookingStatus.booked) ...[
          button(
            'Complete',
            () => setState(() => book.setStatus(a.id, BookingStatus.completed)),
            key: const Key('complete-appointment-button'),
          ),
          button(
            'Cancel booking',
            () => setState(() => book.setStatus(a.id, BookingStatus.cancelled)),
          ),
        ],
      ],
    ];
  }

  List<Widget> serviceContent() => [
    const Text('Services', style: TextStyle(fontSize: 22)),
    for (final s in book.services) ...[
      Text('${s.name} (${s.durationMinutes}m + ${s.bufferMinutes}m buffer)'),
      button('Edit ${s.name}', () => startServiceEditor(s)),
    ],
    button(
      'Add service',
      () => startServiceEditor(),
      key: const Key('add-service-button'),
    ),
    if (serviceEditor) ...[
      field('Service name', serviceName, key: const Key('service-name-field')),
      field(
        'Duration (minutes)',
        duration,
        key: const Key('service-duration-field'),
      ),
      field(
        'Cleanup buffer (minutes)',
        buffer,
        key: const Key('service-buffer-field'),
      ),
      button(
        'Save service',
        saveService,
        key: const Key('save-service-button'),
      ),
    ],
    const Divider(),
    const Text(
      'Working hours (one window per day; empty fields close day)',
      style: TextStyle(fontSize: 18),
    ),
    for (var d = 1; d <= 7; d++) ...[
      button(
        'Edit ${['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d - 1]}',
        () {
          final matches = book.windows.where((w) => w.weekday == d);
          setState(() {
            open.text = matches.isEmpty ? '' : _clock(matches.first.openMinute);
            close.text = matches.isEmpty
                ? ''
                : _clock(matches.first.closeMinute);
            selectedWeekday = d;
          });
        },
      ),
      if (selectedWeekday == d) ...[
        field('Open HH:MM', open),
        field('Close HH:MM', close),
        button('Save hours', () => saveHours(d)),
      ],
    ],
  ];
}
