import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

enum Phase {
  introduction('Introduction'),
  refresher('Refresher'),
  curiosity('Curiosity');

  const Phase(this.label);

  final String label;
}

enum ChatRole { user, assistant }

enum LogLabel {
  debug('DEBUG'),
  info('INFO'),
  warning('WARNING'),
  exception('EXCEPTION'),
  error('ERROR');

  const LogLabel(this.value);

  final String value;

  static LogLabel fromValue(String value) {
    return LogLabel.values.firstWhere(
      (label) => label.value == value,
      orElse: () => LogLabel.info,
    );
  }
}

class AppLogEntry {
  AppLogEntry({
    required this.id,
    required this.source,
    required this.label,
    required this.message,
    required this.timestamp,
  });

  final int id;
  final String source;
  final LogLabel label;
  final String message;
  final DateTime timestamp;

  factory AppLogEntry.fromBackendJson(Map<String, dynamic> json) {
    return AppLogEntry(
      id: json['id'] as int? ?? 0,
      source: json['source'] as String? ?? 'backend',
      label: LogLabel.fromValue(json['label'] as String? ?? 'INFO'),
      message: json['message'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class FrontendLogger {
  FrontendLogger._();

  static final FrontendLogger instance = FrontendLogger._();
  static const int _limit = 200;

  final List<AppLogEntry> _entries = [];
  int _nextId = 1;

  void debug(String message) => _log(LogLabel.debug, message);
  void info(String message) => _log(LogLabel.info, message);
  void warning(String message) => _log(LogLabel.warning, message);
  void exception(String message) => _log(LogLabel.exception, message);
  void error(String message) => _log(LogLabel.error, message);

  List<AppLogEntry> listEntries() {
    final sorted = [..._entries]
      ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
    return sorted.take(_limit).toList(growable: false);
  }

  void _log(LogLabel label, String message) {
    _entries.add(
      AppLogEntry(
        id: _nextId++,
        source: 'frontend',
        label: label,
        message: message,
        timestamp: DateTime.now(),
      ),
    );
    if (_entries.length > _limit) {
      _entries.removeRange(0, _entries.length - _limit);
    }
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.phase,
    required this.role,
    required this.bodyMarkdown,
    required this.createdAt,
  });

  final int id;
  final Phase phase;
  final ChatRole role;
  final String bodyMarkdown;
  final DateTime createdAt;
}

class Lesson {
  Lesson({
    required this.id,
    required this.topic,
    required this.interlocutor,
    required this.title,
    required this.createdAt,
    this.refresherAvailable = false,
    this.curiosityAvailable = false,
    this.refresherStarted = false,
    this.curiosityStarted = false,
    this.curiositySatisfaction = 0,
  });

  final int id;
  final String topic;
  final String interlocutor;
  final String title;
  final DateTime createdAt;
  bool refresherAvailable;
  bool curiosityAvailable;
  bool refresherStarted;
  bool curiosityStarted;
  int curiositySatisfaction;

  bool get needsAttention => refresherAvailable || curiosityAvailable;
}

class ComprehensionQuestion {
  ComprehensionQuestion({
    required this.id,
    required this.question,
    this.answer,
    this.feedback,
    this.isCorrect,
  });

  final int id;
  final String question;
  String? answer;
  String? feedback;
  bool? isCorrect;
}

class DiaryEntry {
  DiaryEntry({
    required this.id,
    required this.date,
    required this.bodyMarkdown,
  });

  final int id;
  final DateTime date;
  final String bodyMarkdown;
}

abstract class CuriosityApi {
  Future<String> createUser(String name);
  Future<List<Lesson>> listLessons();
  Future<Lesson> createLesson(String topic, String interlocutor);
  Future<List<ChatMessage>> listMessages(int lessonId, Phase phase);
  Future<List<ChatMessage>> sendMessage(int lessonId, Phase phase, String body);
  Future<List<ChatMessage>> startQuestions(int lessonId);
  Future<List<ChatMessage>> answerQuestion(int lessonId, String answer);
  Future<List<ChatMessage>> startPhase(int lessonId, Phase phase);
  Future<List<DiaryEntry>> listDiary();
  Future<List<AppLogEntry>> listBackendLogs();
}

class MockCuriosityApi implements CuriosityApi {
  MockCuriosityApi({
    required this.logger,
    this.backendBaseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000/api',
    ),
  });

  final FrontendLogger logger;
  final String backendBaseUrl;
  String? _userName;
  int _nextLessonId = 1;
  int _nextMessageId = 1;
  int _nextQuestionId = 1;
  final List<Lesson> _lessons = [];
  final List<DiaryEntry> _diary = [];
  final Map<int, List<ChatMessage>> _messages = {};
  final Map<int, List<ComprehensionQuestion>> _questions = {};

  @override
  Future<String> createUser(String name) async {
    final cleaned = name.trim();
    if (!RegExp(r'^[A-Za-z]+$').hasMatch(cleaned)) {
      throw ArgumentError('Name must contain alphabetic characters only.');
    }
    _userName = cleaned;
    logger.info('Created local test user $cleaned');
    return cleaned;
  }

  @override
  Future<List<Lesson>> listLessons() async => List.unmodifiable(_lessons);

  @override
  Future<Lesson> createLesson(String topic, String interlocutor) async {
    final now = DateTime.now();
    final lesson = Lesson(
      id: _nextLessonId++,
      topic: topic.trim(),
      interlocutor: interlocutor.trim(),
      title: _titleCase(topic.trim()),
      createdAt: now,
    );
    _lessons.insert(0, lesson);
    logger.info('Created mock lesson ${lesson.id}: ${lesson.title}');
    _messages[lesson.id] = [
      _assistant(
        Phase.introduction,
        '**${lesson.title}**\n\nI am your ${lesson.interlocutor}. Let us make this clear and conversational. What would you like to explore first?',
      ),
    ];
    return lesson;
  }

  @override
  Future<List<ChatMessage>> listMessages(int lessonId, Phase phase) async {
    return (_messages[lessonId] ?? [])
        .where((message) => message.phase == phase)
        .toList(growable: false);
  }

  @override
  Future<List<ChatMessage>> sendMessage(
    int lessonId,
    Phase phase,
    String body,
  ) async {
    final lesson = _lesson(lessonId);
    final user = _user(phase, body.trim());
    final reply = phase == Phase.curiosity
        ? _curiosityReply(lesson, body)
        : _assistant(
            phase,
            'As ${lesson.interlocutor}, I will keep **${lesson.topic}** practical. You said: "$body". Here is the next useful piece to connect.',
          );
    _messages[lessonId]!.addAll([user, reply]);
    logger.debug('Sent ${phase.label} message for lesson $lessonId');
    if (phase == Phase.refresher && !lesson.curiosityAvailable) {
      lesson.curiosityAvailable = true;
    }
    return [user, reply];
  }

  @override
  Future<List<ChatMessage>> startQuestions(int lessonId) async {
    final lesson = _lesson(lessonId);
    _questions.putIfAbsent(
      lessonId,
      () => [
        ComprehensionQuestion(
          id: _nextQuestionId++,
          question: 'What is the core idea of ${lesson.topic}?',
        ),
        ComprehensionQuestion(
          id: _nextQuestionId++,
          question: 'Can you give one example connected to ${lesson.topic}?',
        ),
        ComprehensionQuestion(
          id: _nextQuestionId++,
          question:
              'What would you explain first to someone new to ${lesson.topic}?',
        ),
      ],
    );
    lesson.refresherAvailable = true;
    logger.info('Started mock comprehension questions for lesson $lessonId');
    final first = _questions[lessonId]!.firstWhere(
      (question) => question.answer == null,
    );
    final message = _assistant(Phase.introduction, first.question);
    _messages[lessonId]!.add(message);
    return [message];
  }

  @override
  Future<List<ChatMessage>> answerQuestion(int lessonId, String answer) async {
    final lesson = _lesson(lessonId);
    final questions = _questions[lessonId] ?? [];
    final current = questions.firstWhere((question) => question.answer == null);
    current.answer = answer;
    current.isCorrect = answer.trim().length >= 12;
    current.feedback = current.isCorrect!
        ? 'Good answer. That has enough detail to show the idea is settling in.'
        : 'That is a start, but add the main idea and one concrete example.';
    final messages = [
      _user(Phase.introduction, answer.trim()),
      _assistant(Phase.introduction, current.feedback!),
    ];
    final nextOpen = questions.where((question) => question.answer == null);
    if (nextOpen.isNotEmpty) {
      messages.add(_assistant(Phase.introduction, nextOpen.first.question));
    } else {
      messages.add(
        _assistant(
          Phase.introduction,
          'Introduction complete. The Refresher will be waiting when it is due.',
        ),
      );
    }
    _messages[lesson.id]!.addAll(messages);
    logger.debug('Answered mock comprehension question for lesson $lessonId');
    return messages;
  }

  @override
  Future<List<ChatMessage>> startPhase(int lessonId, Phase phase) async {
    final lesson = _lesson(lessonId);
    if (phase == Phase.refresher) {
      lesson.refresherStarted = true;
      lesson.refresherAvailable = false;
      final message = _assistant(
        phase,
        'Quick check-in from ${lesson.interlocutor}: what part of **${lesson.topic}** still feels most memorable?',
      );
      _messages[lesson.id]!.add(message);
      logger.info('Opened mock Refresher phase for lesson $lessonId');
      return [message];
    }
    lesson.curiosityStarted = true;
    lesson.curiosityAvailable = false;
    final message = _assistant(
      phase,
      'Hi, I am Curiosity. I know almost nothing about **${lesson.topic}**. What is the first thing I should understand?',
    );
    _messages[lesson.id]!.add(message);
    logger.info('Opened mock Curiosity phase for lesson $lessonId');
    return [message];
  }

  @override
  Future<List<DiaryEntry>> listDiary() async {
    if (_diary.isEmpty && _userName != null) {
      _diary.add(
        DiaryEntry(
          id: 1,
          date: DateTime.now(),
          bodyMarkdown:
              '**Dear diary,**\n\nI am waiting to learn something properly from a Curiosity lesson.',
        ),
      );
    }
    return List.unmodifiable(_diary);
  }

  @override
  Future<List<AppLogEntry>> listBackendLogs() async {
    final uri = Uri.parse('$backendBaseUrl/logs?limit=200');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        logger.warning(
          'Backend logs request failed with HTTP ${response.statusCode}',
        );
        return [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        logger.warning('Backend logs response was not a list');
        return [];
      }
      logger.info('Pulled ${decoded.length} backend log entries');
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(AppLogEntry.fromBackendJson)
          .toList(growable: false);
    } on TimeoutException {
      logger.warning('Backend logs request timed out');
      return [];
    } catch (exception) {
      logger.warning('Backend logs unavailable: $exception');
      return [];
    }
  }

  Lesson _lesson(int lessonId) =>
      _lessons.firstWhere((lesson) => lesson.id == lessonId);

  ChatMessage _assistant(Phase phase, String body) {
    return ChatMessage(
      id: _nextMessageId++,
      phase: phase,
      role: ChatRole.assistant,
      bodyMarkdown: body,
      createdAt: DateTime.now(),
    );
  }

  ChatMessage _user(Phase phase, String body) {
    return ChatMessage(
      id: _nextMessageId++,
      phase: phase,
      role: ChatRole.user,
      bodyMarkdown: body,
      createdAt: DateTime.now(),
    );
  }

  ChatMessage _curiosityReply(Lesson lesson, String body) {
    if (lesson.curiositySatisfaction >= 300) {
      _appendDiary(lesson);
      return _assistant(
        Phase.curiosity,
        'I think I finally understand **${lesson.topic}**. Thank you for teaching me so patiently.',
      );
    }
    lesson.curiositySatisfaction =
        (lesson.curiositySatisfaction + body.length * 2).clamp(0, 300);
    if (lesson.curiositySatisfaction >= 300) {
      _appendDiary(lesson);
    }
    return _assistant(
      Phase.curiosity,
      'That helps me understand **${lesson.topic}**. Can you tell me one more thing that would make it clearer?',
    );
  }

  void _appendDiary(Lesson lesson) {
    if (_diary.any((entry) => entry.bodyMarkdown.contains(lesson.topic))) {
      return;
    }
    _diary.insert(
      0,
      DiaryEntry(
        id: _diary.length + 1,
        date: DateTime.now(),
        bodyMarkdown:
            '**Dear diary,**\n\nToday I learned about **${lesson.topic}**. I asked questions, got confused, and then things started making sense.',
      ),
    );
    logger.info('Created mock diary entry for ${lesson.title}');
  }
}

String _titleCase(String value) {
  return value
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Curiosity',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF36C2A3),
          brightness: Brightness.dark,
          surface: const Color(0xFF111418),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0D10),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: CuriosityShell(
        api: MockCuriosityApi(logger: FrontendLogger.instance),
        logger: FrontendLogger.instance,
      ),
    );
  }
}

