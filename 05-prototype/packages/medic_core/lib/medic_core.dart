/// Models and rules shared by the MedicApp patient app and the doctor web:
/// the prescription as written on the Bộ Y tế form, medication courses, the
/// dose log and adherence. Pure Dart, so both apps and their tests compute
/// the same numbers.
library;

export 'src/adherence.dart';
export 'src/medication.dart';
export 'src/visit_result.dart';
