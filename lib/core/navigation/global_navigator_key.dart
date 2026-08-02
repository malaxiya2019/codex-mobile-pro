import 'package:flutter/material.dart';

/// 全局导航 key
///
/// - 作为 GoRouter 的 root navigator
/// - 供全局错误处理器（GlobalErrorHandler）在生产模式弹出崩溃界面
final globalNavigatorKey = GlobalKey<NavigatorState>();
