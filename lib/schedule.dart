/// Local-device wall-clock rules. All minutes are half-open; no UTC scheduling.
/// ponytail: multi-zone scheduling needs an explicit IANA zone database; this
/// offline single-chair book uses device zone and rejects DST folds/gaps.
library;

enum BookingStatus { booked, completed, cancelled }

class Service {
  Service({
    required this.id,
    required this.name,
    required this.durationMinutes,
    required this.bufferMinutes,
  }) {
    if (id.trim().isEmpty ||
        name.trim().isEmpty ||
        durationMinutes <= 0 ||
        bufferMinutes < 0 ||
        durationMinutes + bufferMinutes > 1440) {
      throw ArgumentError('Invalid service');
    }
  }

  final String id, name;
  final int durationMinutes, bufferMinutes;
}

/// ISO weekday (1 Monday ... 7 Sunday), minutes since midnight.
class WorkingWindow {
  WorkingWindow({
    required this.weekday,
    required this.openMinute,
    required this.closeMinute,
  }) {
    if (weekday < 1 ||
        weekday > 7 ||
        openMinute < 0 ||
        closeMinute > 1440 ||
        openMinute >= closeMinute) {
      throw ArgumentError('Invalid working window');
    }
  }

  final int weekday, openMinute, closeMinute;
}

class Appointment {
  Appointment({
    required this.id,
    required this.serviceId,
    required this.startLocal,
    required this.durationMinutes,
    required this.bufferMinutes,
    this.clientLabel,
    this.note,
    this.status = BookingStatus.booked,
  }) {
    if (id.trim().isEmpty ||
        serviceId.trim().isEmpty ||
        durationMinutes <= 0 ||
        bufferMinutes < 0 ||
        durationMinutes + bufferMinutes > 1440) {
      throw ArgumentError('Invalid appointment');
    }
  }

  factory Appointment.forService({
    required String id,
    required Service service,
    required DateTime startLocal,
    String? clientLabel,
    String? note,
  }) => Appointment(
    id: id,
    serviceId: service.id,
    startLocal: startLocal,
    durationMinutes: service.durationMinutes,
    bufferMinutes: service.bufferMinutes,
    clientLabel: clientLabel,
    note: note,
  );

  final String id, serviceId;
  final DateTime startLocal;
  final int durationMinutes, bufferMinutes;
  final String? clientLabel, note;
  final BookingStatus status;

  int get startMinute => startLocal.hour * 60 + startLocal.minute;
  int get endMinute => startMinute + durationMinutes + bufferMinutes;
}

enum SlotError {
  invalidLocalTime,
  crossesMidnight,
  outsideHours,
  conflict,
  duplicateId,
}

/// Tests candidate offset instants against local fields. Two matches mean a
/// DST fold; zero mean a gap. DateTime normalization alone hides both.
bool isUniqueLocalMinute(DateTime local) {
  if (local.isUtc ||
      local.second != 0 ||
      local.millisecond != 0 ||
      local.microsecond != 0) {
    return false;
  }
  final offsets = <Duration>{
    for (final hours in [-36, -12, 0, 12, 36])
      local.add(Duration(hours: hours)).timeZoneOffset,
  };
  final wallAsUtc = DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
  );
  var matches = 0;
  for (final offset in offsets) {
    final candidate = wallAsUtc.subtract(offset).toLocal();
    if (candidate.year == local.year &&
        candidate.month == local.month &&
        candidate.day == local.day &&
        candidate.hour == local.hour &&
        candidate.minute == local.minute) {
      matches++;
    }
  }
  return matches == 1;
}

/// Use this at text/UI input boundary: DateTime silently normalizes gaps.
DateTime parseLocalMinute(int year, int month, int day, int hour, int minute) {
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    throw FormatException('Invalid local minute');
  }
  final local = DateTime(year, month, day, hour, minute);
  if (local.year != year ||
      local.month != month ||
      local.day != day ||
      local.hour != hour ||
      local.minute != minute ||
      !isUniqueLocalMinute(local)) {
    throw FormatException('Skipped or ambiguous local minute');
  }
  return local;
}

bool _validInterval(Appointment booking) {
  if (booking.endMinute > 1440) return false;
  for (var minute = booking.startMinute; minute < booking.endMinute; minute++) {
    try {
      parseLocalMinute(
        booking.startLocal.year,
        booking.startLocal.month,
        booking.startLocal.day,
        minute ~/ 60,
        minute % 60,
      );
    } on FormatException {
      return false;
    }
  }
  return true;
}

/// Conflicts occupy service plus cleanup buffer, including completed bookings.
/// Cancelled bookings release time. Windows can model breaks by splitting hours.
/// Editing same ID is handled by excluding old record from existing.
SlotError? validateSlot(
  Appointment booking,
  Iterable<WorkingWindow> windows,
  Iterable<Appointment> existing,
) {
  if (!isUniqueLocalMinute(booking.startLocal)) {
    return SlotError.invalidLocalTime;
  }
  if (booking.endMinute > 1440) return SlotError.crossesMidnight;
  if (!_validInterval(booking)) return SlotError.invalidLocalTime;
  final withinHours = windows.any(
    (window) =>
        window.weekday == booking.startLocal.weekday &&
        window.openMinute <= booking.startMinute &&
        booking.endMinute <= window.closeMinute,
  );
  if (!withinHours) return SlotError.outsideHours;
  for (final other in existing) {
    if (other.id == booking.id) return SlotError.duplicateId;
    if (other.status == BookingStatus.cancelled ||
        booking.status == BookingStatus.cancelled) {
      continue;
    }
    if (!_validInterval(other)) return SlotError.invalidLocalTime;
    final sameDay =
        other.startLocal.year == booking.startLocal.year &&
        other.startLocal.month == booking.startLocal.month &&
        other.startLocal.day == booking.startLocal.day;
    if (sameDay &&
        booking.startMinute < other.endMinute &&
        other.startMinute < booking.endMinute) {
      return SlotError.conflict;
    }
  }
  return null;
}
