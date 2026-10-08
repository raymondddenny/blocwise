// Target: test/helpers/pump_app.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Swap these for your generated `AppLocalizations.localizationsDelegates`
/// and `AppLocalizations.supportedLocales` so widgets find their strings.
const _delegates = <LocalizationsDelegate<dynamic>>[
  DefaultMaterialLocalizations.delegate,
  DefaultWidgetsLocalizations.delegate,
];
const _locales = <Locale>[Locale('en')];

extension PumpApp on WidgetTester {
  /// Pumps [widget] inside a MaterialApp with localization, an optional
  /// theme, and [providers] above the app so pushed routes see them too.
  ///
  /// Pass cubits as `BlocProvider<OrdersCubit>.value(value: cubit)` so the
  /// test owns and closes them. Spell out the type argument: inside this
  /// list an untyped `BlocProvider.value` infers the base type and lookups
  /// throw ProviderNotFoundException.
  Future<void> pumpApp(
    Widget widget, {
    List<BlocProvider> providers = const [],
    ThemeData? theme,
    Locale locale = const Locale('en'),
    Iterable<LocalizationsDelegate<dynamic>> localizationsDelegates =
        _delegates,
    Iterable<Locale> supportedLocales = _locales,
    List<NavigatorObserver> navigatorObservers = const [],
  }) {
    Widget app = MaterialApp(
      theme: theme,
      locale: locale,
      localizationsDelegates: localizationsDelegates,
      supportedLocales: supportedLocales,
      navigatorObservers: navigatorObservers,
      home: Scaffold(body: widget),
    );
    if (providers.isNotEmpty) {
      app = MultiBlocProvider(providers: providers, child: app);
    }
    return pumpWidget(app);
  }
}
