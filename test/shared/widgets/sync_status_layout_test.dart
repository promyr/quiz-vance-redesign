import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/shared/widgets/sync_status_card.dart';
void main() {
  testWidgets('sync title wraps at narrow width and enlarged font', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320,700));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home:MediaQuery(data:const MediaQueryData(textScaler:TextScaler.linear(1.6)),child:Scaffold(body:Padding(padding:const EdgeInsets.all(20),child:SyncStatusCard(state:SyncStatusState.syncing,message:'Seu resultado está salvo no aparelho.'))))));
    expect(tester.takeException(),isNull);
  });
}
