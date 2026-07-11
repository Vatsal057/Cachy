# flutter_gemma / MediaPipe LLM Inference — keep native-facing classes and
# silence R8 on optional proto classes not present in the release classpath.
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Protocol Buffers (referenced by MediaPipe generated code).
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# On-device RAG / local agents (optional flutter_gemma feature).
-keep class com.google.ai.edge.localagents.** { *; }
-dontwarn com.google.ai.edge.localagents.**
