import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_media_server/features/auth/presentation/screens/code_screen.dart'
    show codeInputFormatter;

void main() {
  const oldValue = TextEditingValue.empty;

  TextEditingValue format(String text) => codeInputFormatter.formatEditUpdate(
    oldValue,
    TextEditingValue.empty.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );

  group('code input formatter', () {
    test('пропускает цифры', () {
      expect(format('123456').text, '123456');
    });

    test('режет буквы и символы', () {
      expect(format('a1b2c3').text, '123');
      expect(format('12-34').text, '1234');
      expect(format('  42 ').text, '42');
    });

    test('пустой ввод остаётся пустым', () {
      expect(format('').text, '');
    });
  });
}
