@file:Suppress("DEPRECATION")

package com.example.lite_dialer

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.role.RoleManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// ---------------------------------------------------------------
// Shared state for all calls
// ---------------------------------------------------------------
object CallHolder {
    val calls = mutableListOf<Call>()
    var service: CallService? = null
    val listeners = mutableListOf<() -> Unit>()
    private val names = HashMap<String, String>()
    private val main = Handler(Looper.getMainLooper())

    fun changed() {
        main.post { listeners.toList().forEach { it() } }
    }

    fun ringing(): Call? = calls.firstOrNull { it.state == Call.STATE_RINGING }

    fun primary(): Call? =
        ringing()
            ?: calls.firstOrNull {
                it.state == Call.STATE_ACTIVE ||
                    it.state == Call.STATE_DIALING ||
                    it.state == Call.STATE_CONNECTING
            }
            ?: calls.firstOrNull()

    fun numberOf(c: Call): String = c.details?.handle?.schemeSpecificPart ?: ""

    fun lookupName(ctx: Context, number: String): String? {
        if (number.isEmpty()) return null
        names[number]?.let { return it }
        var r = ""
        try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(number)
            )
            ctx.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null, null, null
            )?.use { if (it.moveToFirst()) r = it.getString(0) ?: "" }
        } catch (_: Exception) {
        }
        if (r.isEmpty()) return null
        names[number] = r
        return r
    }

    fun stateName(s: Int): String = when (s) {
        Call.STATE_RINGING -> "ringing"
        Call.STATE_ACTIVE -> "active"
        Call.STATE_HOLDING -> "holding"
        Call.STATE_DISCONNECTED, Call.STATE_DISCONNECTING -> "ended"
        else -> "dialing"
    }

    fun snapshot(ctx: Context): Map<String, Any?> {
        val c = primary() ?: return mapOf("active" to false)
        val number = numberOf(c)
        val audio = service?.callAudioState
        return mapOf(
            "active" to true,
            "state" to stateName(c.state),
            "number" to number,
            "name" to (lookupName(ctx, number) ?: c.details?.callerDisplayName ?: ""),
            "connectTime" to (c.details?.connectTimeMillis ?: 0L),
            "muted" to (audio?.isMuted ?: false),
            "speaker" to ((audio?.route ?: 0) == CallAudioState.ROUTE_SPEAKER),
            "count" to calls.size
        )
    }
}

