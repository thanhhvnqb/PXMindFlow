import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/auth/auth_controller.dart';
import '../core/db/database.dart';
import '../core/sync/sync_worker.dart';
import '../features/tasks/data/local_repository.dart';
import '../shared/shell.dart';
import 'providers.dart';

class MindFlowApp extends StatefulWidget {
  final AuthController? auth;
  final AppDatabase Function(String, void Function(String))? databaseFactory;
  const MindFlowApp({super.key, this.auth, this.databaseFactory});
  @override
  State<MindFlowApp> createState() => _MindFlowAppState();
}

class _MindFlowAppState extends State<MindFlowApp> with WidgetsBindingObserver {
  late final auth = widget.auth ?? AuthController();
  final changes = ValueNotifier<int>(0);
  void update(VoidCallback action) {
    setState(action);
    changes.value++;
  }

  Account? account;
  LocalRepository? repository;
  SyncWorker? worker;
  StreamSubscription<int>? subscription;
  Timer? debounce;
  String status = 'offline';
  String? warning;
  bool loading = true;
  bool dark = false;
  bool vietnamese = false;
  late final GoRouter router = GoRouter(
    refreshListenable: changes,
    initialLocation: '/tasks',
    routes: [
      GoRoute(
        path: '/:view',
        builder: (context, state) => ListenableBuilder(
          listenable: changes,
          builder: (context, _) => account == null
              ? LoginPage(auth: auth, onAccount: open)
              : ProviderScope(
                  overrides: [
                    repositoryProvider.overrideWithValue(repository!),
                  ],
                  child: MindFlowShell(
                    view: state.pathParameters['view']!,
                    status: status,
                    warning: warning,
                    sync: () => worker?.run(),
                    logout: close,
                    toggleTheme: () => update(() => dark = !dark),
                    toggleLanguage: () =>
                        update(() => vietnamese = !vietnamese),
                    vietnamese: vietnamese,
                  ),
                ),
        ),
      ),
    ],
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restore();
  }

  Future<void> restore() async {
    try {
      final saved = await auth.restore();
      if (saved != null && mounted) open(saved);
    } catch (_) {
      warning = 'Secure storage unavailable. Sign in to continue.';
    }
    if (mounted) update(() => loading = false);
  }

  void open(Account value) {
    void persistenceWarning(String message) {
      if (mounted) update(() => warning = message);
    }

    final db =
        widget.databaseFactory?.call(value.id, persistenceWarning) ??
        AppDatabase(value.id, persistenceWarning: persistenceWarning);
    repository = LocalRepository(db);
    worker = SyncWorker(repository!, value.api, (value) {
      if (mounted) update(() => status = value);
    });
    subscription = repository!.watchPending().listen((_) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 500), () => worker?.run());
    });
    update(() {
      account = value;
      loading = false;
    });
    worker!.run();
  }

  Future<void> close() async {
    worker?.dispose();
    debounce?.cancel();
    await subscription?.cancel();
    // Wait for active transaction/network cycle before closing its database.
    await worker?.run();
    await auth.logout();
    await repository?.db.close();
    if (mounted) {
      update(() {
        account = null;
        repository = null;
        worker = null;
        status = 'offline';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value == AppLifecycleState.resumed) worker?.run();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    worker?.dispose();
    subscription?.cancel();
    debounce?.cancel();
    router.dispose();
    changes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff24786b),
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      scaffoldBackgroundColor: dark
          ? const Color(0xff101c19)
          : const Color(0xfff6f7f3),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
    );
    return MaterialApp.router(
      title: 'MindFlow',
      locale: Locale(vietnamese ? 'vi' : 'en'),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: router,
      builder: (context, child) => loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : child!,
    );
  }
}

class LoginPage extends StatefulWidget {
  final AuthController auth;
  final void Function(Account) onAccount;
  const LoginPage({super.key, required this.auth, required this.onAccount});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool register = false;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final account = await widget.auth.login(
        email.text.trim(),
        password.text,
        register,
      );
      if (mounted) widget.onAccount(account);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not sign in. Check the API connection and your credentials.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 420,
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.spa_outlined, size: 56),
                const SizedBox(height: 24),
                Text(
                  'Make room for what matters.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'MindFlow · Your tasks, your pace.\nSign in once, then keep working offline.',
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v != null && v.contains('@')
                      ? null
                      : 'Enter an email address',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) => (v?.length ?? 0) >= 12
                      ? null
                      : 'Use at least 12 characters',
                  onFieldSubmitted: (_) => busy ? null : submit(),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(
                    busy
                        ? 'Connecting…'
                        : register
                        ? 'Create account'
                        : 'Sign in',
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => register = !register),
                  child: Text(
                    register
                        ? 'Already have an account? Sign in'
                        : 'New here? Create an account',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
