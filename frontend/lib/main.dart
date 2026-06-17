import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Flux Media Server",
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text("Flux Media Server"),
        ),
      ),
    );
  }
}
