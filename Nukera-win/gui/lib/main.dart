import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

const Color kBg = Color(0xFF0F1724);
const Color kSurface = Color(0xFF1C2533);
const Color kBorder = Color(0xFF2D3A4F);
const Color kPrimary = Color(0xFF1D4ED8);
const Color kAccent = Color(0xFF60A5FA);
const Color kMuted = Color(0xFF8899AA);
const Color kPurple = Color(0xFF6D28D9);
const Color kRed = Color(0xFFDC2626);

enum EngineState { disconnected, connecting, connected, optimizing, failed }

enum AppLang { auto, en, ru }

String _detectSystemLang() {
  final loc = Platform.localeName.toLowerCase();
  return loc.startsWith('ru') ? 'ru' : 'en';
}

class Loc {
  static final ValueNotifier<AppLang> notifier = ValueNotifier(AppLang.en);

  static AppLang get lang => notifier.value;
  static set lang(AppLang v) => notifier.value = v;

  static String t(String key) =>
      (lang == AppLang.ru ? _ru[key] : _en[key]) ?? key;

  static const Map<String, String> _en = {
    'appTitle': 'Nukera',
    'connected': 'Connected',
    'connecting': 'Connecting...',
    'disconnecting': 'Disconnecting...',
    'optimizing': 'Optimizing...',
    'failed': 'Failed',
    'disconnected': 'Disconnected',
    'setupTelegram': 'Setup Telegram',
    'adapt': 'Adapt to your internet',
    'stopTests': 'Stop tests',
    'preparing': 'Preparing...',
    'settings': 'Settings',
    'language': 'Language',
    'auto': 'Auto (system language)',
    'english': 'English',
    'russian': 'Русский',
    'silentAutostart': 'Silent autostart',
    'silentAutostartSub': 'Start the bypass when the system starts',
    'notFound': 'Nukera CLI not found. Place this app next to the Nukera '
        'project or set the NUKERA_ROOT environment variable.',
    'cannotReach': 'Cannot reach Nukera CLI.',
    'contactingWorker': 'Contacting worker...',
    'bypassNotRunning': 'Bypass is not running - start Nukera first.',
    'telegramOpened': 'Telegram was opened - click Connect/OK once.',
    'setupFailed': 'Setup failed. Open Nukera in a terminal for details.',
    'couldNotConnect': 'Could not connect. Run `nukera start` in a terminal to '
        'see the error, and grant admin permission.',
    'routing': 'Routing',
    'routingSub': 'Choose which sites go through the bypass',
    'routingMode': 'Mode',
    'modeAll': 'All sites',
    'modeAllSub': 'Standard behavior: the full site list plus your additions',
    'modeCustom': 'Only selected sites',
    'modeCustomSub': 'Bypass applies only to the categories and domains below',
    'categories': 'Categories (used in the selected mode)',
    'customDomains': 'Your domains',
    'customDomainsHint': 'One domain per line, e.g. example.com',
    'excludes': 'Never touch these domains',
    'excludesHint': 'One domain per line',
    'save': 'Save',
    'routingSaved': 'Saved. Reconnect the bypass to apply.',
    'routingSaveFailed': 'Failed to save routing settings.',
    'routingApplyHint': 'Changes take effect when the bypass (re)starts.',
    'catYouTube': 'YouTube',
    'catTelegram': 'Telegram Web',
    'catDiscord': 'Discord',
    'catMeta': 'Instagram / Facebook / WhatsApp',
    'catGitHub': 'GitHub',
    'catGoogle': 'Google',
    'trayOpen': 'Open Nukera',
    'trayStop': 'Stop bypass',
    'trayStart': 'Start bypass',
    'trayExit': 'Exit',
    'siteAdapt': 'Strategy for specific sites',
    'siteAdaptSub':
        'Test every strategy against your site list and apply the best one',
    'siteAdaptHint': 'One domain per line, e.g. rutor.is',
    'siteAdaptRun': 'Run selection',
    'siteAdaptStop': 'Stop',
    'siteAdaptBest': 'Best strategy: %s — applied',
    'siteAdaptListed': 'Sites were added to Routing → Your domains',
    'siteAdaptNosites': 'Add at least one site',
    'siteAdaptNopass': 'No strategy worked for these sites',
    'siteAdaptInterrupted': 'Stopped, results not applied',
    'hybridMissing': 'Hybrid strategy is missing (files removed by the '
        'update) — it can be rebuilt from the saved configuration',
    'hybridRestoreBtn': 'Rebuild hybrid',
    'hybridRestored': 'Hybrid strategy has been rebuilt',
    'probeTitle': 'Quick site check',
    'probeHint': 'domain, e.g. rutor.is',
    'probeRun': 'Check',
    'probeOk': 'Reachable — the strategy works',
    'probeFail': 'Unreachable — run the strategy selection',
    'siteAdaptCheck': 'Quick hybrid test',
    'siteAdaptCheckOk': 'All hybrid sites are reachable',
    'siteAdaptCheckFail': 'Unreachable: %s — re-selection was performed',
    'siteAdaptCheckNofix': 'No stable strategy found: %s',
    'siteAdaptHybrid': 'Build hybrid strategy',
    'siteAdaptHybridDone': 'Hybrid strategy applied: %s',
    'siteAdaptHybridHint':
        'Overrides replace the base strategy for the listed sites; '
        'everything else keeps using the base strategy',
  };

