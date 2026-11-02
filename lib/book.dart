import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'schedule.dart';

/// Validated backup payload ready for an explicit, atomic restore.
class BackupPreview {
  const BackupPreview._(this.services, this.windows, this.appointments);
  final List<Service> services;
  final List<WorkingWindow> windows;
  final List<Appointment> appointments;

  String get summary =>
      '${services.length} services, ${windows.length} working windows, '
      '${appointments.length} appointments';
}

/// Reject malformed and unsupported backups before touching the live book.
BackupPreview previewBackup(String source) {
  final Object? decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
    throw const FormatException('Unsupported backup version');
  }
  List<Map<String, dynamic>> rows(String key) {
    final value = decoded[key];
    if (value is! List) throw FormatException('Missing $key');
    if (value.length > 10000) throw FormatException('Too many $key');
    return value.map((row) {
      if (row is! Map<String, dynamic>) throw FormatException('Invalid $key');
      return row;
    }).toList();
  }

  int number(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! int) throw FormatException('Invalid $key');
    return value;
  }

  String text(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String) throw FormatException('Invalid $key');
    return value;
  }

  String? optional(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value != null && value is! String) {
      throw FormatException('Invalid $key');
    }
    return value as String?;
  }

  DateTime localStart(Map<String, dynamic> row) {
    final value = text(row, 'startLocal');
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):00(?:\.000)?$',
    ).firstMatch(value);
    if (match == null) throw const FormatException('Invalid local start');
    return parseLocalMinute(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
    );
  }

  final services = [
    for (final row in rows('services'))
      Service(
        id: text(row, 'id'),
        name: text(row, 'name'),
        durationMinutes: number(row, 'duration'),
        bufferMinutes: number(row, 'buffer'),
      ),
  ];
  final windows = [
    for (final row in rows('windows'))
      WorkingWindow(
        weekday: number(row, 'weekday'),
        openMinute: number(row, 'open'),
        closeMinute: number(row, 'close'),
      ),
  ];
  final appointments = [
    for (final row in rows('appointments'))
      Appointment(
        id: text(row, 'id'),
        serviceId: text(row, 'serviceId'),
        startLocal: localStart(row),
        durationMinutes: number(row, 'duration'),
        bufferMinutes: number(row, 'buffer'),
        clientLabel: optional(row, 'clientLabel'),
        note: optional(row, 'note'),
        status: BookingStatus.values.byName(text(row, 'status')),
      ),
  ];
  if (services.map((s) => s.id).toSet().length != services.length ||
      appointments.map((a) => a.id).toSet().length != appointments.length ||
      windows.map((w) => '${w.weekday}:${w.openMinute}').toSet().length !=
          windows.length) {
    throw const FormatException('Duplicate backup ID or working window');
  }
  final serviceIds = services.map((s) => s.id).toSet();
  for (final window in windows) {
    if (windows.any(
      (other) =>
          !identical(window, other) &&
          window.weekday == other.weekday &&
          window.openMinute < other.closeMinute &&
          other.openMinute < window.closeMinute,
    )) {
      throw const FormatException('Overlapping working windows');
    }
  }
  for (final appointment in appointments) {
    if (!serviceIds.contains(appointment.serviceId) ||
        appointment.startLocal.isUtc ||
        !isUniqueLocalMinute(appointment.startLocal) ||
        validateSlot(
              appointment,
              windows,
              appointments.where((a) => a.id != appointment.id),
            ) !=
            null) {
      throw const FormatException('Invalid backup appointment');
    }
  }
  return BackupPreview._(
    List.unmodifiable(services),
    List.unmodifiable(windows),
    List.unmodifiable(appointments),
  );
}

String dailyScheduleCsv(Book book, DateTime day, {required bool redactNames}) {
  String cell(String value) {
    final safe = RegExp(r'^[\s]*[=+\-@\t\r]').hasMatch(value)
        ? "'$value"
        : value;
    return '"${safe.replaceAll('"', '""')}"';
  }

  final services = {for (final s in book.services) s.id: s.name};
  final lines = <String>['Date,Time,Service,Client,Status'];
  for (final a in book.appointments.where(
    (a) =>
        a.startLocal.year == day.year &&
        a.startLocal.month == day.month &&
        a.startLocal.day == day.day,
  )) {
    final start = a.startLocal;
    lines.add(
      [
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
        services[a.serviceId]!,
        redactNames ? 'Private client' : a.clientLabel ?? '',
        a.status.name,
      ].map(cell).join(','),
    );
  }
  return '${lines.join('\r\n')}\r\n';
}

