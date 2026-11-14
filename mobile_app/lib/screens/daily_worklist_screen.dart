import 'package:flutter/material.dart';
import '../core/worklist_engine.dart';
import '../data/local_database.dart';
import 'hearing_update_screen.dart';

class DailyWorklistScreen extends StatefulWidget {
 const DailyWorklistScreen({super.key});
 @override State<DailyWorklistScreen> createState()=>_DailyWorklistScreenState();
}
class _DailyWorklistScreenState extends State<DailyWorklistScreen>{
 List<WorkItem> _items=[]; Map<String,Map<String,Object?>> _cases={}; bool _loading=true;
 @override void initState(){super.initState();_load();}
 Future<void> _load() async {
  setState(()=>_loading=true);
  try{final db=await LocalDatabase.instance.database;final cases=await db.query('cases',where:'is_archived = 0');final tasks=await LocalDatabase.instance.worklistTasks();_cases={for(final c in cases)(c['id']??'').toString():c};_items=WorklistEngine.build(cases:cases,tasks:tasks,now:DateTime.now());}
  finally{if(mounted)setState(()=>_loading=false);}
 }
 String _kind(WorkItem i)=>switch(i.kind){WorkKind.hearingToday=>'आज की पेशी',WorkKind.hearingOverdue=>'बीती पेशी',WorkKind.hearingTomorrow=>'कल की पेशी',WorkKind.hearingUpcoming=>'आगामी पेशी',WorkKind.summonsPending=>'सम्मन लंबित',WorkKind.task=>'निर्धारित कार्य'};
 Future<void> _open(WorkItem item) async {
  if(item.isStoredTask){await LocalDatabase.instance.completeTask(item.taskId!);await _load();return;}
  final c=_cases[item.caseId];if(c==null)return;
  await Navigator.push(context,MaterialPageRoute(builder:(_)=>HearingUpdateScreen(caseRow:c)));await _load();
 }
 Future<void> _dismiss(WorkItem i) async {
  if(i.isStoredTask){await LocalDatabase.instance.dismissTask(i.taskId!);}else{await LocalDatabase.instance.dismissDerived(caseId:i.caseId,dedupeKey:i.dedupeKey);}
  await _load();
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('दैनिक कार्य-सूची'),actions:[IconButton(onPressed:_load,icon:const Icon(Icons.refresh))]),body:_loading?const Center(child:CircularProgressIndicator()):_items.isEmpty?const Center(child:Text('अभी कोई लंबित कार्य नहीं')):RefreshIndicator(onRefresh:_load,child:ListView.builder(padding:const EdgeInsets.all(12),itemCount:_items.length,itemBuilder:(context,index){final i=_items[index];return Card(child:ListTile(title:Text('${_kind(i)} • ST ${i.stNo}'),subtitle:Text('${i.title}\n${i.nextAction}${i.dueDate.isEmpty?'':'\nसमय-सीमा: ${i.dueDate}'}'),isThreeLine:true,leading:CircleAvatar(child:Text('${i.priority}')),onTap:()=>_open(i),trailing:PopupMenuButton<String>(onSelected:(v){if(v=='dismiss')_dismiss(i);},itemBuilder:(_)=>const [PopupMenuItem(value:'dismiss',child:Text('इस याद को हटाएँ'))])));})));
}
