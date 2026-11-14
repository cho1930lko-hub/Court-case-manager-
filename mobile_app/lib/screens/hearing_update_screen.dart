import 'package:flutter/material.dart';
import '../data/local_database.dart';

/// Manual hearing outcome entry. Case date changes only after explicit confirmation.
class HearingUpdateScreen extends StatefulWidget {
  const HearingUpdateScreen({super.key, required this.caseRow});
  final Map<String,Object?> caseRow;
  @override State<HearingUpdateScreen> createState()=>_HearingUpdateScreenState();
}
class _HearingUpdateScreenState extends State<HearingUpdateScreen>{
 final _held=TextEditingController(),_next=TextEditingController(),_outcome=TextEditingController(),_witness=TextEditingController(),_summons=TextEditingController(),_order=TextEditingController(),_action=TextEditingController(),_compliance=TextEditingController(),_notes=TextEditingController();
 bool _applyDate=true,_applySummons=false,_createTasks=true,_saving=false;
 @override void dispose(){for(final c in [_held,_next,_outcome,_witness,_summons,_order,_action,_compliance,_notes]){c.dispose();}super.dispose();}
 Widget _field(String label,TextEditingController c,{int lines=1})=>Padding(padding:const EdgeInsets.only(bottom:12),child:TextField(controller:c,maxLines:lines,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder())));
 Future<void> _save() async {
  setState(()=>_saving=true);
  try{
   await LocalDatabase.instance.saveHearingUpdate(caseId:'${widget.caseRow['id']}',heldDate:_held.text,nextDate:_next.text,outcome:_outcome.text,witnessStatus:_witness.text,summonsStatus:_summons.text,orderSummary:_order.text,nextAction:_action.text,compliance:_compliance.text,notes:_notes.text,applyNextDate:_applyDate,applySummons:_applySummons,createTasks:_createTasks);
   if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('पेशी अपडेट सुरक्षित हुआ')));Navigator.pop(context,true);}
  }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('सुरक्षित नहीं हुआ: $e')));}
  finally{if(mounted)setState(()=>_saving=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('पेशी अपडेट')),body:ListView(padding:const EdgeInsets.all(16),children:[
  Text('ST ${widget.caseRow['st_no']??''} • ${widget.caseRow['accused_name']??''}',style:Theme.of(context).textTheme.titleMedium),
  const SizedBox(height:16),_field('पेशी की तारीख (DD/MM/YYYY)',_held),_field('अगली तारीख (DD/MM/YYYY)',_next),_field('कार्यवाही / परिणाम',_outcome,lines:2),_field('गवाह की स्थिति',_witness),_field('सम्मन की स्थिति',_summons),_field('आदेश का सार',_order,lines:2),_field('अगला कार्य',_action,lines:2),_field('अनुपालन',_compliance,lines:2),_field('टिप्पणी',_notes,lines:2),
  SwitchListTile(value:_applyDate,onChanged:(v)=>setState(()=>_applyDate=v),title:const Text('अगली तारीख केस रिकॉर्ड में लागू करें')),
  SwitchListTile(value:_applySummons,onChanged:(v)=>setState(()=>_applySummons=v),title:const Text('सम्मन स्थिति केस रिकॉर्ड में लागू करें')),
  SwitchListTile(value:_createTasks,onChanged:(v)=>setState(()=>_createTasks=v),title:const Text('अगले कार्यों को कार्य-सूची में जोड़ें')),
  const SizedBox(height:12),FilledButton(onPressed:_saving?null:_save,child:Text(_saving?'सुरक्षित हो रहा है…':'पेशी अपडेट सुरक्षित करें'))
 ]));
}
