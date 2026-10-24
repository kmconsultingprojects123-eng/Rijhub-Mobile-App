package com.rijhub.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    // The channel every push names ("default", in the API's notifications.py
    // and the manifest). Without it Android files pushes under its quiet
    // fallback channel; at high importance a new request or message pops up
    // on screen, like a text.
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "default",
            "Bookings and messages",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = "Requests, bookings, payments and messages" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