class CuriosityShell extends StatefulWidget {
  const CuriosityShell({required this.api, required this.logger, super.key});

  final CuriosityApi api;
  final FrontendLogger logger;

  @override
  State<CuriosityShell> createState() => _CuriosityShellState();
}

class _CuriosityShellState extends State<CuriosityShell> {
  String? userName;
  String activePage = 'home';
  Lesson? selectedLesson;
  List<Lesson> lessons = [];
  List<DiaryEntry> diary = [];
  String? error;
  bool askedForName = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    lessons = await widget.api.listLessons();
    diary = await widget.api.listDiary();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!askedForName && userName == null) {
        askedForName = true;
        _showNameDialog();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Curiosity'),
        actions: [
          _TopAction(
            icon: Icons.home_rounded,
            label: 'Start',
            onPressed: () => _go('home'),
          ),
          _TopAction(
            icon: Icons.menu_book_rounded,
            label: 'Diary',
            onPressed: () => _go('diary'),
          ),
          _TopAction(
            icon: Icons.settings_rounded,
            label: 'Settings',
            onPressed: () => _go('settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (error != null)
              MaterialBanner(
                content: Text(error!),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => error = null),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _page(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page() {
    return switch (activePage) {
      'create' => CreateLessonPage(onCreate: _createLesson),
      'history' => HistoryPage(lessons: lessons, onOpen: _openLesson),
      'lesson' => LessonPage(
        api: widget.api,
        lesson: selectedLesson,
        onLessonChanged: _refreshLesson,
      ),
      'diary' => DiaryPage(entries: diary),
      'settings' => SettingsPage(
        userName: userName ?? 'Guest',
        onLogs: () => _go('logs'),
      ),
      'logs' => LogsPage(api: widget.api, logger: widget.logger),
      _ => HomePage(
        userName: userName ?? 'Guest',
        lessonCount: lessons.length,
        attentionCount: lessons.where((lesson) => lesson.needsAttention).length,
        onStart: () => _go('create'),
        onHistory: () => _go('history'),
        onDiary: () => _go('diary'),
        onSettings: () => _go('settings'),
      ),
    };
  }

  void _go(String page) {
    setState(() => activePage = page);
  }

  Future<void> _createLesson(String topic, String interlocutor) async {
    try {
      final lesson = await widget.api.createLesson(topic, interlocutor);
      lessons = await widget.api.listLessons();
      setState(() {
        selectedLesson = lesson;
        activePage = 'lesson';
      });
    } catch (exception) {
      widget.logger.error('Create lesson failed: $exception');
      setState(() => error = exception.toString());
    }
  }

  void _openLesson(Lesson lesson) {
    setState(() {
      selectedLesson = lesson;
      activePage = 'lesson';
    });
  }

  Future<void> _refreshLesson() async {
    lessons = await widget.api.listLessons();
    diary = await widget.api.listDiary();
    if (selectedLesson != null) {
      selectedLesson = lessons.firstWhere(
        (lesson) => lesson.id == selectedLesson!.id,
      );
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showNameDialog() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Welcome'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _saveName(controller),
          ),
          actions: [
            FilledButton(
              onPressed: () => _saveName(controller),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveName(TextEditingController controller) async {
    try {
      final name = await widget.api.createUser(controller.text);
      if (mounted) {
        Navigator.of(context).pop();
        setState(() => userName = name);
      }
    } catch (exception) {
      widget.logger.warning('Name validation failed: $exception');
      setState(() => error = exception.toString());
    }
  }
}

class _TopAction extends StatelessWidget {
  const _TopAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(tooltip: label, icon: Icon(icon), onPressed: onPressed);
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    required this.userName,
    required this.lessonCount,
    required this.attentionCount,
    required this.onStart,
    required this.onHistory,
    required this.onDiary,
    required this.onSettings,
    super.key,
  });

  final String userName;
  final int lessonCount;
  final int attentionCount;
  final VoidCallback onStart;
  final VoidCallback onHistory;
  final VoidCallback onDiary;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('home'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Hello, $userName',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '$lessonCount lessons saved. $attentionCount waiting for attention.',
              ),
              const SizedBox(height: 24),
              _MenuButton(
                icon: Icons.add_comment_rounded,
                label: 'Start',
                onPressed: onStart,
              ),
              _MenuButton(
                icon: Icons.history_edu_rounded,
                label: 'Lessons',
                onPressed: onHistory,
              ),
              _MenuButton(
                icon: Icons.menu_book_rounded,
                label: 'Diary',
                onPressed: onDiary,
              ),
              _MenuButton(
                icon: Icons.settings_rounded,
                label: 'Settings',
                onPressed: onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FilledButton.icon(
        icon: Icon(icon),
        label: Text(label),
        onPressed: onPressed,
      ),
    );
  }
}

class CreateLessonPage extends StatefulWidget {
  const CreateLessonPage({required this.onCreate, super.key});

  final Future<void> Function(String topic, String interlocutor) onCreate;

  @override
  State<CreateLessonPage> createState() => _CreateLessonPageState();
}

class _CreateLessonPageState extends State<CreateLessonPage> {
  final topic = TextEditingController();
  final interlocutor = TextEditingController();
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('create'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Create lesson',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: topic,
              decoration: const InputDecoration(labelText: 'Topic'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: interlocutor,
              decoration: const InputDecoration(labelText: 'Interlocutor'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: const Text('Start lesson'),
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      await widget.onCreate(topic.text, interlocutor.text);
                      if (mounted) {
                        setState(() => busy = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({required this.lessons, required this.onOpen, super.key});

  final List<Lesson> lessons;
  final ValueChanged<Lesson> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const ValueKey('history'),
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final lesson = lessons[index];
        return ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          tileColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
          leading: Icon(
            lesson.needsAttention
                ? Icons.priority_high_rounded
                : Icons.chat_bubble_outline_rounded,
          ),
          title: Text(lesson.title),
          subtitle: Text(lesson.interlocutor),
          trailing: lesson.needsAttention
              ? const Icon(Icons.error_rounded, color: Color(0xFFFF5A66))
              : const Icon(Icons.chevron_right_rounded),
          onTap: () => onOpen(lesson),
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: lessons.length,
    );
  }
}

class LessonPage extends StatefulWidget {
  const LessonPage({
    required this.api,
    required this.lesson,
    required this.onLessonChanged,
    super.key,
  });

  final CuriosityApi api;
  final Lesson? lesson;
  final Future<void> Function() onLessonChanged;

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  Phase phase = Phase.introduction;
  List<ChatMessage> messages = [];
  final input = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LessonPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lesson?.id != widget.lesson?.id) {
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.lesson == null) {
      return;
    }
    messages = await widget.api.listMessages(widget.lesson!.id, phase);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    if (lesson == null) {
      return const Center(
        key: ValueKey('lesson-empty'),
        child: Text('No lesson selected.'),
      );
    }
    return Column(
      key: ValueKey('lesson-${lesson.id}'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      lesson.interlocutor,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (phase == Phase.curiosity)
                Chip(
                  avatar: const Icon(Icons.favorite_rounded, size: 16),
                  label: Text('${lesson.curiositySatisfaction}/300'),
                ),
            ],
          ),
        ),
        SegmentedButton<Phase>(
          segments: Phase.values
              .map(
                (item) => ButtonSegment(
                  value: item,
                  icon: _phaseIcon(item, lesson),
                  label: Text(item.label),
                ),
              )
              .toList(),
          selected: {phase},
          onSelectionChanged: (selection) {
            setState(() => phase = selection.first);
            _load();
          },
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) =>
                ChatBubble(message: messages[index]),
          ),
        ),
        _phaseAction(lesson),
        ChatComposer(
          controller: input,
          busy: busy,
          onSend: () => _send(lesson),
        ),
      ],
    );
  }

  Widget _phaseIcon(Phase item, Lesson lesson) {
    final waiting =
        item == Phase.refresher && lesson.refresherAvailable ||
        item == Phase.curiosity && lesson.curiosityAvailable;
    return Icon(waiting ? Icons.error_rounded : Icons.chat_rounded);
  }

  Widget _phaseAction(Lesson lesson) {
    if (phase == Phase.introduction) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.check_circle_rounded),
          label: const Text('Understood!'),
          onPressed: busy
              ? null
              : () => _run(() => widget.api.startQuestions(lesson.id)),
        ),
      );
    }
    if (phase == Phase.refresher && !lesson.refresherStarted) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FilledButton.icon(
          icon: const Icon(Icons.bolt_rounded),
          label: const Text('Open refresher'),
          onPressed: lesson.refresherAvailable
              ? () => _run(() => widget.api.startPhase(lesson.id, phase))
              : null,
        ),
      );
    }
    if (phase == Phase.curiosity && !lesson.curiosityStarted) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FilledButton.icon(
          icon: const Icon(Icons.psychology_alt_rounded),
          label: const Text('Meet Curiosity'),
          onPressed: lesson.curiosityAvailable
              ? () => _run(() => widget.api.startPhase(lesson.id, phase))
              : null,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _send(Lesson lesson) async {
    final text = input.text.trim();
    if (text.isEmpty) {
      return;
    }
    input.clear();
    if (phase == Phase.introduction && _looksLikeQuestionAnswer()) {
      await _run(() => widget.api.answerQuestion(lesson.id, text));
    } else {
      await _run(() => widget.api.sendMessage(lesson.id, phase, text));
    }
  }

  bool _looksLikeQuestionAnswer() {
    return messages.isNotEmpty &&
        messages.last.role == ChatRole.assistant &&
        messages.last.bodyMarkdown.endsWith('?');
  }

  Future<void> _run(Future<List<ChatMessage>> Function() action) async {
    setState(() => busy = true);
    final newMessages = await action();
    await widget.onLessonChanged();
    if (mounted) {
      setState(() {
        messages.addAll(newMessages);
        busy = false;
      });
    }
  }
}

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    required this.controller,
    required this.busy,
    required this.onSend,
    super.key,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Reply'),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: busy ? null : onSend,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({required this.message, super.key});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isUser
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: MarkdownText(message.bodyMarkdown),
        ),
      ),
    );
  }
}

