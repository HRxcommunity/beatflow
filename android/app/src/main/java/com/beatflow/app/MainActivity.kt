package com.beatflow.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : AudioServiceActivity() {

    companion object {
        private const val CHANNEL          = "com.beatflow.app/media"
        private const val SETTINGS_CHANNEL = "beatflow/settings"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // ── Media channel (video query) ───────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "queryVideos" -> {
                    try {
                        result.success(queryVideoFiles())
                    } catch (e: Exception) {
                        result.error("QUERY_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // BUG-VN04 FIX: Settings channel — open system notification settings
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SETTINGS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openNotificationSettings" -> {
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.fromParts("package", packageName, null)
                            }
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun queryVideoFiles(): String {
        val videos = JSONArray()

        // MediaStore.Video collection — works on all Android versions
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }

        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.TITLE,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.ARTIST,
            MediaStore.Video.Media.ALBUM,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.DATE_ADDED,
        )

        contentResolver.query(
            collection,
            projection,
            null,
            null,
            "${MediaStore.Video.Media.TITLE} ASC"
        )?.use { cursor ->
            val idCol     = cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
            val titleCol  = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.TITLE)
            val nameCol   = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
            val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.ARTIST)
            val albumCol  = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.ALBUM)
            val durCol    = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
            val dataCol   = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
            val dateCol   = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)

            while (cursor.moveToNext()) {
                val duration = cursor.getLong(durCol)
                // Skip very short clips (ringtones, GIFs, etc.)
                if (duration < 30_000L) continue

                val rawData = cursor.getString(dataCol) ?: continue
                if (rawData.isEmpty()) continue

                val displayName = cursor.getString(nameCol) ?: ""
                val rawTitle    = cursor.getString(titleCol)

                // Prefer TITLE tag; fall back to filename without extension
                val title = if (!rawTitle.isNullOrBlank() && !rawTitle.startsWith("<")) {
                    rawTitle
                } else {
                    val fn = displayName
                    if (fn.contains('.')) fn.substring(0, fn.lastIndexOf('.')) else fn
                }

                val id = cursor.getLong(idCol)

                // BUG-VID-META FIX: Android MediaStore stores "<unknown>" (literal
                // string) when a video has no embedded artist metadata tag.
                // Sanitize it to a human-readable fallback here so Flutter never
                // sees the raw "<unknown>" string shown in the Together video card.
                val rawArtist = cursor.getString(artistCol) ?: ""
                val artist = if (rawArtist.isBlank() ||
                    rawArtist == "<unknown>" ||
                    (rawArtist.startsWith("<") && rawArtist.endsWith(">"))) {
                    "Unknown"
                } else {
                    rawArtist
                }

                val rawAlbum = cursor.getString(albumCol) ?: ""
                val album = if (rawAlbum.isBlank() ||
                    rawAlbum == "<unknown>" ||
                    (rawAlbum.startsWith("<") && rawAlbum.endsWith(">"))) {
                    "Videos"
                } else {
                    rawAlbum
                }

                val obj = JSONObject().apply {
                    put("id",        id)
                    put("title",     title)
                    put("artist",    artist)
                    put("album",     album)
                    put("duration",  duration)
                    put("data",      rawData)
                    put("dateAdded", cursor.getLong(dateCol))
                }
                videos.put(obj)
            }
        }

        return videos.toString()
    }
}
