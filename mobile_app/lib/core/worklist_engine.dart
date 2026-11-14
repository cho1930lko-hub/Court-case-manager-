import 'dates.dart';
import 'hearings.dart' show finishedStatuses;
enum WorkKind { hearingToday,hearingOverdue,hearingTomorrow,summonsPending,task,hearingUpcoming }
class WorkItem {
 const WorkItem({required this.kind,required this.caseId,required this.stNo,required this.title,required this.court,required this.hearingDate,required this.taskType,required this.status,required this.priority,required this.related,required this.nextAction,required this.dedupeKey,this.taskId,this.dueDate='',this.overdue=false});
 final WorkKind kind; final String caseId,stNo,title,court,hearingDate,taskType,status,related,nextAction,dedupeKey; final int priority; final String? taskId; final String dueDate; final bool overdue;
 bool get isStoredTask=>taskId!=null;
}
String _s(Object? v)=>(v??'').toString().trim();
class WorklistEngine {
 WorklistEngine._();
 static const taskPending='pending',taskDismissal='dismissal';
 static List<WorkItem> build({required List<Map<String,Object?>> cases,required List<Map<String,Object?>> tasks,required DateTime now}) {
  final today=AppDates.dateOnly(now),tomorrow=DateTime(now.year,now.month,now.day+1),weekEnd=DateTime(now.year,now.month,now.day+7);
  final dismissed=<String>{for(final t in tasks) if(_s(t['task_type'])==taskDismissal)_s(t['dedupe_key'])};
  final byId=<String,Map<String,Object?>>{for(final c in cases) _s(c['id']):c};
  final out=<WorkItem>[],seen=<String>{};
  void add(WorkItem i){if(!dismissed.contains(i.dedupeKey)&&seen.add(i.dedupeKey))out.add(i);}
  for(final c in cases){
   final id=_s(c['id']),status=_s(c['status']),hearing=_s(c['next_hearing']),summons=_s(c['summons_status']);
   if(finishedStatuses.contains(status)) continue;
   final d=AppDates.parse(hearing);
   WorkItem mk(WorkKind k,String key,int p,String action,{String type='hearing'})=>WorkItem(kind:k,caseId:id,stNo:_s(c['st_no']),title:_s(c['accused_name']),court:_s(c['court_name']),hearingDate:hearing,taskType:type,status:'pending',priority:p,related:summons.isEmpty?'':'सम्मन: $summons',nextAction:action,dedupeKey:key);
   if(d!=null){
    if(d==today)add(mk(WorkKind.hearingToday,'derived:hearing_today:$id:$hearing',1,'पेशी का परिणाम और अगली तारीख दर्ज करें'));
    else if(d==tomorrow)add(mk(WorkKind.hearingTomorrow,'derived:hearing_tomorrow:$id:$hearing',2,'कल की पेशी की तैयारी देखें'));
    else if(d.isAfter(tomorrow)&&!d.isAfter(weekEnd))add(mk(WorkKind.hearingUpcoming,'derived:hearing_upcoming:$id:$hearing',3,'तैयारी / सम्मन की स्थिति जाँचें'));
    else if(d.isBefore(today))add(mk(WorkKind.hearingOverdue,'derived:hearing_overdue:$id:$hearing',1,'तारीख बीत चुकी — परिणाम/नई तारीख जाँचकर अपडेट करें'));
   }
   if(summons=='बनाना है')add(mk(WorkKind.summonsPending,'derived:summons:$id:$hearing',2,'सम्मन बनाने का निर्णय आप लें',type:'summons'));
  }
  for(final t in tasks){
   if(_s(t['task_type'])==taskDismissal||_s(t['status'])!=taskPending)continue;
   final cid=_s(t['case_id']),c=byId[cid]; if(c==null||finishedStatuses.contains(_s(c['status'])))continue;
   final due=AppDates.parse(_s(t['due_date'])),late=due!=null&&due.isBefore(today);
   var p=int.tryParse(_s(t['priority']))??2;if(p<1||p>3)p=2;if(late)p=1;
   add(WorkItem(kind:WorkKind.task,caseId:cid,stNo:_s(c['st_no']),title:_s(c['accused_name']),court:_s(c['court_name']),hearingDate:_s(c['next_hearing']),taskType:_s(t['task_type']),status:_s(t['status']),priority:p,related:_s(t['title']),nextAction:_s(t['note']).isEmpty?_s(t['title']):_s(t['note']),dedupeKey:_s(t['dedupe_key']),taskId:_s(t['id']),dueDate:_s(t['due_date']),overdue:late));
  }
  out.sort((a,b){
   final p=a.priority.compareTo(b.priority);if(p!=0)return p;
   final da=AppDates.parse(a.dueDate)??AppDates.parse(a.hearingDate),db=AppDates.parse(b.dueDate)??AppDates.parse(b.hearingDate);
   if(da!=null&&db!=null){final c=da.compareTo(db);if(c!=0)return c;}else if(da!=null)return -1;else if(db!=null)return 1;
   return a.stNo.compareTo(b.stNo);
  });
  return out;
 }
}
