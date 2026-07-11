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
/// best JSON-following per size. HF-gated: download needs a HuggingFace token
/// with the Gemma license accepted.
const kLocalAiModelUrl =
    'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task';
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

  @override
  Future<void> saveHfToken(String token) => _store.setHfToken(token);

  void _set(LocalAiStatus s) {
    _status = s;
    notifyListeners();
  }

  Future<void> _init() async {
    if (!_supported) return;
    _set(const LocalAiStatus(LocalAiPhase.notInstalled));
    try {
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
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(kLocalAiModelUrl, token: _store.hfToken)
          .withProgress((int percent) {
        _set(LocalAiStatus(LocalAiPhase.downloading, progress: percent / 100));
      }).install();
      _set(const LocalAiStatus(LocalAiPhase.ready));
    } catch (e) {
      debugPrint('local-ai: download failed: $e');
      _set(LocalAiStatus(LocalAiPhase.error,
          message: 'Download failed — check connection and HF token'));
    }
  }

  @override
  Future<void> delete() async {
    if (!_supported) return;
    try {
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
