package com.sharelink.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val channelName = "com.sharelink.app/network"
    private val fileChannelName = "com.sharelink.app/file"
    private val requestCodeLocation = 1001
    private val requestCodeOpenFile = 2001

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

        // 文件打开方法通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fileChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openFileWithChooser" -> {
                        val path = call.argument<String>("path")
                        val mimeType = call.argument<String>("mimeType")
                        if (path != null) {
                            openFileWithChooser(path, mimeType ?: "*/*", result)
                        } else {
                            result.error("invalid_args", "path is required", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// 使用系统选择器打开文件（显示所有可打开该文件的应用）
    private fun openFileWithChooser(path: String, mimeType: String, result: MethodChannel.Result) {
        try {
            val file = File(path)
            if (!file.exists()) {
                result.error("file_not_found", "File does not exist: $path", null)
                return
            }

            val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(
                    this,
                    applicationContext.packageName + ".fileprovider",
                    file
                )
            } else {
                Uri.fromFile(file)
            }

            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            // 创建选择器，系统应用会排在前面
            val chooserIntent = Intent.createChooser(viewIntent, "选择打开方式").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            // 授予所有匹配的应用读取权限
            val resInfoList = packageManager.queryIntentActivities(viewIntent, PackageManager.MATCH_DEFAULT_ONLY)
            for (resolveInfo in resInfoList) {
                val packageName = resolveInfo.activityInfo.packageName
                grantUriPermission(packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            startActivityForResult(chooserIntent, requestCodeOpenFile)
            result.success(true)
        } catch (e: Exception) {
            Log.e("ShareLink", "Failed to open file with chooser: ${e.message}")
            result.error("open_failed", e.message, null)
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
