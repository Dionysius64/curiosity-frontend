import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    required this.severity,
    required this.loggerName,
    required this.message,
    required this.timestamp,
    this.attributes = const {},
  });

  final int id;
  final String source;
  final LogLabel label;
  final LogLabel severity;
  final String loggerName;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic> attributes;

  factory AppLogEntry.fromBackendJson(Map<String, dynamic> json) {
    final rawLevel =
        json['label'] as String? ??
        json['severity'] as String? ??
        json['level'] as String? ??
        'INFO';
    final rawSeverity =
        json['severity'] as String? ??
        json['level'] as String? ??
        json['label'] as String? ??
        rawLevel;
    final attributes = json['attributes'];
    return AppLogEntry(
      id: json['id'] as int? ?? 0,
      source: json['source'] as String? ?? 'backend',
      label: LogLabel.fromValue(rawLevel),
      severity: LogLabel.fromValue(rawSeverity),
      loggerName: json['logger'] as String? ?? 'curiosity.backend',
      message: json['message'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      attributes: attributes is Map<String, dynamic> ? attributes : const {},
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
        severity: label == LogLabel.exception ? LogLabel.error : label,
        loggerName: 'curiosity.frontend',
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

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int? ?? 0,
      phase: _phaseFromApi(json['phase'] as String? ?? 'introduction'),
      role: (json['role'] as String? ?? 'assistant') == 'user'
          ? ChatRole.user
          : ChatRole.assistant,
      bodyMarkdown: json['body_markdown'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
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

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      id: json['id'] as int? ?? 0,
      topic: json['topic'] as String? ?? '',
      interlocutor: json['interlocutor'] as String? ?? '',
      title: json['title'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      refresherAvailable: json['refresher_available'] as bool? ?? false,
      curiosityAvailable: json['curiosity_available'] as bool? ?? false,
      refresherStarted: json['refresher_started_at'] != null,
      curiosityStarted: json['curiosity_started_at'] != null,
      curiositySatisfaction: json['curiosity_satisfaction'] as int? ?? 0,
    );
  }
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

  factory ComprehensionQuestion.fromJson(Map<String, dynamic> json) {
    return ComprehensionQuestion(
      id: json['id'] as int? ?? 0,
      question: json['question'] as String? ?? '',
      answer: json['answer'] as String?,
      feedback: json['feedback'] as String?,
      isCorrect: json['is_correct'] as bool?,
    );
  }
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

  factory DiaryEntry.fromJson(Map<String, dynamic> json) {
    return DiaryEntry(
      id: json['id'] as int? ?? 0,
      date:
          DateTime.tryParse(json['entry_date'] as String? ?? '') ??
          DateTime.now(),
      bodyMarkdown: json['body_markdown'] as String? ?? '',
    );
  }
}

class Account {
  Account({
    required this.id,
    required this.username,
    required this.email,
    this.token,
  });

  final int id;
  final String username;
  final String email;
  final String? token;

  factory Account.fromJson(Map<String, dynamic> json, {String? token}) {
    return Account(
      id: json['id'] as int? ?? 0,
      username:
          json['username'] as String? ?? json['name'] as String? ?? 'User',
      email: json['email'] as String? ?? '',
      token: token,
    );
  }
}

abstract class CuriosityApi {
  Future<Account?> restoreSession();
  Future<Account> register(String username, String email, String password);
  Future<Account> login(String email, String password);
  Future<Account> updateAccount({String? username, String? email});
  Future<void> updatePassword(String currentPassword, String newPassword);
  Future<void> logout();
  Future<List<Lesson>> listLessons();
  Future<Lesson> createLesson(String topic, String interlocutor);
  Future<List<ChatMessage>> listMessages(int lessonId, Phase phase);
  Future<List<ChatMessage>> sendMessage(int lessonId, Phase phase, String body);
  Future<List<ChatMessage>> startQuestions(int lessonId);
  Future<List<ComprehensionQuestion>> listQuestions(int lessonId);
  Future<List<ChatMessage>> answerQuestion(int lessonId, String answer);
  Future<List<ChatMessage>> startPhase(int lessonId, Phase phase);
  Future<List<DiaryEntry>> listDiary();
  Future<List<AppLogEntry>> listBackendLogs();
}

class RestCuriosityApi implements CuriosityApi {
  RestCuriosityApi({
    required this.logger,
    this.backendBaseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000/api',
    ),
    http.Client? client,
  }) : client = client ?? http.Client();

  final FrontendLogger logger;
  final String backendBaseUrl;
  final http.Client client;
  final Map<int, int> _currentQuestionByLesson = {};
  int? _userId;
  String? _token;

  @override
  Future<Account?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null || token.isEmpty) {
      return null;
    }
    _token = token;
    try {
      final json = await _getObject('/users/me');
      return _storeAccount(Account.fromJson(json, token: token));
    } catch (exception) {
      logger.warning('Stored session was not accepted: $exception');
      await logout();
      return null;
    }
  }

  @override
  Future<Account> register(
    String username,
    String email,
    String password,
  ) async {
    final json = await _post('/auth/register', {
      'username': username.trim(),
      'email': email.trim(),
      'password': password,
    });
    final account = _accountFromAuth(json);
    logger.info('Registered backend user ${account.id}');
    return account;
  }

  @override
  Future<Account> login(String email, String password) async {
    final json = await _post('/auth/login', {
      'email': email.trim(),
      'password': password,
    });
    final account = _accountFromAuth(json);
    logger.info('Logged in backend user ${account.id}');
    return account;
  }

  @override
  Future<Account> updateAccount({String? username, String? email}) async {
    final json = await _patch('/users/me', {
      if (username != null) 'username': username.trim(),
      if (email != null) 'email': email.trim(),
    });
    final account = _storeAccount(Account.fromJson(json, token: _token));
    logger.info('Updated backend account ${account.id}');
    return account;
  }

  @override
  Future<void> updatePassword(
    String currentPassword,
    String newPassword,
  ) async {
    await _patch('/users/me/password', {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    logger.info('Updated backend account password');
  }

  @override
  Future<void> logout() async {
    _token = null;
    _userId = null;
    _currentQuestionByLesson.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_user_id');
    await prefs.remove('auth_username');
    await prefs.remove('auth_email');
  }

  @override
  Future<List<Lesson>> listLessons() async {
    final userId = _userId;
    if (userId == null) {
      return [];
    }
    final json = await _getList('/lessons?user_id=$userId');
    return json.whereType<Map<String, dynamic>>().map(Lesson.fromJson).toList();
  }

  @override
  Future<Lesson> createLesson(String topic, String interlocutor) async {
    final userId = _requireUser();
    final json = await _post('/lessons', {
      'user_id': userId,
      'topic': topic.trim(),
      'interlocutor': interlocutor.trim(),
    });
    logger.info('Created backend lesson ${json['id']}');
    return Lesson.fromJson(json);
  }

  @override
  Future<List<ChatMessage>> listMessages(int lessonId, Phase phase) async {
    final json = await _getList(
      '/lessons/$lessonId/messages?phase=${_phaseToApi(phase)}',
    );
    return json
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
  }

  @override
  Future<List<ChatMessage>> sendMessage(
    int lessonId,
    Phase phase,
    String body,
  ) async {
    final json = await _post('/lessons/$lessonId/messages', {
      'phase': _phaseToApi(phase),
      'body_markdown': body.trim(),
    });
    final messages = <ChatMessage>[
      ChatMessage.fromJson(json['user_message'] as Map<String, dynamic>),
      for (final item in json['assistant_messages'] as List<dynamic>)
        ChatMessage.fromJson(item as Map<String, dynamic>),
    ];
    logger.debug('Sent backend ${phase.label} message for lesson $lessonId');
    return messages;
  }

  @override
  Future<List<ChatMessage>> startQuestions(int lessonId) async {
    final json = await _post('/lessons/$lessonId/understood', {});
    _rememberCurrentQuestion(
      lessonId,
      json['questions'] as List<dynamic>? ?? [],
    );
    final assistant = json['assistant_message'];
    logger.info('Started backend comprehension questions for lesson $lessonId');
    return assistant is Map<String, dynamic>
        ? [ChatMessage.fromJson(assistant)]
        : [];
  }

  @override
  Future<List<ComprehensionQuestion>> listQuestions(int lessonId) async {
    final json = await _getList('/lessons/$lessonId/questions');
    final questions = json
        .whereType<Map<String, dynamic>>()
        .map(ComprehensionQuestion.fromJson)
        .toList();
    _rememberCurrentQuestion(lessonId, json);
    return questions;
  }

  @override
  Future<List<ChatMessage>> answerQuestion(int lessonId, String answer) async {
    final questionId = await _currentQuestionId(lessonId);
    final json = await _post('/lessons/$lessonId/answers', {
      'question_id': questionId,
      'answer': answer.trim(),
    });
    _rememberCurrentQuestion(
      lessonId,
      json['questions'] as List<dynamic>? ?? [],
    );
    final messages = <ChatMessage>[
      ChatMessage.fromJson(json['user_message'] as Map<String, dynamic>),
      ChatMessage.fromJson(json['feedback_message'] as Map<String, dynamic>),
    ];
    final next = json['next_question_message'];
    if (next is Map<String, dynamic>) {
      messages.add(ChatMessage.fromJson(next));
    }
    logger.debug(
      'Answered backend comprehension question for lesson $lessonId',
    );
    return messages;
  }

  @override
  Future<List<ChatMessage>> startPhase(int lessonId, Phase phase) async {
    final json = await _post(
      '/lessons/$lessonId/phases/${_phaseToApi(phase)}/start',
      {},
    );
    final assistant = json['assistant_message'];
    logger.info('Started backend ${phase.label} phase for lesson $lessonId');
    return assistant is Map<String, dynamic>
        ? [ChatMessage.fromJson(assistant)]
        : [];
  }

  @override
  Future<List<DiaryEntry>> listDiary() async {
    final userId = _userId;
    if (userId == null) {
      return [];
    }
    final json = await _getList('/diary?user_id=$userId');
    return json
        .whereType<Map<String, dynamic>>()
        .map(DiaryEntry.fromJson)
        .toList();
  }

  @override
  Future<List<AppLogEntry>> listBackendLogs() async {
    try {
      final json = await _getList('/logs?limit=200', logErrors: false);
      logger.info('Pulled ${json.length} backend log entries');
      return json
          .whereType<Map<String, dynamic>>()
          .map(AppLogEntry.fromBackendJson)
          .toList();
    } catch (exception) {
      logger.warning('Backend logs unavailable: $exception');
      return [];
    }
  }

  Future<int> _currentQuestionId(int lessonId) async {
    final known = _currentQuestionByLesson[lessonId];
    if (known != null) {
      return known;
    }
    final questions = await _getList('/lessons/$lessonId/questions');
    _rememberCurrentQuestion(lessonId, questions);
    final resolved = _currentQuestionByLesson[lessonId];
    if (resolved == null) {
      throw StateError('No unanswered comprehension question is available.');
    }
    return resolved;
  }

  void _rememberCurrentQuestion(int lessonId, List<dynamic> rawQuestions) {
    final questions = rawQuestions
        .whereType<Map<String, dynamic>>()
        .map(ComprehensionQuestion.fromJson)
        .toList();
    final unanswered = questions.where((question) => question.answer == null);
    if (unanswered.isEmpty) {
      _currentQuestionByLesson.remove(lessonId);
    } else {
      _currentQuestionByLesson[lessonId] = unanswered.first.id;
    }
  }

  int _requireUser() {
    final userId = _userId;
    if (userId == null) {
      throw StateError('Create a user before starting lessons.');
    }
    return userId;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await client
        .post(
          Uri.parse('$backendBaseUrl$path'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await client
        .patch(
          Uri.parse('$backendBaseUrl$path'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    return _decodeObject(response);
  }

  Future<List<dynamic>> _getList(String path, {bool logErrors = true}) async {
    try {
      final response = await client
          .get(Uri.parse('$backendBaseUrl$path'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final decoded = _decode(response);
      if (decoded is List<dynamic>) {
        return decoded;
      }
      throw StateError('Expected a JSON list from $path.');
    } catch (exception) {
      if (logErrors) {
        logger.warning('Backend request failed: $exception');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _getObject(String path) async {
    final response = await client
        .get(Uri.parse('$backendBaseUrl$path'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    return _decodeObject(response);
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    final decoded = _decode(response);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw StateError('Expected a JSON object.');
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          detail = decoded['detail']?.toString() ?? detail;
        }
      } catch (_) {
        // Keep the raw body.
      }
      throw StateError('Backend HTTP ${response.statusCode}: $detail');
    }
    return jsonDecode(response.body);
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Account _accountFromAuth(Map<String, dynamic> json) {
    final token = json['token'] as String? ?? '';
    final rawUser = json['user'] as Map<String, dynamic>;
    return _storeAccount(Account.fromJson(rawUser, token: token));
  }

  Account _storeAccount(Account account) {
    _userId = account.id;
    _token = account.token ?? _token;
    SharedPreferences.getInstance().then((prefs) {
      if (_token != null) {
        prefs.setString('auth_token', _token!);
      }
      prefs.setInt('auth_user_id', account.id);
      prefs.setString('auth_username', account.username);
      prefs.setString('auth_email', account.email);
    });
    return account;
  }
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
  Account? _account;
  final Map<String, Account> _accounts = {
    'tester@example.com': Account(
      id: 1,
      username: 'tester',
      email: 'tester@example.com',
      token: 'mock-token',
    ),
  };
  final Map<String, String> _passwords = {'tester@example.com': 'curious'};
  int _nextUserId = 2;
  int _nextLessonId = 1;
  int _nextMessageId = 1;
  int _nextQuestionId = 1;
  final List<Lesson> _lessons = [];
  final List<DiaryEntry> _diary = [];
  final Map<int, List<ChatMessage>> _messages = {};
  final Map<int, List<ComprehensionQuestion>> _questions = {};

  @override
  Future<Account?> restoreSession() async => _account;

  @override
  Future<Account> register(
    String username,
    String email,
    String password,
  ) async {
    _validateAccount(username, email, password);
    final key = email.trim().toLowerCase();
    if (_accounts.containsKey(key)) {
      throw ArgumentError('Email already exists');
    }
    final account = Account(
      id: _nextUserId++,
      username: username.trim(),
      email: key,
      token: 'mock-token-$key',
    );
    _accounts[key] = account;
    _passwords[key] = password;
    _account = account;
    logger.info('Registered local test user ${account.email}');
    return account;
  }

  @override
  Future<Account> login(String email, String password) async {
    final key = email.trim().toLowerCase();
    final account = _accounts[key];
    if (account == null || _passwords[key] != password) {
      throw ArgumentError('Invalid email or password');
    }
    _account = account;
    logger.info('Logged in local test user ${account.email}');
    return account;
  }

  @override
  Future<Account> updateAccount({String? username, String? email}) async {
    final current = _requireAccount();
    final nextUsername = username?.trim() ?? current.username;
    final nextEmail = email?.trim().toLowerCase() ?? current.email;
    _validateAccount(
      nextUsername,
      nextEmail,
      _passwords[current.email] ?? 'curious',
    );
    if (nextEmail != current.email && _accounts.containsKey(nextEmail)) {
      throw ArgumentError('Email already exists');
    }
    _accounts.remove(current.email);
    final updated = Account(
      id: current.id,
      username: nextUsername,
      email: nextEmail,
      token: current.token,
    );
    _accounts[nextEmail] = updated;
    _passwords[nextEmail] = _passwords.remove(current.email) ?? 'curious';
    _account = updated;
    return updated;
  }

  @override
  Future<void> updatePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final account = _requireAccount();
    if (_passwords[account.email] != currentPassword) {
      throw ArgumentError('Current password is incorrect');
    }
    if (newPassword.length < 5) {
      throw ArgumentError('Password must be at least 5 characters');
    }
    _passwords[account.email] = newPassword;
  }

  @override
  Future<void> logout() async {
    _account = null;
  }

  @override
  Future<List<Lesson>> listLessons() async {
    _requireAccount();
    return List.unmodifiable(_lessons);
  }

  @override
  Future<Lesson> createLesson(String topic, String interlocutor) async {
    _requireAccount();
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
  Future<List<ComprehensionQuestion>> listQuestions(int lessonId) async {
    return List.unmodifiable(_questions[lessonId] ?? []);
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
    _requireAccount();
    if (_diary.isEmpty && _account != null) {
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

  Account _requireAccount() {
    final account = _account;
    if (account == null) {
      throw StateError('Sign in before using Curiosity.');
    }
    return account;
  }

  void _validateAccount(String username, String email, String password) {
    final cleanUsername = username.trim();
    final cleanEmail = email.trim().toLowerCase();
    if (cleanUsername.isEmpty || cleanUsername.length > 20) {
      throw ArgumentError('Username must be between 1 and 20 characters');
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(cleanEmail)) {
      throw ArgumentError('Email must be a valid email address');
    }
    if (password.length < 5) {
      throw ArgumentError('Password must be at least 5 characters');
    }
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

String _phaseToApi(Phase phase) {
  return switch (phase) {
    Phase.introduction => 'introduction',
    Phase.refresher => 'refresher',
    Phase.curiosity => 'curiosity',
  };
}

Phase _phaseFromApi(String value) {
  return switch (value) {
    'refresher' => Phase.refresher,
    'curiosity' => Phase.curiosity,
    _ => Phase.introduction,
  };
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const useMockApi = bool.fromEnvironment('USE_MOCK_API');
    final logger = FrontendLogger.instance;
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
        api: useMockApi
            ? MockCuriosityApi(logger: logger)
            : RestCuriosityApi(logger: logger),
        logger: logger,
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
  Account? account;
  String activePage = 'home';
  Lesson? selectedLesson;
  List<Lesson> lessons = [];
  List<DiaryEntry> diary = [];
  Uint8List? userAvatarBytes;
  String? error;
  bool enterSendsReply = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadLocalSettings();
  }

  Future<void> _load() async {
    if (account == null) {
      final restored = await widget.api.restoreSession();
      if (mounted && restored != null) {
        setState(() => account = restored);
      }
    }
    if (account == null) {
      return;
    }
    lessons = await widget.api.listLessons();
    diary = await widget.api.listDiary();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
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
    if (account == null) {
      return AuthPage(
        onLogin: _login,
        onRegister: _register,
        onUseTestAccount: () => _login('tester@example.com', 'curious'),
      );
    }
    return switch (activePage) {
      'create' => CreateLessonPage(onCreate: _createLesson),
      'history' => HistoryPage(lessons: lessons, onOpen: _openLesson),
      'lesson' => LessonPage(
        api: widget.api,
        lesson: selectedLesson,
        onLessonChanged: _refreshLesson,
        userAvatarBytes: userAvatarBytes,
        enterSendsReply: enterSendsReply,
      ),
      'diary' => DiaryPage(entries: diary),
      'settings' => SettingsPage(
        account: account!,
        userAvatarBytes: userAvatarBytes,
        enterSendsReply: enterSendsReply,
        showEnterKeySetting: _supportsEnterKeySetting,
        onPickAvatar: _pickUserAvatar,
        onEditUsername: _showEditUsernameDialog,
        onEditEmail: _showEditEmailDialog,
        onEditPassword: _showEditPasswordDialog,
        onLogout: _logout,
        onEnterSendsReplyChanged: _setEnterSendsReply,
        onLogs: () => _go('logs'),
      ),
      'logs' => LogsPage(api: widget.api, logger: widget.logger),
      _ => HomePage(
        userName: account!.username,
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
    if (account == null) {
      setState(() => activePage = 'home');
      return;
    }
    setState(() => activePage = page);
    if (page == 'home' || page == 'history' || page == 'diary') {
      _load();
    }
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

  Future<void> _login(String email, String password) async {
    try {
      final signedIn = await widget.api.login(email, password);
      await _setAccount(signedIn);
    } catch (exception) {
      widget.logger.warning('Login failed: $exception');
      setState(() => error = exception.toString());
    }
  }

  Future<void> _register(String username, String email, String password) async {
    try {
      final created = await widget.api.register(username, email, password);
      await _setAccount(created);
    } catch (exception) {
      widget.logger.warning('Registration failed: $exception');
      setState(() => error = exception.toString());
    }
  }

  Future<void> _setAccount(Account value) async {
    account = value;
    lessons = await widget.api.listLessons();
    diary = await widget.api.listDiary();
    if (mounted) {
      setState(() {
        account = value;
        activePage = 'home';
        error = null;
      });
    }
  }

  Future<void> _logout() async {
    await widget.api.logout();
    setState(() {
      account = null;
      lessons = [];
      diary = [];
      selectedLesson = null;
      activePage = 'home';
    });
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

  bool get _supportsEnterKeySetting {
    return kIsWeb || defaultTargetPlatform == TargetPlatform.windows;
  }

  Future<void> _loadLocalSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final avatar = prefs.getString('user_avatar_base64');
      if (mounted) {
        setState(() {
          enterSendsReply = prefs.getBool('enter_sends_reply') ?? true;
          userAvatarBytes = avatar == null ? null : base64Decode(avatar);
        });
      }
    } catch (exception) {
      widget.logger.warning('Local settings unavailable: $exception');
    }
  }

  Future<void> _setEnterSendsReply(bool value) async {
    setState(() => enterSendsReply = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('enter_sends_reply', value);
    } catch (exception) {
      widget.logger.warning('Could not save Enter key setting: $exception');
    }
  }

  Future<void> _pickUserAvatar() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 85,
      );
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_avatar_base64', base64Encode(bytes));
      if (mounted) {
        setState(() => userAvatarBytes = bytes);
      }
      widget.logger.info('Updated user profile picture');
    } catch (exception) {
      widget.logger.error('Profile picture upload failed: $exception');
      setState(() => error = 'Could not update profile picture.');
    }
  }

  Future<void> _showEditUsernameDialog() async {
    final controller = TextEditingController(text: account?.username ?? '');
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Username'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            decoration: const InputDecoration(labelText: 'Username'),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _updateUsername(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => _updateUsername(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditEmailDialog() async {
    final controller = TextEditingController(text: account?.email ?? '');
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Email'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _updateEmail(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => _updateEmail(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditPasswordDialog() async {
    final current = TextEditingController();
    final next = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: current,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: next,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => _updatePassword(current.text, next.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateUsername(String username) async {
    try {
      final updated = await widget.api.updateAccount(username: username);
      if (mounted) {
        Navigator.of(context).pop();
        setState(() => account = updated);
      }
    } catch (exception) {
      widget.logger.warning('Username update failed: $exception');
      setState(() => error = exception.toString());
    }
  }

  Future<void> _updateEmail(String email) async {
    try {
      final updated = await widget.api.updateAccount(email: email);
      if (mounted) {
        Navigator.of(context).pop();
        setState(() => account = updated);
      }
    } catch (exception) {
      widget.logger.warning('Email update failed: $exception');
      setState(() => error = exception.toString());
    }
  }

  Future<void> _updatePassword(
    String currentPassword,
    String newPassword,
  ) async {
    try {
      await widget.api.updatePassword(currentPassword, newPassword);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (exception) {
      widget.logger.warning('Password update failed: $exception');
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

class AuthPage extends StatefulWidget {
  const AuthPage({
    required this.onLogin,
    required this.onRegister,
    required this.onUseTestAccount,
    super.key,
  });

  final Future<void> Function(String email, String password) onLogin;
  final Future<void> Function(String username, String email, String password)
  onRegister;
  final Future<void> Function() onUseTestAccount;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final username = TextEditingController();
  final email = TextEditingController(text: 'tester@example.com');
  final password = TextEditingController(text: 'curious');
  bool registering = false;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('auth'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.login_rounded),
                  label: Text('Sign in'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.person_add_rounded),
                  label: Text('Create'),
                ),
              ],
              selected: {registering},
              onSelectionChanged: busy
                  ? null
                  : (value) => setState(() => registering = value.first),
            ),
            const SizedBox(height: 16),
            if (registering) ...[
              TextField(
                controller: username,
                maxLength: 20,
                decoration: const InputDecoration(labelText: 'Username'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      registering
                          ? Icons.person_add_rounded
                          : Icons.login_rounded,
                    ),
              label: Text(registering ? 'Create account' : 'Sign in'),
              onPressed: busy ? null : _submit,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.science_rounded),
              label: const Text('Use test account'),
              onPressed: busy ? null : _useTestAccount,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => busy = true);
    if (registering) {
      await widget.onRegister(username.text, email.text, password.text);
    } else {
      await widget.onLogin(email.text, password.text);
    }
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> _useTestAccount() async {
    setState(() => busy = true);
    await widget.onUseTestAccount();
    if (mounted) {
      setState(() => busy = false);
    }
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
    required this.userAvatarBytes,
    required this.enterSendsReply,
    super.key,
  });

  final CuriosityApi api;
  final Lesson? lesson;
  final Future<void> Function() onLessonChanged;
  final Uint8List? userAvatarBytes;
  final bool enterSendsReply;

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  Phase phase = Phase.introduction;
  final Map<Phase, List<ChatMessage>> phaseMessages = {
    for (final item in Phase.values) item: <ChatMessage>[],
  };
  bool questionsStarted = false;
  final input = TextEditingController();
  final scrollController = ScrollController();
  bool busy = false;
  bool processingVisible = false;
  Timer? processingTimer;
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadAll();
    refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshLessonState(),
    );
  }

  @override
  void didUpdateWidget(covariant LessonPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lesson?.id != widget.lesson?.id) {
      _loadAll();
    } else if (oldWidget.lesson != widget.lesson) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    processingTimer?.cancel();
    scrollController.dispose();
    input.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (widget.lesson == null) {
      return;
    }
    final lessonId = widget.lesson!.id;
    final loaded = <Phase, List<ChatMessage>>{};
    for (final item in Phase.values) {
      loaded[item] = await widget.api.listMessages(lessonId, item);
    }
    final questions = await widget.api.listQuestions(lessonId);
    if (mounted) {
      setState(() {
        phaseMessages
          ..clear()
          ..addAll(loaded);
        questionsStarted = questions.isNotEmpty;
        final visible = _visiblePhases;
        if (!visible.contains(phase)) {
          phase = visible.last;
        }
      });
      _scrollToBottom(jump: true);
    }
  }

  Future<void> _refreshLessonState() async {
    if (widget.lesson == null || busy) {
      return;
    }
    await widget.onLessonChanged();
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
    final visiblePhases = _visiblePhases;
    final currentMessages = phaseMessages[phase] ?? [];
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
        if (visiblePhases.length > 1)
          SegmentedButton<Phase>(
            segments: visiblePhases
                .map(
                  (item) => ButtonSegment(
                    value: item,
                    icon: _phaseIcon(item),
                    label: Text(item.label),
                  ),
                )
                .toList(),
            selected: {phase},
            onSelectionChanged: (selection) {
              setState(() => phase = selection.first);
              _scrollToBottom(jump: true);
            },
          ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: currentMessages.length,
            itemBuilder: (context, index) => ChatBubble(
              message: currentMessages[index],
              userAvatarBytes: widget.userAvatarBytes,
            ),
          ),
        ),
        _phaseAction(lesson),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: processingVisible
              ? Padding(
                  key: const ValueKey('processing'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.center,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text('Processing your reply...'),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no-processing')),
        ),
        ChatComposer(
          controller: input,
          busy: busy,
          enterSendsReply: widget.enterSendsReply,
          onSend: () => _send(lesson),
        ),
      ],
    );
  }

  List<Phase> get _visiblePhases {
    final visible = Phase.values
        .where((item) => (phaseMessages[item] ?? []).isNotEmpty)
        .toList();
    return visible.isEmpty ? [Phase.introduction] : visible;
  }

  Widget _phaseIcon(Phase item) => const Icon(Icons.chat_rounded);

  Widget _phaseAction(Lesson lesson) {
    if (lesson.curiosityAvailable && !lesson.curiosityStarted) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FilledButton.icon(
          icon: const Icon(Icons.psychology_alt_rounded),
          label: const Text('Meet Curiosity'),
          onPressed: busy ? null : () => _startPhase(lesson, Phase.curiosity),
        ),
      );
    }
    if (lesson.refresherAvailable && !lesson.refresherStarted) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FilledButton.icon(
          icon: const Icon(Icons.bolt_rounded),
          label: const Text('Open refresher'),
          onPressed: busy ? null : () => _startPhase(lesson, Phase.refresher),
        ),
      );
    }
    if (phase == Phase.introduction && !questionsStarted) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.check_circle_rounded),
          label: const Text('Understood!'),
          onPressed: busy ? null : () => _startQuestions(lesson),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _send(Lesson lesson) async {
    if (busy) {
      return;
    }
    final text = input.text.trim();
    if (text.isEmpty) {
      return;
    }
    input.clear();
    if (phase == Phase.introduction && _looksLikeQuestionAnswer()) {
      await _run(phase, () => widget.api.answerQuestion(lesson.id, text));
    } else {
      await _run(phase, () => widget.api.sendMessage(lesson.id, phase, text));
    }
  }

  bool _looksLikeQuestionAnswer() {
    final messages = phaseMessages[Phase.introduction] ?? [];
    return questionsStarted &&
        phase == Phase.introduction &&
        messages.isNotEmpty &&
        messages.last.role == ChatRole.assistant &&
        messages.last.bodyMarkdown.trim().endsWith('?');
  }

  Future<void> _startQuestions(Lesson lesson) async {
    await _run(Phase.introduction, () => widget.api.startQuestions(lesson.id));
    if (mounted) {
      setState(() => questionsStarted = true);
    }
  }

  Future<void> _startPhase(Lesson lesson, Phase targetPhase) async {
    await _run(
      targetPhase,
      () => widget.api.startPhase(lesson.id, targetPhase),
    );
    if (mounted) {
      setState(() => phase = targetPhase);
      _scrollToBottom(jump: true);
    }
  }

  Future<void> _run(
    Phase targetPhase,
    Future<List<ChatMessage>> Function() action,
  ) async {
    _showProcessing();
    setState(() => busy = true);
    try {
      final newMessages = await action();
      await widget.onLessonChanged();
      if (mounted) {
        setState(() {
          final current = phaseMessages[targetPhase] ?? <ChatMessage>[];
          phaseMessages[targetPhase] = [...current, ...newMessages];
          busy = false;
          processingVisible = false;
        });
        processingTimer?.cancel();
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          processingVisible = false;
        });
      }
      processingTimer?.cancel();
      rethrow;
    }
  }

  void _showProcessing() {
    processingTimer?.cancel();
    setState(() => processingVisible = true);
    processingTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() => processingVisible = false);
      }
    });
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) {
        return;
      }
      final target = scrollController.position.maxScrollExtent;
      if (jump) {
        scrollController.jumpTo(target);
      } else {
        scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }
}

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    required this.controller,
    required this.busy,
    required this.enterSendsReply,
    required this.onSend,
    super.key,
  });

  final TextEditingController controller;
  final bool busy;
  final bool enterSendsReply;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (!enterSendsReply || event is! KeyDownEvent) {
                  return KeyEventResult.ignored;
                }
                if (event.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  onSend();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                textInputAction: enterSendsReply
                    ? TextInputAction.send
                    : TextInputAction.newline,
                decoration: const InputDecoration(labelText: 'Reply'),
                onSubmitted: enterSendsReply ? (_) => onSend() : null,
              ),
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
  const ChatBubble({
    required this.message,
    required this.userAvatarBytes,
    super.key,
  });

  final ChatMessage message;
  final Uint8List? userAvatarBytes;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final avatar = ProfileAvatar(
      phase: message.phase,
      isUser: isUser,
      userAvatarBytes: userAvatarBytes,
    );
    final bubble = ConstrainedBox(
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
    );
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[avatar, const SizedBox(width: 8)],
          Flexible(child: bubble),
          if (isUser) ...[const SizedBox(width: 8), avatar],
        ],
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.phase,
    required this.isUser,
    required this.userAvatarBytes,
    super.key,
  });

  final Phase phase;
  final bool isUser;
  final Uint8List? userAvatarBytes;

  @override
  Widget build(BuildContext context) {
    ImageProvider image;
    if (isUser && userAvatarBytes != null) {
      image = MemoryImage(userAvatarBytes!);
    } else if (isUser) {
      image = const AssetImage('assets/profile/user_placeholder.png');
    } else if (phase == Phase.curiosity) {
      image = const AssetImage('assets/profile/curiosity_placeholder.png');
    } else {
      image = const AssetImage('assets/profile/interlocutor_placeholder.png');
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      backgroundImage: image,
    );
  }
}

