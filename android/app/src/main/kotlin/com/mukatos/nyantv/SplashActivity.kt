package com.mukatos.nyantv

import android.app.Activity
import android.content.Intent
import android.media.MediaPlayer
import android.os.Bundle
import android.view.View
import android.view.animation.AlphaAnimation
import android.widget.ImageView
import androidx.lifecycle.lifecycleScope
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class SplashActivity : Activity() {
    private var mediaPlayer: MediaPlayer? = null
    private var hasNavigated = false
    private var flutterEngine: FlutterEngine? = null
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Fullscreen
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        )
        
        setContentView(R.layout.activity_splash)
        
        // WICHTIG: Flutter Engine SOFORT im Hintergrund starten
        preloadFlutterEngine()
        
        // Logo Fade-In
        val logoView = findViewById<ImageView>(R.id.splash_logo)
        val fadeIn = AlphaAnimation(0f, 1f).apply {
            duration = 400
            fillAfter = true
        }
        logoView.startAnimation(fadeIn)
        
        // Sound
        try {
            mediaPlayer = MediaPlayer.create(this, R.raw.splash_sound)
            mediaPlayer?.setOnCompletionListener {
                lifecycleScope.launch {
                    delay(500)
                    navigateToMain()
                }
            }
            mediaPlayer?.start()
        } catch (e: Exception) {
            e.printStackTrace()
            lifecycleScope.launch {
                delay(1500)
                navigateToMain()
            }
        }
    }
    
    private fun preloadFlutterEngine() {
        // Flutter Engine im Hintergrund vorwärmen
        flutterEngine = FlutterEngine(this)
        
        // Dart Code sofort ausführen
        flutterEngine?.dartExecutor?.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        
        // Engine cachen für MainActivity
        FlutterEngineCache
            .getInstance()
            .put("nyantv_engine", flutterEngine!!)
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
        mediaPlayer?.release()
        mediaPlayer = null
        // Engine NICHT destroyen - wird von MainActivity genutzt
    }
}