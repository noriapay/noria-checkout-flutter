import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noria_checkout_example/main.dart';

void main() {
  testWidgets('renders the Noria Checkout customer journey', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NoriaCheckoutExample());

    expect(find.text('Noria Checkout'), findsOneWidget);
    expect(find.text('Aurora Speaker'), findsAtLeastNWidgets(1));
    expect(find.text('Pagar com a '), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('R\$ 259,00'), findsNWidgets(2));
    expect(
      find.textContaining('Nenhuma chave privada fica no app.'),
      findsOneWidget,
    );
  });
}