  static const Map<String, String> _ru = {
    'appTitle': 'Nukera',
    'connected': 'Подключено',
    'connecting': 'Подключение...',
    'disconnecting': 'Отключение...',
    'optimizing': 'Оптимизация...',
    'failed': 'Ошибка',
    'disconnected': 'Отключено',
    'setupTelegram': 'Настроить Telegram',
    'adapt': 'Адаптировать под ваш интернет',
    'stopTests': 'Остановить тесты',
    'preparing': 'Подготовка...',
    'settings': 'Настройки',
    'language': 'Язык',
    'auto': 'Авто (язык системы)',
    'english': 'English',
    'russian': 'Русский',
    'silentAutostart': 'Тихий автозапуск',
    'silentAutostartSub': 'Запускать обход при старте системы',
    'notFound': 'Nukera CLI не найден. Поместите приложение рядом с проектом '
        'Nukera или задайте переменную NUKERA_ROOT.',
    'cannotReach': 'Не удаётся связаться с Nukera CLI.',
    'contactingWorker': 'Связываемся с воркером...',
    'bypassNotRunning': 'Обход не запущен — сначала запустите Nukera.',
    'telegramOpened': 'Telegram открыт — нажмите Connect/OK один раз.',
    'setupFailed': 'Не удалось настроить. Откройте Nukera в терминале.',
    'couldNotConnect': 'Не удалось подключиться. Запустите `nukera start` в '
        'терминале, чтобы увидеть ошибку, и дайте права администратора.',
    'routing': 'Маршрутизация',
    'routingSub': 'Выберите, какие сайты идут через обход',
    'routingMode': 'Режим',
    'modeAll': 'Все сайты',
    'modeAllSub': 'Стандартное поведение: полный список + ваши добавления',
    'modeCustom': 'Только выбранные сайты',
    'modeCustomSub': 'Обход применяется только к категориям и доменам ниже',
    'categories': 'Категории (для режима «Только выбранные»)',
    'customDomains': 'Свои домены',
    'customDomainsHint': 'По одному домену в строке, например example.com',
    'excludes': 'Никогда не обрабатывать',
    'excludesHint': 'По одному домену в строке',
    'save': 'Сохранить',
    'routingSaved': 'Сохранено. Переподключите обход, чтобы применить.',
    'routingSaveFailed': 'Не удалось сохранить настройки маршрутизации.',
    'routingApplyHint': 'Изменения вступают в силу при (пере)запуске обхода.',
    'catYouTube': 'YouTube',
    'catTelegram': 'Telegram Web',
    'catDiscord': 'Discord',
    'catMeta': 'Instagram / Facebook / WhatsApp',
    'catGitHub': 'GitHub',
    'catGoogle': 'Google',
    'trayOpen': 'Открыть Nukera',
    'trayStop': 'Остановить обход',
    'trayStart': 'Запустить обход',
    'trayExit': 'Выход',
    'siteAdapt': 'Подбор стратегии для сайтов',
    'siteAdaptSub':
        'Протестировать все стратегии на вашем списке сайтов и применить лучшую',
    'siteAdaptHint': 'По одному домену в строке, например rutor.is',
    'siteAdaptRun': 'Подобрать стратегию',
    'siteAdaptStop': 'Остановить',
    'siteAdaptBest': 'Лучшая стратегия: %s — применена',
    'siteAdaptListed': 'Сайты добавлены в Маршрутизация → Свои домены',
    'siteAdaptNosites': 'Добавьте хотя бы один сайт',
    'siteAdaptNopass': 'Ни одна стратегия не справилась с этими сайтами',
    'siteAdaptInterrupted': 'Подбор остановлен, результаты не применены',
    'siteAdaptHybrid': 'Собрать гибридную стратегию',
    'siteAdaptHybridDone': 'Гибридная стратегия применена: %s',
    'siteAdaptHybridHint':
        'Переопределения заменяют базовую стратегию для указанных сайтов; '
        'остальной трафик идёт по базовой стратегии',
    'hybridMissing': 'Гибридная стратегия отсутствует (файлы удалены после '
        'обновления) — её можно восстановить из сохранённой конфигурации',
    'hybridRestoreBtn': 'Восстановить гибрид',
    'hybridRestored': 'Гибридная стратегия восстановлена',
    'probeTitle': 'Быстрая проверка сайта',
    'probeHint': 'домен, например rutor.is',
    'probeRun': 'Проверить',
    'probeOk': 'Открывается — стратегия действует',
    'probeFail': 'Не открывается — запустите подбор стратегии',
    'siteAdaptCheck': 'Быстрый тест гибрида',
    'siteAdaptCheckOk': 'Все сайты гибрида открываются',
    'siteAdaptCheckFail': 'Не открываются: %s — выполнен переподбор',
    'siteAdaptCheckNofix': 'Стабильной стратегии не найдено: %s',
  };
}

class SettingsManager {
  static AppLang lang = AppLang.auto;
  static bool silentAutostart = false;
  static String _path = '';

  static String get effectiveLang {
    if (lang != AppLang.auto) return lang.name;
    return _detectSystemLang();
  }

  static Future<void> load(String root) async {
    _path = root.isEmpty ? '' : '$root\\state\\gui.settings.json';
    if (_path.isNotEmpty) {
      try {
        final f = File(_path);
        if (await f.exists()) {
          final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          final l = m['lang'];
          lang = l == 'en' || l == 'ru' ? AppLang.values.byName(l) : AppLang.auto;
          silentAutostart = m['silentAutostart'] == true;
        }
      } catch (_) {}
    }
    Loc.lang = effectiveLang == 'ru' ? AppLang.ru : AppLang.en;
  }

  static Future<void> _save() async {
    if (_path.isEmpty) return;
    try {
      await File(_path).writeAsString(jsonEncode({
        'lang': lang.name,
        'silentAutostart': silentAutostart,
      }));
    } catch (_) {}
  }

  static Future<void> setLang(AppLang v) async {
    lang = v;
    Loc.lang = effectiveLang == 'ru' ? AppLang.ru : AppLang.en;
    await _save();
  }

  static Future<void> setSilentAutostart(bool v, String root) async {
    silentAutostart = v;
    await _applyAutostart(v, root);
    await _save();
  }

  static const String _runKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _runName = 'Nukera';

  static Future<void> _applyAutostart(bool enable, String root) async {
    if (root.isEmpty) return;
    try {
      if (enable) {
        final value =
            '"$root\\tools\\python\\pythonw.exe" -u "$root\\cli\\nukera.py" start';
        await Process.run('reg',
            ['add', _runKey, '/v', _runName, '/t', 'REG_SZ', '/d', value, '/f']);
      } else {
        await Process.run('reg', ['delete', _runKey, '/v', _runName, '/f']);
      }
    } catch (_) {}
  }
}

String findNukeraRoot() {
  final candidates = <String>[];
  final env = Platform.environment['NUKERA_ROOT'];
  if (env != null && env.isNotEmpty) {
    candidates.add(env);
  }
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 10; i++) {
    candidates.add(dir.path);
    candidates.add('${dir.path}\\Nukera');
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  final home = Platform.environment['USERPROFILE'] ?? '';
  candidates.addAll([
    '$home\\Documents\\projects\\Nukera',
    '$home\\Documents\\Nukera',
    '$home\\projects\\Nukera',
  ]);
  for (final c in candidates) {
    if (c.isNotEmpty && File('$c\\cli\\nukera.py').existsSync()) {
      return c;
    }
  }
  return '';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await SettingsManager.load(findNukeraRoot());

  const options = WindowOptions(
    size: Size(420, 640),
    minimumSize: Size(380, 520),
    center: true,
    title: 'Nukera',
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const NukeraApp());
}

