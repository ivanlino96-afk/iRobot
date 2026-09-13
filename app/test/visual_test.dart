import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airobot/presentation/home_page.dart';
import 'package:airobot/presentation/theme.dart';
import 'package:airobot/presentation/robot_view_model.dart';
void main() {
 testWidgets('Five screens fit phone and tablet', (tester) async {
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final vm=RobotViewModel();
  await tester.runAsync(() async {
   if(const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
    final font=File('/System/Library/Fonts/SFNS.ttf');
    if(font.existsSync()) { final loader=FontLoader('.SF Pro Text')..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));await loader.load(); }
   }
   await vm.demo();await vm.reference(vm.profile!.home);await vm.send('enable');
  });
  final key=GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(theme:airobotTheme(),home:HomePage(model:vm))));
  await tester.pump(const Duration(milliseconds:20));
  for(final label in ['Control','Mover TCP','Programas','Enseñar','Configurar']) {
   await tester.tap(find.text(label).last);await tester.pump(const Duration(milliseconds:400));
   expect(tester.takeException(),isNull,reason:label);
   if(const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
    await tester.runAsync(() async {
     final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
     final image=await boundary.toImage();final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
     final dir=Directory('../docs/previews')..createSync(recursive:true);
     File('${dir.path}/${label.replaceAll(' ','-')}.png').writeAsBytesSync(bytes!.buffer.asUint8List());image.dispose();
    });
   }
  }
  tester.view.physicalSize=const Size(1024,768);await tester.pump(const Duration(milliseconds:100));
  expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());vm.dispose();
 });
}
