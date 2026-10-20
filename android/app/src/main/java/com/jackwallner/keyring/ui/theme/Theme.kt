package com.jackwallner.keyring.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.VehicleTint

/**
 * Every color, spacing and radius in the app, from `Theme.swift`. The look is
 * a well-kept logbook: warm paper, deep ink, brass for the things that matter,
 * and each vehicle wearing its own color like a key tag.
 */
@Immutable
data class KeyringColors(
    val paper: Color,
    val surface: Color,
    val raised: Color,
    val ink: Color,
    val secondaryInk: Color,
    val faintInk: Color,
    val hairline: Color,
    val brass: Color,
    val brassSoft: Color,
    val overdue: Color,
    val dueSoon: Color,
    val good: Color,
    val unknown: Color,
    val onAction: Color,
) {
    val action: Color get() = ink

    fun status(status: DueStatus): Color = when (status) {
        DueStatus.OVERDUE -> overdue
        DueStatus.DUE_SOON -> dueSoon
        DueStatus.OK -> good
        DueStatus.NO_RECORD -> unknown
    }
}

private fun hex(value: Long) = Color(0xFF000000 or value)

val LightColors = KeyringColors(
    paper = hex(0xF4F1EA), surface = hex(0xFFFFFF), raised = hex(0xEDE8DD), ink = hex(0x1C1B19),
    secondaryInk = hex(0x69655C), faintInk = hex(0x9A958A), hairline = hex(0xDED8CB), brass = hex(0xA9771F),
    brassSoft = hex(0xF3E6C8), overdue = hex(0xB9381A), dueSoon = hex(0xA86A0C), good = hex(0x2E6E50),
    unknown = hex(0x8A857A), onAction = hex(0xF8F5EE),
)

val DarkColors = KeyringColors(
    paper = hex(0x12110F), surface = hex(0x1D1C19), raised = hex(0x282622), ink = hex(0xF3EFE6),
    secondaryInk = hex(0xA8A397), faintInk = hex(0x6F6B62), hairline = hex(0x34312C), brass = hex(0xD8A84A),
    brassSoft = hex(0x3A2F1A), overdue = hex(0xF07A55), dueSoon = hex(0xE8B04B), good = hex(0x6CC69A),
    unknown = hex(0x8F8A7F), onAction = hex(0x16150F),
)

object Space {
    val xxs = 4.dp
    val xs = 8.dp
    val sm = 12.dp
    val md = 16.dp
    val lg = 20.dp
    val xl = 28.dp
    val xxl = 40.dp
    val margin = 20.dp
    val radius = 20.dp
    val smallRadius = 12.dp
    val cardHeight = 212.dp
    val sectionGap = xl
    val stackGap = sm
    val cardPadding = md
    val rowPadding = sm
    val touch = 48.dp
}

object Type {
    fun title(size: Int = 28) = TextStyle(fontSize = size.sp, fontWeight = FontWeight.Bold, lineHeight = (size * 1.18).sp)
    fun figure(size: Int = 17, weight: FontWeight = FontWeight.SemiBold) =
        TextStyle(fontSize = size.sp, fontWeight = weight, fontFeatureSettings = "tnum")
    val body = TextStyle(fontSize = 17.sp, lineHeight = 22.sp)
    val callout = TextStyle(fontSize = 16.sp, lineHeight = 21.sp)
    val subheadline = TextStyle(fontSize = 15.sp, lineHeight = 20.sp)
    val subheadlineBold = subheadline.copy(fontWeight = FontWeight.SemiBold)
    val footnote = TextStyle(fontSize = 13.sp, lineHeight = 18.sp)
    val caption = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.8.sp)
    val headline = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, lineHeight = 22.sp)
}

fun VehicleTint.color(): Color = hex(hex)
fun VehicleTint.foreground(): Color = if (isLight) hex(0x1C1B19) else hex(0xF8F5EE)
fun VehicleTint.outline(): Color? = if (this == VehicleTint.white) hex(0x1C1B19) else null

val LocalColors = staticCompositionLocalOf { LightColors }

object Keyring {
    val colors: KeyringColors
        @Composable @ReadOnlyComposable get() = LocalColors.current
}

@Composable
fun KeyringTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colors = if (dark) DarkColors else LightColors
    val scheme = if (dark) {
        darkColorScheme(primary = colors.ink, onPrimary = colors.onAction, background = colors.paper, surface = colors.surface,
            onSurface = colors.ink, onBackground = colors.ink, secondary = colors.brass, outline = colors.hairline, error = colors.overdue)
    } else {
        lightColorScheme(primary = colors.ink, onPrimary = colors.onAction, background = colors.paper, surface = colors.surface,
            onSurface = colors.ink, onBackground = colors.ink, secondary = colors.brass, outline = colors.hairline, error = colors.overdue)
    }
    CompositionLocalProvider(LocalColors provides colors) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
