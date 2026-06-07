import 'dart:async';
import 'dart:convert';
import 'package:abyadpos_tab/core/di/service_lacator.dart';
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'package:edfapay_softpos_sdk/edfapay_softpos_sdk.dart';
import 'package:edfapay_softpos_sdk/helpers.dart';
import 'package:abyadpos_tab/features/auth/presentation/cubit/user_cubit.dart';

class EdfaPayResult<T> {
  final T? data;
  final String? error;

  EdfaPayResult({this.data, this.error});
  bool get hasError => error != null;
}

class EdfaPayManager {
  static final EdfaPayManager _instance = EdfaPayManager._internal();
  factory EdfaPayManager() => _instance;
  EdfaPayManager._internal();

  bool _isInitialized = false;
  bool _isInitializing = false;

  bool get isInitialized => _isInitialized;

  Future<EdfaPayResult<void>> initializeEdfaPay() async {
    if (_isInitialized) return EdfaPayResult(data: null);
    if (_isInitializing)
      return EdfaPayResult(error: "جاري تهيئة النظام، يرجى الانتظار.");

    _isInitializing = true;
    final completer = Completer<EdfaPayResult<void>>();

    try {
      final userSettings = getIt<UserCubit>().state.userModel?.data;

      final String targetTid = "TID-5130001500000000";
      EdfaPayPlugin.enableLogs(true);

      EdfaPayCredentials credentials = EdfaPayCredentials.withToken(
        environment: Env.SANDBOX,
        token:
            "0DD7C72502F53DF07D37C1600468B2E3EC0574678052DA38AC8472DD2E1EB85F",
      );

      await _applyCustomTheme();

      EdfaPayPlugin.initiate(
          credentials: credentials,
          onError: (e) {
            _isInitializing = false;
            debugPrint('** Error Initializing SDK **: ${jsonEncode(e)}');
            if (!completer.isCompleted) {
              completer.complete(
                  EdfaPayResult(error: "فشل التهيئة: ${jsonEncode(e)}"));
            }
          },
          onTerminalBindingTask: (bindingTask) {
            debugPrint('>>> Terminal Binding Required');

            final terminals = bindingTask.terminals;

            if (terminals.isEmpty) {
              debugPrint('>>> No terminals available for this token!');
              return;
            }

            for (var t in terminals) {
              debugPrint(">>> Available Terminal ID: ${t.terminalId}");
            }

            final myTerminal =
                terminals.where((t) => t.terminalId == targetTid).firstOrNull;

            if (myTerminal != null) {
              debugPrint(">>> Target TID found. Binding...");
              bindingTask.bind(terminal: myTerminal);
            } else {
              debugPrint(
                  ">>> Target TID ($targetTid) not found. Binding first available terminal as fallback.");
              bindingTask.bind(terminal: terminals.first);
            }
          },
          onSuccess: (sessionId) {
            debugPrint(
                '** Successfully Initialized SDK ** Session ID: $sessionId');
            _isInitialized = true;
            _isInitializing = false;
            if (!completer.isCompleted) {
              completer.complete(EdfaPayResult(data: null));
            }
          });
    } catch (e, s) {
      _isInitializing = false;
      FirebaseCrashlytics.instance.recordError(e, s);
      if (!completer.isCompleted) {
        completer
            .complete(EdfaPayResult(error: "خطأ غير متوقع أثناء التهيئة: $e"));
      }
    }

    return completer.future;
  }

  Future<void> _applyCustomTheme() async {
    try {
      final logoBase64 = await assetsBase64('assets/images/logo.png');

      final presentation = Presentation.DIALOG_CENTER
          .sizePercent(0.85)
          .dismissOnTouchOutside(false)
          .dimBackground(true)
          .dimAmount(1.0)
          .animateEntry(true)
          .animateExit(true)
          .cornerRadius(20)
          .setPurchaseSecondaryAction(PurchaseSecondaryAction.NONE);

      EdfaPayPlugin.theme()
          .setPrimaryColor("#06E59F")
          .setSecondaryColor("#000000")
          .setHeaderImage(logoBase64)
          .setPoweredByImage(logoBase64)
          .setPresentation(presentation);
    } catch (e) {
      debugPrint("Theme customization failed: $e");
    }
  }

  Future<EdfaPayResult<dynamic>> startPaymentTransaction(double amount,
      {String? orderId}) async {
    if (!_isInitialized) {
      return EdfaPayResult(error: "جهاز الدفع غير مهيأ للاستخدام.");
    }

    final completer = Completer<EdfaPayResult<dynamic>>();

    try {
      final params = TxnParams(
        amount: amount.toStringAsFixed(2),
        orderId: orderId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      );

      EdfaPayPlugin.purchase(
        txnParams: params,
        flowType: FlowType.DETAIL,
        onPaymentProcessComplete: (status, code, result, isFlowCompleted) {
          if (status) {
            debugPrint('>>> Payment Success: ${jsonEncode(result)}');
            completer.complete(EdfaPayResult(data: result));
          } else {
            debugPrint('>>> Payment Failed: ${jsonEncode(result)}');
            completer.complete(EdfaPayResult(
                error: "فشلت عملية الدفع. الرمز: $code", data: result));
          }
        },
        onRequestTimerEnd: () {
          debugPrint('>>> Server Timeout');
          completer
              .complete(EdfaPayResult(error: "انتهى وقت الاتصال بالخادم."));
        },
        onCardScanTimerEnd: () {
          debugPrint('>>> Scan Card Timeout');
          completer.complete(
              EdfaPayResult(error: "انتهى وقت انتظار تمرير البطاقة."));
        },
        onCancelByUser: () {
          debugPrint('>>> Canceled By User');
          completer.complete(
              EdfaPayResult(error: "تم إلغاء عملية الدفع بواسطة المستخدم."));
        },
        onError: (error) {
          debugPrint('>>> Payment Error: ${jsonEncode(error)}');
          completer.complete(EdfaPayResult(
              error: "حدث خطأ أثناء الدفع: ${jsonEncode(error)}"));
        },
      );
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s);
      if (!completer.isCompleted) {
        completer.complete(
            EdfaPayResult(error: "خطأ في النظام أثناء محاولة الدفع: $e"));
      }
    }

    return completer.future;
  }

  void logout() {
    _isInitialized = false;
    _isInitializing = false;
  }
}
