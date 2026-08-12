package com.splitfree.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * The app's color vocabulary, ported from the iOS `Palette`.
 *
 * Two signal colors carry almost all the meaning: **positive** (money coming
 * back to you) and **negative** (money you owe). They are deliberately the only
 * saturated colors in a balance context, so a glance at any screen answers "am
 * I up or down?".
 *
 * These are held in a CompositionLocal rather than squeezed into Material's
 * ColorScheme, because Material has no slot that means "you are owed money".
 */
data class SplitColors(
    val accent: Color,
    val accentSoft: Color,
    val positive: Color,
    val positiveSoft: Color,
    val negative: Color,
    val negativeSoft: Color,
    val neutral: Color,
    val background: Color,
    val surface: Color,
    val surfaceSunken: Color,
    val separator: Color,
    val primaryText: Color,
    val secondaryText: Color,
    val tertiaryText: Color,
    val categoryOrange: Color,
    val categoryBlue: Color,
    val categoryPurple: Color,
    val categoryPink: Color,
    val categoryTeal: Color,
    val categoryIndigo: Color,
    val categoryGray: Color,
    val isDark: Boolean,
) {
    /** Green when you're up, red when you're down, gray when it's level. */
    fun forBalance(minorUnits: Long): Color = when {
        minorUnits > 0 -> positive
        minorUnits < 0 -> negative
        else -> neutral
    }

    fun softForBalance(minorUnits: Long): Color = when {
        minorUnits > 0 -> positiveSoft
        minorUnits < 0 -> negativeSoft
        else -> surfaceSunken
    }

    /**
     * Avatar backgrounds, chosen for even perceived brightness so no one's
     * initials are harder to read than anyone else's.
     */
    val avatarColors: List<Color> = listOf(
        Color(0xFF2D7EE2), Color(0xFF0B9669), Color(0xFFD94F98), Color(0xFFEA842E),
        Color(0xFF7E5AE1), Color(0xFF0B9296), Color(0xFFCB4A49), Color(0xFF4C5AC9),
        Color(0xFF808B29), Color(0xFFA96731), Color(0xFF2E7398), Color(0xFFA342CB),
    )

    fun avatarColor(index: Int): Color = avatarColors[kotlin.math.abs(index) % avatarColors.size]

    fun groupColor(index: Int): Color = avatarColor(index)

    fun categoryColor(group: com.splitfree.core.CategoryGroup): Color =
        when (group) {
            com.splitfree.core.CategoryGroup.FOOD_AND_DRINK -> categoryOrange
            com.splitfree.core.CategoryGroup.HOME -> categoryIndigo
            com.splitfree.core.CategoryGroup.TRANSPORT -> categoryBlue
            com.splitfree.core.CategoryGroup.ENTERTAINMENT -> categoryPink
            com.splitfree.core.CategoryGroup.TRAVEL -> categoryTeal
            com.splitfree.core.CategoryGroup.LIFE -> categoryPurple
            com.splitfree.core.CategoryGroup.OTHER -> categoryGray
        }
}

private val LightColors = SplitColors(
    accent = Color(0xFF0B9876),
    accentSoft = Color(0xFFE5F7F1),
    positive = Color(0xFF0B9669),
    positiveSoft = Color(0xFFE6F7EE),
    negative = Color(0xFFD94742),
    negativeSoft = Color(0xFFFEEDEC),
    neutral = Color(0xFF6F767E),
    background = Color(0xFFF8F9FA),
    surface = Color(0xFFFFFFFF),
    surfaceSunken = Color(0xFFF1F3F5),
    separator = Color(0xFFE5E8EC),
    primaryText = Color(0xFF0E131B),
    secondaryText = Color(0xFF666F7A),
    tertiaryText = Color(0xFF939CA7),
    categoryOrange = Color(0xFFEA842E),
    categoryBlue = Color(0xFF2D7EE2),
    categoryPurple = Color(0xFF7E5AE1),
    categoryPink = Color(0xFFD94F98),
    categoryTeal = Color(0xFF0B9296),
    categoryIndigo = Color(0xFF4C5AC9),
    categoryGray = Color(0xFF6F797F),
    isDark = false,
)

