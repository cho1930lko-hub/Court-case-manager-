/// Worklist persistence schema. Additive only: no existing case/register data is altered.
class WorklistSql {
  WorklistSql._();

  static const String hearingHistory = '''
CREATE TABLE IF NOT EXISTS hearing_history (
  id TEXT PRIMARY KEY,
  case_id TEXT NOT NULL,
  hearing_date TEXT NOT NULL DEFAULT '',
  outcome TEXT NOT NULL DEFAULT '',
  next_date TEXT NOT NULL DEFAULT '',
  witness_status TEXT NOT NULL DEFAULT '',
  summons_status TEXT NOT NULL DEFAULT '',
  order_summary TEXT NOT NULL DEFAULT '',
  next_action TEXT NOT NULL DEFAULT '',
  compliance TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  date_applied INTEGER NOT NULL DEFAULT 0,
  summons_applied INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
)''';

  static const String caseTasks = '''
CREATE TABLE IF NOT EXISTS case_tasks (
  id TEXT PRIMARY KEY,
  case_id TEXT NOT NULL,
  task_type TEXT NOT NULL DEFAULT 'other',
  title TEXT NOT NULL DEFAULT '',
  due_date TEXT NOT NULL DEFAULT '',
  priority INTEGER NOT NULL DEFAULT 2,
  status TEXT NOT NULL DEFAULT 'pending',
  source TEXT NOT NULL DEFAULT 'user',
  dedupe_key TEXT NOT NULL UNIQUE,
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  completed_at TEXT NOT NULL DEFAULT '',
  dismissed_at TEXT NOT NULL DEFAULT ''
)''';

  static const String taskHistory = '''
CREATE TABLE IF NOT EXISTS case_task_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,
  action TEXT NOT NULL,
  at TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT ''
)''';

  static const List<String> indexes = <String>[
    'CREATE INDEX IF NOT EXISTS idx_hearing_history_case ON hearing_history(case_id)',
    'CREATE INDEX IF NOT EXISTS idx_case_tasks_case ON case_tasks(case_id)',
    'CREATE INDEX IF NOT EXISTS idx_case_tasks_status ON case_tasks(status)',
    'CREATE INDEX IF NOT EXISTS idx_task_history_task ON case_task_history(task_id)',
  ];
}
