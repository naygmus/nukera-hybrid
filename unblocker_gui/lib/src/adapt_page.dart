import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'localization.dart';

/// Adaptation / per-site / routing control page (Windows parity).
///
/// Root mutations go through `pkexec /usr/bin/unblocker ...`; the CLI is
/// allowlisted in the polkit rule. Progress is polled from
/// /tmp/unblocker-adapt.json, which the root CLI keeps world-readable.
class AdaptPage extends StatefulWidget {
  const AdaptPage({super.key});

  @override
  State<AdaptPage> createState() => _AdaptPageState();
}

class _AdaptPageState extends State<AdaptPage> {
  bool _addingSite = false;
  Timer? _poll;
  Map<String, dynamic> _progress = {};
  bool _running = false;
  List<String> _sites = [];
  final _siteCtrl = TextEditingController();
  String _mode = 'all';
  final _domainsCtrl = TextEditingController();
  final _excludesCtrl = TextEditingController();
  String _status = '';

  @override
  void initState() {
    super.initState();
    _refreshSites();
    _loadProgress();
    _loadRouting();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _siteCtrl.dispose();
    _domainsCtrl.dispose();
    _excludesCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Resolve the CLI binary the GUI execs. Priority: the polkit-allowlisted
  /// canonical paths, then the repo's dev build found by walking up from the
  /// running GUI executable (flutter build linux --release layout).
  String _resolveCli() {
    const candidates = [
      '/usr/bin/unblocker',
      '/usr/lib/nukera/unblocker',
      '/usr/local/bin/unblocker',
    ];
    for (final p in candidates) {
      if (File(p).existsSync()) return p;
    }
    var dir = Directory(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++) {
      final dev = '${dir.path}${Platform.pathSeparator}target'
          '${Platform.pathSeparator}release${Platform.pathSeparator}unblocker';
      if (File(dev).existsSync()) return dev;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return '/usr/bin/unblocker';
  }

  /// Runs an unblocker subcommand as root via pkexec.
  Future<String> _pkexec(List<String> args) async {
    try {
      final cli = _resolveCli();
      // Puppy (no polkit/systemd) runs the desktop as root: call the CLI
      // directly; Debian-family keeps the pkexec privilege elevation.
      final usePk = File('/usr/bin/pkexec').existsSync() &&
          File('/run/systemd/system').existsSync();
      /*final r = await (usePk
          ? Process.run('pkexec', [cli, ...args],
              stdoutEncoding: utf8, stderrEncoding: utf8)
          : Process.run(cli, args,
              stdoutEncoding: utf8, stderrEncoding: utf8));*/
            final r = await (usePk
              ? Process.run('pkexec', [cli, ...args],
                  stdoutEncoding: utf8, stderrEncoding: utf8)
              : Process.run(cli, args,
                  stdoutEncoding: utf8, stderrEncoding: utf8))
          .timeout(const Duration(minutes: 30), onTimeout: () {
            return ProcessResult(-1, 124, '', 'timeout after 30m');
          });
      if (r.exitCode != 0) {
        final err = (r.stderr as String).trim();
        return 'ERR: ${err.isEmpty ? 'exit ${r.exitCode}' : err}';
      }
      return (r.stdout as String).trim();
    } on ProcessException catch (e) {
      return 'ERR: ${e.executable}: ${e.message}';
    }
  }

 
  static String _str(dynamic v) =>
      v is String ? v : (v == null ? '' : v.toString());

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
   /// Очищает сырой stdout от ANSI-кодов и логов, оставляя только результат.
  String _extractResult(String raw) {
    if (raw.isEmpty) return raw;
    // Убираем ANSI escape-последовательности (цвета терминала)
    String clean = raw.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
    // Берём последнюю непустую строку (обычно там финальный ответ CLI)
    final lines = clean.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isNotEmpty) {
      return lines.last.trim();
    }
    return clean.trim();
  }
  /// Достаёт best.strategy из структуры бэкенда (best — объект, не строка).
  static String _bestStrategy(Map<dynamic, dynamic> p) {
    final b = p['best'];
    if (b is Map) return _str(b['strategy']);
    return _str(b);
  }

  /// Человекочитаемое сообщение из полей бэкенда (strategy → host).
  static String _composeMessage(Map<dynamic, dynamic> p) {
    final backendMsg = _str(p['message']);
    if (backendMsg.isNotEmpty) return backendMsg;
    final strat = _str(p['strategy']);
    final host  = _str(p['host']);
    if (strat.isEmpty && host.isEmpty) return '';
    if (host.isEmpty)  return strat;
    if (strat.isEmpty) return host;
    return '$strat → $host';
  }
  
//fix DeepSeek
  Future<void> _loadProgress() async {
    try {
      final s = await File('/tmp/unblocker-adapt.json').readAsString();
      if (!mounted) return;
      final raw = jsonDecode(s);
      if (raw is! Map) return;
      final stage = _str(raw['stage']);
      final p = <String, dynamic>{
        'stage':    stage,
        'message':  _str(raw['message']),
        'best':     raw['best'], // Передаем объект как есть, его распарсит _bestStrategy
        'current':  _int(raw['current']), // <--- ИСПРАВЛЕНО
        'total':    _int(raw['total']),
      };
      setState(() {
        _progress = p;
        const terminal = {'done', 'error', 'cancelled'};
        _running = stage.isNotEmpty && !terminal.contains(stage);
      });
    } catch (_) {}
  }
//fix

  /*void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 900), (_) {
      _loadProgress();
      if (!mounted) return;
      if (!_running) {
        _poll?.cancel();
        _refreshSites();
      }
    });
  }*/
     void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 900), (_) async {
      await _loadProgress();
      if (!mounted) return;
      if (!_running) {
        _poll?.cancel();
        _refreshSites();
      }
    });
  }

  Future<void> _refreshSites() async {
    final dir = Directory('/etc/unblocker/sites');
    final list = <String>[];
    try {
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.conf')) {
          list.add(e.uri.pathSegments.last.replaceAll('.conf', ''));
        }
      }
      list.sort();
    } catch (_) {}
    if (mounted) setState(() => _sites = list);
  }

  /*Future<void> _startAdapt() async {
    setState(() {
      _running = true;
      _status = '';
    });
    _startPolling();
    final msg = await _pkexec(['adapt']);
    if (!mounted) return;
    setState(() => _status = msg.startsWith('ERR:') ? msg : '');
    if (!msg.startsWith('ERR:')) _toast(msg);
  }
*/

  Future<void> _startAdapt() async {
    try {
      await File('/tmp/unblocker-adapt.json').delete();
    } catch (_) {}
    setState(() {
      _running = true;
      _status = '';
      _progress = {};
    });
    _startPolling();
    final msg = await _pkexec(['adapt']);
    if (!mounted) return;
    if (msg.startsWith('ERR:')) {
      // CLI завершился с ошибкой. Останавливаем поллинг и удаляем
      // остаточный progress-файл, иначе next-poll снова увидит stage=running
      // и навсегда заблокирует кнопку «Старт».
      _poll?.cancel();
      try {
        await File('/tmp/unblocker-adapt.json').delete();
      } catch (_) {}
      setState(() {
        _running = false;
        _status = msg;
        _progress = {};
      });
      return;
    }
    _toast(msg);
    // Успех: дочитываем финальный стейт (done/best) — теперь await реально
    // дожидается завершения чтения файла.
    await _loadProgress();
    if (mounted && _status.isEmpty) {
      final errField = _str(_progress['error']);
      if (errField.isNotEmpty) setState(() => _status = errField);
    }
  }
  
  Future<void> _loadSitesFromFile() async {
    if (_addingSite) return;

    final home = Platform.environment['HOME'] ?? '/root';
    String? filePath;

    // 1. Пытаемся открыть системный диалог (с таймаутом на случай зависания)
    try {
      final r = await Process.run('zenity', [
        '--file-selection',
        '--title=Выберите файл со списком сайтов',
        '--filename=$home/',
        '--file-filter=Текстовые файлы (*.txt, *.csv, *.list) | *.txt *.csv *.list',
      ]).timeout(const Duration(seconds: 15)); // Если zenity зависнет, через 15 сек вылетит TimeoutException

      if (r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty) {
        filePath = (r.stdout as String).trim();
      }
    } catch (_) {
      // Игнорируем ошибки и таймауты, переходим к ручному вводу
    }

    // 2. Если системный диалог не дал результата, просим путь вручную
    if (filePath == null || filePath.isEmpty) {
      if (!mounted) return;
      
      final TextEditingController pathCtrl = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF16202E),
          title: const Text('Путь к файлу'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Системный диалог не открылся. Введите полный путь к файлу со списком сайтов:', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: pathCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '/root/sites.txt',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(pathCtrl.text.trim()),
              child: const Text('Загрузить'),
            ),
          ],
        ),
      );
      
      pathCtrl.dispose();
      filePath = result;
    }

    if (filePath == null || filePath.isEmpty) return;

    // 3. Читаем файл по выбранному или введенному пути
    final file = File(filePath);
    if (!await file.exists()) {
      _toast('Файл не найден: $filePath');
      return;
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        _toast('Файл пуст');
        return;
      }

      _siteCtrl.text = content;
      final count = content.split(RegExp(r'[\s,]+')).where((s) => s.trim().isNotEmpty).length;
      _toast('Загружено $count сайт(ов). Нажмите "+" для подбора.');
    } catch (e) {
      _toast('Ошибка чтения файла: $e');
    }
  }
  
  Future<void> _stopAdapt() async {
    final msg = await _pkexec(['adapt-stop']);
    _toast(msg.startsWith('ERR:') ? msg : 'cancel requested');
  }

  Future<void> _addSites() async {
    final rawText = _siteCtrl.text.trim();
    if (rawText.isEmpty || _addingSite) return;

    // Парсим ввод: разделяем по пробелам, запятым и переносам строк
    final hosts = rawText
        .split(RegExp(r'[\s,]+'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet() // Убираем дубликаты
        .toList();

    if (hosts.isEmpty) return;

    _siteCtrl.clear();
    setState(() {
      _addingSite = true;
      _running = true;
      _status = '';
      _progress = {};
    });
    
    try {
      await File('/tmp/unblocker-adapt.json').delete();
    } catch (_) {}

    _startPolling();
    _toast('Начат подбор для ${hosts.length} сайт(ов)...');

    // Передаем ВСЕ сайты одной командой
    final rawMsg = await _pkexec(['adapt-sites', ...hosts]);
    final msg = _extractResult(rawMsg);

    _poll?.cancel();
    if (!mounted) return;
    
    setState(() {
      _addingSite = false;
      _running = false;
    });
    
    _toast(msg);
    await _refreshSites();
  }

  /*Future<void> _loadSitesFromFile() async {
    if (_addingSite) return;

    try {
      final r = await Process.run('zenity', [
        '--file-selection',
        '--title=Выберите файл со списком сайтов',
        '--file-filter=Текстовые файлы (*.txt, *.csv, *.list) | *.txt *.csv *.list',
        '--file-filter=Все файлы | *',
      ]);

      if (r.exitCode != 0) return; // Отмена

      final path = (r.stdout as String).trim();
      if (path.isEmpty) return;

      final file = File(path);
      if (!await file.exists()) {
        _toast('Файл не найден: $path');
        return;
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        _toast('Файл пуст');
        return;
      }

      _siteCtrl.text = content;
      final count = content.split(RegExp(r'[\s,]+')).where((s) => s.trim().isNotEmpty).length;
      _toast('Загружено $count сайт(ов). Нажмите "+" для подбора.');

    } on ProcessException {
      _toast('Ошибка: утилита zenity не найдена.');
    } catch (e) {
      _toast('Ошибка чтения файла: $e');
    }
  }*/
  
  Future<void> _removeSite(String host) async {
    try {
      final usePk = File('/usr/bin/pkexec').existsSync() &&
          File('/run/systemd/system').existsSync();
      await Process.run(
          usePk ? 'pkexec' : 'rm',
          usePk
              ? ['/usr/bin/rm', '/etc/unblocker/sites/$host.conf']
              : ['-f', '/etc/unblocker/sites/$host.conf']);
    } catch (_) {}
    await _refreshSites();
  }

Future<void> _hybridBuild() async {
    try {
      await File('/tmp/unblocker-adapt.json').delete();
    } catch (_) {}
    setState(() {
      _running = true;
      _status = '';
      _progress = {};
    });
    _startPolling();
    _toast(AppLocalizations.tr('hybridBuilding'));

    final rawMsg = await _pkexec(['hybrid-build']);
    final msg = _extractResult(rawMsg);

    _poll?.cancel();
    if (!mounted) return;
    setState(() => _running = false);
    _toast(msg);
  }

  Future<void> _hybridCheck() async {
    try {
      await File('/tmp/unblocker-adapt.json').delete();
    } catch (_) {}
    setState(() {
      _running = true;
      _status = '';
      _progress = {};
    });
    _startPolling();
    _toast(AppLocalizations.tr('hybridChecking'));

    final rawMsg = await _pkexec(['hybrid-check']);
    final msg = _extractResult(rawMsg);

    _poll?.cancel();
    if (!mounted) return;
    setState(() => _running = false);
    _toast(msg);
  }

Future<void> _hybridRevert() async {
    _toast('Откат гибридной стратегии...');
    final rawMsg = await _pkexec(['hybrid-revert']);
    final msg = _extractResult(rawMsg);
    _toast(msg);
  }

   Future<void> _loadRouting() async {
    try {
      // На Debian конфиг /etc/unblocker/* может быть недоступен на чтение
      // обычному пользователю — идём через тот же канал, что и мутации.
      final raw = await _pkexec(['routing-get']);
      if (raw.startsWith('ERR:')) return;
      final cfg = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _mode = (cfg['mode'] as String?) ?? 'all';
        _domainsCtrl.text = ((cfg['custom_domains'] as List?) ?? [])
            .join(', ');
        _excludesCtrl.text = ((cfg['excludes'] as List?) ?? []).join(', ');
      });
    } catch (_) {}
  }

  Future<void> _saveRouting() async {
    final args = ['routing-set', '--mode', _mode];
    final domains = _domainsCtrl.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final excludes = _excludesCtrl.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (domains.isNotEmpty) args.addAll(['--domains', domains.join(',')]);
    if (excludes.isNotEmpty) args.addAll(['--excludes', excludes.join(',')]);
    final msg = await _pkexec(args);
    _toast(msg.startsWith('ERR:') ? msg : AppLocalizations.tr('routingSaved'));
  }

   Future<void> _restartEngine() async {
    try {
      final systemd = File('/run/systemd/system').existsSync();
      final usePk =
          File('/usr/bin/pkexec').existsSync() && systemd;
      final r = await (systemd
          ? (usePk
              ? Process.run(
                  'pkexec', ['systemctl', 'restart', 'unblocker.service'],
                  stdoutEncoding: utf8, stderrEncoding: utf8)
              : Process.run(
                  'systemctl', ['restart', 'unblocker.service'],
                  stdoutEncoding: utf8, stderrEncoding: utf8))
          : Process.run('/etc/init.d/unblocker', ['restart'],
              stdoutEncoding: utf8, stderrEncoding: utf8));
      if (r.exitCode == 0) {
        _toast(AppLocalizations.tr('engineRestarted'));
      } else {
        _toast('${AppLocalizations.tr('engineRestartFailed')} '
            '(${(r.stderr as String).trim()})');
      }
    } catch (_) {
      _toast(AppLocalizations.tr('engineRestartFailed'));
    }
  }

  @override
  Widget build(BuildContext context) {
  	final stage    = _str(_progress['stage']);
    final message  = _composeMessage(_progress);
    final best     = _bestStrategy(_progress);
    final attempts = _int(_progress['current']);  // ← было 'attempts', бэкенд пишет 'current'
    final total    = _int(_progress['total']);
    final frac = total > 0 ? (attempts / total).clamp(0.0, 1.0) : 0.0;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('adaptTitle')),
        backgroundColor: const Color(0xFF0F1724),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFF16202E),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.tr('adaptSection'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  if (_running) ...[
                    LinearProgressIndicator(value: frac),
                    const SizedBox(height: 8),
                    Text('$message ($attempts/$total)',
                        style: const TextStyle(fontSize: 13)),
                  ] else if (stage == 'done' && best.isNotEmpty) ...[
                    Text('${AppLocalizations.tr('adaptDone')}: $best',
                        style: const TextStyle(fontSize: 13)),
                  ] else
                    Text(AppLocalizations.tr('adaptIdle'),
                        style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(children: [
                    ElevatedButton.icon(
                      onPressed: _running ? null : _startAdapt,
                      icon: const Icon(Icons.auto_fix_high),
                      label: Text(AppLocalizations.tr('adaptStart')),
                    ),
                    const SizedBox(width: 8),
                    if (_running)
                      OutlinedButton(
                        onPressed: _stopAdapt,
                        child: Text(AppLocalizations.tr('adaptStop')),
                      ),
                  ]),
                  if (_status.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_status,
                        style: const TextStyle(
                            color: Color(0xFFFF7B72), fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),

          Card(
            color: const Color(0xFF16202E),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.tr('sitesSection'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                                    Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _siteCtrl,
                        maxLines: 3,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: 'example.com, site2.com\n(через запятую или с новой строки)',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // --- НОВАЯ КНОПКА ЗАГРУЗКИ ИЗ ФАЙЛА ---
                    IconButton(
                      tooltip: 'Загрузить из файла',
                      onPressed: _addingSite ? null : _loadSitesFromFile,
                      icon: const Icon(Icons.folder_open),
                    ),
                    // --- КНОПКА ДОБАВЛЕНИЯ (ПЛЮС) ---
                    IconButton(
                      tooltip: 'Добавить сайты',
                      onPressed: _addingSite ? null : _addSites,
                      icon: _addingSite 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_circle_outline)),
                  ]),
                  const SizedBox(height: 8),
                  if (_sites.isEmpty)
                    Text(AppLocalizations.tr('sitesEmpty'),
                        style: const TextStyle(fontSize: 13)),
                  for (final s in _sites)
                    ListTile(
                      dense: true,
                      title: Text(s),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeSite(s),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Card(
            color: const Color(0xFF16202E),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.tr('hybridSection'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(AppLocalizations.tr('hybridHint'),
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 12),
					Row(children: [
                    ElevatedButton(
                        onPressed: _hybridBuild,
                        child: Text(AppLocalizations.tr('hybridBuild'))),
                    const SizedBox(width: 8),
                    OutlinedButton(
                        onPressed: _hybridCheck,
                        child: Text(AppLocalizations.tr('hybridCheck'))),
                    const SizedBox(width: 8),
                    // Кнопка отката
                    TextButton.icon(
                        onPressed: _hybridRevert,
                        icon: const Icon(Icons.undo, size: 18, color: Colors.orange),
                        label: const Text('Откатить', style: TextStyle(color: Colors.orange)),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          Card(
            color: const Color(0xFF16202E),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.tr('routingSection'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  RadioGroup<String>(
                    groupValue: _mode,
                    onChanged: (v) => setState(() => _mode = v ?? 'all'),
                    child: Column(children: [
                      RadioListTile<String>(
                        value: 'all',
                        title: Text(AppLocalizations.tr('routingAll')),
                      ),
                      RadioListTile<String>(
                        value: 'custom',
                        title: Text(AppLocalizations.tr('routingCustom')),
                      ),
                    ]),
                  ),
                  TextField(
                    controller: _domainsCtrl,
                    decoration: InputDecoration(
                        labelText: AppLocalizations.tr('routingDomains'),
                        isDense: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _excludesCtrl,
                    decoration: InputDecoration(
                        labelText: AppLocalizations.tr('routingExcludes'),
                        isDense: true),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                      onPressed: _saveRouting,
                      child: Text(AppLocalizations.tr('routingSave'))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