// ---------------------------------------------------------------
// The in-call service (Android binds to this when we are the default phone app)
// ---------------------------------------------------------------
class CallService : InCallService() {
    private val cb = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) {
            refresh()
            CallHolder.changed()
        }

        override fun onDetailsChanged(call: Call, details: Call.Details) {
            CallHolder.changed()
        }
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        call.registerCallback(cb)
        CallHolder.calls.add(call)
        CallHolder.service = this
        refresh()
        if (call.state != Call.STATE_RINGING) {
            try {
                startActivity(
                    Intent(this, InCallActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (_: Exception) {
            }
        }
        CallHolder.changed()
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        call.unregisterCallback(cb)
        CallHolder.calls.remove(call)
        refresh()
        CallHolder.changed()
    }

    override fun onCallAudioStateChanged(audioState: CallAudioState?) {
        CallHolder.changed()
    }

    private fun action(a: String, code: Int): PendingIntent =
        PendingIntent.getBroadcast(
            this, code,
            Intent(this, CallActionReceiver::class.java).putExtra("a", a),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

    private fun refresh() {
        val nm = getSystemService(NotificationManager::class.java)
        val c = CallHolder.primary()
        if (c == null) {
            nm.cancel(1)
            return
        }
        if (Build.VERSION.SDK_INT >= 26) {
            val inc = NotificationChannel("incoming", "Incoming calls", NotificationManager.IMPORTANCE_HIGH)
            inc.setSound(null, null)
            inc.enableVibration(false)
            nm.createNotificationChannel(inc)
            nm.createNotificationChannel(
                NotificationChannel("ongoing", "Ongoing calls", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val ringing = c.state == Call.STATE_RINGING
        val number = CallHolder.numberOf(c)
        val title = CallHolder.lookupName(this, number)
            ?: (if (number.isEmpty()) "Unknown" else number)
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, InCallActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val b = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(this, if (ringing) "incoming" else "ongoing")
        else
            Notification.Builder(this)
        b.setSmallIcon(android.R.drawable.sym_action_call)
        b.setContentTitle(title)
        b.setContentText(if (ringing) "Incoming call" else "Ongoing call")
        b.setCategory(Notification.CATEGORY_CALL)
        b.setOngoing(true)
        b.setOnlyAlertOnce(true)
        b.setContentIntent(open)
        if (ringing) {
            b.setFullScreenIntent(open, true)
            b.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Decline", action("decline", 2))
            b.addAction(android.R.drawable.sym_action_call, "Answer", action("answer", 3))
        } else {
            b.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Hang up", action("hangup", 4))
        }
        nm.notify(1, b.build())
    }
}

// ---------------------------------------------------------------
// Buttons on the notification
// ---------------------------------------------------------------
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val c = CallHolder.primary() ?: return
        when (intent.getStringExtra("a")) {
            "answer" -> {
                c.answer(VideoProfile.STATE_AUDIO_ONLY)
                try {
                    context.startActivity(
                        Intent(context, InCallActivity::class.java)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                } catch (_: Exception) {
                }
            }
            "decline" -> c.reject(false, null)
            "hangup" -> c.disconnect()
        }
    }
}

// ---------------------------------------------------------------
// Bridge between Flutter (Dart) and Android calls
// ---------------------------------------------------------------
class Bridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "dialer")
    private val listener: () -> Unit = {
        channel.invokeMethod("changed", CallHolder.snapshot(activity))
    }

    init {
        CallHolder.listeners.add(listener)
        channel.setMethodCallHandler { m, result -> handle(m, result) }
    }

    fun dispose() {
        CallHolder.listeners.remove(listener)
        channel.setMethodCallHandler(null)
    }

    fun dial(number: String) {
        channel.invokeMethod("dial", number)
    }

    private fun handle(m: MethodCall, result: MethodChannel.Result) {
        val tm = activity.getSystemService(TelecomManager::class.java)
        when (m.method) {
            "snapshot" -> result.success(CallHolder.snapshot(activity))

            "placeCall" -> {
                val n = m.argument<String>("number") ?: ""
                try {
                    tm.placeCall(Uri.fromParts("tel", n, null), Bundle())
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }

            "answer" -> {
                CallHolder.ringing()?.answer(VideoProfile.STATE_AUDIO_ONLY)
                result.success(null)
            }

            "reject" -> {
                CallHolder.ringing()?.reject(false, null)
                result.success(null)
            }

            "hangup" -> {
                val c = CallHolder.primary()
                if (c != null) {
                    if (c.state == Call.STATE_RINGING) c.reject(false, null) else c.disconnect()
                }
                result.success(null)
            }

            "hold" -> {
                val on = m.argument<Boolean>("on") ?: false
                val c = CallHolder.primary()
                if (c != null) {
                    if (on) c.hold() else c.unhold()
                }
                result.success(null)
            }

            "swap" -> {
                CallHolder.calls.firstOrNull { it.state == Call.STATE_HOLDING }?.unhold()
                result.success(null)
            }

            "mute" -> {
                CallHolder.service?.setMuted(m.argument<Boolean>("on") ?: false)
                result.success(null)
            }

            "speaker" -> {
                val on = m.argument<Boolean>("on") ?: false
                CallHolder.service?.setAudioRoute(
                    if (on) CallAudioState.ROUTE_SPEAKER else CallAudioState.ROUTE_WIRED_OR_EARPIECE
                )
                result.success(null)
            }

            "dtmf" -> {
                val d = m.argument<String>("digit")?.firstOrNull()
                val c = CallHolder.primary()
                if (d != null && c != null) {
                    c.playDtmfTone(d)
                    Handler(Looper.getMainLooper()).postDelayed({ c.stopDtmfTone() }, 150)
                }
                result.success(null)
            }

            "addCall" -> {
                activity.startActivity(
                    Intent(activity, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(null)
            }

            "openContacts" -> {
                try {
                    activity.startActivity(
                        Intent(Intent.ACTION_VIEW, ContactsContract.Contacts.CONTENT_URI)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                } catch (_: Exception) {
                }
                result.success(null)
            }

            "isDefault" -> result.success(tm.defaultDialerPackage == activity.packageName)

            "requestDefault" -> {
                try {
                    if (Build.VERSION.SDK_INT >= 29) {
                        val rm = activity.getSystemService(RoleManager::class.java)
                        if (rm.isRoleAvailable(RoleManager.ROLE_DIALER) &&
                            !rm.isRoleHeld(RoleManager.ROLE_DIALER)
                        ) {
                            activity.startActivityForResult(
                                rm.createRequestRoleIntent(RoleManager.ROLE_DIALER), 1001
                            )
                        }
                    } else {
                        activity.startActivity(
                            Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER)
                                .putExtra(
                                    TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME,
                                    activity.packageName
                                )
                        )
                    }
                } catch (_: Exception) {
                }
                result.success(null)
            }

            "initialNumber" -> result.success(activity.intent?.data?.schemeSpecificPart)

            "finish" -> {
                activity.finish()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}

// ---------------------------------------------------------------
// Activities
// ---------------------------------------------------------------
class MainActivity : FlutterActivity() {
    private var bridge: Bridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = Bridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.data?.schemeSpecificPart?.let { bridge?.dial(it) }
    }

    override fun onDestroy() {
        bridge?.dispose()
        super.onDestroy()
    }
}

class InCallActivity : FlutterActivity() {
    private var bridge: Bridge? = null

    override fun getDartEntrypointFunctionName(): String = "inCallMain"

    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = Bridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        bridge?.dispose()
        super.onDestroy()
    }
}
