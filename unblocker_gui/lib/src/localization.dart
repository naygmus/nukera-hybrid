class AppLocalizations {
  static const Map<String, Map<String, String>> _translations = {
    'en': {
      'appTitle': 'Nukera',
      'adaptTitle': 'Adaptation & routing',
      'adaptSection': 'Strategy adaptation',
      'adaptStart': 'Start',
      'adaptStop': 'Stop',
      'adaptIdle': 'Not running',
      'adaptDone': 'Best strategy',
      'sitesSection': 'Per-site adaptation',
      'sitesHint': 'example.com',
      'sitesEmpty': 'No sites yet',
      'hybridSection': 'Hybrid strategy',
      'hybridHint': 'One multi-profile strategy: base + per-site winners',
      'hybridBuild': 'Build',
      'hybridCheck': 'Re-check',
      'hybridBuilding': 'Building hybrid strategy...',
      'hybridChecking': 'Checking hybrid sites...',
      'routingSection': 'Routing',
      'routingAll': 'All traffic',
      'routingCustom': 'Custom (selected domains only)',
      'routingDomains': 'Extra domains (comma-separated)',
      'routingExcludes': 'Excluded domains',
      'routingSave': 'Save and apply',
      'routingSaved': 'Routing saved',
      'engineRestarted': 'Engine restarted',
      'engineRestartFailed': 'Failed to restart engine',
      'connected': 'Connected',
      'disconnected': 'Disconnected',
      'connecting': 'Connecting...',
      'optimizing': 'Optimizing...',
      'failed': 'Failed',
      'setupTelegram': 'Setup Telegram',
      'settings': 'Settings',
      'language': 'Language',
      'autostart': 'Autostart with system',
    },
    'ru': {
      'appTitle': 'Nukera',
      'connected': 'Подключено',
      'disconnected': 'Отключено',
      'connecting': 'Подключение...',
      'optimizing': 'Оптимизация...',
      'failed': 'Ошибка',
      'setupTelegram': 'Настроить Telegram',
      'settings': 'Настройки',
      'language': 'Язык',
      'autostart': 'Автозапуск с системой',
      'adaptTitle': 'Адаптация и маршрутизация',
      'adaptSection': 'Подбор стратегии',
      'adaptStart': 'Начать подбор',
      'adaptStop': 'Остановить',
      'adaptIdle': 'Не запускался',
      'adaptDone': 'Лучшая стратегия',
      'sitesSection': 'Адаптация по сайтам',
      'sitesHint': 'example.com',
      'sitesEmpty': 'Сайтов пока нет',
      'hybridSection': 'Гибридная стратегия',
      'hybridHint': 'Единая стратегия: базовый профиль + победители по сайтам',
      'hybridBuild': 'Собрать',
      'hybridCheck': 'Перепроверить',
      'hybridBuilding': 'Собираю гибридную стратегию...',
      'hybridChecking': 'Перепроверяю сайты...',
      'routingSection': 'Маршрутизация',
      'routingAll': 'Весь трафик',
      'routingCustom': 'Только выбранные домены',
      'routingDomains': 'Домены через запятую',
      'routingExcludes': 'Исключённые домены',
      'routingSave': 'Сохранить и применить',
      'routingSaved': 'Маршрутизация сохранена',
      'engineRestarted': 'Движок перезапущен',
      'engineRestartFailed': 'Не удалось перезапустить движок',
},
  };

  static String _currentLocale = 'en';

  static String get currentLocale => _currentLocale;

  static void setLocale(String locale) {
    if (_translations.containsKey(locale)) {
      _currentLocale = locale;
    }
  }

  static String tr(String key) {
    return _translations[_currentLocale]?[key] ?? _translations['en']?[key] ?? key;
  }
}
