import 'package:flutter_test/flutter_test.dart';
import '../lib/core/worklist_engine.dart';

void main() {
  group('WorklistEngine', () {
    final now = DateTime(2026, 11, 14);
    test('closed cases do not create hearing or summons reminders', () {
      final items = WorklistEngine.build(
        now: now,
        cases: [
          {'id':'1','st_no':'01','status':'निस्तारित','next_hearing':'14/11/2026','summons_status':'बनाना है'},
        ],
        tasks: [],
      );
      expect(items, isEmpty);
    });

    test('overdue tasks sort before future tasks and use due date', () {
      final cases = [
        {'id':'1','st_no':'01','status':'विचाराधीन','next_hearing':'20/11/2026'},
        {'id':'2','st_no':'02','status':'विचाराधीन','next_hearing':'20/11/2026'},
      ];
      final items = WorklistEngine.build(now: now, cases: cases, tasks: [
        {'id':'t2','case_id':'2','task_type':'compliance','title':'Future','due_date':'18/11/2026','priority':2,'status':'pending','dedupe_key':'k2'},
        {'id':'t1','case_id':'1','task_type':'compliance','title':'Late','due_date':'10/11/2026','priority':2,'status':'pending','dedupe_key':'k1'},
      ]);
      expect(items.where((e) => e.isStoredTask).first.taskId, 't1');
      expect(items.where((e) => e.isStoredTask).first.overdue, isTrue);
    });

    test('dismissed derived reminder is not recreated', () {
      final cases = [
        {'id':'1','st_no':'01','status':'विचाराधीन','next_hearing':'14/11/2026'},
      ];
      final items = WorklistEngine.build(now: now, cases: cases, tasks: [
        {'task_type':'dismissal','dedupe_key':'derived:hearing_today:1:14/11/2026','status':'dismissed'},
      ]);
      expect(items, isEmpty);
    });
  });
}
