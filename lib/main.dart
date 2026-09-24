import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:intl/intl.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(home: TKHubBotApp()));
}

class SignalModel {
  String time;      // "HH:MM:SS"
  String asset;     // "EURUSD_otc"
  String direction; // "CALL" / "PUT"
  double amount;
  bool executed = false;

  SignalModel({required this.time, required this.asset, required this.direction, required this.amount});
}

class TKHubBotApp extends StatefulWidget {
  @override
  _TKHubBotAppState createState() => _TKHubBotAppState();
}

class _TKHubBotAppState extends State<TKHubBotApp> {
  InAppWebViewController? webViewController;
  
  // কন্ট্রোলার ও স্টেট
  TextEditingController signalTextController = TextEditingController();
  double stopLossLimit = 50.0;
  double takeProfitLimit = 100.0;
  double currentSessionPnL = 0.0;
  
  bool isBotRunning = false;
  List<SignalModel> futureSignals = [];
  Timer? schedulerTimer;
  String logs = "Bot Ready. System Initialized.\n";

  @override
  void initState() {
    super.initState();
    // ডিফল্ট ডেমো সিগন্যাল টেমপ্লেট
    signalTextController.text = "17:30:00, EURUSD_otc, CALL, 100\n17:32:00, GBPUSD_otc, PUT, 100";
  }

  void log(String text) {
    setState(() {
      logs += "[${DateFormat('HH:mm:ss').format(DateTime.now())}] $text\n";
    });
  }

  // ফিউচার সিগন্যাল টেক্সট পার্স করা
  void parseSignals() {
    futureSignals.clear();
    List<String> lines = signalTextController.text.split('\n');
    for (var line in lines) {
      var parts = line.split(',');
      if (parts.length >= 4) {
        futureSignals.add(SignalModel(
          time: parts[0].trim(),
          asset: parts[1].trim(),
          direction: parts[2].trim().toUpperCase(),
          amount: double.tryParse(parts[3].trim()) ?? 10.0,
        ));
      }
    }
    log("📌 ${futureSignals.length}টি সিগন্যাল লোড করা হয়েছে।");
  }

  // বট স্টার্ট লুপ
  void startBotSession() {
    parseSignals();
    if (futureSignals.isEmpty) {
      log("❌ কোনো সঠিক সিগন্যাল পাওয়া যায়নি!");
      return;
    }

    setState(() => isBotRunning = true);
    log("🚀 সেশন শুরু হয়েছে। স্টপ-লস: -\$$stopLossLimit | টেক-প্রফিট: +\$$takeProfitLimit");

    schedulerTimer = Timer.periodic(Duration(milliseconds: 200), (timer) {
      if (!isBotRunning) return;

      // ১. স্টপ-লস ও টেক-প্রফিট চেক
      if (currentSessionPnL <= -stopLossLimit) {
        log("🛑 [STOP-LOSS HIT] সেশন অটো-স্টপ করা হলো!");
        stopBotSession();
        return;
      }

      if (currentSessionPnL >= (takeProfitLimit * 0.90)) {
        log("🎯 [TARGET REACHED] ৯০%+ প্রফিট সম্পন্ন! ওভার-ট্রেডিং বন্ধ করতে সেশন সমাপ্ত।");
        stopBotSession();
        return;
      }

      // ২. টাইমিং চেক ও ট্রেড এক্সিকিউশন
      String nowStr = DateFormat('HH:mm:ss').format(DateTime.now());

      for (var signal in futureSignals) {
        if (!signal.executed && signal.time == nowStr) {
          signal.executed = true;
          executeTradeOnQuotex(signal);
        }
      }
    });
  }

  void stopBotSession() {
    schedulerTimer?.cancel();
    setState(() => isBotRunning = false);
    log("⏹️ বট সেশন বন্ধ করা হয়েছে।");
  }

  // Webview-তে জাভাস্ক্রিপ্ট ইনজেক্ট করে ট্রেড প্রেস করা
  void executeTradeOnQuotex(SignalModel signal) async {
    log("⚡ Trading Signal Match: ${signal.asset} | ${signal.direction} | \$${signal.amount}");

    if (webViewController != null) {
      String jsCode = """
        (function() {
          let amountInput = document.querySelector('input[name="amount"]') || document.querySelector('.input-control__input');
          if (amountInput) {
              amountInput.value = "${signal.amount}";
              amountInput.dispatchEvent(new Event('input', { bubbles: true }));
              amountInput.dispatchEvent(new Event('change', { bubbles: true }));
          }
          let btnSelector = "${signal.direction}" === "CALL" ? '.btn-call, .tab-button--call' : '.btn-put, .tab-button--put';
          let btn = document.querySelector(btnSelector);
          if (btn) {
              btn.click();
              return "EXECUTED";
          }
          return "BTN_NOT_FOUND";
        })();
      """;

      var res = await webViewController!.evaluateJavascript(source: jsCode);
      log("📊 Execution Result: $res");
    } else {
      log("❌ Quotex Webview কানেক্টেড নেই!");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("T.K HUB Custom Auto-Trader"),
        backgroundColor: Colors.blueGrey[900],
      ),
      body: Column(
        children: [
          // ১. Embedded Quotex View (লগইন ও লাইভ ট্রেড দেখার জন্য)
          Container(
            height: 320,
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri("https://quotex.com")),
              onWebViewCreated: (controller) {
                webViewController = controller;
              },
            ),
          ),
          
          // ২. কন্ট্রোল প্যানেল ও সিগন্যাল ইনপুট
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: ListView(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(labelText: "Stop Loss (\$)"),
                          keyboardType: TextInputType.number,
                          onChanged: (val) => stopLossLimit = double.tryParse(val) ?? 50.0,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(labelText: "Take Profit (\$)"),
                          keyboardType: TextInputType.number,
                          onChanged: (val) => takeProfitLimit = double.tryParse(val) ?? 100.0,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  TextField(
                    controller: signalTextController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: "Future Signals (HH:MM:SS, Asset, Dir, Amount)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isBotRunning ? Colors.red : Colors.green,
                      padding: EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: isBotRunning ? stopBotSession : startBotSession,
                    child: Text(
                      isBotRunning ? "STOP BOT SESSION" : "START FUTURE SIGNAL BOT",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(height: 10),
                  Container(
                    padding: EdgeInsets.all(8),
                    color: Colors.black12,
                    height: 120,
                    child: SingleChildScrollView(
                      child: Text(logs, style: TextStyle(fontSize: 11, fontFamily: 'monospace')),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
