set -e
mkdir -p www && cp index.html www/index.html
npm install
npx cap add android
P=android/app/src/main/java/com/meqat/app
mkdir -p $P

cat > $P/MainActivity.java <<'EOF'
package com.meqat.app;
import android.os.Build;
import android.os.Bundle;
import com.getcapacitor.BridgeActivity;
public class MainActivity extends BridgeActivity {
  @Override
  public void onCreate(Bundle s) {
    registerPlugin(MeqatPlugin.class);
    super.onCreate(s);
    if (Build.VERSION.SDK_INT >= 33) {
      requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"}, 1);
    }
  }
}
EOF

cat > $P/MeqatPlugin.java <<'EOF'
package com.meqat.app;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
@CapacitorPlugin(name = "Meqat")
public class MeqatPlugin extends Plugin {
  @PluginMethod
  public void schedule(PluginCall call) {
    JSArray a = call.getArray("times");
    getContext().getSharedPreferences("meqat", 0).edit().putString("times", a.toString()).apply();
    int n = Sched.run(getContext());
    JSObject r = new JSObject();
    r.put("count", n);
    call.resolve(r);
  }
}
EOF

cat > $P/Sched.java <<'EOF'
package com.meqat.app;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import org.json.JSONArray;
import org.json.JSONObject;
class Sched {
  static int run(Context c) {
    int n = 0;
    try {
      JSONArray a = new JSONArray(c.getSharedPreferences("meqat", 0).getString("times", "[]"));
      AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
      long now = System.currentTimeMillis();
      for (int i = 0; i < a.length(); i++) {
        JSONObject o = a.getJSONObject(i);
        long ts = o.getLong("ts");
        if (ts <= now) continue;
        Intent it = new Intent(c, AdhanReceiver.class);
        it.putExtra("name", o.getString("name"));
        PendingIntent pi = PendingIntent.getBroadcast(c, (int) (ts / 60000), it,
            PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        am.setAlarmClock(new AlarmManager.AlarmClockInfo(ts, null), pi);
        n++;
      }
    } catch (Exception e) {}
    return n;
  }
}
EOF

cat > $P/AdhanReceiver.java <<'EOF'
package com.meqat.app;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.os.Build;
import androidx.core.app.NotificationCompat;
public class AdhanReceiver extends BroadcastReceiver {
  @Override
  public void onReceive(Context c, Intent i) {
    String name = i.getStringExtra("name");
    NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
    if (Build.VERSION.SDK_INT >= 26) {
      NotificationChannel ch = new NotificationChannel("adhan", "الأذان", NotificationManager.IMPORTANCE_HIGH);
      ch.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
          new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build());
      nm.createNotificationChannel(ch);
    }
    NotificationCompat.Builder b = new NotificationCompat.Builder(c, "adhan")
        .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
        .setContentTitle("حان وقت صلاة " + name)
        .setContentText("مِيقات - رفيقك إلى الصلاة")
        .setPriority(NotificationCompat.PRIORITY_MAX)
        .setAutoCancel(true);
    nm.notify((int) System.currentTimeMillis(), b.build());
  }
}
EOF

cat > $P/BootReceiver.java <<'EOF'
package com.meqat.app;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
public class BootReceiver extends BroadcastReceiver {
  @Override
  public void onReceive(Context c, Intent i) {
    Sched.run(c);
  }
}
EOF

M=android/app/src/main/AndroidManifest.xml
REC='<receiver android:name=".AdhanReceiver" android:exported="false"/><receiver android:name=".BootReceiver" android:exported="true"><intent-filter><action android:name="android.intent.action.BOOT_COMPLETED"/><action android:name="android.intent.action.TIMEZONE_CHANGED"/></intent-filter></receiver></application>'
PERM='<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/><uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/><uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/><uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/></manifest>'
sed -i "s#</application>#$REC#" $M
sed -i "s#</manifest>#$PERM#" $M
