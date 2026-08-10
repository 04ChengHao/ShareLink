package com.sharelink.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.sharelink.app/network"
    private val requestCodeLocation = 1001

    private var multicastLock: WifiManager.MulticastLock? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquireMulticastLock" -> {
                        acquireMulticastLock()
                        result.success(true)
                    }
                    "releaseMulticastLock" -> {
                        releaseMulticastLock()
                        result.success(true)
                    }
                    "hasLocationPermission" -> {
                        result.success(hasLocationPermission())
                    }
                    "requestLocationPermission" -> {
                        if (hasLocationPermission()) {
                            result.success(true)
                        } else {
                            pendingPermissionResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                                requestCodeLocation
                            )
                        }
                    }
                    "getSdkInt" -> {
                        result.success(Build.VERSION.SDK_INT)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// 获取 MulticastLock，让 Android WiFi 驱动不再过滤 UDP 广播包
    private fun acquireMulticastLock() {
        try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifiManager.createMulticastLock("sharelink_multicast")
            multicastLock?.let {
                it.setReferenceCounted(false)
                it.acquire()
                Log.d("ShareLink", "MulticastLock acquired")
            }
        } catch (e: Exception) {
            Log.e("ShareLink", "Failed to acquire MulticastLock: ${e.message}")
        }
    }

    private fun releaseMulticastLock() {
        try {
            multicastLock?.let {
                if (it.isHeld) {
                    it.release()
                    Log.d("ShareLink", "MulticastLock released")
                }
            }
            multicastLock = null
        } catch (e: Exception) {
            Log.e("ShareLink", "Failed to release MulticastLock: ${e.message}")
        }
    }

    private fun hasLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == requestCodeLocation) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            Log.d("ShareLink", "Location permission granted: $granted")
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }
}
