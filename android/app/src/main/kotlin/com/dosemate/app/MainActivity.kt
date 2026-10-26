package com.dosemate.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.graphics.Color
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        createAlarmChannel(this)
        super.onCreate(savedInstanceState)
    }

    companion object {
        /** NotificationService.alarmsChannel in Dart. */
        const val ALARMS_CHANNEL = "dose_alarms"

        /**
         * The alarm channel, made here because awesome_notifications always
         * gives channel sounds notification audio: a muted notification
         * volume then silences alarms. This one plays on the alarm stream
         * (alarm volume, like a clock app).
         *
         * Every other setting matches what awesome_notifications would set
         * for the channel in Dart, so it keeps this channel instead of
         * replacing it. A channel's sound and audio can't change once
         * created, so a change means a new channel id.
         */
        fun createAlarmChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(ALARMS_CHANNEL) != null) return
            val sound = Uri.parse(
                "android.resource://${context.packageName}/${R.raw.alarm}"
            )
            val channel = NotificationChannel(
                ALARMS_CHANNEL,
                "Medicine & appointment alarms",
                NotificationManager.IMPORTANCE_MAX,
            ).apply {
                description = "Rings at each dose and appointment reminder"
                setSound(
                    sound,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 200, 200, 200, 200, 200, 200)
                enableLights(true)
                lightColor = Color.WHITE
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
    }
}
