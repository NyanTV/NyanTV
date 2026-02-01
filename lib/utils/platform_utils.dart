import 'package:flutter/foundation.dart';



import 'package:shared_preferences/shared_preferences.dart';





class PlatformUtils {


  static const String _forceDesktopLayoutKey = 'force_desktop_layout';


  static bool? _isTV;


  static bool? _forceDesktopLayout;





  // TV Detection


  static Future<bool> isAndroidTV() async {


    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {


      _isTV ??= await _checkTVMode();


      return _isTV!;


    }


    return false;


  }





  static Future<bool> _checkTVMode() async {


    try {


      // Check UI Mode via platform channel


      final result = await const MethodChannel('app.nyantv/platform')


          .invokeMethod<String>('getUIMode');


      return result?.contains('television') ?? false;


    } catch (_) {


      return false;


    }


  }





  // Desktop Layout Toggle


  static Future<bool> shouldUseDesktopLayout() async {


    final prefs = await SharedPreferences.getInstance();


    _forceDesktopLayout = prefs.getBool(_forceDesktopLayoutKey);


    


    if (_forceDesktopLayout == true) return true;


    


    if (await isAndroidTV()) return true;


    


    return kIsWeb || 


           defaultTargetPlatform == TargetPlatform.macOS ||


           defaultTargetPlatform == TargetPlatform.windows ||


           defaultTargetPlatform == TargetPlatform.linux;


  }





  static Future<void> setForceDesktopLayout(bool value) async {


    final prefs = await SharedPreferences.getInstance();


    await prefs.setBool(_forceDesktopLayoutKey, value);


    _forceDesktopLayout = value;


  }





  static Future<bool> getForceDesktopLayout() async {


    final prefs = await SharedPreferences.getInstance();


    return prefs.getBool(_forceDesktopLayoutKey) ?? false;


  }


