package com.mukatos.nyantv

import android.app.Activity
import android.content.Intent
import android.media.MediaPlayer
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.animation.AlphaAnimation
import android.widget.ImageView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

class SplashActivity : Activity() {
    private var mediaPlayer: MediaPlayer? = null
    private var hasNavigated = false
    private var flutterEngine: FlutterEngine? = null
    private val handler = Handler(Looper.getMainLooper())
    
    override fun onCreate(savedInstanceState: Bundle?) {
            if (!isTaskRoot) {
                val intent = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                startActivity(intent)
                finish()
                return
            }
            super.onCreate(savedInstanceState)
        
        // Fullscreen
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        )
        
        setContentView(R.layout.activity_splash)
        
        // Flutter Engine SOFORT im Hintergrund starten
        preloadFlutterEngine()
        
        // Logo Fade-In
        val logoView = findViewById<ImageView>(R.id.splash_logo)
        val fadeIn = AlphaAnimation(0f, 1f).apply {
            duration = 400
            fillAfter = true
        }
        logoView.startAnimation(fadeIn)
        
        try {
            mediaPlayer = MediaPlayer.create(this, R.raw.splash_sound)
            mediaPlayer?.setOnCompletionListener {
                // Warte noch 500ms nach Sound-Ende
                handler.postDelayed({
                    navigateToMain()
                }, 500)
            }
            mediaPlayer?.start()
        } catch (e: Exception) {
            e.printStackTrace()
            // Fallback ohne Sound
            handler.postDelayed({
                navigateToMain()
            }, 1500)
        }
    }
    
    private fun preloadFlutterEngine() {
        if (FlutterEngineCache.getInstance().contains("nyantv_engine")) return
        try {
            flutterEngine = FlutterEngine(this)
            
            // Dart Code sofort ausführen
            flutterEngine?.dartExecutor?.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            
            // Engine cachen für MainActivity
            FlutterEngineCache
                .getInstance()
                .put("nyantv_engine", flutterEngine!!)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
    
    private fun navigateToMain() {
        if (hasNavigated) return
        hasNavigated = true
        
        mediaPlayer?.stop()
        val intent = Intent(this, MainActivity::class.java)
        startActivity(intent)
        overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out)
        finish()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacksAndMessages(null)
        mediaPlayer?.release()
        mediaPlayer = null
    }
}