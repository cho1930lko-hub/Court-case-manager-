import 'dates.dart';
const finishedStatuses = {'जजमेंट','सजा','दोष मुक्त','दोषमुक्त','निस्तारित'};
String _s(Object? v)=>(v??'').toString().trim();
class HearingBuckets {
  HearingBuckets({required this.today,required this.upcoming,required this.overdue,required this.noDate,required this.summonsPending});
  final List<Map<String,Object?>> today,upcoming,overdue,noDate,summonsPending;
}
HearingBuckets classifyHearings(List<Map<String,Object?>> cases,DateTime now,{int upcomingDays=7}) {
  final today=AppDates.dateOnly(now), limit=DateTime(now.year,now.month,now.day+upcomingDays);
  final dated=<MapEntry<DateTime,Map<String,Object?>>>[], noDate=<Map<String,Object?>>[], pending=<Map<String,Object?>>[];
  for(final row in cases){
    final closed=finishedStatuses.contains(_s(row['status']));
    if(!closed && _s(row['summons_status'])=='बनाना है') pending.add(row);
    final d=AppDates.parse(_s(row['next_hearing']));
    if(d==null){noDate.add(row);}else{dated.add(MapEntry(d,row));}
  }
  dated.sort((a,b)=>a.key.compareTo(b.key));
  final t=<Map<String,Object?>>[],u=<Map<String,Object?>>[],o=<Map<String,Object?>>[];
  for(final e in dated){final d=e.key,r=e.value; if(d==today)t.add(r);else if(d.isAfter(today)&&!d.isAfter(limit))u.add(r);else if(d.isBefore(today)&&!finishedStatuses.contains(_s(r['status'])))o.add(r);}
  return HearingBuckets(today:t,upcoming:u,overdue:o,noDate:noDate,summonsPending:pending);
}
