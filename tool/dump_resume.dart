import 'dart:io';
import 'package:proof_pitch/insights.dart';

void main(List<String> args) {
  final text = pdfToText(File(args[0]).readAsBytesSync());
  print('=====RAW=====');
  print(text);
  final r = parseResume(text);
  print('=====PARSED=====');
  print('name=${r.name} | email=${r.email} | phone=${r.phone} | college=${r.college} | cgpa=${r.cgpa} | year=${r.graduationYear}');
  print('github=${r.github} | linkedin=${r.linkedin} | portfolio=${r.portfolio}');
  print('skills=${r.skills}');
  for (final p in r.projects) print('PROJECT ${p.name} | ${p.url} | ${p.tags} | ${p.oneLiner}');
}