class NukeraApp extends StatelessWidget {
  const NukeraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nukera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.dark(
          primary: kPrimary,
          surface: kSurface,
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: kAccent),
        ),
        progressIndicatorTheme:
            const ProgressIndicatorThemeData(color: kAccent),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WindowListener {
  EngineState _state = EngineState.disconnected;

  String _root = '';
  bool _rootOk = false;

  bool _busy = false;
  bool _adapting = false;
  int _adaptDone = 0;
  int _adaptTotal = 0;

  String _message = '';
  bool _messageIsError = false;

  final List<Process> _live = <Process>[];
  int _pollErrors = 0;

  Timer? _pollTimer;

  bool _disconnecting = false;
  bool _pendingConnect = false;
  DateTime? _connectDeadline;

  final SystemTray _tray = SystemTray();
  MenuItemLabel? _trayToggleItem;
  bool _hybridMissing = false;

  void _updateTrayToggle() {
    final item = _trayToggleItem;
    if (item == null) return;
    final running = _state == EngineState.connected;
    item.setLabel(Loc.t(running ? 'trayStop' : 'trayStart'));
  }

  String get _statusText {
    if (_disconnecting) return Loc.t('disconnecting');
    switch (_state) {
      case EngineState.connected:
        return Loc.t('connected');
      case EngineState.connecting:
        return Loc.t('connecting');
      case EngineState.optimizing:
        return Loc.t('optimizing');
      case EngineState.failed:
        return Loc.t('failed');
      case EngineState.disconnected:
        return Loc.t('disconnected');
    }
  }

  @override
  void initState() {
    super.initState();
    Loc.notifier.addListener(_onLangChanged);
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    _initTray();
    _resolveRoot();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    Loc.notifier.removeListener(_onLangChanged);
    _pollTimer?.cancel();
    for (final p in _live) {
      try {
        p.kill();
      } catch (_) {}
    }
    _live.clear();
    super.dispose();
  }

  // Close button: while the bypass is running the window hides into the
  // tray (the engine keeps running in its own processes); otherwise the
  // app exits. The tray menu's "Exit" always terminates the app.
  @override
  void onWindowClose() async {
    if (_state == EngineState.connected) {
      await windowManager.hide();
    } else {
      await _trayExit();
    }
  }

  Future<void> _initTray() async {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final iconPath = '$exeDir\\app_icon.ico';
      await _tray.initSystemTray(
        title: 'Nukera',
        iconPath: File(iconPath).existsSync() ? iconPath : '',
      );
      _trayToggleItem = MenuItemLabel(
          label: Loc.t('trayStop'), onClicked: (_) => _trayToggleBypass());
      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(
            label: Loc.t('trayOpen'), onClicked: (_) => _showFromTray()),
        MenuSeparator(),
        _trayToggleItem!,
        MenuItemLabel(
            label: Loc.t('trayExit'), onClicked: (_) => _trayExit()),
      ]);
      await _tray.setContextMenu(menu);
      _tray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) {
          _showFromTray();
        } else if (eventName == kSystemTrayEventRightClick) {
          _tray.popUpContextMenu();
        }
      });
    } catch (_) {}
  }

  Future<void> _showFromTray() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _trayToggleBypass() async {
    if (_busy || _adapting || !_rootOk) return;
    final start = _state != EngineState.connected;
    await _runCli([start ? 'start' : 'stop']);
    if (mounted) await _pollStatus();
    _updateTrayToggle();
  }

  Future<void> _trayExit() async {
    try {
      await windowManager.setPreventClose(false);
      await _tray.destroy();
    } catch (_) {}
    await windowManager.destroy();
  }

  void _onLangChanged() {
    if (!mounted) return;
    setState(() => _message = '');
  }

  void _resolveRoot() {
    final root = findNukeraRoot();
    if (root.isNotEmpty) {
      setState(() {
        _root = root;
        _rootOk = true;
      });
      _startPolling();
      _pollStatus();
    } else {
      setState(() {
        _messageIsError = true;
        _message = Loc.t('notFound');
      });
    }
  }

  Future<List<String>> _runCli(List<String> args) async {
    final Process p;
    try {
      p = await Process.start(
        '$_root\\tools\\python\\pythonw.exe',
        ['-u', 'cli\\nukera.py', ...args],
        workingDirectory: _root,
      );
    } catch (_) {
      return const <String>[];
    }
    _live.add(p);
    final lines = <String>[];
    p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(lines.add, onError: (_) {});
    p.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((_) {}, onError: (_) {});
    try {
      await p.exitCode;
    } catch (_) {}
    _live.remove(p);
    return lines;
  }

  Future<int> _runCliLive(
    List<String> args,
    void Function(String line) onLine,
  ) async {
    final Process p;
    try {
      p = await Process.start(
        '$_root\\tools\\python\\pythonw.exe',
        ['-u', 'cli\\nukera.py', ...args],
        workingDirectory: _root,
      );
    } catch (_) {
      return 1;
    }
    _live.add(p);
    p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine, onError: (_) {});
    p.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine, onError: (_) {});
    final code = await p.exitCode;
    _live.remove(p);
    return code;
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollStatus();
    });
  }

  /// Reads the worker's status snapshot (state\engine.status, refreshed once
  /// per second by the elevated worker). Reading a small file is free; the
  /// old approach spawned `pythonw nukera.py status` plus tasklist/powershell
  /// on every tick, which showed as a blinking python process and a loading
  /// cursor every couple of seconds.
  Map<String, dynamic>? _readStatusFile() {
    try {
      final f = File('$_root\\state\\engine.status');
      if (!f.existsSync()) return null;
      final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final ts = (m['ts'] as num?)?.toDouble() ?? 0.0;
      final age = DateTime.now().millisecondsSinceEpoch / 1000 - ts;
      if (age < -5 || age > 6) return null; // stale: worker stopped writing
      return m;
    } catch (_) {
      return null;
    }
  }

  void _applyRunning(bool running) {
    if (running) {
      if (_state != EngineState.connected) {
        setState(() => _state = EngineState.connected);
        _setMessage('');
      }
      _pendingConnect = false;
    } else if (_pendingConnect) {
      if (_connectDeadline != null &&
          DateTime.now().isAfter(_connectDeadline!)) {
        _pendingConnect = false;
        setState(() => _state = EngineState.disconnected);
        _setMessage(Loc.t('couldNotConnect'), isError: true);
      }
    } else {
      if (_state != EngineState.disconnected) {
        setState(() => _state = EngineState.disconnected);
      }
    }
    _updateTrayToggle();
  }

  Future<void> _pollStatus() async {
    if (_busy || _adapting || !_rootOk || !mounted) return;
    final st = _readStatusFile();
    if (st != null) {
      if (_messageIsError && _message == Loc.t('cannotReach')) {
        _setMessage('');
      }
      _applyRunning(st['running'] == true);
      // a generated hybrid lives in engine\strategies; an update replaces
      // that folder, so flag the mismatch and offer a one-click rebuild
      final stName = (st['strategy'] as String?) ?? '';
      final missing = stName.startsWith('Hybrid') &&
          !File('$_root\\engine\\strategies\\$stName.bat').existsSync();
      if (missing != _hybridMissing) {
        setState(() => _hybridMissing = missing);
      }
      return;
    }
    // No fresh status file: the worker is down or the installed CLI is an
    // older build. Fall back to the CLI probe, but only every 5th tick
    // (~10s) so we never reintroduce the per-2s process churn.
    _pollErrors++;
    if (_pollErrors < 5) return;
    _pollErrors = 0;
    var lines = const <String>[];
    try {
      lines = await _runCli(const ['status']);
    } catch (_) {}
    if (!mounted) return;
    if (lines.isEmpty) {
      if (_state != EngineState.failed) {
        setState(() => _state = EngineState.failed);
        _pendingConnect = false;
        _setMessage(Loc.t('cannotReach'), isError: true);
      }
      return;
    }
    if (_messageIsError && _message == Loc.t('cannotReach')) {
      _setMessage('');
    }
    _applyRunning(
      lines.any((l) => l.trim().startsWith('Status: running')),
    );
  }

  Future<void> _restoreHybrid() async {
    if (_busy || _adapting || !_rootOk) return;
    _busy = true;
    await _runCli(const ['hybrid_build']);
    _busy = false;
    if (!mounted) return;
    setState(() {
      _hybridMissing = false;
      _message = Loc.t('hybridRestored');
      _messageIsError = false;
    });
    await _pollStatus();
  }

  void _setMessage(String text, {bool isError = false}) {
    setState(() {
      _message = text;
      _messageIsError = isError;
    });
  }

  Future<void> _toggleConnection() async {
    if (_busy ||
        _adapting ||
        !_rootOk ||
        _state == EngineState.connecting ||
        _state == EngineState.optimizing) {
      return;
    }
    final wantConnect = _state != EngineState.connected;
    setState(() {
      _state = EngineState.connecting;
      _disconnecting = !wantConnect;
      _message = '';
    });
    if (wantConnect) {
      _pendingConnect = true;
      _connectDeadline = DateTime.now().add(const Duration(seconds: 90));
    } else {
      _pendingConnect = false;
    }
    _busy = true;
    final lines = await _runCli([wantConnect ? 'start' : 'stop']);
    _busy = false;
    if (!mounted) return;
    if (wantConnect) {
      final failed = lines.any((l) =>
          l.contains('winws failed to start') ||
          l.contains('winws failed to initialize') ||
          l.contains("'zapret' Windows service is running") ||
          l.contains('permission was not granted'));
      if (failed) {
        _pendingConnect = false;
        setState(() => _state = EngineState.disconnected);
        _setMessage(Loc.t('couldNotConnect'), isError: true);
        setState(() => _disconnecting = false);
        return;
      }
    }
    await _pollStatus();
    setState(() => _disconnecting = false);
  }

  Future<void> _setupTelegram() async {
    if (_busy || !_rootOk) return;
    setState(() => _message = Loc.t('contactingWorker'));
    _busy = true;
    final lines = await _runCli(const ['setup_telegram']);
    _busy = false;
    if (!mounted) return;
    final linkLine =
        lines.where((l) => l.startsWith('TGPROXY_LINK=')).firstOrNull;
    final refused = lines.any((l) => l.contains('is not running'));
    if (refused) {
      _setMessage(Loc.t('bypassNotRunning'), isError: true);
    } else if (linkLine != null) {
      _setMessage(Loc.t('telegramOpened'));
    } else {
      _setMessage(Loc.t('setupFailed'), isError: true);
    }
  }

  void _adapt() {
    if (_adapting && _rootOk) {
      try {
        File('$_root\\state\\adapt.cancel').writeAsStringSync('1\n');
      } catch (_) {}
      return;
    }
    if (_busy || !_rootOk) return;
    if (_state == EngineState.connected ||
        _state == EngineState.disconnected) {
      _runAdapt();
    }
  }

  Future<void> _runAdapt() async {
    setState(() {
      _adapting = true;
      _adaptDone = 0;
      _adaptTotal = 0;
      _state = EngineState.optimizing;
      _message = '';
    });
    _busy = true;
    await _runCliLive(['adapt'], (line) {
      final t = RegExp(r'^Adapt: testing (\d+) strategies').firstMatch(line);
      if (t != null) {
        setState(() => _adaptTotal = int.parse(t.group(1)!));
      }
      final p = RegExp(r'^\[(\d+)/(\d+)\]').firstMatch(line.trim());
      if (p != null) {
        final done = int.parse(p.group(1)!);
        final total = int.parse(p.group(2)!);
        if (done > 0) {
          setState(() {
            _adaptDone = done;
            _adaptTotal = total;
          });
        }
      }
    });
    _busy = false;
    if (!mounted) return;
    setState(() {
      _adapting = false;
      _state = EngineState.disconnected;
      _message = '';
    });
    await _pollStatus();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(root: _root)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Column(
        children: [
          _TitleBar(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 480),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 8),
                      _HeroButton(
                        state: _state,
                        adapting: _adapting,
                        onTap: _toggleConnection,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _statusText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: _state == EngineState.connected
                              ? kAccent
                              : kMuted,
                        ),
                      ),
                      if (_hybridMissing) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: kSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: kRed.withValues(alpha: 0.55)),
                            ),
                            child: Column(
                              children: [
                                Text(Loc.t('hybridMissing'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 12, color: kRed)),
                                const SizedBox(height: 6),
                                TextButton(
                                  onPressed: (_busy || _adapting)
                                      ? null
                                      : _restoreHybrid,
                                  child: Text(Loc.t('hybridRestoreBtn')),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (_state == EngineState.connected) ...[
                        TextButton(
                          onPressed: _busy ? null : _setupTelegram,
                          child: Text(Loc.t('setupTelegram')),
                        ),
                        const SizedBox(height: 14),
                      ],
                      _AdaptButton(
                        adapting: _adapting,
                        onTap: _adapt,
                      ),
                      if (_adapting) ...[
                        const SizedBox(height: 18),
                        SizedBox(
                          width: 230,
                          child: LinearProgressIndicator(
                            value: _adaptTotal > 0
                                ? (_adaptDone / _adaptTotal).clamp(0.0, 1.0)
                                : null,
                            minHeight: 5,
                            backgroundColor: kBorder,
                            color: kAccent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _adaptTotal > 0
                              ? '$_adaptDone/$_adaptTotal'
                              : Loc.t('preparing'),
                          style: const TextStyle(
                            fontSize: 13,
                            color: kMuted,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                      _ActionButton(
                        label: Loc.t('settings'),
                        icon: Icons.settings,
                        onTap: _openSettings,
                      ),
                      const SizedBox(height: 12),
                      if (_message.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Text(
                            _message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: _messageIsError ? kRed : kAccent,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 40,
        color: kBg,
        child: Row(
          children: [
            const SizedBox(width: 14),
            Text(
              Loc.t('appTitle'),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const Spacer(),
            _WindowButton(
              icon: Icons.minimize,
              onTap: () => windowManager.minimize(),
            ),
            _WindowButton(
              icon: Icons.close,
              onTap: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _WindowButton({required this.icon, required this.onTap});

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 40,
          alignment: Alignment.center,
          color: _hover ? kSurface : Colors.transparent,
          child: Icon(widget.icon, size: 16, color: _hover ? Colors.white : kMuted),
        ),
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  final EngineState state;
  final bool adapting;
  final VoidCallback onTap;

  const _HeroButton({
    required this.state,
    required this.adapting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final busy = state == EngineState.connecting || adapting;
    Color bgColor;
    Color iconColor;
    if (adapting) {
      bgColor = kPurple;
      iconColor = Colors.white;
    } else {
      switch (state) {
        case EngineState.connected:
          bgColor = kPrimary;
          iconColor = Colors.white;
          break;
        case EngineState.connecting:
        case EngineState.optimizing:
          bgColor = kPurple;
          iconColor = Colors.white;
          break;
        case EngineState.failed:
          bgColor = kRed;
          iconColor = Colors.white;
          break;
        case EngineState.disconnected:
          bgColor = kSurface;
          iconColor = kMuted;
          break;
      }
    }

    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [bgColor, bgColor.withValues(alpha: 0.7)],
          ),
          boxShadow: state == EngineState.connected && !adapting
              ? [
                  BoxShadow(
                    color: kPrimary.withValues(alpha: 0.4),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ]
              : const [],
        ),
        child: adapting
            ? const _SpinningGear(iconSize: 48)
            : state == EngineState.connecting
                ? const Padding(
                    padding: EdgeInsets.all(35),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : Icon(
                    state == EngineState.failed
                        ? Icons.error_outline
                        : Icons.power_settings_new,
                    size: 50,
                    color: iconColor,
                  ),
      ),
    );
  }
}

class _SpinningGear extends StatefulWidget {
  const _SpinningGear({required this.iconSize});

  final double iconSize;

  @override
  State<_SpinningGear> createState() => _SpinningGearState();
}

class _SpinningGearState extends State<_SpinningGear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(
        Icons.settings,
        size: widget.iconSize,
        color: Colors.white,
      ),
    );
  }
}

class _AdaptButton extends StatelessWidget {
  final bool adapting;
  final VoidCallback onTap;

  const _AdaptButton({required this.adapting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = adapting ? kRed : kMuted;
    final border = adapting ? kRed.withValues(alpha: 0.55) : kBorder;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              adapting ? Icons.close : Icons.tune,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Text(
              adapting ? Loc.t('stopTests') : Loc.t('adapt'),
              style: TextStyle(color: color, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: kMuted),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: kMuted)),
          ],
        ),
      ),
    );
  }
}

class RoutingScreen extends StatefulWidget {
  final String root;

  const RoutingScreen({super.key, required this.root});

  @override
  State<RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends State<RoutingScreen> {
  static const List<String> _catOrder = [
    'youtube', 'telegram', 'discord', 'meta', 'github', 'google',
  ];
  static const Map<String, String> _catLabel = {
    'youtube': 'catYouTube',
    'telegram': 'catTelegram',
    'discord': 'catDiscord',
    'meta': 'catMeta',
    'github': 'catGitHub',
    'google': 'catGoogle',
  };
  static const String _placeholder = 'domain.example.abc';

  String _mode = 'all';
  final Set<String> _cats = Set<String>.from(_catOrder);
  final TextEditingController _customCtrl = TextEditingController();
  final TextEditingController _excludeCtrl = TextEditingController();
  bool _loaded = false;
  String _note = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    _excludeCtrl.dispose();
    super.dispose();
  }

  Future<String> _readList(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return '';
      final lines = (await f.readAsString())
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#') &&
              l != _placeholder)
          .toList();
      return lines.join('\n');
    } catch (_) {
      return '';
    }
  }

  Future<void> _load() async {
    Map<String, dynamic>? m;
    try {
      final f = File('${widget.root}\\state\\routing.json');
      if (await f.exists()) {
        final v = jsonDecode(await f.readAsString());
        if (v is Map<String, dynamic>) m = v;
      }
    } catch (_) {}
    String custom = '';
    String excludes = '';
    if (m != null) {
      _mode = m['mode'] == 'custom' ? 'custom' : 'all';
      final cats = m['categories'];
      if (cats is Map) {
        _cats.clear();
        cats.forEach((k, v) {
          if (v == true && _catOrder.contains(k)) _cats.add(k.toString());
        });
      }
      custom = ((m['custom_domains'] as List?) ?? []).join('\n');
      excludes = ((m['excludes'] as List?) ?? []).join('\n');
    } else {
      // First run: import the current lists, so domains added manually
      // (before the GUI existed) survive the first save.
      custom = await _readList(
          '${widget.root}\\engine\\lists\\list-general-user.txt');
      excludes = await _readList(
          '${widget.root}\\engine\\lists\\list-exclude-user.txt');
    }
    if (!mounted) return;
    setState(() {
      _customCtrl.text = custom;
      _excludeCtrl.text = excludes;
      _loaded = true;
    });
  }

  List<String> _parseLines(String text) => text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim().toLowerCase())
      .where((l) => l.isNotEmpty && !l.startsWith('#') && l != _placeholder)
      .toList();

  Future<void> _save() async {
    final data = {
      'mode': _mode,
      'categories': {for (final k in _catOrder) k: _cats.contains(k)},
      'custom_domains': _parseLines(_customCtrl.text),
      'excludes': _parseLines(_excludeCtrl.text),
      'ts': DateTime.now().millisecondsSinceEpoch / 1000,
    };
    try {
      await Directory('${widget.root}\\state').create(recursive: true);
      await File('${widget.root}\\state\\routing.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      if (!mounted) return;
      setState(() => _note = Loc.t('routingSaved'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _note = Loc.t('routingSaveFailed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(Loc.t('routing'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: kBg,
        elevation: 0,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(Loc.t('routingMode'),
                      style:
                          const TextStyle(color: kMuted, fontSize: 13)),
                ),
                RadioListTile<String>(
                  value: 'all',
                  groupValue: _mode,
                  activeColor: kAccent,
                  onChanged: (v) => setState(() => _mode = v!),
                  title: Text(Loc.t('modeAll')),
                  subtitle: Text(Loc.t('modeAllSub'),
                      style: const TextStyle(
                          color: kMuted, fontSize: 12.5)),
                ),
                RadioListTile<String>(
                  value: 'custom',
                  groupValue: _mode,
                  activeColor: kAccent,
                  onChanged: (v) => setState(() => _mode = v!),
                  title: Text(Loc.t('modeCustom')),
                  subtitle: Text(Loc.t('modeCustomSub'),
                      style: const TextStyle(
                          color: kMuted, fontSize: 12.5)),
                ),
                if (_mode == 'custom') ...[
                  const Divider(height: 24, color: kBorder),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Text(Loc.t('categories'),
                        style: const TextStyle(
                            color: kMuted, fontSize: 13)),
                  ),
                  for (final k in _catOrder)
                    SwitchListTile(
                      activeColor: kAccent,
                      value: _cats.contains(k),
                      onChanged: (v) => setState(() {
                        if (v) {
                          _cats.add(k);
                        } else {
                          _cats.remove(k);
                        }
                      }),
                      title: Text(Loc.t(_catLabel[k]!)),
                    ),
                ],
                const Divider(height: 24, color: kBorder),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(Loc.t('customDomains'),
                      style: const TextStyle(color: kMuted, fontSize: 13)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _customCtrl,
                    maxLines: 6,
                    style: const TextStyle(fontSize: 13),
                    decoration: _fieldDeco(Loc.t('customDomainsHint')),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(Loc.t('excludes'),
                      style: const TextStyle(color: kMuted, fontSize: 13)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _excludeCtrl,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 13),
                    decoration: _fieldDeco(Loc.t('excludesHint')),
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(Loc.t('save')),
                  ),
                ),
                if (_note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Text(_note,
                        style: const TextStyle(
                            color: kAccent, fontSize: 12.5)),
                  ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Text(Loc.t('routingApplyHint'),
                      style: const TextStyle(
                          color: kMuted, fontSize: 12)),
                ),
              ],
            ),
    );
  }

  InputDecoration _fieldDeco(String hint) {
    OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kBorder),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kMuted, fontSize: 12),
      filled: true,
      fillColor: kSurface,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kAccent),
      ),
    );
  }
}