class AvatarPreview extends StatelessWidget {
  const AvatarPreview({required this.userAvatarBytes, super.key});

  final Uint8List? userAvatarBytes;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 22,
      backgroundImage: userAvatarBytes == null
          ? const AssetImage('assets/profile/user_placeholder.png')
          : MemoryImage(userAvatarBytes!) as ImageProvider,
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
  const SettingsPage({
    required this.account,
    required this.userAvatarBytes,
    required this.enterSendsReply,
    required this.showEnterKeySetting,
    required this.onPickAvatar,
    required this.onEditUsername,
    required this.onEditEmail,
    required this.onEditPassword,
    required this.onLogout,
    required this.onEnterSendsReplyChanged,
    required this.onLogs,
    super.key,
  });

  final Account account;
  final Uint8List? userAvatarBytes;
  final bool enterSendsReply;
  final bool showEnterKeySetting;
  final VoidCallback onPickAvatar;
  final VoidCallback onEditUsername;
  final VoidCallback onEditEmail;
  final VoidCallback onEditPassword;
  final VoidCallback onLogout;
  final ValueChanged<bool> onEnterSendsReplyChanged;
  final VoidCallback onLogs;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('settings'),
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: AvatarPreview(userAvatarBytes: userAvatarBytes),
          title: const Text('User'),
          subtitle: Text(account.username),
          trailing: IconButton(
            tooltip: 'Upload profile picture',
            icon: const Icon(Icons.photo_camera_rounded),
            onPressed: onPickAvatar,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.badge_rounded),
          title: const Text('Username'),
          subtitle: Text(account.username),
          trailing: const Icon(Icons.edit_rounded),
          onTap: onEditUsername,
        ),
        ListTile(
          leading: const Icon(Icons.alternate_email_rounded),
          title: const Text('Email'),
          subtitle: Text(account.email),
          trailing: const Icon(Icons.edit_rounded),
          onTap: onEditEmail,
        ),
        ListTile(
          leading: const Icon(Icons.password_rounded),
          title: const Text('Password'),
          subtitle: const Text('Change password'),
          trailing: const Icon(Icons.edit_rounded),
          onTap: onEditPassword,
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
        if (showEnterKeySetting)
          SwitchListTile(
            value: enterSendsReply,
            onChanged: onEnterSendsReplyChanged,
            title: const Text('Enter shortcut'),
            subtitle: Text(
              enterSendsReply
                  ? 'Shift+Enter inserts a newline'
                  : 'Enter inserts a newline',
            ),
            secondary: const Icon(Icons.keyboard_return_rounded),
          ),
        SwitchListTile(
          value: true,
          onChanged: (_) {},
          title: const Text('Dark theme'),
          secondary: const Icon(Icons.dark_mode_rounded),
        ),
        ListTile(
          leading: const Icon(Icons.logout_rounded),
          title: const Text('Sign out'),
          onTap: onLogout,
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
