package io.github.strangertheunknown.chesslibrary

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager

/**
 * Uygulamanın simgesini görünüme göre değiştirir (10.13.0).
 *
 * Her görünümün başlatıcıda kendi girdisi var: manifestteki
 * `activity-alias`'lar, hepsi [ChessActivity]'yi açıyor. Yalnızca biri açık;
 * simge değişirken yenisi açılıp ötekiler kapatılıyor.
 *
 * Varsayılan görünümün girdisi `.MainActivity` adını taşıyor: etkinliğin
 * 10.12.0'a kadarki adı. Ana ekrandaki kısayollar o adı sakladığı için
 * güncellemeden sonra da çalışıyorlar.
 */
object AppIcon {
    private const val DEFAULT = "yesil"

    /** Görünüm adları; `lib/theme/app_look.dart` ile aynı olmalı. */
    val looks = listOf(
        "yesil", "gece", "gok", "petrol", "mor",
        "bordo", "mercan", "altin", "kahve", "antrasit",
    )

    /**
     * Manifestteki girdi adlarının başı (`.MainActivity` → bu ad + o):
     * `android/app/build.gradle.kts` içindeki `namespace`.
     *
     * Sabit yazılı, sınıftan okunmuyor: sürüm derlemesinde kod küçültülünce
     * sınıfın paketi kalmıyor (`Class.getPackage()` null dönüyor) ve
     * uygulama açılırken çöküyordu. Deneme derlemesinde görünmüyordu;
     * `test/app_look_test.dart` iki adın aynı olduğunu denetliyor.
     */
    private const val NAMESPACE = "io.github.strangertheunknown.chesslibrary"

    private fun component(context: Context, look: String): ComponentName {
        val name = if (look == DEFAULT) {
            "MainActivity"
        } else {
            "Icon" + look.replaceFirstChar { it.uppercase() }
        }
        return ComponentName(context.packageName, "$NAMESPACE.$name")
    }

    private fun enabled(context: Context, look: String): Boolean =
        when (context.packageManager.getComponentEnabledSetting(component(context, look))) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            // Manifestteki hâli: yalnızca varsayılan açık.
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> look == DEFAULT
            else -> false
        }

    /** Başlatıcıda görünen simgenin görünümü. */
    fun current(context: Context): String =
        looks.firstOrNull { enabled(context, it) } ?: DEFAULT

    /**
     * Simgeyi [look]'a çevirir. Döndürdüğü: "same" (zaten öyle), "changed"
     * ya da "restarting" (uygulama yeniden açılıyor).
     *
     * Önce yenisi açılıyor, sonra ötekiler kapanıyor: arada uygulama
     * başlatıcıda girdisiz kalmıyor. Yarıda kalmış bir değişiklik (iki
     * girdi açık) bir sonraki çağrıda toparlanıyor.
     *
     * Android, kapatılan bir girdiyle açılmış görevi kaldırıyor
     * (DONT_KILL_APP süreci koruyor, görevi değil): simge değişince uygulama
     * kapanıp arkadaki uygulama öne geliyordu (öykünücüde, Android 15).
     * Uygulama o girdiyle açıldıysa önce kendini doğrudan [ChessActivity]
     * ile yeniden açıyor; eski girdi yeni açılışta (Dart tarafı simgeyi
     * açılışta bir kez daha istiyor) kapatılıyor.
     */
    fun set(activity: Activity, look: String): String {
        require(look in looks) { "bilinmeyen görünüm: $look" }
        val manager = activity.packageManager
        val stale = looks.filter { it != look && enabled(activity, it) }
        val wasEnabled = enabled(activity, look)
        if (wasEnabled && stale.isEmpty()) return "same"
        if (!wasEnabled) {
            manager.setComponentEnabledSetting(
                component(activity, look),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
        val launchedBy = activity.intent?.component?.className
        if (stale.any { component(activity, it).className == launchedBy }) {
            // Eski görev kaldırılıp yeni bir görev, doğrudan etkinliğin
            // adıyla açılıyor: yeni görevin temel isteği bir girdi değil.
            // Denenip işe yaramayanlar (öykünücü, Android 15):
            // * Önce startActivity: etkinlik singleTop olduğu için istek açık
            //   pencereye teslim ediliyor, yeni pencere açılmıyor.
            // * NEW_TASK | CLEAR_TASK (makeRestartActivityTask): pencere
            //   yeniden kuruluyor ama görevin temel isteği eski girdi olarak
            //   kalıyor; girdi kapanınca görev yine kaldırılıyor.
            val context = activity.applicationContext
            activity.finishAndRemoveTask()
            context.startActivity(
                Intent(context, ChessActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK,
                ),
            )
            return "restarting"
        }
        for (other in stale) {
            manager.setComponentEnabledSetting(
                component(activity, other),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
        return "changed"
    }
}
