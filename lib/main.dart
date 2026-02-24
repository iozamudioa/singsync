import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/singsync_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const SingSyncApp());
}
