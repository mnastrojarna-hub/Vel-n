import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../catalog/moto_model.dart';
import 'edit_reservation_calendar.dart';
import 'reservation_edit_widgets.dart';

/// Calendar + date-range card for the reservation edit screen.
class EditCalendarSection extends StatelessWidget {
  final String tab;
  final bool isActive;
  final DateTime origStart, origEnd;
  final DateTime? newStart, newEnd;
  final int diffDays;
  final String? shortenDir;
  final String calendarInstruction;
  final String motoName, shortId;
  final List<BookedDateRange> bookedDates;
  final void Function(DateTime, DateTime) onDatesChanged;
  final ValueChanged<String> onError;
  final VoidCallback onShortenStart, onShortenEnd;

  const EditCalendarSection({
    super.key,
    required this.tab,
    required this.isActive,
    required this.origStart,
    required this.origEnd,
    required this.newStart,
    required this.newEnd,
    required this.diffDays,
    required this.shortenDir,
    required this.calendarInstruction,
    required this.motoName,
    required this.shortId,
    required this.bookedDates,
    required this.onDatesChanged,
    required this.onError,
    required this.onShortenStart,
    required this.onShortenEnd,
  });

  String _fmt(DateTime? d) {
    if (d == null) return '–';
    return '${d.day}.${d.month}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return EditCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.calendar_month, size: 16, color: MotoGoColors.dark),
        const SizedBox(width: 6),
        Text(t(context).tr('termLabel'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        EditDateBox(label: t(context).tr('pickupEditLabel'), date: _fmt(newStart)),
        const SizedBox(width: 8),
        EditDateBox(label: t(context).tr('returnEditLabel'), date: _fmt(newEnd)),
      ]),
      if (diffDays != 0)
        Padding(padding: const EdgeInsets.only(top: 6),
          child: Text(
            diffDays > 0 ? '+$diffDays ${diffDays == 1 ? t(context).tr('day1') : diffDays < 5 ? t(context).tr('days24') : t(context).tr('days5')} (${t(context).tr('extensionWord')})'
                : '${diffDays.abs()} ${diffDays.abs() == 1 ? t(context).tr('day1') : diffDays.abs() < 5 ? t(context).tr('days24') : t(context).tr('days5')} (${t(context).tr('shorteningWord')})',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: diffDays > 0 ? MotoGoColors.greenDarker : MotoGoColors.red),
          )),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: MotoGoColors.greenPale,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MotoGoColors.green, width: 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            isActive ? t(context).tr('yourActiveReservation') : t(context).tr('yourUpcomingReservation'),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker),
          ),
          Text(
            '${_fmt(origStart)} – ${_fmt(origEnd)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black),
          ),
          Text(
            '$motoName · $shortId',
            style: const TextStyle(fontSize: 11, color: MotoGoColors.g400),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      Text(
        calendarInstruction,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: MotoGoColors.g400),
      ),
      if (tab == 'extend')
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            t(context).tr('searchSingleDayHint'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: MotoGoColors.g400),
          ),
        ),
      if (tab == 'shorten' && !isActive) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: onShortenStart,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: shortenDir == 'start' ? MotoGoColors.green : MotoGoColors.g100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: shortenDir == 'start' ? MotoGoColors.green : MotoGoColors.g200),
              ),
              child: Center(child: Text(
                t(context).tr('shortenStart'),
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: shortenDir == 'start' ? Colors.black : MotoGoColors.g600,
                ),
              )),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: GestureDetector(
            onTap: onShortenEnd,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: shortenDir == 'end' ? MotoGoColors.green : MotoGoColors.g100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: shortenDir == 'end' ? MotoGoColors.green : MotoGoColors.g200),
              ),
              child: Center(child: Text(
                t(context).tr('shortenEnd'),
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: shortenDir == 'end' ? Colors.black : MotoGoColors.g600,
                ),
              )),
            ),
          )),
        ]),
      ],
      const SizedBox(height: 4),
      EditReservationCalendar(
        bookedDates: bookedDates,
        origStart: origStart,
        origEnd: origEnd,
        newStart: newStart,
        newEnd: newEnd,
        isActive: isActive,
        mode: tab,
        shortenDir: shortenDir,
        onDatesChanged: onDatesChanged,
        onError: onError,
      ),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (tab == 'shorten') ...[
          EditLegendDot(color: MotoGoColors.green, label: t(context).tr('existingLabel')),
          const SizedBox(width: 10),
          EditLegendDot(color: MotoGoColors.red, label: t(context).tr('shortenedLabel')),
          const SizedBox(width: 10),
          EditLegendDot(color: MotoGoColors.dark, label: t(context).tr('occupiedLabel')),
        ] else ...[
          EditLegendDot(color: MotoGoColors.green, label: t(context).tr('freeLabel')),
          const SizedBox(width: 10),
          EditLegendDot(color: MotoGoColors.dark, label: t(context).tr('occupiedLabel')),
        ],
      ]),
    ]));
  }
}
