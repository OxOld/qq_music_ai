package com.qqmusicai.qq_music_ai

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.Display
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {

    /// 应用自更新：ABI 检测 + 拉起系统安装器（file_paths.xml 的 cache-path 覆盖下载目录）
    private val updateChannel = "qq_music_ai/update"

    /// 后台连续播放：省电策略豁免（电池优化白名单）
    private val batteryChannel = "qq_music_ai/battery"

    /// 投屏排查：窗口/显示器关键参数（车机实车定位方向与比例问题）
    private val displayChannel = "qq_music_ai/display"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAbi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "")
                    "installApk" -> installApk(call.arguments as? String, result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, batteryChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoring" -> result.success(isIgnoringBatteryOptimizations())
                    "requestIgnore" -> requestIgnoreBatteryOptimizations(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, displayChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "displayInfo" -> result.success(displayInfo())
                    else -> result.notImplemented()
                }
            }
    }

    /// Activity 所在显示器 + 当前配置的关键参数，供 Flutter 侧诊断角标展示。
    /// 车机投屏窗口的 displayId / rotation / 物理像素 / 密度与手机主屏不同，
    /// 据此判断投屏窗口的方向与 dp 比例是否被互联框架改写。
    private fun displayInfo(): Map<String, Any> {
        val d = currentDisplay()
        val m = DisplayMetrics()
        @Suppress("DEPRECATION")
        d?.getRealMetrics(m)
        val cfg = resources.configuration
        return mapOf(
            "displayId" to (d?.displayId ?: -1),
            "rotation" to (d?.rotation ?: -1),
            "widthPx" to m.widthPixels,
            "heightPx" to m.heightPixels,
            "densityDpi" to m.densityDpi,
            "flags" to (d?.flags ?: -1),
            "configOrientation" to cfg.orientation,
            "configWidthDp" to cfg.screenWidthDp,
            "configHeightDp" to cfg.screenHeightDp,
            "configDensityDpi" to cfg.densityDpi,
        )
    }

    @Suppress("DEPRECATION")
    private fun currentDisplay(): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display
        else windowManager.defaultDisplay

    private fun isIgnoringBatteryOptimizations(): Boolean =
        (getSystemService(POWER_SERVICE) as PowerManager)
            .isIgnoringBatteryOptimizations(packageName)

    @SuppressLint("BatteryLife")
    private fun requestIgnoreBatteryOptimizations(result: MethodChannel.Result) {
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            if (pm.isIgnoringBatteryOptimizations(packageName)) {
                result.success(true)
                return
            }
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("request_failed", e.message, null)
        }
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path == null) {
            result.error("bad_args", "path is null", null)
            return
        }
        try {
            val file = File(path)
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(this, "$packageName.fileProvider", file)
            } else {
                Uri.fromFile(file)
            }
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("install_failed", e.message, null)
        }
    }
}
