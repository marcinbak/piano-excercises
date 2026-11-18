import 'package:material_ui/material_ui.dart';
import 'package:piano_exercises/app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await bootstrapPianoExercisesRoot());
}
