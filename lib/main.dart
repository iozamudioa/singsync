import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/lyric_notifier_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const LyricNotifierApp());
}
