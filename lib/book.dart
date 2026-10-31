import 'package:sqlite3/sqlite3.dart';

import 'schedule.dart';

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
}
