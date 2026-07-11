/// Real on-device runtime: Gemma 3 1B int4 (~550 MB) via flutter_gemma
/// (MediaPipe LLM Inference). Android-only — every other platform reports
/// [LocalAiPhase.unsupported] and the feature stays hidden.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../local_store.dart';
import 'local_ai_service.dart';

/// Gemma 3 1B IT, int4 .task build — the flutter_gemma-supported model with the
/// best JSON-following per size. Self-hosted on our GitHub release so end users
/// need no HuggingFace account or license token (Gemma license permits
/// redistribution with its use-restrictions notice, shipped in NOTICE).
const kLocalAiModelUrl =
    'https://github.com/Vatsal057/Cachy/releases/download/model-v1/gemma3-1b-it-int4.task';
const kLocalAiModelFile = 'gemma3-1b-it-int4.task';
const kLocalAiModelSizeLabel = '~550 MB';

class GemmaLocalAiService extends LocalAiService {
  GemmaLocalAiService({required LocalStore store}) : _store = store {
    _init();
  }

  final LocalStore _store;
  LocalAiStatus _status = const LocalAiStatus(LocalAiPhase.unsupported);

  @override
  LocalAiStatus get status => _status;

  @override
  bool get enabled => _store.localAiEnabled;

  @override
  Future<void> setEnabled(bool value) async {
    await _store.setLocalAiEnabled(value);
    notifyListeners();
  }

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// flutter_gemma requires FlutterGemma.initialize() before any other call.
  /// Lazy + memoized so app startup never pays for it when the feature is unused.
  Future<void>? _gemmaInit;
  Future<void> _ensureGemmaInit() => _gemmaInit ??= FlutterGemma.initialize();

  void _set(LocalAiStatus s) {
    _status = s;
    notifyListeners();
  }

  Future<void> _init() async {
    if (!_supported) return;
    _set(const LocalAiStatus(LocalAiPhase.notInstalled));
    try {
      await _ensureGemmaInit();
      final installed = await FlutterGemma.isModelInstalled(kLocalAiModelFile);
      if (installed) _set(const LocalAiStatus(LocalAiPhase.ready));
    } catch (e) {
      debugPrint('local-ai: install check failed: $e');
    }
  }

  @override
  Future<void> download() async {
    if (!_supported || _status.phase == LocalAiPhase.downloading) return;
    _set(const LocalAiStatus(LocalAiPhase.downloading));
    try {
      await _ensureGemmaInit();
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(kLocalAiModelUrl)
          .withProgress((int percent) {
        _set(LocalAiStatus(LocalAiPhase.downloading, progress: percent / 100));
      }).install();
      _set(const LocalAiStatus(LocalAiPhase.ready));
    } catch (e) {
      debugPrint('local-ai: download failed: $e');
      // Surface the real cause — a generic message made this undebuggable.
      final detail = e.toString();
      _set(LocalAiStatus(LocalAiPhase.error,
          message:
              'Download failed: ${detail.length > 220 ? detail.substring(0, 220) : detail}'));
    }
  }

  @override
  Future<void> delete() async {
    if (!_supported) return;
    try {
      await _ensureGemmaInit();
      await FlutterGemma.uninstallModel(kLocalAiModelFile);
    } catch (e) {
      debugPrint('local-ai: delete failed: $e');
    }
    _set(const LocalAiStatus(LocalAiPhase.notInstalled));
  }

  @override
  Future<Map<String, dynamic>?> structureBundle(
    String bundle, {
    String transcript = '',
    String caption = '',
  }) async {
    if (!canStructure) return null;
    InferenceModel? model;
    try {
      await _ensureGemmaInit();
      model = await FlutterGemma.getActiveModel(maxTokens: 2048);
      final session = await model.createSession(temperature: 0.3, topK: 40);
      try {
        await session.addQueryChunk(
          Message.text(text: buildStructurePrompt(bundle), isUser: true),
        );
        final raw = await session.getResponse();
        return parseModelCardJson(raw);
      } finally {
        await session.close();
      }
    } catch (e) {
      // Silent grace: paragraph card stays, log only.
      debugPrint('local-ai: structuring failed: $e');
      return null;
    } finally {
      try {
        await model?.close();
      } catch (_) {}
    }
  }
}