class SlotRejected implements Exception {
  const SlotRejected(this.reason);
  final SlotError reason;
  @override
  String toString() => 'Slot rejected: ${reason.name}';
}

/// One local SQLite book. Keep synchronous transactions short; no network or shared writer.
/// ponytail: large multi-stylist books need a background isolate; solo-chair MVP is local-only.
class Book {
  Book._(this._db);
  final Database _db;

  static Book open(String path) {
    final db = sqlite3.open(path);
    try {
      db.execute('PRAGMA foreign_keys = ON');
      db.execute('BEGIN IMMEDIATE');
      try {
        final version =
            db.select('PRAGMA user_version').single.values.single as int;
        if (version != 0 && version != 1) {
          throw StateError('Unsupported book schema: $version');
        }
        if (version == 0) {
          db.execute('''
            CREATE TABLE services (id TEXT PRIMARY KEY, name TEXT NOT NULL,
              duration INTEGER NOT NULL, buffer INTEGER NOT NULL);
            CREATE TABLE windows (weekday INTEGER NOT NULL, open_minute INTEGER NOT NULL,
              close_minute INTEGER NOT NULL, PRIMARY KEY(weekday, open_minute));
            CREATE TABLE appointments (id TEXT PRIMARY KEY,
              service_id TEXT NOT NULL REFERENCES services(id),
              year INTEGER NOT NULL, month INTEGER NOT NULL, day INTEGER NOT NULL,
              hour INTEGER NOT NULL, minute INTEGER NOT NULL,
              duration INTEGER NOT NULL, buffer INTEGER NOT NULL,
              client_label TEXT, note TEXT, status TEXT NOT NULL);
            PRAGMA user_version = 1;
          ''');
        }
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
      return Book._(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  void close() => _db.close();

  T _transaction<T>(T Function() action) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<Service> get services => [
    for (final row in _db.select('SELECT * FROM services ORDER BY name, id'))
      Service(
        id: row['id'] as String,
        name: row['name'] as String,
        durationMinutes: row['duration'] as int,
        bufferMinutes: row['buffer'] as int,
      ),
  ];

  List<WorkingWindow> get windows => [
    for (final row in _db.select(
      'SELECT * FROM windows ORDER BY weekday, open_minute',
    ))
      WorkingWindow(
        weekday: row['weekday'] as int,
        openMinute: row['open_minute'] as int,
        closeMinute: row['close_minute'] as int,
      ),
  ];

  List<Appointment> get appointments => [
    for (final row in _db.select(
      'SELECT * FROM appointments ORDER BY year, month, day, hour, minute, id',
    ))
      Appointment(
        id: row['id'] as String,
        serviceId: row['service_id'] as String,
        startLocal: parseLocalMinute(
          row['year'] as int,
          row['month'] as int,
          row['day'] as int,
          row['hour'] as int,
          row['minute'] as int,
        ),
        durationMinutes: row['duration'] as int,
        bufferMinutes: row['buffer'] as int,
        clientLabel: row['client_label'] as String?,
        note: row['note'] as String?,
        status: BookingStatus.values.byName(row['status'] as String),
      ),
  ];

  void saveService(Service service) => _transaction(() {
    _db.execute(
      '''INSERT INTO services (id, name, duration, buffer) VALUES (?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET name=excluded.name, duration=excluded.duration,
      buffer=excluded.buffer''',
      [
        service.id,
        service.name,
        service.durationMinutes,
        service.bufferMinutes,
      ],
    );
  });

  void setWindows(List<WorkingWindow> proposed) => _transaction(() {
    for (final window in proposed) {
      final sameDay = proposed.where(
        (other) => other.weekday == window.weekday && !identical(other, window),
      );
      if (sameDay.any(
        (other) =>
            window.openMinute < other.closeMinute &&
            other.openMinute < window.closeMinute,
      )) {
        throw ArgumentError('Overlapping working windows');
      }
    }
    for (final booking in appointments.where(
      (item) => item.status != BookingStatus.cancelled,
    )) {
      final reason = validateSlot(booking, proposed, const []);
      if (reason != null) throw SlotRejected(reason);
    }
    _db.execute('DELETE FROM windows');
    for (final w in proposed) {
      _db.execute('INSERT INTO windows VALUES (?, ?, ?)', [
        w.weekday,
        w.openMinute,
        w.closeMinute,
      ]);
    }
  });

  void saveAppointment(Appointment booking) => _transaction(() {
    if (!services.any((s) => s.id == booking.serviceId)) {
      throw ArgumentError('Unknown service');
    }
    final others = appointments.where((item) => item.id != booking.id);
    final reason = validateSlot(booking, windows, others);
    if (reason != null) throw SlotRejected(reason);
    _db.execute(
      '''INSERT INTO appointments
      (id, service_id, year, month, day, hour, minute, duration, buffer, client_label, note, status)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET service_id=excluded.service_id,
      year=excluded.year, month=excluded.month, day=excluded.day,
      hour=excluded.hour, minute=excluded.minute, duration=excluded.duration,
      buffer=excluded.buffer, client_label=excluded.client_label, note=excluded.note,
      status=excluded.status''',
      [
        booking.id,
        booking.serviceId,
        booking.startLocal.year,
        booking.startLocal.month,
        booking.startLocal.day,
        booking.startLocal.hour,
        booking.startLocal.minute,
        booking.durationMinutes,
        booking.bufferMinutes,
        booking.clientLabel,
        booking.note,
        booking.status.name,
      ],
    );
  });

  void setStatus(String id, BookingStatus status) => _transaction(() {
    final matches = appointments.where((a) => a.id == id);
    if (matches.isEmpty) throw ArgumentError('Unknown appointment');
    final current = matches.single;
    if (status != BookingStatus.cancelled &&
        current.status == BookingStatus.cancelled) {
      final revived = Appointment(
        id: current.id,
        serviceId: current.serviceId,
        startLocal: current.startLocal,
        durationMinutes: current.durationMinutes,
        bufferMinutes: current.bufferMinutes,
        clientLabel: current.clientLabel,
        note: current.note,
        status: status,
      );
      final others = appointments.where((item) => item.id != id);
      final reason = validateSlot(revived, windows, others);
      if (reason != null) throw SlotRejected(reason);
    }
    _db.execute('UPDATE appointments SET status = ? WHERE id = ?', [
      status.name,
      id,
    ]);
  });

  String exportJson() => jsonEncode({
    'version': 1,
    'services': [
      for (final s in services)
        {
          'id': s.id,
          'name': s.name,
          'duration': s.durationMinutes,
          'buffer': s.bufferMinutes,
        },
    ],
    'windows': [
      for (final w in windows)
        {'weekday': w.weekday, 'open': w.openMinute, 'close': w.closeMinute},
    ],
    'appointments': [
      for (final a in appointments)
        {
          'id': a.id,
          'serviceId': a.serviceId,
          'startLocal':
              '${a.startLocal.year.toString().padLeft(4, '0')}-'
              '${a.startLocal.month.toString().padLeft(2, '0')}-'
              '${a.startLocal.day.toString().padLeft(2, '0')}T'
              '${a.startLocal.hour.toString().padLeft(2, '0')}:'
              '${a.startLocal.minute.toString().padLeft(2, '0')}:00',
          'duration': a.durationMinutes,
          'buffer': a.bufferMinutes,
          'clientLabel': a.clientLabel,
          'note': a.note,
          'status': a.status.name,
        },
    ],
  });

  void restore(BackupPreview backup) => _transaction(() {
    _db.execute('DELETE FROM appointments');
    _db.execute('DELETE FROM windows');
    _db.execute('DELETE FROM services');
    for (final s in backup.services) {
      _db.execute(
        'INSERT INTO services (id, name, duration, buffer) VALUES (?, ?, ?, ?)',
        [s.id, s.name, s.durationMinutes, s.bufferMinutes],
      );
    }
    for (final w in backup.windows) {
      _db.execute(
        'INSERT INTO windows (weekday, open_minute, close_minute) VALUES (?, ?, ?)',
        [w.weekday, w.openMinute, w.closeMinute],
      );
    }
    for (final a in backup.appointments) {
      _db.execute(
        '''INSERT INTO appointments
        (id, service_id, year, month, day, hour, minute, duration, buffer, client_label, note, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          a.id,
          a.serviceId,
          a.startLocal.year,
          a.startLocal.month,
          a.startLocal.day,
          a.startLocal.hour,
          a.startLocal.minute,
          a.durationMinutes,
          a.bufferMinutes,
          a.clientLabel,
          a.note,
          a.status.name,
        ],
      );
    }
  });
}