private val DarkColors = SplitColors(
    accent = Color(0xFF3DD9AB),
    accentSoft = Color(0xFF133229),
    positive = Color(0xFF45DA9D),
    positiveSoft = Color(0xFF143425),
    negative = Color(0xFFFF7A6F),
    negativeSoft = Color(0xFF3C1D1B),
    neutral = Color(0xFF9CA3AA),
    background = Color(0xFF0B0D10),
    surface = Color(0xFF16191E),
    surfaceSunken = Color(0xFF21252B),
    separator = Color(0xFF2E3238),
    primaryText = Color(0xFFF6F8FA),
    secondaryText = Color(0xFF98A2AF),
    tertiaryText = Color(0xFF6F7987),
    categoryOrange = Color(0xFFFAA95D),
    categoryBlue = Color(0xFF6DAAFA),
    categoryPurple = Color(0xFFAD92FA),
    categoryPink = Color(0xFFF980BA),
    categoryTeal = Color(0xFF44C9CD),
    categoryIndigo = Color(0xFF8B96F2),
    categoryGray = Color(0xFF9CA5B1),
    isDark = true,
)

val LocalSplitColors: ProvidableCompositionLocal<SplitColors> =
    staticCompositionLocalOf { LightColors }

/**
 * Chart series colors, checked for colorblind separation against both surfaces.
 * Assigned in fixed order and never cycled; past the eighth slot the tail folds
 * into "Other" rather than inventing a ninth hue nobody can tell apart.
 */
object ChartPalette {
    private val light = listOf(
        Color(0xFF0E9384), Color(0xFFCE6F22), Color(0xFF6C5CE0), Color(0xFF4C8C2B),
        Color(0xFFC2417F), Color(0xFF2D7EE2), Color(0xFF9A7B10), Color(0xFFA8437A),
    )
    private val dark = listOf(
        Color(0xFF22A99A), Color(0xFFC9812F), Color(0xFF8672E0), Color(0xFF5FA53C),
        Color(0xFFD25992), Color(0xFF4483DC), Color(0xFFA98A22), Color(0xFFB85E96),
    )

    fun series(isDark: Boolean): List<Color> = if (isDark) dark else light

    /** Most of our charts show one series, because the bars carry their own labels. */
    fun primary(isDark: Boolean): Color = series(isDark).first()
}

object Metrics {
    val screenPadding = 20.dp
    val cardPadding = 16.dp
    val cardRadius = 20.dp
    val controlRadius = 14.dp
    val chipRadius = 11.dp
    val avatarSmall = 30.dp
    val avatarMedium = 42.dp
    val avatarLarge = 76.dp
}

/**
 * Money uses a monospace-digit style at fixed width so figures don't jitter
 * while a balance animates.
 */
object MoneyType {
    val display = TextStyle(fontSize = 38.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Default)
    val title = TextStyle(fontSize = 26.sp, fontWeight = FontWeight.Bold)
    val row = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    val caption = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
}

private val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(11.dp),
    medium = RoundedCornerShape(14.dp),
    large = RoundedCornerShape(20.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

private val AppTypography = Typography(
    headlineLarge = TextStyle(fontSize = 32.sp, fontWeight = FontWeight.Bold),
    headlineMedium = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.Bold),
    titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 16.sp),
    bodyMedium = TextStyle(fontSize = 15.sp),
    bodySmall = TextStyle(fontSize = 13.sp),
    labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold),
)

enum class AppearanceSetting { SYSTEM, LIGHT, DARK }

@Composable
fun SplitFreeTheme(
    appearance: AppearanceSetting = AppearanceSetting.SYSTEM,
    content: @Composable () -> Unit,
) {
    val dark = when (appearance) {
        AppearanceSetting.SYSTEM -> isSystemInDarkTheme()
        AppearanceSetting.LIGHT -> false
        AppearanceSetting.DARK -> true
    }
    val colors = if (dark) DarkColors else LightColors

    val material = if (dark) {
        darkColorScheme(
            primary = colors.accent,
            onPrimary = Color(0xFF06231B),
            background = colors.background,
            onBackground = colors.primaryText,
            surface = colors.surface,
            onSurface = colors.primaryText,
            surfaceVariant = colors.surfaceSunken,
            onSurfaceVariant = colors.secondaryText,
            error = colors.negative,
            outline = colors.separator,
        )
    } else {
        lightColorScheme(
            primary = colors.accent,
            onPrimary = Color.White,
            background = colors.background,
            onBackground = colors.primaryText,
            surface = colors.surface,
            onSurface = colors.primaryText,
            surfaceVariant = colors.surfaceSunken,
            onSurfaceVariant = colors.secondaryText,
            error = colors.negative,
            outline = colors.separator,
        )
    }

    CompositionLocalProvider(LocalSplitColors provides colors) {
        MaterialTheme(colorScheme = material, typography = AppTypography, shapes = AppShapes, content = content)
    }
}

/** Shorthand so screens can write `theme.positive` instead of the full local. */
val splitColors: SplitColors
    @Composable @ReadOnlyComposable get() = LocalSplitColors.current
