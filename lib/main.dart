import 'package:flutter/material.dart';

void main() => runApp(const VulcanicApp());

class VulcanicApp extends StatelessWidget {
  const VulcanicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vulcanic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const Scaffold(body: Center(child: Text('Vulcanic'))),
    );
  }
}
