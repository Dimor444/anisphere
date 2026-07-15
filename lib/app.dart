import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_strings.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'shared/providers/language_provider.dart';

class AniSphereApp extends ConsumerWidget {
  const AniSphereApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);

    return MaterialApp.router(
      title: 'AniSphere',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark, // dark only — always
      routerConfig: appRouter,
      locale: Locale(lang.code),
      supportedLocales: AppStrings.languages.map((l) => Locale(l.code)).toList(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Force app-wide text direction from the language provider (RTL for Arabic).
      builder: (context, child) => Directionality(
        textDirection: lang.direction,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
