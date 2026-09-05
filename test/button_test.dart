import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noria_checkout/noria_checkout.dart';

import 'support/fixtures.dart';

void main() {
  late FakeAppLinks appLinks;
  late FakeLauncher launcher;
  late FakeStatusReader statusReader;
  late NoriaCheckoutController controller;

  NoriaCheckoutController build() {
    return NoriaCheckoutController(
      appLinks: appLinks,
      launcher: launcher,
      statusReader: statusReader,
      clock: () => now,
      pollInterval: Duration.zero,
    );
  }

  setUp(() {
    appLinks = FakeAppLinks();
    launcher = FakeLauncher();
    statusReader = FakeStatusReader();
    controller = build();
  });

  // Gates must be created inside the test body: a Completer built in setUp
  // belongs to the root zone and its continuations never run under the
  // widget tester's FakeAsync.
  Completer<void> gateLauncher() => launcher.gate = Completer<void>();

  tearDown(() => appLinks.dispose());

  Widget app(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('creates a session, opens the Checkout and reports the return', (
    WidgetTester tester,
  ) async {
    int created = 0;
    final List<NoriaCheckoutResult> results = <NoriaCheckoutResult>[];
    final Completer<void> browser = gateLauncher();
    await tester.pumpWidget(
      app(
        NoriaCheckoutButton(
          controller: controller,
          createSession: () async {
            created++;
            return session();
          },
          expectedCheckoutOrigin: checkoutOrigin,
          returnUrl: returnUrl,
          onComplete: results.add,
          child: const Text('Pagar'),
        ),
      ),
    );

    expect(find.text('Pagar'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(created, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Pagar'), findsNothing);
    expect(launcher.launched, hasLength(1));

    // A second tap while the browser is still opening must not create
    // another session.
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(created, 1);

    // Once the Checkout is on screen the button releases its busy state even
    // though the wait for completion is still pending.
    browser.complete();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Pagar'), findsOneWidget);
    expect(controller.hasPending, isTrue);
    expect(results, isEmpty);

    appLinks.emit(returnLinkFor(session()));
    await tester.pump();

    expect(results.map((r) => r.sessionId), <String>[sessionId]);
    expect(launcher.closeCalls, 1);
    expect(controller.hasPending, isFalse);
    expect(find.text('Pagar'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('reports errors from createSession with a stack trace', (
    WidgetTester tester,
  ) async {
    Object? reported;
    StackTrace? trace;
    await tester.pumpWidget(
      app(
        NoriaCheckoutButton(
          controller: controller,
          createSession: () async => throw StateError('backend down'),
          expectedCheckoutOrigin: checkoutOrigin,
          returnUrl: returnUrl,
          onError: (Object error, StackTrace stackTrace) {
            reported = error;
            trace = stackTrace;
          },
          child: const Text('Pagar'),
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(reported, isA<StateError>());
    expect(trace, isNotNull);
    expect(launcher.launched, isEmpty);
    expect(find.text('Pagar'), findsOneWidget);
  });

  testWidgets('reports validation failures from the controller', (
    WidgetTester tester,
  ) async {
    Object? reported;
    await tester.pumpWidget(
      app(
        NoriaCheckoutButton(
          controller: controller,
          createSession: () async => session(expiresAt: now),
          expectedCheckoutOrigin: checkoutOrigin,
          returnUrl: returnUrl,
          onError: (Object error, StackTrace _) => reported = error,
          child: const Text('Pagar'),
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(
      reported,
      isA<NoriaCheckoutException>().having(
        (e) => e.code,
        'code',
        NoriaCheckoutErrorCode.sessionExpired,
      ),
    );
  });

  testWidgets('is inert when disabled', (WidgetTester tester) async {
    int created = 0;
    await tester.pumpWidget(
      app(
        NoriaCheckoutButton(
          controller: controller,
          enabled: false,
          createSession: () async {
            created++;
            return session();
          },
          expectedCheckoutOrigin: checkoutOrigin,
          returnUrl: returnUrl,
          child: const Text('Pagar'),
        ),
      ),
    );

    final FilledButton button = tester.widget(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(created, 0);
  });

  testWidgets('supports a custom loading indicator and style', (
    WidgetTester tester,
  ) async {
    final Completer<NoriaCheckoutSession> gate =
        Completer<NoriaCheckoutSession>();
    final Completer<void> browser = gateLauncher();
    await tester.pumpWidget(
      app(
        NoriaCheckoutButton(
          controller: controller,
          createSession: () => gate.future,
          expectedCheckoutOrigin: checkoutOrigin,
          returnUrl: returnUrl,
          loadingIndicator: const Text('Aguarde'),
          style: FilledButton.styleFrom(backgroundColor: Colors.purple),
          child: const Text('Pagar'),
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.text('Aguarde'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final FilledButton button = tester.widget(find.byType(FilledButton));
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      Colors.purple,
    );

    gate.complete(session());
    await tester.pump();
    expect(find.text('Aguarde'), findsOneWidget);
    browser.complete();
    await tester.pump();
    expect(find.text('Pagar'), findsOneWidget);
    appLinks.emit(returnLinkFor(session()));
    await tester.pump();
    expect(find.text('Pagar'), findsOneWidget);
  });

  testWidgets('does not call back after being unmounted', (
    WidgetTester tester,
  ) async {
    int completions = 0;
    await tester.pumpWidget(
      app(
        NoriaCheckoutButton(
          controller: controller,
          createSession: () async => session(),
          expectedCheckoutOrigin: checkoutOrigin,
          returnUrl: returnUrl,
          onComplete: (_) => completions++,
          child: const Text('Pagar'),
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pumpWidget(app(const SizedBox()));
    // A shared controller is not cancelled on dispose; only an owned one is.
    expect(controller.hasPending, isTrue);

    appLinks.emit(returnLinkFor(session()));
    await tester.pump();
    expect(completions, 0);
    expect(controller.hasPending, isFalse);
  });

  testWidgets('a second tap supersedes the pending wait silently', (
    WidgetTester tester,
  ) async {
    final List<Object> errors = <Object>[];
    final List<NoriaCheckoutResult> results = <NoriaCheckoutResult>[];
    await tester.pumpWidget(
      app(
        NoriaCheckoutButton(
          controller: controller,
          createSession: () async => session(),
          expectedCheckoutOrigin: checkoutOrigin,
          returnUrl: returnUrl,
          onComplete: results.add,
          onError: (Object error, StackTrace _) => errors.add(error),
          child: const Text('Pagar'),
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.text('Pagar'), findsOneWidget);
    expect(controller.hasPending, isTrue);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(launcher.launched, hasLength(2));
    expect(errors, isEmpty);

    appLinks.emit(returnLinkFor(session()));
    await tester.pump();
    expect(results, hasLength(1));
    expect(errors, isEmpty);
  });

  testWidgets('reports terminal statuses through onError', (
    WidgetTester tester,
  ) async {
    Object? reported;
    statusReader = FakeStatusReader(<Object?>[
      NoriaCheckoutSessionStatus.failed,
    ]);
    controller = build();
    await tester.pumpWidget(
      app(
        NoriaCheckoutButton(
          controller: controller,
          createSession: () async => session(),
          expectedCheckoutOrigin: checkoutOrigin,
          returnUrl: returnUrl,
          onError: (Object error, StackTrace _) => reported = error,
          child: const Text('Pagar'),
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump();

    expect(
      reported,
      isA<NoriaCheckoutStatusException>().having(
        (e) => e.status,
        'status',
        NoriaCheckoutSessionStatus.failed,
      ),
    );
    expect(find.text('Pagar'), findsOneWidget);
  });

  testWidgets('owns a controller when none is supplied', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      app(
        NoriaCheckoutButton(
          createSession: () async => session(),
          expectedCheckoutOrigin: checkoutOrigin,
          returnUrl: returnUrl,
          child: const Text('Pagar'),
        ),
      ),
    );
    final NoriaCheckoutButton button = tester.widget(
      find.byType(NoriaCheckoutButton),
    );
    expect(button.controller, isNull);
    expect(find.text('Pagar'), findsOneWidget);
  });

  testWidgets('exposes an accessible button semantics node', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        NoriaCheckoutButton(
          controller: controller,
          createSession: () async => session(),
          expectedCheckoutOrigin: checkoutOrigin,
          returnUrl: returnUrl,
          semanticLabel: 'Pagar agora',
          child: const Text('Pagar'),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(NoriaCheckoutButton)),
      isSemantics(
        label: 'Pagar agora',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('brands only Noria in the label', (WidgetTester tester) async {
    await tester.pumpWidget(app(const NoriaCheckoutButtonLabel()));

    expect(find.text('Pagar com a '), findsOneWidget);
    final Image brand = tester.widget<Image>(find.byType(Image));
    expect(brand.semanticLabel, isNull);
    expect(brand.height, NoriaCheckoutButtonLabel.wordmarkHeight);
    expect(find.bySemanticsLabel(RegExp('Noria')), findsNothing);
  });

  testWidgets('label accepts a custom prefix', (WidgetTester tester) async {
    await tester.pumpWidget(
      app(const NoriaCheckoutButtonLabel(prefix: 'Pay with ')),
    );
    expect(find.text('Pay with '), findsOneWidget);
  });
}