class AdaptSitesScreen extends StatefulWidget {
  final String root;

  const AdaptSitesScreen({super.key, required this.root});

  @override
  State<AdaptSitesScreen> createState() => _AdaptSitesScreenState();
}

class _AdaptSitesScreenState extends State<AdaptSitesScreen> {
  static const String _placeholder = 'domain.example.abc';

  final TextEditingController _sitesCtrl = TextEditingController();
  final List<Process> _live = <Process>[];
  bool _running = false;
  int _done = 0;
  int _total = 0;
  final List<String> _rows = <String>[];
  final List<String> _siteBest = <String>[];
  String _prevStrategy = '';
  String _best = '';
  String _note = '';
  bool _hybridExists = false;
  final TextEditingController _probeCtrl = TextEditingController();
  bool _probeBusy = false;
  bool _probeOk = false;
  String _probeResult = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final p in _live) {
      try {
        p.kill();
      } catch (_) {}
    }
    _live.clear();
    _sitesCtrl.dispose();
    _probeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<String>? sites;
    try {
      final f = File('${widget.root}\\state\\adapt.sites.json');
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        sites = (m['sites'] as List?)?.cast<String>();
      }
      _hybridExists =
          await File('${widget.root}\\state\\hybrid.json').exists();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _sitesCtrl.text = (sites ?? const []).join('\n'));
  }

  List<String> _parseLines(String text) => text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim().toLowerCase())
      .where((l) => l.isNotEmpty && !l.startsWith('#') &&
          l != _placeholder)
      .toList();

  Future<void> _run() async {
    final sites = _parseLines(_sitesCtrl.text);
    if (sites.isEmpty) {
      setState(() => _note = Loc.t('siteAdaptNosites'));
      return;
    }
    try {
      await Directory('${widget.root}\\state').create(recursive: true);
      await File('${widget.root}\\state\\adapt.sites.json').writeAsString(
          const JsonEncoder.withIndent('  ')
              .convert({'sites': sites, 'ts': DateTime.now()
                  .millisecondsSinceEpoch / 1000}));
    } catch (_) {}
    setState(() {
      _running = true;
      _done = 0;
      _total = 0;
      _rows.clear();
      _siteBest.clear();
      _prevStrategy = '';
      _best = '';
      _note = '';
    });
    final progress = RegExp(r'^\[(\d+)/(\d+)\]\s+(.+):\sscore\s+(\d+)/(\d+)');
    final header =
        RegExp(r'^AdaptSites: testing (\d+) strategies');
    void onLine(String line) {
      if (!mounted) return;
      if (line.startsWith('ADAPTSITES_BEST=')) {
        setState(() => _best = line.substring('ADAPTSITES_BEST='.length));
        return;
      }
      if (line.startsWith('ADAPTSITES_PREV=')) {
        setState(() =>
            _prevStrategy = line.substring('ADAPTSITES_PREV='.length));
        return;
      }
      if (line.startsWith('ADAPTSITES_PER_SITE=')) {
        final body = line.substring('ADAPTSITES_PER_SITE='.length);
        final eq = body.indexOf('=');
        if (eq > 0) {
          setState(() => _siteBest.insert(0,
              '${body.substring(0, eq)} → ${body.substring(eq + 1)}'));
        }
        return;
      }
      if (line.startsWith('HYBRID=')) {
        setState(() {
          _best = '';
          _note = Loc.t('siteAdaptHybridDone')
              .replaceAll('%s', line.substring('HYBRID='.length));
        });
        return;
      }
      if (line.startsWith('AdaptSites INTERRUPTED')) {
        setState(() => _note = Loc.t('siteAdaptInterrupted'));
        return;
      }
      final h = header.firstMatch(line);
      if (h != null) {
        setState(() => _total = int.parse(h.group(1)!));
        return;
      }
      final m = progress.firstMatch(line.trim());
      if (m != null) {
        setState(() {
          _done = int.parse(m.group(1)!);
          _total = int.parse(m.group(2)!);
          _rows.insert(0,
              '${m.group(3)} — ${m.group(4)}/${m.group(5)}');
        });
      }
    }

    Process? p;
    try {
      p = await Process.start(
        '${widget.root}\\tools\\python\\pythonw.exe',
        ['-u', 'cli\\nukera.py', 'adapt_sites'],
        workingDirectory: widget.root,
      );
    } catch (_) {}
    if (p == null) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _note = Loc.t('siteAdaptNopass');
      });
      return;
    }
    _live.add(p);
    p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine, onError: (_) {});
    p.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine, onError: (_) {});
    await p.exitCode;
    _live.remove(p);
    if (!mounted) return;
    setState(() {
      _running = false;
      if (_best.isEmpty && _note.isEmpty) {
        _note = Loc.t('siteAdaptNopass');
      }
    });
  }

  Future<void> _stop() async {
    try {
      File('${widget.root}\\state\\adapt.cancel').writeAsStringSync('1\n');
    } catch (_) {}
  }

  Future<void> _runQuickProbe() async {
    final host = _probeCtrl.text.trim().toLowerCase();
    if (host.isEmpty || host.contains(' ') || host.contains('/')) return;
    setState(() {
      _probeBusy = true;
      _probeResult = '';
    });
    Process? p;
    try {
      p = await Process.start(
        '${widget.root}\\tools\\python\\pythonw.exe',
        ['-u', 'cli\\nukera.py', 'probe_site', host],
        workingDirectory: widget.root,
      );
    } catch (_) {}
    if (p == null) {
      if (mounted) setState(() => _probeBusy = false);
      return;
    }
    _live.add(p);
    p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (!mounted) return;
      if (line.startsWith('PROBE=')) {
        final ok = line.substring(6).trim() == 'ok';
        setState(() {
          _probeOk = ok;
          _probeResult = Loc.t(ok ? 'probeOk' : 'probeFail');
        });
      }
    }, onError: (_) {});
    await p.exitCode;
    _live.remove(p);
    if (mounted) setState(() => _probeBusy = false);
  }

  Future<void> _runHybridCheck() async {
    if (_running) return;
    setState(() {
      _running = true;
      _done = 0;
      _total = 0;
      _rows.clear();
      _siteBest.clear();
      _best = '';
      _note = '';
    });
    final failing = <String>[];
    final nofix = <String>[];
    void onLine(String line) {
      if (!mounted) return;
      if (line.startsWith('HYBRIDCHECK=ok')) {
        setState(() => _note = Loc.t('siteAdaptCheckOk'));
        return;
      }
      if (line.startsWith('HYBRIDCHECK_FAILING=')) {
        failing.addAll(
            line.substring('HYBRIDCHECK_FAILING='.length).split(','));
        return;
      }
      if (line.startsWith('HYBRIDCHECK_NOFIX=')) {
        nofix.addAll(line.substring('HYBRIDCHECK_NOFIX='.length).split(','));
        return;
      }
      if (line.startsWith('HYBRIDCHECK_DONE')) {
        setState(() {
          if (failing.isNotEmpty) {
            _note = Loc.t('siteAdaptCheckFail')
                .replaceAll('%s', failing.join(', '));
          }
          if (nofix.isNotEmpty) {
            _note = (_note.isEmpty ? '' : '$_note ') +
                Loc.t('siteAdaptCheckNofix').replaceAll('%s', nofix.join(', '));
          }
        });
        return;
      }
      if (line.startsWith('HYBRID=')) {
        setState(() => _note = Loc.t('siteAdaptHybridDone')
            .replaceAll('%s', line.substring('HYBRID='.length)));
        return;
      }
      if (line.startsWith('ADAPTSITES_PER_SITE=')) {
        final body = line.substring('ADAPTSITES_PER_SITE='.length);
        final eq = body.indexOf('=');
        if (eq > 0) {
          setState(() => _siteBest.insert(0,
              '${body.substring(0, eq)} → ${body.substring(eq + 1)}'));
        }
        return;
      }
      final m = RegExp(r'^\[(\d+)/(\d+)\]\s+(.+):\sscore\s+(\d+)/(\d+)')
          .firstMatch(line.trim());
      if (m != null) {
        setState(() {
          _done = int.parse(m.group(1)!);
          _total = int.parse(m.group(2)!);
          _rows.insert(0,
              '${m.group(3)} — ${m.group(4)}/${m.group(5)}');
        });
      }
    }

    Process? p;
    try {
      p = await Process.start(
        '${widget.root}\\tools\\python\\pythonw.exe',
        ['-u', 'cli\\nukera.py', 'hybrid_check'],
        workingDirectory: widget.root,
      );
    } catch (_) {}
    if (p == null) {
      if (mounted) setState(() => _running = false);
      return;
    }
    _live.add(p);
    p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine, onError: (_) {});
    p.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine, onError: (_) {});
    await p.exitCode;
    _live.remove(p);
    if (mounted) setState(() => _running = false);
  }

  Future<void> _buildHybrid() async {
    if (_prevStrategy.isEmpty || _siteBest.isEmpty) return;
    // group per-site winners by strategy, skipping the base strategy
    final base = _prevStrategy;
    final Map<String, List<String>> overrides = {};
    for (final row in _siteBest) {
      final arrow = row.indexOf(' → ');
      if (arrow <= 0) continue;
      final site = row.substring(0, arrow);
      final strat = row.substring(arrow + 3);
      if (strat == base) continue; // base already covers this site
      overrides.putIfAbsent(strat, () => []).add(site);
    }
    final data = {
      'base': base,
      'base_strategy': base,
      'overrides': [
        for (final e in overrides.entries)
          {'sites': e.value, 'strategy': e.key},
      ],
      'ts': DateTime.now().millisecondsSinceEpoch / 1000,
    };
    setState(() {
      _running = true;
      _note = '';
      _best = '';
    });
    try {
      await File('${widget.root}\\state\\hybrid.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(data));
    } catch (_) {}
    void onLine(String line) {
      if (!mounted) return;
      if (line.startsWith('HYBRID=')) {
        setState(() {
          _running = false;
          _note = Loc.t('siteAdaptHybridDone')
              .replaceAll('%s', line.substring('HYBRID='.length));
        });
      }
    }

    Process? p;
    try {
      p = await Process.start(
        '${widget.root}\\tools\\python\\pythonw.exe',
        ['-u', 'cli\\nukera.py', 'hybrid_build'],
        workingDirectory: widget.root,
      );
    } catch (_) {}
    if (p == null) {
      if (!mounted) return;
      setState(() => _running = false);
      return;
    }
    _live.add(p);
    p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine, onError: (_) {});
    p.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine, onError: (_) {});
    await p.exitCode;
    _live.remove(p);
    if (!mounted) return;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(Loc.t('siteAdapt'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: kBg,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(Loc.t('siteAdaptSub'),
                style: const TextStyle(color: kMuted, fontSize: 12.5)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _probeCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: Loc.t('probeHint'),
                      hintStyle:
                          const TextStyle(color: kMuted, fontSize: 12),
                      isDense: true,
                      filled: true,
                      fillColor: kSurface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: kBorder)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: kBorder)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: kAccent)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kSurface,
                    foregroundColor: kAccent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _probeBusy ? null : _runQuickProbe,
                  child: _probeBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(Loc.t('probeRun')),
                ),
              ],
            ),
          ),
          if (_probeResult.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(_probeResult,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: _probeOk ? kAccent : kRed)),
            ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _sitesCtrl,
              maxLines: 5,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: Loc.t('siteAdaptHint'),
                hintStyle: const TextStyle(color: kMuted, fontSize: 12),
                filled: true,
                fillColor: kSurface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kAccent)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _running ? null : _run,
                icon: const Icon(Icons.travel_explore, size: 18),
                label: Text(Loc.t('siteAdaptRun')),
              ),
              if (_running) ...[
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _stop,
                  icon: const Icon(Icons.stop, size: 18),
                  label: Text(Loc.t('siteAdaptStop')),
                ),
              ],
              if (_hybridExists && !_running) ...[
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kSurface,
                    foregroundColor: kAccent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _runHybridCheck,
                  icon: const Icon(Icons.health_and_safety, size: 18),
                  label: Text(Loc.t('siteAdaptCheck')),
                ),
              ],
            ],
          ),
          if (_running && _total > 0) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(
                value: (_done / _total).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: kBorder,
                color: kAccent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text('$_done/$_total',
                  style: const TextStyle(
                      color: kMuted, fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ],
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in _rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(row,
                          style: const TextStyle(
                              fontSize: 12.5, color: kAccent)),
                    ),
                ],
              ),
            ),
          ],
          if (_siteBest.isNotEmpty && !_running) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in _siteBest)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(row,
                          style: const TextStyle(
                              fontSize: 12.5, color: kPurple)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _prevStrategy.isEmpty ? null : _buildHybrid,
                icon: const Icon(Icons.merge_type, size: 18),
                label: Text(Loc.t('siteAdaptHybrid')),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(Loc.t('siteAdaptHybridHint'),
                  style: const TextStyle(color: kMuted, fontSize: 12)),
            ),
          ],
          if (_best.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(Loc.t('siteAdaptBest').replaceAll('%s', _best),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(Loc.t('siteAdaptListed'),
                  style: const TextStyle(color: kMuted, fontSize: 12)),
            ),
          ],
          if (_note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(_note,
                  style: const TextStyle(color: kRed, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final String root;

  const SettingsScreen({super.key, required this.root});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    Loc.notifier.addListener(_onLangChanged);
  }

  @override
  void dispose() {
    Loc.notifier.removeListener(_onLangChanged);
    super.dispose();
  }

  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(Loc.t('settings'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: kBg,
        elevation: 0,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.travel_explore, color: kAccent),
            title: Text(Loc.t('siteAdapt')),
            subtitle: Text(Loc.t('siteAdaptSub'),
                style: const TextStyle(color: kMuted, fontSize: 12.5)),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) =>
                  AdaptSitesScreen(root: widget.root)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.alt_route, color: kAccent),
            title: Text(Loc.t('routing')),
            subtitle: Text(Loc.t('routingSub'),
                style: const TextStyle(color: kMuted, fontSize: 12.5)),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) =>
                  RoutingScreen(root: widget.root)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              Loc.t('language'),
              style: const TextStyle(color: kMuted, fontSize: 13),
            ),
          ),
          _LangTile(
            label: Loc.t('auto'),
            value: AppLang.auto,
          ),
          _LangTile(
            label: Loc.t('english'),
            value: AppLang.en,
          ),
          _LangTile(
            label: Loc.t('russian'),
            value: AppLang.ru,
          ),
          const Divider(height: 24, color: kBorder),
          SwitchListTile(
            activeColor: kAccent,
            title: Text(Loc.t('silentAutostart')),
            subtitle: Text(
              Loc.t('silentAutostartSub'),
              style: const TextStyle(color: kMuted, fontSize: 12.5),
            ),
            value: SettingsManager.silentAutostart,
            onChanged: (v) async {
              await SettingsManager.setSilentAutostart(v, widget.root);
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

class _LangTile extends StatelessWidget {
  final String label;
  final AppLang value;

  const _LangTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final selected = SettingsManager.lang == value;
    return ListTile(
      title: Text(label),
      trailing: selected
          ? const Icon(Icons.check, color: kAccent, size: 20)
          : null,
      onTap: () => SettingsManager.setLang(value),
    );
  }
}