class MarkdownText extends StatelessWidget {
  const MarkdownText(this.markdown, {super.key});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final lines = markdown.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          if (line.trim().isEmpty)
            const SizedBox(height: 8)
          else if (line.startsWith('# '))
            Text(
              line.substring(2),
              style: Theme.of(context).textTheme.titleLarge,
            )
          else if (line.startsWith('## '))
            Text(
              line.substring(3),
              style: Theme.of(context).textTheme.titleMedium,
            )
          else if (line.startsWith('- '))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('- ${line.substring(2)}'),
            )
          else if (line == '---')
            const Divider()
          else
            RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: _inlineSpans(line),
              ),
            ),
      ],
    );
  }

  List<TextSpan> _inlineSpans(String line) {
    final spans = <TextSpan>[];
    final parts = line.split('**');
    for (var index = 0; index < parts.length; index++) {
      spans.add(
        TextSpan(
          text: parts[index],
          style: index.isOdd
              ? const TextStyle(fontWeight: FontWeight.w700)
              : null,
        ),
      );
    }
    return spans;
  }
}

class DiaryPage extends StatelessWidget {
  const DiaryPage({required this.entries, super.key});

  final List<DiaryEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        key: ValueKey('diary-empty'),
        child: Text('No diary entries yet.'),
      );
    }
    return Row(
      key: const ValueKey('diary'),
      children: [
        SizedBox(
          width: 220,
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                leading: const Icon(Icons.calendar_month_rounded),
                title: Text(_dateLabel(entry.date)),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: MarkdownText(entries.first.bodyMarkdown),
          ),
        ),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.userName, required this.onLogs, super.key});

  final String userName;
  final VoidCallback onLogs;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('settings'),
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.person_rounded),
          title: const Text('User'),
          subtitle: Text(userName),
        ),
        const ListTile(
          leading: Icon(Icons.dns_rounded),
          title: Text('Backend'),
          subtitle: Text('http://localhost:8000/api'),
        ),
        ListTile(
          leading: const Icon(Icons.receipt_long_rounded),
          title: const Text('Logs'),
          subtitle: const Text('Frontend and backend activity'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onLogs,
        ),
        SwitchListTile(
          value: true,
          onChanged: (_) {},
          title: const Text('Dark theme'),
          secondary: const Icon(Icons.dark_mode_rounded),
        ),
      ],
    );
  }
}

class LogsPage extends StatefulWidget {
  const LogsPage({required this.api, required this.logger, super.key});

  final CuriosityApi api;
  final FrontendLogger logger;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  List<AppLogEntry> entries = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    widget.logger.info('Opened logs page');
    final backendLogs = await widget.api.listBackendLogs();
    final combined = [...backendLogs, ...widget.logger.listEntries()]
      ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
    if (mounted) {
      setState(() {
        entries = combined.take(200).toList(growable: false);
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('logs'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Logs',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh logs',
                onPressed: loading ? null : _load,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : entries.isEmpty
              ? const Center(child: Text('No logs yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) =>
                      LogEntryTile(entry: entries[index]),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: entries.length,
                ),
        ),
      ],
    );
  }
}

class LogEntryTile extends StatelessWidget {
  const LogEntryTile({required this.entry, super.key});

  final AppLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final borderColor = entry.source == 'backend'
        ? const Color(0xFF4EA1FF)
        : const Color(0xFFFFD24D);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1.4),
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label.value,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  _timestampLabel(entry.timestamp),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(entry.message)),
        ],
      ),
    );
  }
}

String _dateLabel(DateTime value) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

String _timestampLabel(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
