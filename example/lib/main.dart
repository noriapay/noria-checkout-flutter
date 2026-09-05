import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:noria_checkout/noria_checkout.dart';

const String _sessionEndpoint = String.fromEnvironment(
  'NORIA_DEMO_SESSION_ENDPOINT',
);
const String _checkoutOrigin = String.fromEnvironment('NORIA_CHECKOUT_ORIGIN');
const String _returnUrl = String.fromEnvironment('NORIA_CHECKOUT_RETURN_URL');

void main() {
  runApp(const NoriaCheckoutExample());
}

class NoriaCheckoutExample extends StatelessWidget {
  const NoriaCheckoutExample({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noria Checkout',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF5F5F7),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF141416),
          surface: Colors.white,
        ),
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor: const Color(0xFF1D1D1F),
          displayColor: const Color(0xFF1D1D1F),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF111113),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFE1E1E5),
            disabledForegroundColor: const Color(0xFF8A8A8E),
            minimumSize: const Size.fromHeight(58),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
      home: const CheckoutDemoPage(),
    );
  }
}

class CheckoutDemoPage extends StatefulWidget {
  const CheckoutDemoPage({super.key});

  @override
  State<CheckoutDemoPage> createState() => _CheckoutDemoPageState();
}

class _CheckoutDemoPageState extends State<CheckoutDemoPage> {
  static final Uri _expectedCheckoutOrigin =
      Uri.tryParse(_checkoutOrigin) ?? Uri();
  static final Uri _expectedReturnUrl = Uri.tryParse(_returnUrl) ?? Uri();

  String _status = 'Pronto para pagar';

  Future<NoriaCheckoutSession> _createSession() async {
    if (_sessionEndpoint.isEmpty) {
      throw const NoriaCheckoutException(
        NoriaCheckoutErrorCode.malformedSession,
        'Configure NORIA_DEMO_SESSION_ENDPOINT no build do exemplo.',
      );
    }
    final Uri endpoint = Uri.parse(_sessionEndpoint);
    if (!isSecureCheckoutUri(endpoint) ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.fragment.isNotEmpty) {
      throw const NoriaCheckoutException(
        NoriaCheckoutErrorCode.insecureUrl,
        'Endpoint de sessão inseguro.',
      );
    }

    setState(() => _status = 'Criando sessão segura…');
    final http.Response response = await http
        .post(
          endpoint,
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(const <String, String>{'cartId': 'cart-demo-001'}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NoriaCheckoutException(
        NoriaCheckoutErrorCode.malformedSession,
        'O backend não criou a sessão (${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const NoriaCheckoutException(
        NoriaCheckoutErrorCode.malformedSession,
        'Resposta de sessão inválida.',
      );
    }
    return NoriaCheckoutSession.fromJson(decoded);
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (!mounted) {
      return;
    }
    final String message = error is NoriaCheckoutException
        ? error.message
        : 'Erro inesperado ao abrir o Checkout.';
    setState(() => _status = 'Não foi possível abrir o Checkout');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  void _onComplete(NoriaCheckoutResult result) {
    if (!mounted) {
      return;
    }
    setState(() => _status = 'Pagamento enviado para confirmação');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool compact = constraints.maxWidth < 920;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? 20 : 48,
                compact ? 20 : 34,
                compact ? 20 : 48,
                40,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const _Header(),
                      SizedBox(height: compact ? 28 : 48),
                      if (compact)
                        Column(
                          children: <Widget>[
                            const _ProductPanel(),
                            const SizedBox(height: 16),
                            _PaymentPanel(
                              status: _status,
                              enabled: _configurationReady,
                              createSession: _createSession,
                              onComplete: _onComplete,
                              onError: _onError,
                              checkoutOrigin: _expectedCheckoutOrigin,
                              returnUrl: _expectedReturnUrl,
                            ),
                          ],
                        )
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Expanded(flex: 6, child: _ProductPanel()),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 5,
                              child: _PaymentPanel(
                                status: _status,
                                enabled: _configurationReady,
                                createSession: _createSession,
                                onComplete: _onComplete,
                                onError: _onError,
                                checkoutOrigin: _expectedCheckoutOrigin,
                                returnUrl: _expectedReturnUrl,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  bool get _configurationReady =>
      _sessionEndpoint.isNotEmpty &&
      _checkoutOrigin.isNotEmpty &&
      _returnUrl.isNotEmpty;
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF141416),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const Text(
            'N',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 19,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Noria Checkout',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE1E1E5)),
          ),
          child: const Text(
            'DEMO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductPanel extends StatelessWidget {
  const _ProductPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 540,
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0E9),
        borderRadius: BorderRadius.circular(32),
      ),
      padding: const EdgeInsets.all(34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Aurora Speaker',
            style: TextStyle(
              fontSize: 38,
              height: 1.02,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Som imersivo. Design essencial.',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.58),
              fontSize: 17,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          Center(
            child: Container(
              width: 220,
              height: 260,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFF353738), Color(0xFF0E0F10)],
                ),
                borderRadius: BorderRadius.circular(42),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 38,
                    offset: Offset(0, 26),
                  ),
                ],
              ),
              child: Stack(
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 146,
                      height: 146,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                          width: 20,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: Color(0xFFB8FFCE),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 22,
                    child: Text(
                      'AURORA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _PaymentPanel extends StatelessWidget {
  const _PaymentPanel({
    required this.status,
    required this.enabled,
    required this.createSession,
    required this.onComplete,
    required this.onError,
    required this.checkoutOrigin,
    required this.returnUrl,
  });

  final String status;
  final bool enabled;
  final NoriaCreateSession createSession;
  final NoriaCheckoutCallback onComplete;
  final NoriaCheckoutErrorCallback onError;
  final Uri checkoutOrigin;
  final Uri returnUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 540,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
      ),
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'Seu pedido',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.9,
            ),
          ),
          const SizedBox(height: 32),
          const _SummaryLine(label: 'Aurora Speaker', value: 'R\$ 259,00'),
          const SizedBox(height: 14),
          const _SummaryLine(label: 'Entrega', value: 'Grátis'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Divider(height: 1, color: Color(0xFFE7E7EA)),
          ),
          const _SummaryLine(label: 'Total', value: 'R\$ 259,00', strong: true),
          const Spacer(),
          Row(
            children: <Widget>[
              const Icon(Icons.lock_outline_rounded, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  status,
                  style: const TextStyle(
                    color: Color(0xFF6E6E73),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          NoriaCheckoutButton(
            enabled: enabled,
            createSession: createSession,
            expectedCheckoutOrigin: checkoutOrigin,
            returnUrl: returnUrl,
            onComplete: onComplete,
            onError: onError,
            child: const NoriaCheckoutButtonLabel(),
          ),
          if (!enabled) ...<Widget>[
            const SizedBox(height: 12),
            const Text(
              'Prévia visual — configure o endpoint do backend para pagar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF8A8A8E),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            'O valor é definido no servidor. Nenhuma chave privada fica no app.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF8A8A8E),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      fontSize: strong ? 18 : 15,
      fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
      letterSpacing: strong ? -0.4 : -0.1,
      color: strong ? const Color(0xFF1D1D1F) : const Color(0xFF5D5D61),
    );
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}
